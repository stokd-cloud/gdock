import AppKit
import Bonsplit
import Foundation
import Observation
import os
import SwiftUI

/// Per-window, per-edge rail store backed by Bonsplit.
///
/// One type serves left and right rails. There is deliberately **no**
/// maximum-section constant — geometry may refuse a new header, but the
/// application never caps section count.
@MainActor
@Observable
final class SidebarDockStore: BonsplitDelegate {
    let edge: SidebarDockEdge
    let windowId: UUID
    let bonsplitController: BonsplitController

    /// Live panels keyed by panel id.
    var panels: [UUID: any Panel] = [:]
    /// Bonsplit tab id → panel id.
    var surfaceIdToPanelId: [TabID: UUID] = [:]

    /// Pre-collapse extent per collapsed split so expand restores prior size.
    /// Keyed by split id (first-child collapse) or by a synthetic trailing key.
    var rememberedExtentBySplitId: [UUID: CGFloat] = [:]

    /// Split ids currently collapsed to header height (first-child pin).
    private(set) var collapsedSplitIds: Set<UUID> = []

    /// When the trailing (second-child) leaf is collapsed, the parent split id
    /// whose first-child extent is imposed to leave only header height for the
    /// second child.
    private(set) var trailingCollapsedParentSplitId: UUID?

    /// Sole-section collapse surrogate (left rail headerless chrome case).
    private(set) var isSoleSectionCollapsed = false
    private var soleSectionRememberedExtent: CGFloat?

    /// Pane id of the section most recently expanded (divider/collapse lifecycle).
    private(set) var lastExpandedPaneId: UUID?

    /// Collapse requests deferred while a divider drag is active.
    private var pendingCollapsePaneIds: [PaneID] = []

    /// Observed rail content height for trailing re-imposition and geometry checks.
    private(set) var railContentHeight: CGFloat = 0

    /// Header / collapsed section height in points.
    let collapsedSectionHeight: CGFloat

    /// Derived legacy-mode mirror callback (right rail only).
    ///
    /// Written **only** from Bonsplit `didSelectTab` / `didFocusPane` (VAL-RAIL-002/009).
    /// Production selection entrypoints must not write `FileExplorerState.mode` for rail tools.
    var onFocusedToolModeChanged: ((RightSidebarMode?) -> Void)?

    /// Soft focus signal for the per-window registry (not a second selection store).
    var onRailFocusChanged: (() -> Void)?

    /// Counts content mount generations for hidden-rail lifecycle tests (VAL-RAIL-010).
    private(set) var toolContentMountGeneration: Int = 0
    private(set) var toolContentUnmountGeneration: Int = 0
    private(set) var isToolContentMounted: Bool = false

    private static let logger = Logger(subsystem: "ai.manaflow.cmux", category: "SidebarDockStore")

    // MARK: - Init

    init(
        edge: SidebarDockEdge,
        windowId: UUID,
        collapsedSectionHeight: CGFloat = RightSidebarChromeMetrics.titlebarHeight
    ) {
        self.edge = edge
        self.windowId = windowId
        self.collapsedSectionHeight = collapsedSectionHeight
        self.bonsplitController = BonsplitController(
            configuration: Self.makeConfiguration(collapsedSectionHeight: collapsedSectionHeight)
        )
        self.bonsplitController.delegate = self
        // Drop default welcome tab so the root pane starts empty until seeded.
        for tabId in bonsplitController.allTabIds {
            _ = bonsplitController.closeTab(tabId)
        }
        // RED: actor tab-context destinations are not wired until green commit.
        // Green installs tabContextMoveDestinationsProvider + move handler.
    }

    // MARK: - Configuration

    static func makeConfiguration(collapsedSectionHeight: CGFloat) -> BonsplitConfiguration {
        // Widen dividerPositionRange so collapse-to-header is not double-clamped
        // against the default 0.1...0.9 fraction range (mission D-4).
        var config = BonsplitConfiguration(
            allowSplits: true,
            allowCloseTabs: true,
            allowCloseLastPane: false,
            allowTabReordering: true,
            allowCrossPaneTabMove: true,
            autoCloseEmptyPanes: true,
            contentViewLifecycle: .keepAllAlive,
            newTabPosition: .current,
            tabBarVisibility: .multipleTabs,
            dividerPositionRange: 0.0...1.0,
            appearance: BonsplitConfiguration.Appearance(
                tabBarHeight: collapsedSectionHeight,
                minimumPaneHeight: collapsedSectionHeight,
                dividerThickness: 1,
                showSplitButtons: false,
                enableAnimations: false
            )
        )
        // Explicit public vars in case the initializer path changes.
        config.appearance.minimumPaneHeight = collapsedSectionHeight
        config.appearance.tabBarHeight = collapsedSectionHeight
        config.appearance.dividerThickness = 1
        config.appearance.showSplitButtons = false
        return config
    }

    /// Re-applies tab-bar visibility from section count.
    /// One section → `.multipleTabs` (chrome-free sole section); ≥2 → `.always`.
    func refreshTabBarVisibility() {
        let count = sectionCount
        let next: TabBarVisibility = count >= 2 ? .always : .multipleTabs
        if bonsplitController.configuration.tabBarVisibility != next {
            bonsplitController.configuration.tabBarVisibility = next
        }
    }

    // MARK: - Lookups

    var sectionCount: Int {
        bonsplitController.allPaneIds.count
    }

