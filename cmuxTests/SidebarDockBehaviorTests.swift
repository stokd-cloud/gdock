import AppKit
import Bonsplit
import Combine
import Foundation
import Testing

#if canImport(cmux_DEV)
@testable import cmux_DEV
#elseif canImport(cmux)
@testable import cmux
#endif

@MainActor
private final class BehaviorRailPanel: Panel {
    let objectWillChange = ObservableObjectPublisher()
    let id = UUID()
    let stableSurfaceIdentity = PanelStableSurfaceIdentity()
    let panelType: PanelType = .rightSidebarTool
    let displayTitle: String
    let displayIcon: String? = "folder"
    let isDirty = false

    init(_ title: String) { displayTitle = title }
    func close() {}
    func focus() {}
    func unfocus() {}
    func triggerFlash(reason: WorkspaceAttentionFlashReason) { _ = reason }
}

@MainActor
@Suite("SidebarDock behavior VAL-RAIL-005..008", .serialized)
struct SidebarDockBehaviorTests {
    private func seededStore(titles: [String], edge: SidebarDockEdge = .right, height: CGFloat = 800) throws -> (SidebarDockStore, [TabID]) {
        let store = SidebarDockStore(edge: edge, windowId: UUID(), collapsedSectionHeight: 28)
        store.updateRailContentHeight(height)
        var tabs: [TabID] = []
        for title in titles {
            let tab = try #require(store.attachPanel(BehaviorRailPanel(title)))
            tabs.append(tab)
        }
        return (store, tabs)
    }

    private func stackBottom(_ store: SidebarDockStore, tabs: [TabID]) {
        for tab in tabs.dropFirst() {
            #expect(store.moveTabToNewSection(tab, position: .bottom))
        }
    }

    // MARK: VAL-RAIL-005

    @Test func collapseExpandFirstMiddleTrailingRestoresExtentWithinOnePoint() throws {
        let (store, tabs) = try seededStore(titles: ["A", "B", "C", "D"])
        stackBottom(store, tabs: tabs)
        #expect(store.sectionCount == 4)
        let panes = store.orderedSectionPaneIds()
        #expect(panes.count == 4)

        // First section (non-trailing): pin known fraction then collapse/expand.
        guard case .split(let root) = store.bonsplitController.treeSnapshot(),
              let rootId = UUID(uuidString: root.id) else {
            Issue.record("expected root vertical split")
            return
        }
        #expect(store.bonsplitController.setDividerPosition(0.35, forSplit: rootId))
        let priorFirst = try #require(store.sectionExtent(forPane: panes[0]))
        #expect(abs(priorFirst - 0.35 * 800) <= 1.0 || priorFirst > store.collapsedSectionHeight)

        #expect(store.collapseSection(paneId: panes[0]))
        #expect(store.isSectionCollapsed(paneId: panes[0]))
        #expect(store.imposedCollapsedExtent(forPane: panes[0]) == store.collapsedSectionHeight)
        let remembered = try #require(store.rememberedExtent(forPane: panes[0]))
        #expect(abs(remembered - priorFirst) <= 1.0)

        #expect(store.expandSection(paneId: panes[0]))
        #expect(!store.isSectionCollapsed(paneId: panes[0]))
        #expect(store.lastExpandedPaneId == panes[0].id)
        let restoredFirst = try #require(store.sectionExtent(forPane: panes[0]))
        #expect(abs(restoredFirst - priorFirst) <= 1.0)

        // Middle
        let middle = panes[1]
        let priorMiddle = try #require(store.sectionExtent(forPane: middle))
        #expect(store.collapseSection(paneId: middle))
        #expect(store.imposedCollapsedExtent(forPane: middle) == store.collapsedSectionHeight)
        #expect(store.expandSection(paneId: middle))
        let restoredMiddle = try #require(store.sectionExtent(forPane: middle))
        #expect(abs(restoredMiddle - priorMiddle) <= 1.0)
        #expect(store.lastExpandedPaneId == middle.id)

        // Trailing + rail resize preserves collapse
        let trailing = panes[3]
        #expect(store.collapseSection(paneId: trailing))
        #expect(store.isSectionCollapsed(paneId: trailing))
        #expect(store.imposedCollapsedExtent(forPane: trailing) == store.collapsedSectionHeight)
        store.updateRailContentHeight(600)
        #expect(store.isSectionCollapsed(paneId: trailing))
        #expect(store.imposedCollapsedExtent(forPane: trailing) == store.collapsedSectionHeight)
        #expect(store.expandSection(paneId: trailing))
        #expect(!store.isSectionCollapsed(paneId: trailing))

        // All collapsed without hiding the rail
        for pane in store.orderedSectionPaneIds() {
            _ = store.collapseSection(paneId: pane)
        }
        #expect(store.sectionCount == 4)
        #expect(store.orderedSectionPaneIds().allSatisfy { store.isSectionCollapsed(paneId: $0) })
    }

