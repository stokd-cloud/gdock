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
private final class LiveSectionRailPanel: Panel {
    let objectWillChange = ObservableObjectPublisher()
    let id = UUID()
    let stableSurfaceIdentity = PanelStableSurfaceIdentity()
    let panelType: PanelType
    let displayTitle: String
    let displayIcon: String? = "folder"
    let isDirty = false

    init(_ title: String, panelType: PanelType = .rightSidebarTool) {
        self.displayTitle = title
        self.panelType = panelType
    }
    func close() {}
    func focus() {}
    func unfocus() {}
    func triggerFlash(reason: WorkspaceAttentionFlashReason) { _ = reason }
}

/// VAL-RAIL-003/004/007 live section/drop/tab semantics (D-32).
///
/// Red suite for residual Empty panes after sole-tab create, final-tab
/// teardown, live center no-op, allowed/disallowed matrix, tab reorder /
/// selection / orphan handling, narrow command availability, and DEBUG
/// reorder_tab dogfood registration.
@MainActor
@Suite("SidebarDock live section/drop/tab semantics VAL-RAIL-003/004/007", .serialized)
struct SidebarDockLiveSectionSemanticsTests {
    private func seeded(
        titles: [String],
        edge: SidebarDockEdge = .right,
        height: CGFloat = 800
    ) throws -> (SidebarDockStore, [TabID]) {
        let store = SidebarDockStore(edge: edge, windowId: UUID(), collapsedSectionHeight: 28)
        store.updateRailContentHeight(height)
        var tabs: [TabID] = []
        for title in titles {
            let tab = try #require(store.attachPanel(LiveSectionRailPanel(title)))
            tabs.append(tab)
        }
        return (store, tabs)
    }

    private func placeholderEmptyTitles(in store: SidebarDockStore) -> [String] {
        store.orderedSectionPaneIds().flatMap { pane in
            store.bonsplitController.tabs(inPane: pane)
                .map(\.title)
                .filter { $0 == "Empty" }
        }
    }

    private func unmappedTabCount(in store: SidebarDockStore) -> Int {
        store.bonsplitController.allTabIds.filter { store.surfaceIdToPanelId[$0] == nil }.count
    }

    private func liveTabIds(in store: SidebarDockStore) -> [TabID] {
        store.orderedSectionPaneIds().flatMap { pane in
            store.bonsplitController.tabs(inPane: pane)
                .map(\.id)
                .filter { store.surfaceIdToPanelId[$0] != nil }
        }
    }

    private func repoRoot() -> URL {
        URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
    }

    // MARK: VAL-RAIL-003 / VAL-RAIL-007 — no Empty residual; final-tab teardown

    @Test func multiTabCreateLeavesNoEmptyPlaceholderOrUnmappedTab() throws {
        let (store, tabs) = try seeded(titles: ["A", "B", "C"])
        #expect(store.moveTabToNewSection(tabs[1], position: .bottom))
        #expect(store.sectionCount == 2)
        #expect(placeholderEmptyTitles(in: store).isEmpty)
        #expect(unmappedTabCount(in: store) == 0)
        #expect(store.surfaceIdToPanelId.count == 3)
        #expect(Set(liveTabIds(in: store)) == Set(tabs))
    }

    @Test func finalTabMoveOutClosesSectionWithoutEmptyResidual() throws {
        let (store, tabs) = try seeded(titles: ["A1", "A2", "B", "C"])
        // Multi-tab top + sole middle + sole trailing.
        #expect(store.moveTabToNewSection(tabs[2], position: .bottom))
        #expect(store.moveTabToNewSection(tabs[3], position: .bottom))
        #expect(store.sectionCount == 3)
        #expect(placeholderEmptyTitles(in: store).isEmpty)

        let top = try #require(store.orderedSectionPaneIds().first)
        let middle = store.orderedSectionPaneIds()[1]
        let middleTab = try #require(
            store.bonsplitController.tabs(inPane: middle)
                .map(\.id)
                .first(where: { store.surfaceIdToPanelId[$0] != nil })
        )
        let before = store.sectionCount
        #expect(store.selectTab(tabs[0]))
        #expect(store.bonsplitController.selectedTab(inPane: top)?.id == tabs[0])