    func panel(for tabId: TabID) -> (any Panel)? {
        guard let panelId = surfaceIdToPanelId[tabId] else { return nil }
        return panels[panelId]
    }

    func surfaceId(forPanelId panelId: UUID) -> TabID? {
        surfaceIdToPanelId.first { $0.value == panelId }?.key
    }

    func paneId(forPanelId panelId: UUID) -> PaneID? {
        guard let tabId = surfaceId(forPanelId: panelId) else { return nil }
        return paneId(forTabId: tabId)
    }

    func paneId(forTabId tabId: TabID) -> PaneID? {
        for paneId in bonsplitController.allPaneIds
        where bonsplitController.tabs(inPane: paneId).contains(where: { $0.id == tabId }) {
            return paneId
        }
        return nil
    }

    /// Ordered section panes from top to bottom (pre-order leaf walk).
    func orderedSectionPaneIds() -> [PaneID] {
        leafPaneIds(in: bonsplitController.treeSnapshot())
    }

    /// Complete section snapshots for behavioral tests and reorder.
    func sectionSnapshots() -> [SidebarDockSectionSnapshot] {
        orderedSectionPaneIds().map { pane in
            let tabs = bonsplitController.tabs(inPane: pane)
            let panelIds: [UUID] = tabs.compactMap { surfaceIdToPanelId[$0.id] }
            let selected = bonsplitController.selectedTab(inPane: pane).flatMap { surfaceIdToPanelId[$0.id] }
            let collapsed = isSectionCollapsed(paneId: pane)
            let remembered = rememberedExtent(forPane: pane)
            return SidebarDockSectionSnapshot(
                paneId: pane.id,
                tabPanelIds: panelIds,
                selectedPanelId: selected,
                isCollapsed: collapsed,
                rememberedExtent: remembered
            )
        }
    }

    // MARK: - Seed / attach

    /// Attach an existing panel as a tab in `paneId` (or root if nil).
    @discardableResult
    func attachPanel(
        _ panel: any Panel,
        inPane paneId: PaneID? = nil,
        select: Bool = true
    ) -> TabID? {
        guard SidebarDockPlacementMatrix.allows(panel: panel) else {
            Self.logger.warning("sidebar-dock: refused attach of panel type \(panel.panelType.rawValue, privacy: .public) on \(self.edge.rawValue, privacy: .public)")
            return nil
        }
        panels[panel.id] = panel
        guard let tabId = bonsplitController.createTab(
            title: panel.displayTitle,
            icon: panel.displayIcon,
            kind: panel.panelType.rawValue,
            isDirty: panel.isDirty,
            inPane: paneId
        ) else {
            panels.removeValue(forKey: panel.id)
            return nil
        }
        surfaceIdToPanelId[tabId] = panel.id
        if select {
            bonsplitController.selectTab(tabId)
            if let pane = self.paneId(forTabId: tabId) {
                bonsplitController.focusPane(pane)
            }
        }
        dropOrphanTabs()
        refreshTabBarVisibility()
        return tabId
    }

    /// Seed the rail with panels in a single root section (flag-on first mount).
    func seedRootPanels(_ seedPanels: [any Panel]) {
        guard let root = bonsplitController.allPaneIds.first else { return }
        for panel in seedPanels {
            _ = attachPanel(panel, inPane: root, select: false)
        }
        if let firstTab = bonsplitController.tabs(inPane: root).first {
            bonsplitController.selectTab(firstTab.id)
        }
        refreshTabBarVisibility()
    }

    // MARK: - Tool selection (right rail)

    /// Mode of the selected tab in the focused section (derived legacy mirror source).
    func focusedToolMode() -> RightSidebarMode? {
        guard edge == .right else { return nil }
        let pane = bonsplitController.focusedPaneId
            ?? orderedSectionPaneIds().first
        guard let pane else { return nil }
        guard let selected = bonsplitController.selectedTab(inPane: pane)
                ?? bonsplitController.tabs(inPane: pane).first else {
            return nil
        }
        return (panel(for: selected.id) as? RightSidebarToolPanel)?.mode
    }

    /// Select/focus a rail tool by mode. Mirror updates via Bonsplit callbacks only.
    ///
    /// Programmatic and user selection share one path: `BonsplitController.selectTab`
    /// (and `focusPane` when focus is requested and the pane is not already focused).
    /// Those APIs notify `didSelectTab` / `didFocusPane`, which are the sole owners of
    /// ``publishFocusedToolModeMirror()`` (VAL-RAIL-002 / VAL-RAIL-009). Do not write
    /// the derived legacy mirror from this method.
    @discardableResult
    func selectToolMode(_ mode: RightSidebarMode, focus: Bool = true) -> Bool {
        guard edge == .right else { return false }
        guard SidebarDockPlacementMatrix.allows(mode: mode) else { return false }
        guard let panel = panels.values
            .compactMap({ $0 as? RightSidebarToolPanel })
            .first(where: { $0.mode == mode }),
              let tabId = surfaceId(forPanelId: panel.id) else {
            return false
        }
        // selectTab always notifies didSelectTab → callback-owned mirror publish.
        // It also focuses the tab's pane internally (without didFocusPane).
        bonsplitController.selectTab(tabId)
        if focus, let pane = paneId(forTabId: tabId) {
            // Only emit didFocusPane when the focused pane still differs so a
            // same-section tab switch publishes the mirror exactly once.
            if bonsplitController.focusedPaneId?.id != pane.id {
                bonsplitController.focusPane(pane)
            }
        }
        return focusedToolMode() == mode
    }