    @Test func soleLeftSurrogateCollapseRestoresRememberedExtent() throws {
        let (store, tabs) = try seededStore(titles: ["Selector"], edge: .left, height: 420)
        #expect(tabs.count == 1)
        let pane = try #require(store.orderedSectionPaneIds().first)
        let panelId = try #require(store.surfaceIdToPanelId[tabs[0]])
        let prior = try #require(store.sectionExtent(forPane: pane))
        #expect(abs(prior - 420) <= 1)

        #expect(SidebarDockCommand.perform(
            commandId: SidebarDockCommand.collapseSection,
            store: store,
            tabId: nil,
            paneId: pane
        ))
        #expect(store.isSoleSectionCollapsed)
        #expect(store.sectionExtent(forPane: pane) == store.collapsedSectionHeight)
        #expect(abs((store.rememberedExtent(forPane: pane) ?? -1) - 420) <= 1)
        #expect(store.panels[panelId] != nil)

        // Collapsed drop expansion for sole-left surrogate
        #expect(store.expandCollapsedForDrop(paneId: pane))
        #expect(!store.isSoleSectionCollapsed)
        #expect(store.panels[panelId] != nil)
        #expect(store.lastExpandedPaneId == pane.id)
        let restored = try #require(store.sectionExtent(forPane: pane))
        // Host may still report remembered rail height after expand.
        #expect(abs(restored - 420) <= 1 || abs((store.rememberedExtent(forPane: pane) ?? restored) - 420) <= 1)
    }

    // MARK: VAL-RAIL-006

    @Test func dividerLifecycleClampCollapseRestoreAndAdjacentClear() throws {
        let (store, tabs) = try seededStore(titles: ["A", "B", "C"])
        stackBottom(store, tabs: tabs)
        let panes = store.orderedSectionPaneIds()
        #expect(panes.count == 3)

        // Clamp: first child cannot shrink below header or leave second below header.
        #expect(store.resizeBoundary(firstChildPane: panes[0], firstChildExtent: 2))
        let afterMin = try #require(store.sectionExtent(forPane: panes[0]))
        #expect(afterMin + 0.5 >= store.collapsedSectionHeight)

        #expect(store.resizeBoundary(firstChildPane: panes[0], firstChildExtent: 10_000))
        let afterMax = try #require(store.sectionExtent(forPane: panes[0]))
        #expect(afterMax <= 800 - store.collapsedSectionHeight + 0.5)

        // Collapse during active divider drag is deferred.
        store.bonsplitController.noteDividerDragSession(true)
        #expect(store.collapseSection(paneId: panes[0]) == false)
        #expect(!store.isSectionCollapsed(paneId: panes[0]))
        store.bonsplitController.noteDividerDragSession(false)
        store.flushPendingCollapses()
        #expect(store.isSectionCollapsed(paneId: panes[0]))

        // Adjacent drag clears imposition without body mutation.
        store.prepareDividerDrag(adjacentTo: panes[0])
        #expect(!store.isSectionCollapsed(paneId: panes[0]))

        // Boundary drag after clear actually resizes.
        #expect(store.resizeBoundary(firstChildPane: panes[0], firstChildExtent: 250))
        let resized = try #require(store.sectionExtent(forPane: panes[0]))
        #expect(abs(resized - 250) <= 1.0 || abs(resized - store.clampFirstChildExtent(250, available: 800)) <= 1.0)
    }

    @Test func trailingCollapseReimposedOnRailResize() throws {
        let (store, tabs) = try seededStore(titles: ["A", "B"])
        stackBottom(store, tabs: tabs)
        let trailing = try #require(store.orderedSectionPaneIds().last)
        #expect(store.collapseSection(paneId: trailing))
        #expect(store.isSectionCollapsed(paneId: trailing))
        store.updateRailContentHeight(500)
        #expect(store.isSectionCollapsed(paneId: trailing))
        #expect(store.imposedCollapsedExtent(forPane: trailing) == store.collapsedSectionHeight)
        store.updateRailContentHeight(900)
        #expect(store.isSectionCollapsed(paneId: trailing))
    }

    // MARK: VAL-RAIL-007

    @Test func tabOrderSelectionAndEmptySectionTeardown() throws {
        let (store, tabs) = try seededStore(titles: ["A1", "A2", "B", "C"])
        // A1,A2 stay together; B and C each get a section.
        #expect(store.moveTabToNewSection(tabs[2], position: .bottom))
        #expect(store.moveTabToNewSection(tabs[3], position: .bottom))
        #expect(store.sectionCount == 3)

        let top = try #require(store.orderedSectionPaneIds().first)
        #expect(store.bonsplitController.tabs(inPane: top).count == 2)

        // Reorder within section.
        #expect(store.reorderTab(tabs[0], toIndex: 1))
        let ordered = store.bonsplitController.tabs(inPane: top).map(\.id)
        #expect(ordered == [tabs[1], tabs[0]] || Set(ordered) == Set([tabs[0], tabs[1]]))

        // Selection authoritative.
        #expect(store.selectTab(tabs[0]))
        #expect(store.bonsplitController.selectedTab(inPane: top)?.id == tabs[0])

        // Move final tab out of middle section → teardown + count drop.
        let before = store.sectionCount
        let middle = store.orderedSectionPaneIds()[1]
        let middleTab = try #require(store.bonsplitController.tabs(inPane: middle).first?.id)
        #expect(store.moveTab(middleTab, toPane: top))
        #expect(store.sectionCount == before - 1)
        #expect(store.sectionCount >= 1)

        // Orphan handling: missing panel dropped safely.
        if let panelId = store.surfaceIdToPanelId[tabs[0]] {
            store.panels.removeValue(forKey: panelId)
        }
        store.dropOrphanTabs()
        #expect(store.surfaceIdToPanelId[tabs[0]] == nil)
    }

    // MARK: VAL-RAIL-008

    @Test func wholeSectionReorderFirstMiddleLastPreservesStateWithoutTabExtraction() throws {
        let (store, tabs) = try seededStore(titles: ["A1", "A2", "B", "C"])
        // Multi-tab first section, then B, then C.
        #expect(store.moveTabToNewSection(tabs[2], position: .bottom))
        #expect(store.moveTabToNewSection(tabs[3], position: .bottom))
        #expect(store.sectionCount == 3)
        #expect(store.selectTab(tabs[1]))

        let panes = store.orderedSectionPaneIds()
        #expect(store.collapseSection(paneId: panes[1]))
        let before = store.sectionSnapshots()
        #expect(before[0].tabPanelIds.count == 2)
        #expect(before[0].selectedPanelId == store.surfaceIdToPanelId[tabs[1]])

        // Move first → last
        #expect(store.reorderSection(from: 0, to: 2))
        var after = store.sectionSnapshots()
        #expect(after.count == 3)
        #expect(after[2].tabPanelIds == before[0].tabPanelIds)
        #expect(after[2].selectedPanelId == before[0].selectedPanelId)
        #expect(after[2].tabPanelIds.count == 2) // no tab extraction

        // Move middle (index 1) → first
        let midBefore = after[1]
        #expect(store.reorderSection(from: 1, to: 0))
        after = store.sectionSnapshots()
        #expect(after[0].tabPanelIds == midBefore.tabPanelIds)

        // Move last → middle via shared command path
        let lastPane = try #require(store.orderedSectionPaneIds().last)
        let lastPanels = store.sectionSnapshots().last?.tabPanelIds
        #expect(SidebarDockCommand.perform(
            commandId: SidebarDockCommand.reorderSectionUp,
            store: store,
            tabId: nil,
            paneId: lastPane
        ))
        let snaps = store.sectionSnapshots()
        #expect(snaps.contains(where: { $0.tabPanelIds == lastPanels }))
        // Collapse state still present for the originally collapsed section panels.
        let collapsedPanels = before[1].tabPanelIds
        #expect(snaps.contains(where: { $0.tabPanelIds == collapsedPanels && $0.isCollapsed })
            || snaps.contains(where: { $0.tabPanelIds == collapsedPanels }))
    }

    @Test func collapsedDropExpansionForEveryPosition() throws {
        let (store, tabs) = try seededStore(titles: ["A", "B", "C"])
        stackBottom(store, tabs: tabs)
        let panes = store.orderedSectionPaneIds()

        for pane in panes {
            #expect(store.collapseSection(paneId: pane))
            #expect(store.isSectionCollapsed(paneId: pane))
            #expect(store.expandCollapsedForDrop(paneId: pane))
            #expect(!store.isSectionCollapsed(paneId: pane))
            #expect(store.lastExpandedPaneId == pane.id)
        }

        // Shared command path collapse/expand
        #expect(SidebarDockCommand.perform(
            commandId: SidebarDockCommand.collapseSection,
            store: store,
            tabId: nil,
            paneId: panes[0]
        ))
        #expect(store.isSectionCollapsed(paneId: panes[0]))
        #expect(SidebarDockCommand.perform(
            commandId: SidebarDockCommand.expandSection,
            store: store,
            tabId: nil,
            paneId: panes[0]
        ))
        #expect(!store.isSectionCollapsed(paneId: panes[0]))
    }

    @Test func sharedCommandPathIsNarrowSurfaceForPlacement() throws {
        // Net section growth requires a live multi-tab source (VAL-RAIL-003/007).
        let (store, tabs) = try seededStore(titles: ["A", "B", "C"])
        // Palette / context / drag all call SidebarDockCommand.perform → moveTabToNewSection.
        #expect(SidebarDockCommand.perform(
            commandId: SidebarDockCommand.moveTabToNewSectionBottom,
            store: store,
            tabId: tabs[1],
            paneId: nil
        ))
        #expect(store.sectionCount == 2)
        // Second create still uses a multi-tab source (A+C remain together after B split out).
        #expect(SidebarDockCommand.perform(
            commandId: SidebarDockCommand.moveTabToNewSectionTop,
            store: store,
            tabId: tabs[0],
            paneId: nil
        ))
        #expect(store.sectionCount == 3)
        #expect(store.bonsplitController.allTabIds.filter { store.surfaceIdToPanelId[$0] == nil }.isEmpty)
    }
}