        #expect(store.moveTab(middleTab, toPane: top))
        #expect(store.sectionCount == before - 1)
        #expect(placeholderEmptyTitles(in: store).isEmpty)
        #expect(unmappedTabCount(in: store) == 0)
        #expect(store.surfaceIdToPanelId[middleTab] != nil)
        // Selection on the destination remains authoritative (not stale/nil).
        #expect(store.bonsplitController.selectedTab(inPane: top) != nil)
    }

    @Test func soleTabCreateDoesNotLeaveEmptyPlaceholderSection() throws {
        // Stack to three sole-tab sections, then "create" from the trailing sole tab
        // (source == target for bottom split). Must not leave residual Empty.
        let (store, tabs) = try seeded(titles: ["A", "B", "C"])
        #expect(store.moveTabToNewSection(tabs[1], position: .bottom))
        #expect(store.moveTabToNewSection(tabs[2], position: .bottom))
        #expect(store.sectionCount == 3)
        #expect(placeholderEmptyTitles(in: store).isEmpty)

        let before = store.sectionCount
        let beforeLive = store.surfaceIdToPanelId.count
        // Final-tab create: either refuses net-growth or relocates without Empty.
        _ = store.moveTabToNewSection(tabs[2], position: .bottom)
        #expect(placeholderEmptyTitles(in: store).isEmpty)
        #expect(unmappedTabCount(in: store) == 0)
        #expect(store.surfaceIdToPanelId.count == beforeLive)
        // No empty-panel-only sections (tabPanelIds empty while pane remains).
        #expect(store.sectionSnapshots().allSatisfy { !$0.tabPanelIds.isEmpty })
        // Section count never inflates via Empty placeholders.
        #expect(store.sectionCount <= before + 1)
        #expect(store.sectionCount >= 1)
    }

    @Test func createFromMultiTabSourceGrowsSectionCountWithoutDuplicates() throws {
        let (store, tabs) = try seeded(titles: ["Files", "Find", "Vault"])
        let before = store.sectionCount
        #expect(store.moveTabToNewSection(tabs[1], position: .bottom))
        #expect(store.sectionCount == before + 1)
        #expect(placeholderEmptyTitles(in: store).isEmpty)
        // No duplicate panel/tab mappings.
        #expect(store.surfaceIdToPanelId.count == 3)
        #expect(Set(store.surfaceIdToPanelId.values).count == 3)
        let titles = store.orderedSectionPaneIds().flatMap { pane in
            store.bonsplitController.tabs(inPane: pane).map(\.title)
        }
        #expect(Set(titles) == Set(["Files", "Find", "Vault"]))
    }

    // MARK: VAL-RAIL-004 — center no-op + allowed/disallowed matrix

    @Test func liveCenterSamePaneDropIsTrueNoop() throws {
        let (store, tabs) = try seeded(titles: ["A", "B", "C"])
        #expect(store.moveTabToNewSection(tabs[1], position: .bottom))
        let pane = try #require(store.paneId(forTabId: tabs[0]))
        let beforeSnaps = store.sectionSnapshots()
        let beforePanels = store.panels.count
        let beforeTabs = store.surfaceIdToPanelId.count
        let outcome = store.handleTabEdgeBandDrop(
            tabId: tabs[0],
            zone: .center,
            targetPaneId: pane
        )
        #expect(outcome == .samePaneNoop)
        #expect(store.sectionSnapshots() == beforeSnaps)
        #expect(store.panels.count == beforePanels)
        #expect(store.surfaceIdToPanelId.count == beforeTabs)
        #expect(placeholderEmptyTitles(in: store).isEmpty)
    }

    @Test func allowedAndDisallowedPlacementMatrixIsLossless() throws {
        let (store, tabs) = try seeded(titles: ["A", "B"])
        #expect(store.moveTabToNewSection(tabs[1], position: .bottom))
        let beforeSnaps = store.sectionSnapshots()
        let beforePanels = store.panels.count
        let beforeTabs = store.surfaceIdToPanelId.count

        // Horizontal refuse lossless.
        for zone: SidebarDockEdgeBand.Zone in [.left, .right] {
            let outcome = store.handleTabEdgeBandDrop(tabId: tabs[0], zone: zone)
            #expect(outcome == .refused(reason: .horizontal))
            #expect(store.sectionSnapshots() == beforeSnaps)
            #expect(store.panels.count == beforePanels)
            #expect(store.surfaceIdToPanelId.count == beforeTabs)
        }

        // Disallowed panel types cannot attach; rail membership unchanged.
        let terminal = LiveSectionRailPanel("Term", panelType: .terminal)
        #expect(store.attachPanel(terminal) == nil)
        #expect(store.panels[terminal.id] == nil)
        #expect(store.sectionSnapshots() == beforeSnaps)

        let browser = LiveSectionRailPanel("Browser", panelType: .browser)
        #expect(store.attachPanel(browser) == nil)
        #expect(store.sectionSnapshots() == beforeSnaps)

        // Allowed tools remain present.
        #expect(store.surfaceIdToPanelId[tabs[0]] != nil)
        #expect(store.surfaceIdToPanelId[tabs[1]] != nil)
        #expect(SidebarDockPlacementMatrix.allows(panelType: .rightSidebarTool))
        #expect(!SidebarDockPlacementMatrix.allows(panelType: .terminal))
        #expect(!SidebarDockPlacementMatrix.allows(panelType: .browser))

        // Drop-handler must expose a lossless disallowed-panel refuse for dogfood.
        let dropSource = try String(
            contentsOf: repoRoot()
                .appendingPathComponent("Sources/Sidebar/SidebarDockDropHandler.swift"),
            encoding: .utf8
        )
        #expect(dropSource.contains("refuseDisallowedPanel"))
        #expect(dropSource.contains("disallowedPanel"))
    }

    // MARK: VAL-RAIL-007 — reorder / selection / orphan

    @Test func tabReorderSelectionAndOrphanHandling() throws {
        let (store, tabs) = try seeded(titles: ["A1", "A2", "B"])
        #expect(store.moveTabToNewSection(tabs[2], position: .bottom))
        let top = try #require(store.orderedSectionPaneIds().first)
        #expect(store.bonsplitController.tabs(inPane: top).count == 2)

        #expect(store.reorderTab(tabs[0], toIndex: 1))
        let ordered = store.bonsplitController.tabs(inPane: top).map(\.id)
        #expect(Set(ordered) == Set([tabs[0], tabs[1]]))
        #expect(ordered.count == 2)

        #expect(store.selectTab(tabs[1]))
        #expect(store.bonsplitController.selectedTab(inPane: top)?.id == tabs[1])

        // Orphan: panel removed while tab map remains → drop safely.
        if let panelId = store.surfaceIdToPanelId[tabs[0]] {
            store.panels.removeValue(forKey: panelId)
        }
        store.dropOrphanTabs()
        #expect(store.surfaceIdToPanelId[tabs[0]] == nil)
        #expect(placeholderEmptyTitles(in: store).isEmpty)
        #expect(store.surfaceIdToPanelId[tabs[1]] != nil)
    }

    // MARK: Narrow command availability (VAL-RAIL-003)

    @Test func narrowWidthCommandsRemainUsableOnProductionPath() throws {
        let (store, tabs) = try seeded(titles: ["A", "B", "C"], height: 400)
        // Production command path must remain usable when drag is unreachable
        // (rail width ≤160). Width channel + invoker path grow sections from a
        // multi-tab source without Empty residuals.
        store.updateRailContentWidth(160)
        #expect(store.railContentWidth <= 160 + 0.5)

        let topOK = SidebarDockCommand.perform(
            commandId: SidebarDockCommand.moveTabToNewSectionTop,
            store: store,
            tabId: tabs[1],
            paneId: nil
        )
        #expect(topOK)
        #expect(store.sectionCount >= 2)
        #expect(placeholderEmptyTitles(in: store).isEmpty)
        #expect(unmappedTabCount(in: store) == 0)

        // Context destinations for a multi-tab source remain non-empty.
        if let multiTab = liveTabIds(in: store).first(where: {
            guard let pane = store.paneId(forTabId: $0) else { return false }
            return store.bonsplitController.tabs(inPane: pane).count > 1
        }) {
            let destinations = SidebarDockCommand.tabMoveDestinations(store: store, tabId: multiTab)
            #expect(!destinations.isEmpty)
        }

        // DEBUG resize_rail must accept width for auditable narrow dogfood.
        let debugSource = try String(
            contentsOf: repoRoot()
                .appendingPathComponent("Sources/TerminalController+SidebarDockDebug.swift"),
            encoding: .utf8
        )
        #expect(debugSource.contains("updateRailContentWidth") || debugSource.contains("rail_content_width"))
    }

    @Test func dropHandlerRefusesDisallowedPanelTypeWithoutMutation() throws {
        let (store, tabs) = try seeded(titles: ["A", "B"])
        let beforeSnaps = store.sectionSnapshots()
        let beforePanels = store.panels.count
        let beforeTabs = store.surfaceIdToPanelId.count
        let outcome = SidebarDockDropHandler.refuseDisallowedPanel(
            store: store,
            panelType: .terminal
        )
        #expect(outcome == .refused(reason: .disallowedPanel))
        #expect(store.sectionSnapshots() == beforeSnaps)
        #expect(store.panels.count == beforePanels)
        #expect(store.surfaceIdToPanelId.count == beforeTabs)
        #expect(store.surfaceIdToPanelId[tabs[0]] != nil)
    }

    // MARK: DEBUG dogfood surface (tab reorder + live resolve)

    @Test func debugTabReorderMethodIsRegisteredAndRoutesToStoreReorder() throws {
        let debugURL = repoRoot()
            .appendingPathComponent("Sources/TerminalController+SidebarDockDebug.swift")
        let source = try String(contentsOf: debugURL, encoding: .utf8)
        #expect(source.contains("debug.sidebar_dock.reorder_tab"))
        #expect(source.contains("store.reorderTab") || source.contains(".reorderTab("))
        // Live tab/panel id resolution for simulate_drop fixtures.
        #expect(
            source.contains("resolveSidebarDockLiveTab")
                || (source.contains("panel_id") && source.contains("tab_title"))
                || source.contains("section_index")
        )
#if DEBUG
        let names = TerminalController.sidebarDockDebugMethodNames
        #expect(names.contains("debug.sidebar_dock.reorder_tab"))
        #expect(TerminalController.v2DebugMethodNames.contains("debug.sidebar_dock.reorder_tab"))
#endif
    }

    @Test func storeReorderTabIsProductionPathForDebugDogfood() throws {
        let (store, tabs) = try seeded(titles: ["A1", "A2"])
        #expect(store.reorderTab(tabs[0], toIndex: 1))
        let top = try #require(store.orderedSectionPaneIds().first)
        let ordered = store.bonsplitController.tabs(inPane: top).map(\.id)
        #expect(ordered.count == 2)
        #expect(Set(ordered) == Set(tabs))
    }
}