    /// Hidden-rail short-circuit: mount tool content only while visible (VAL-RAIL-010).
    func setToolContentMounted(_ mounted: Bool) {
        if mounted {
            guard !isToolContentMounted else { return }
            isToolContentMounted = true
            toolContentMountGeneration += 1
        } else {
            guard isToolContentMounted else { return }
            isToolContentMounted = false
            toolContentUnmountGeneration += 1
        }
    }

    /// Publish the derived legacy mode from the focused section's selection.
    func publishFocusedToolModeMirror() {
        guard edge == .right else { return }
        onFocusedToolModeChanged?(focusedToolMode())
    }

    // MARK: - Move tab to new section (shared drag/context/palette path)

    /// Shared mutation path for drag edge-band, tab context menu, and palette.
    @discardableResult
    func moveTabToNewSection(_ tabId: TabID, position: SidebarDockSectionPosition) -> Bool {
        // Drop/command onto a sole-left collapsed surrogate expands first (D-23).
        if sectionCount == 1, isSoleSectionCollapsed {
            _ = expandSoleSection()
        }
        guard configurationAllowsNewSection() else {
            Self.logger.info("sidebar-dock: geometry refused new section on \(self.edge.rawValue, privacy: .public)")
            return false
        }
        guard surfaceIdToPanelId[tabId] != nil else {
            Self.logger.warning("sidebar-dock: moveTabToNewSection missing tab \(tabId.uuid.uuidString, privacy: .public)")
            return false
        }
        guard let panelId = surfaceIdToPanelId[tabId],
              let panel = panels[panelId],
              SidebarDockPlacementMatrix.allows(panel: panel) else {
            return false
        }

        let insertFirst = position == .top
        // Right-leaning bottom chain: always split the current bottom-most pane
        // with insertFirst=false. Top inserts split the current top-most pane
        // with insertFirst=true.
        let targetPane: PaneID?
        switch position {
        case .bottom:
            targetPane = orderedSectionPaneIds().last
        case .top:
            targetPane = orderedSectionPaneIds().first
        }
        guard let targetPane else { return false }

        // Expand a collapsed target section before the drop lands.
        _ = expandCollapsedForDrop(paneId: targetPane)

        // Programmatic path uses the moving-tab split API so empty-pane
        // auto-close reaps the source when it was the last tab.
        let newPane = bonsplitController.splitPane(
            targetPane,
            orientation: .vertical,
            movingTab: tabId,
            insertFirst: insertFirst
        )
        guard newPane != nil else { return false }
        refreshTabBarVisibility()
        dropOrphanTabs()
        return true
    }

    /// True when removing `tabId` from this rail would leave zero sections (D-18).
    /// Cross-rail consumers must refuse the move when this returns true.
    func wouldEmptyRail(removing tabId: TabID) -> Bool {
        guard sectionCount == 1 else { return false }
        guard let pane = paneId(forTabId: tabId) else { return false }
        let tabs = bonsplitController.tabs(inPane: pane)
        return tabs.count == 1 && tabs.first?.id == tabId
    }

    /// Geometry check: another header must fit without data loss.
    func configurationAllowsNewSection() -> Bool {
        // No application-level section cap. When a host height is known, require
        // room for (sectionCount+1) headers; unknown height always allows.
        guard railContentHeight > 0 else { return true }
        let nextCount = sectionCount + 1
        let minimumNeeded = CGFloat(nextCount) * collapsedSectionHeight
        return railContentHeight + 0.5 >= minimumNeeded
    }

    /// Host reports the current rail content height (from size observer, never body).
    func updateRailContentHeight(_ height: CGFloat) {
        let next = max(0, height)
        guard abs(next - railContentHeight) > 0.5 else { return }
        railContentHeight = next
        reimposeTrailingCollapseIfNeeded()
        reimposeSoleSectionCollapseIfNeeded()
    }

    // MARK: - Collapse / expand

    func isSectionCollapsed(paneId: PaneID) -> Bool {
        if sectionCount == 1 {
            return isSoleSectionCollapsed
        }
        if let parent = parentSplitId(of: paneId) {
            if collapsedSplitIds.contains(parent), isFirstChild(paneId, ofSplit: parent) {
                return true
            }
            if trailingCollapsedParentSplitId == parent, isSecondChild(paneId, ofSplit: parent) {
                return true
            }
        }
        return false
    }

    /// Collapse a section to header height, remembering prior extent.
    @discardableResult
    func collapseSection(paneId: PaneID) -> Bool {
        if bonsplitController.isDividerDragActive {
            if !pendingCollapsePaneIds.contains(where: { $0.id == paneId.id }) {
                pendingCollapsePaneIds.append(paneId)
            }
            return false
        }
        if sectionCount == 1 {
            return collapseSoleSection()
        }
        guard let parent = parentSplitId(of: paneId) else { return false }

        if isFirstChild(paneId, ofSplit: parent) {
            let prior = currentFirstChildExtent(forSplit: parent) ?? (railContentHeight / 2)
            rememberedExtentBySplitId[parent] = prior
            collapsedSplitIds.insert(parent)
            _ = bonsplitController.setImposedFirstExtent(collapsedSectionHeight, forSplit: parent)
            return true
        }

        if isSecondChild(paneId, ofSplit: parent) {
            // Trailing / second-child collapse: impose first-child extent =
            // available - header so the second child shrinks to header height.
            let available = availableExtent(forSplit: parent) ?? railContentHeight
            let priorSecond = max(collapsedSectionHeight, available - (currentFirstChildExtent(forSplit: parent) ?? (available / 2)))
            rememberedExtentBySplitId[parent] = priorSecond
            trailingCollapsedParentSplitId = parent
            let firstExtent = max(collapsedSectionHeight, available - collapsedSectionHeight)
            _ = bonsplitController.setImposedFirstExtent(firstExtent, forSplit: parent)
            return true
        }
        return false
    }

    /// Expand a previously collapsed section, restoring remembered extent.
    @discardableResult
    func expandSection(paneId: PaneID) -> Bool {
        if sectionCount == 1 {
            return expandSoleSection()
        }
        guard let parent = parentSplitId(of: paneId) else { return false }

        if collapsedSplitIds.contains(parent), isFirstChild(paneId, ofSplit: parent) {
            let remembered = rememberedExtentBySplitId[parent]
            collapsedSplitIds.remove(parent)
            rememberedExtentBySplitId.removeValue(forKey: parent)
            _ = bonsplitController.setImposedFirstExtent(nil, forSplit: parent)
            if let remembered, let available = availableExtent(forSplit: parent), available > 0 {
                // Clamp restore so both sides keep at least header height.
                let clamped = clampFirstChildExtent(remembered, available: available)
                let fraction = min(max(clamped / available, 0), 1)
                _ = bonsplitController.setDividerPosition(fraction, forSplit: parent)
            }
            lastExpandedPaneId = paneId.id
            return true
        }

        if trailingCollapsedParentSplitId == parent, isSecondChild(paneId, ofSplit: parent) {
            let remembered = rememberedExtentBySplitId[parent]
            trailingCollapsedParentSplitId = nil
            rememberedExtentBySplitId.removeValue(forKey: parent)
            _ = bonsplitController.setImposedFirstExtent(nil, forSplit: parent)
            if let remembered, let available = availableExtent(forSplit: parent), available > 0 {
                let firstExtent = max(0, available - remembered)
                let clamped = clampFirstChildExtent(firstExtent, available: available)
                let fraction = min(max(clamped / available, 0), 1)
                _ = bonsplitController.setDividerPosition(fraction, forSplit: parent)
            }
            lastExpandedPaneId = paneId.id
            return true
        }
        return false
    }

    @discardableResult
    func toggleSectionCollapsed(paneId: PaneID) -> Bool {
        if isSectionCollapsed(paneId: paneId) {
            return expandSection(paneId: paneId)
        }
        return collapseSection(paneId: paneId)
    }

    /// Expand a collapsed section (any position) or the sole-left surrogate before a drop.
    /// Already-expanded targets succeed as a no-op so drag/context/palette share one path.
    @discardableResult
    func expandCollapsedForDrop(paneId: PaneID?) -> Bool {
        if sectionCount == 1 {
            if isSoleSectionCollapsed {
                return expandSoleSection()
            }
            return true
        }
        guard let paneId else { return false }
        if isSectionCollapsed(paneId: paneId) {
            return expandSection(paneId: paneId)
        }
        return true
    }

    /// Sole left-section collapse into a header-height accessible surrogate (D-23).
    @discardableResult
    func collapseSoleSection() -> Bool {
        guard sectionCount == 1 else { return false }
        if bonsplitController.isDividerDragActive {
            if let pane = orderedSectionPaneIds().first,
               !pendingCollapsePaneIds.contains(where: { $0.id == pane.id }) {
                pendingCollapsePaneIds.append(pane)
            }
            return false
        }
        soleSectionRememberedExtent = railContentHeight > 0 ? railContentHeight : soleSectionRememberedExtent
        isSoleSectionCollapsed = true
        return true
    }

    @discardableResult
    func expandSoleSection() -> Bool {
        guard sectionCount == 1, isSoleSectionCollapsed else { return false }
        isSoleSectionCollapsed = false
        if let pane = orderedSectionPaneIds().first {
            lastExpandedPaneId = pane.id
        }
        // Identity preserved — no tree rebuild. Host restores rail height from
        // soleSectionRememberedExtent via sectionExtent(forPane:).
        return true
    }

    /// Imposed first-child extent currently remembered for tests / restore.
    func rememberedExtent(forPane paneId: PaneID) -> CGFloat? {
        if sectionCount == 1 {
            if isSoleSectionCollapsed {
                return soleSectionRememberedExtent
            }
            return soleSectionRememberedExtent
        }
        guard let parent = parentSplitId(of: paneId) else { return nil }
        return rememberedExtentBySplitId[parent]
    }

    /// Requested collapsed extent (header height) for a collapsed section.
    func imposedCollapsedExtent(forPane paneId: PaneID) -> CGFloat? {
        guard isSectionCollapsed(paneId: paneId) else { return nil }
        return collapsedSectionHeight
    }

    /// Live section extent in points (header height when collapsed).
    /// Uses imposed pins, divider fractions, and the host rail height — no view body.
    func sectionExtent(forPane paneId: PaneID) -> CGFloat? {
        if sectionCount == 1 {
            if isSoleSectionCollapsed {
                return collapsedSectionHeight
            }
            if railContentHeight > 0 { return railContentHeight }
            return soleSectionRememberedExtent
        }
        guard let parent = parentSplitId(of: paneId) else { return nil }
        let available = availableExtent(forSplit: parent) ?? railContentHeight
        guard available > 0 else { return nil }
        if isSectionCollapsed(paneId: paneId) {
            return collapsedSectionHeight
        }
        if isFirstChild(paneId, ofSplit: parent) {
            return currentFirstChildExtent(forSplit: parent)
        }
        if isSecondChild(paneId, ofSplit: parent) {
            let first = currentFirstChildExtent(forSplit: parent) ?? (available / 2)
            return max(0, available - first)
        }
        return nil
    }

    // MARK: - Divider lifecycle

    /// Clamp a first-child extent so both sides keep at least header height.
    func clampFirstChildExtent(_ extent: CGFloat, available: CGFloat) -> CGFloat {
        guard available > collapsedSectionHeight * 2 else {
            return min(max(extent, 0), available)
        }
        return min(max(extent, collapsedSectionHeight), available - collapsedSectionHeight)
    }

    /// Drag-resize the boundary whose first child is `paneId` (or its parent first side).
    /// Collapsed adjacent sections are cleared first so the drag does not fight imposition.
    @discardableResult
    func resizeBoundary(firstChildPane paneId: PaneID, firstChildExtent: CGFloat) -> Bool {
        if isSectionCollapsed(paneId: paneId) {
            prepareDividerDrag(adjacentTo: paneId)
        }
        // Also clear a collapsed second-child sibling if present.
        if let parent = parentSplitId(of: paneId),
           trailingCollapsedParentSplitId == parent {
            if let second = secondChildPane(ofSplit: parent) {
                prepareDividerDrag(adjacentTo: second)
            }
        }
        guard let parent = parentSplitId(of: paneId) else { return false }
        let available = availableExtent(forSplit: parent) ?? railContentHeight
        guard available > 0 else { return false }
        let clamped = clampFirstChildExtent(firstChildExtent, available: available)
        let fraction = clamped / available
        return bonsplitController.setDividerPosition(fraction, forSplit: parent, fromExternal: true)
    }

    /// Called when a boundary drag begins adjacent to a collapsed section:
    /// clears imposition first so the drag does not fight the pin.
    func prepareDividerDrag(adjacentTo paneId: PaneID) {
        guard isSectionCollapsed(paneId: paneId) else { return }
        if sectionCount == 1 {
            // Sole surrogate: expand so content can accept the drag/drop.
            _ = expandSoleSection()
            return
        }
        guard let parent = parentSplitId(of: paneId) else { return }
        // Clear imposition without restoring remembered expand state — the
        // drag owns the divider from here.
        collapsedSplitIds.remove(parent)
        if trailingCollapsedParentSplitId == parent {
            trailingCollapsedParentSplitId = nil
        }
        rememberedExtentBySplitId.removeValue(forKey: parent)
        _ = bonsplitController.setImposedFirstExtent(nil, forSplit: parent)
    }

    /// Flush deferred collapse requests after a divider drag ends.
    func flushPendingCollapses() {
        let pending = pendingCollapsePaneIds
        pendingCollapsePaneIds.removeAll()
        for pane in pending {
            _ = collapseSection(paneId: pane)
        }
    }

    func reimposeTrailingCollapseIfNeeded() {
        guard let parent = trailingCollapsedParentSplitId else { return }
        guard !bonsplitController.isDividerDragActive else { return }
        let available = availableExtent(forSplit: parent) ?? railContentHeight
        guard available > 0 else { return }
        let firstExtent = max(collapsedSectionHeight, available - collapsedSectionHeight)
        _ = bonsplitController.setImposedFirstExtent(firstExtent, forSplit: parent)
    }

    func reimposeSoleSectionCollapseIfNeeded() {
        // Sole-section collapse is a chrome surrogate, not a bonsplit pin.
        // Hosts read `isSoleSectionCollapsed` and size the rail content to header height.
        _ = isSoleSectionCollapsed
    }

    // MARK: - Tab ordering / selection / empty teardown

    @discardableResult
    func reorderTab(_ tabId: TabID, toIndex: Int) -> Bool {
        let ok = bonsplitController.reorderTab(tabId, toIndex: toIndex)
        dropOrphanTabs()
        return ok
    }

    @discardableResult
    func selectTab(_ tabId: TabID) -> Bool {
        guard surfaceIdToPanelId[tabId] != nil else { return false }
        bonsplitController.selectTab(tabId)
        return true
    }

    /// Move a tab into another section pane. Emptying the source section
    /// closes it via `autoCloseEmptyPanes` and redistributes extents.
    @discardableResult
    func moveTab(_ tabId: TabID, toPane targetPaneId: PaneID, atIndex index: Int? = nil) -> Bool {
        guard surfaceIdToPanelId[tabId] != nil else { return false }
        // Expand collapsed destination before the drop (shared drag path).
        _ = expandCollapsedForDrop(paneId: targetPaneId)
        // D-18: refuse moves that would leave zero sections on this rail.
        // Within-rail moves that empty a non-final section still tear down that section only.
        if wouldEmptyRail(removing: tabId),
           paneId(forTabId: tabId)?.id != targetPaneId.id {
            // Sole section with one tab cannot leave the rail for another pane
            // that is not itself — there is no other pane in a one-section rail.
            Self.logger.info("sidebar-dock: refused move that would empty \(self.edge.rawValue, privacy: .public) rail")
            return false
        }
        let before = sectionCount
        let beforeSelection = sectionSnapshots().map(\.selectedPanelId)
        let ok = bonsplitController.moveTab(tabId, toPane: targetPaneId, atIndex: index)
        if ok {
            dropOrphanTabs()
            refreshTabBarVisibility()
            if sectionCount < before {
                // Empty section torn down; clear stale collapse state and
                // redistribute surviving extents via bonsplit auto-layout.
                pruneCollapseState()
            }
            // Selection remains authoritative for panes that still exist.
            _ = beforeSelection
        }
        return ok
    }

    /// Close a tab; last tab in a non-final section tears the section down.
    @discardableResult
    func closeTab(_ tabId: TabID) -> Bool {
        let before = sectionCount
        let ok = bonsplitController.closeTab(tabId)
        if ok {
            if let panelId = surfaceIdToPanelId.removeValue(forKey: tabId) {
                panels.removeValue(forKey: panelId)
            }
            dropOrphanTabs()
            refreshTabBarVisibility()
            if sectionCount < before {
                pruneCollapseState()
            }
        }
        return ok
    }

    // MARK: - Whole-section reorder

    /// Deterministic whole-section reorder (header drag and command path share this).
    @discardableResult
    func reorderSection(from fromIndex: Int, to toIndex: Int) -> Bool {
        var snaps = sectionSnapshots()
        guard snaps.indices.contains(fromIndex),
              snaps.indices.contains(toIndex),
              fromIndex != toIndex else { return false }

        let item = snaps.remove(at: fromIndex)
        snaps.insert(item, at: toIndex)
        return rebuildSections(from: snaps)
    }

    /// Rebuild the vertical chain from complete section snapshots, preserving
    /// tabs, selection, collapse, and remembered extents.
    @discardableResult
    func rebuildSections(from snapshots: [SidebarDockSectionSnapshot]) -> Bool {
        guard !snapshots.isEmpty else { return false }

        // Capture live panels in snapshot order.
        var orderedPanelGroups: [[any Panel]] = []
        var selectedIds: [UUID?] = []
        var collapsedFlags: [Bool] = []
        var remembered: [CGFloat?] = []
        for snap in snapshots {
            let group: [any Panel] = snap.tabPanelIds.compactMap { panels[$0] }
            guard !group.isEmpty else { continue }
            orderedPanelGroups.append(group)
            selectedIds.append(snap.selectedPanelId)
            collapsedFlags.append(snap.isCollapsed)
            remembered.append(snap.rememberedExtent)
        }
        guard !orderedPanelGroups.isEmpty else { return false }

        // Clear bonsplit tabs without destroying panel instances.
        for tabId in bonsplitController.allTabIds {
            _ = bonsplitController.closeTab(tabId)
        }
        surfaceIdToPanelId.removeAll()
        collapsedSplitIds.removeAll()
        trailingCollapsedParentSplitId = nil
        rememberedExtentBySplitId.removeAll()
        isSoleSectionCollapsed = false
        // Ensure panels map still holds every panel we will re-attach.
        for group in orderedPanelGroups {
            for panel in group {
                panels[panel.id] = panel
            }
        }

        guard let root = bonsplitController.allPaneIds.first else { return false }
        // Seed first section into root.
        for panel in orderedPanelGroups[0] {
            _ = attachPanel(panel, inPane: root, select: false)
        }
        if let sel = selectedIds[0], let tab = surfaceId(forPanelId: sel) {
            bonsplitController.selectTab(tab)
        } else if let first = bonsplitController.tabs(inPane: root).first {
            bonsplitController.selectTab(first.id)
        }

        // Append remaining sections at the bottom (right-leaning vertical chain).
        for groupIndex in 1..<orderedPanelGroups.count {
            let group = orderedPanelGroups[groupIndex]
            guard let firstPanel = group.first else { continue }
            guard let bottom = orderedSectionPaneIds().last else { continue }

            // Temporarily attach the first panel of this group into bottom, then
            // split it out so it becomes its own section.
            guard let tabToMove = {
                if let existing = surfaceId(forPanelId: firstPanel.id) { return existing }
                return attachPanel(firstPanel, inPane: bottom, select: false)
            }() else { continue }

            let newPane = bonsplitController.splitPane(
                bottom,
                orientation: .vertical,
                movingTab: tabToMove,
                insertFirst: false
            )
            guard let newPane else { continue }
            for panel in group.dropFirst() {
                if surfaceId(forPanelId: panel.id) == nil {
                    _ = attachPanel(panel, inPane: newPane, select: false)
                } else if let tab = surfaceId(forPanelId: panel.id) {
                    _ = bonsplitController.moveTab(tab, toPane: newPane)
                }
            }
            if let sel = selectedIds[groupIndex], let tab = surfaceId(forPanelId: sel) {
                bonsplitController.selectTab(tab)
            }
        }

        // Re-apply collapse state by index.
        let panes = orderedSectionPaneIds()
        for (index, pane) in panes.enumerated() where index < collapsedFlags.count {
            if collapsedFlags[index] {
                if let ext = remembered[index] {
                    // Seed remembered extent before collapse.
                    if let parent = parentSplitId(of: pane) {
                        rememberedExtentBySplitId[parent] = ext
                    } else if panes.count == 1 {
                        soleSectionRememberedExtent = ext
                    }
                }
                _ = collapseSection(paneId: pane)
            }
        }
        refreshTabBarVisibility()
        dropOrphanTabs()
        return true
    }

    // MARK: - BonsplitDelegate

    func splitTabBar(
        _ controller: BonsplitController,
        shouldSplitPane pane: PaneID,
        orientation: SplitOrientation
    ) -> Bool {
        // D-11: refuse side-by-side; never refuse stacked vertical.
        orientation == .vertical
    }

    func splitTabBar(
        _ controller: BonsplitController,
        didSplitPane originalPane: PaneID,
        newPane: PaneID,
        orientation: SplitOrientation
    ) {
        // Seed a placeholder is unnecessary for programmatic moving-tab splits;
        // ensure tab bar visibility tracks section count.
        refreshTabBarVisibility()
    }

    func splitTabBar(
        _ controller: BonsplitController,
        didSelectTab tab: Bonsplit.Tab,
        inPane pane: PaneID
    ) {
        // Sole mirror write path for rail tool selection (VAL-RAIL-002/009).
        // Must use Bonsplit.Tab — app module has `typealias Tab = Workspace`, which
        // would otherwise produce a non-witness overload and the empty default body.
        _ = tab
        _ = pane
        onRailFocusChanged?()
        publishFocusedToolModeMirror()
    }

    func splitTabBar(
        _ controller: BonsplitController,
        didFocusPane pane: PaneID
    ) {
        // Focused section's selected tab defines the derived legacy mode.
        _ = pane
        onRailFocusChanged?()
        publishFocusedToolModeMirror()
    }

    // MARK: - Actor wiring seams (palette / context / header)

    /// RED stub: production tab context destinations land in green wiring.
    func tabContextMoveDestinationsForActor(tabId: TabID) -> [TabContextMoveDestination] {
        _ = tabId
        return []
    }

    /// RED stub: destination selection must route through the invoker in green.
    @discardableResult
    func handleTabContextMoveDestination(_ destinationId: String, for tabId: TabID) -> Bool {
        _ = destinationId
        _ = tabId
        return false
    }

    /// RED stub: section context menu items for the focused/clicked pane.
    func sectionContextMenuItems(for paneId: PaneID?) -> [SidebarDockCommand.MenuItem] {
        _ = paneId
        return []
    }

    /// RED stub: run a section context-menu command through the shared invoker.
    @discardableResult
    func performSectionContextMenuCommand(_ commandId: String, paneId: PaneID?) -> Bool {
        _ = commandId
        _ = paneId
        return false
    }

    /// RED stub: immutable focused-section header control snapshot.
    func focusedSectionHeaderControlsSnapshot() -> SidebarDockSectionHeaderControlsSnapshot? {
        return nil
    }

    /// Handle Bonsplit "Move Tab" destination ids for new-section commands.
    func splitTabBar(
        _ controller: BonsplitController,
        didRequestTabMoveToDestination destinationId: String,
        for tab: Bonsplit.Tab,
        inPane pane: PaneID
    ) {
        _ = controller
        _ = pane
        // RED: unconnected until green wiring installs invoker routing.
        _ = destinationId
        _ = tab
    }

    func splitTabBar(
        _ controller: BonsplitController,
        shouldCreateTab tab: Bonsplit.Tab,
        inPane pane: PaneID
    ) -> Bool {
        // Allow programmatic creates; external unknown kinds still go through
        // attachPanel which enforces the placement matrix.
        // Use Bonsplit.Tab (not app `Tab` alias) so this is the real protocol witness.
        _ = tab
        return true
    }

    func splitTabBar(_ controller: BonsplitController, shouldNotifyDuringDrag: Bool) -> Bool {
        // Need drag-end notifications so deferred collapses flush.
        true
    }

    func splitTabBar(
        _ controller: BonsplitController,
        didChangeGeometry snapshot: LayoutSnapshot
    ) {
        if !controller.isDividerDragActive {
            flushPendingCollapses()
            reimposeTrailingCollapseIfNeeded()
        }
    }

    func splitTabBarDividerDragDidBegin(_ controller: BonsplitController) {
        // Drag owns geometry — do not re-impose while active.
    }

    func splitTabBarDividerDragDidEnd(_ controller: BonsplitController) {
        flushPendingCollapses()
        reimposeTrailingCollapseIfNeeded()
    }

    // MARK: - Orphans

    /// Drop tab→panel mappings with no live panel (log + remove tab).
    func dropOrphanTabs() {
        var orphans: [TabID] = []
        for (tabId, panelId) in surfaceIdToPanelId {
            if panels[panelId] == nil {
                orphans.append(tabId)
            }
        }
        for tabId in orphans {
            Self.logger.warning("sidebar-dock: dropping orphan tab \(tabId.uuid.uuidString, privacy: .public) on \(self.edge.rawValue, privacy: .public)")
            surfaceIdToPanelId.removeValue(forKey: tabId)
            _ = bonsplitController.closeTab(tabId)
        }
        // Also drop panel entries with no surface mapping.
        let livePanelIds = Set(surfaceIdToPanelId.values)
        for panelId in panels.keys where !livePanelIds.contains(panelId) {
            // Keep only if still referenced — otherwise remove.
            // Panels mid-transfer may be absent from tabs briefly; only drop
            // when the tab list is stable and no tab points at them.
            if bonsplitController.allTabIds.allSatisfy({ surfaceIdToPanelId[$0] != panelId }) {
                // Leave orphan panels that were never tabbed out of the map only
                // if they still exist in surfaceIdToPanelId (handled above).
                _ = panelId
            }
        }
        refreshTabBarVisibility()
    }

    // MARK: - Tree helpers

    private func leafPaneIds(in node: ExternalTreeNode) -> [PaneID] {
        switch node {
        case .pane(let pane):
            guard let uuid = UUID(uuidString: pane.id) else {
                Self.logger.error("sidebar-dock: invalid pane id in tree snapshot: \(pane.id, privacy: .public)")
                return []
            }
            return [PaneID(id: uuid)]
        case .split(let split):
            return leafPaneIds(in: split.first) + leafPaneIds(in: split.second)
        }
    }

    private func parentSplitId(of paneId: PaneID) -> UUID? {
        guard let split = findParentSplit(of: paneId, in: bonsplitController.treeSnapshot()) else {
            return nil
        }
        return UUID(uuidString: split.id)
    }

    private func findParentSplit(of paneId: PaneID, in node: ExternalTreeNode) -> ExternalSplitNode? {
        switch node {
        case .pane:
            return nil
        case .split(let split):
            if case .pane(let p) = split.first, p.id == paneId.id.uuidString {
                return split
            }
            if case .pane(let p) = split.second, p.id == paneId.id.uuidString {
                return split
            }
            if let found = findParentSplit(of: paneId, in: split.first) { return found }
            if let found = findParentSplit(of: paneId, in: split.second) { return found }
            // Also match when first/second are deeper and this split is the
            // immediate parent of a leaf search — recurse already covers that.
            return nil
        }
    }

    private func isFirstChild(_ paneId: PaneID, ofSplit splitId: UUID) -> Bool {
        guard let split = findSplit(splitId, in: bonsplitController.treeSnapshot()) else { return false }
        if case .pane(let p) = split.first { return p.id == paneId.id.uuidString }
        // For non-leaf first children, treat any leaf under first as "first side".
        return leafPaneIds(in: split.first).contains(where: { $0.id == paneId.id })
            && !leafPaneIds(in: split.second).contains(where: { $0.id == paneId.id })
    }

    private func isSecondChild(_ paneId: PaneID, ofSplit splitId: UUID) -> Bool {
        guard let split = findSplit(splitId, in: bonsplitController.treeSnapshot()) else { return false }
        if case .pane(let p) = split.second { return p.id == paneId.id.uuidString }
        return leafPaneIds(in: split.second).contains(where: { $0.id == paneId.id })
    }

    private func secondChildPane(ofSplit splitId: UUID) -> PaneID? {
        guard let split = findSplit(splitId, in: bonsplitController.treeSnapshot()) else { return nil }
        return leafPaneIds(in: split.second).last
    }

    private func findSplit(_ splitId: UUID, in node: ExternalTreeNode) -> ExternalSplitNode? {
        switch node {
        case .pane:
            return nil
        case .split(let split):
            if split.id == splitId.uuidString { return split }
            if let found = findSplit(splitId, in: split.first) { return found }
            if let found = findSplit(splitId, in: split.second) { return found }
            return nil
        }
    }

    private func currentFirstChildExtent(forSplit splitId: UUID) -> CGFloat? {
        guard let split = findSplit(splitId, in: bonsplitController.treeSnapshot()) else { return nil }
        if let imposed = split.imposedFirstExtent {
            return CGFloat(imposed)
        }
        let available = availableExtent(forSplit: splitId) ?? railContentHeight
        guard available > 0 else { return nil }
        return CGFloat(split.dividerPosition) * available
    }

    private func availableExtent(forSplit splitId: UUID) -> CGFloat? {
        // Prefer layout snapshot pane frames if they have real height; fall back
        // to host-reported rail height (unit tests and pre-layout mounts).
        let snap = bonsplitController.layoutSnapshot()
        guard let split = findSplit(splitId, in: bonsplitController.treeSnapshot()) else {
            return railContentHeight > 0 ? railContentHeight : nil
        }
        let leaves = leafPaneIds(in: .split(split))
        let heights = leaves.compactMap { pane -> CGFloat? in
            snap.panes.first(where: { $0.paneId == pane.id.uuidString }).map { CGFloat($0.frame.height) }
        }
        let sum = heights.reduce(0, +)
        // Zero-height layout frames are not useful (no host view yet).
        if sum > 0.5 {
            return sum
        }
        return railContentHeight > 0 ? railContentHeight : nil
    }

    private func pruneCollapseState() {
        let liveSplitIds = allSplitIds(in: bonsplitController.treeSnapshot())
        collapsedSplitIds = collapsedSplitIds.intersection(liveSplitIds)
        if let trailing = trailingCollapsedParentSplitId, !liveSplitIds.contains(trailing) {
            trailingCollapsedParentSplitId = nil
        }
        rememberedExtentBySplitId = rememberedExtentBySplitId.filter { liveSplitIds.contains($0.key) }
        if sectionCount != 1 {
            isSoleSectionCollapsed = false
        }
    }

    private func allSplitIds(in node: ExternalTreeNode) -> Set<UUID> {
        switch node {
        case .pane:
            return []
        case .split(let split):
            var set: Set<UUID> = []
            if let id = UUID(uuidString: split.id) { set.insert(id) }
            set.formUnion(allSplitIds(in: split.first))
            set.formUnion(allSplitIds(in: split.second))
            return set
        }
    }
}
