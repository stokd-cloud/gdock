import AppKit
import Bonsplit
import Combine
import CmuxCommandPalette
import Foundation
import Testing

#if canImport(cmux_DEV)
@testable import cmux_DEV
#elseif canImport(cmux)
@testable import cmux
#endif

@MainActor
private final class ActorSurfaceRailPanel: Panel {
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

/// VAL-RAIL-003..008 actor surface: edge-band drops, header reorder, public
/// palette registration, shared routing, and DEBUG `debug.sidebar_dock` schema.
@MainActor
@Suite("SidebarDock actor surface (drop/header/debug)", .serialized)
struct SidebarDockActorSurfaceTests {
    private func multiTabStore(
        titles: [String] = ["A", "B", "C", "D"],
        edge: SidebarDockEdge = .right,
        height: CGFloat = 800
    ) throws -> (SidebarDockStore, [TabID]) {
        let store = SidebarDockStore(edge: edge, windowId: UUID(), collapsedSectionHeight: 28)
        store.updateRailContentHeight(height)
        var tabs: [TabID] = []
        for title in titles {
            let tab = try #require(store.attachPanel(ActorSurfaceRailPanel(title)))
            tabs.append(tab)
        }
        return (store, tabs)
    }

    // MARK: Edge band geometry (VAL-RAIL-003)

    @Test func edgeBandUses25PercentWith80PointMinimum() {
        #expect(SidebarDockEdgeBand.fraction == 0.25)
        #expect(SidebarDockEdgeBand.minimumPoints == 80)
        // Tall pane: 25% of 400 = 100 > 80
        #expect(SidebarDockEdgeBand.bandLength(for: 400) == 100)
        // Short pane: 25% of 200 = 50 → clamped to 80
        #expect(SidebarDockEdgeBand.bandLength(for: 200) == 80)
        #expect(SidebarDockEdgeBand.bandLength(for: 160) == 80)
    }

    @Test func edgeBandResolvesTopBottomCenterAndHorizontalPriority() {
        let size = CGSize(width: 200, height: 400)
        // Top band (y < 100)
        #expect(SidebarDockEdgeBand.resolveZone(location: CGPoint(x: 100, y: 10), size: size) == .top)
        // Bottom band
        #expect(SidebarDockEdgeBand.resolveZone(location: CGPoint(x: 100, y: 390), size: size) == .bottom)
        // Center
        #expect(SidebarDockEdgeBand.resolveZone(location: CGPoint(x: 100, y: 200), size: size) == .center)
        // Left/right take priority at corners
        #expect(SidebarDockEdgeBand.resolveZone(location: CGPoint(x: 5, y: 5), size: size) == .left)
        #expect(SidebarDockEdgeBand.resolveZone(location: CGPoint(x: 195, y: 395), size: size) == .right)
    }

    // MARK: Drop handler shared path (VAL-RAIL-003/004)

    @Test(arguments: [
        (SidebarDockEdge.left, SidebarDockEdgeBand.Zone.top),
        (.left, .bottom),
        (.right, .top),
        (.right, .bottom),
    ])
    func edgeBandDropCreatesVerticalSectionOnSharedPath(
        edge: SidebarDockEdge,
        zone: SidebarDockEdgeBand.Zone
    ) throws {
        let (store, tabs) = try multiTabStore(edge: edge)
        let before = store.sectionCount
        #expect(before == 1)
        let outcome = store.handleTabEdgeBandDrop(tabId: tabs[1], zone: zone)
        #expect(outcome.isSuccess)
        if case .createdSection(let position) = outcome {
            #expect(position == zone.sectionPosition)
        } else {
            Issue.record("expected createdSection for \(edge)/\(zone)")
        }
        #expect(store.sectionCount == 2)
        if case .split(let split) = store.bonsplitController.treeSnapshot() {
            #expect(split.orientation == "vertical")
        } else {
            Issue.record("expected vertical split tree")
        }
    }

    @Test func horizontalDropIsRefusedLosslessly() throws {
        let (store, tabs) = try multiTabStore()
        #expect(store.moveTabToNewSection(tabs[1], position: .bottom))
        let beforeSnaps = store.sectionSnapshots()
        let beforePanels = store.panels.count
        let beforeTabs = store.surfaceIdToPanelId.count
        for zone: SidebarDockEdgeBand.Zone in [.left, .right] {
            let outcome = store.handleTabEdgeBandDrop(tabId: tabs[2], zone: zone)
            #expect(outcome == .refused(reason: .horizontal))
            #expect(store.sectionSnapshots() == beforeSnaps)
            #expect(store.panels.count == beforePanels)
            #expect(store.surfaceIdToPanelId.count == beforeTabs)
            #expect(store.surfaceIdToPanelId[tabs[2]] != nil)
        }
        // Delegate veto for horizontal splits.
        let pane = try #require(store.orderedSectionPaneIds().first)
        #expect(store.splitTabBar(store.bonsplitController, shouldSplitPane: pane, orientation: .horizontal) == false)
        #expect(store.bonsplitController.splitPane(pane, orientation: .horizontal) == nil)
        #expect(store.sectionSnapshots() == beforeSnaps)
    }

    @Test func disallowedPanelAttachAndDropRefuseWithoutMutation() throws {
        let store = SidebarDockStore(edge: .right, windowId: UUID(), collapsedSectionHeight: 28)
        store.updateRailContentHeight(800)
        let before = store.sectionCount
        let terminal = ActorSurfaceRailPanel("Term", panelType: .terminal)
        #expect(store.attachPanel(terminal) == nil)
        #expect(store.sectionCount == before)
        #expect(store.panels[terminal.id] == nil)
    }

    @Test func geometryRefusalIsLosslessOnSharedDropPath() throws {
        let (store, tabs) = try multiTabStore(height: 28)
        // Only room for one header.
        #expect(!store.configurationAllowsNewSection())
        let beforeSnaps = store.sectionSnapshots()
        let beforeTabs = store.surfaceIdToPanelId.count
        let outcome = store.handleTabEdgeBandDrop(tabId: tabs[1], zone: .bottom)
        #expect(outcome == .refused(reason: .geometry))
        #expect(store.sectionSnapshots() == beforeSnaps)
        #expect(store.surfaceIdToPanelId.count == beforeTabs)
        #expect(store.surfaceIdToPanelId[tabs[0]] != nil)
        #expect(store.surfaceIdToPanelId[tabs[1]] != nil)
    }

    @Test func samePaneCenterDropIsNoop() throws {
        let (store, tabs) = try multiTabStore()
        let pane = try #require(store.orderedSectionPaneIds().first)
        let before = store.sectionSnapshots()
        let outcome = store.handleTabEdgeBandDrop(tabId: tabs[0], zone: .center, targetPaneId: pane)
        #expect(outcome == .samePaneNoop)
        #expect(store.sectionSnapshots() == before)
    }

    // MARK: Header reorder (VAL-RAIL-008)

    @Test func headerReorderSharesMutationPathWithCommand() throws {
        let (store, tabs) = try multiTabStore()
        #expect(store.moveTabToNewSection(tabs[1], position: .bottom))
        #expect(store.moveTabToNewSection(tabs[2], position: .bottom))
        #expect(store.sectionCount == 3)
        let before = store.sectionSnapshots().map(\.tabPanelIds)
        #expect(store.handleSectionHeaderReorder(from: 0, to: 2))
        let afterHeader = store.sectionSnapshots().map(\.tabPanelIds)
        #expect(afterHeader != before)
        #expect(afterHeader.last == before.first)

        // Command path produces the same reorder primitive.
        let midBefore = store.sectionSnapshots()
        #expect(SidebarDockActionInvoker.perform(
            commandId: SidebarDockCommand.reorderSectionUp,
            store: store,
            tabId: nil,
            paneId: store.orderedSectionPaneIds().last
        ))
        #expect(store.sectionSnapshots() != midBefore)
    }

    @Test func headerDragGestureWiringUsesSharedCommandPath() throws {
        // Source pin: panel view routes header drag through performSectionContextMenuCommand
        // (invoker → SidebarDockCommand.perform → reorderSection).
        let root = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        let panelURL = root
            .appendingPathComponent("Sources")
            .appendingPathComponent("Sidebar")
            .appendingPathComponent("SidebarDockPanelView.swift")
        let source = try String(contentsOf: panelURL, encoding: .utf8)
        #expect(source.contains("handleSectionHeaderDragEnded"))
        #expect(source.contains("SidebarDockCommand.reorderSectionUp"))
        #expect(source.contains("SidebarDockCommand.reorderSectionDown"))
        #expect(source.contains("DragGesture"))
        #expect(source.contains("performSectionContextMenuCommand"))
        #expect(source.contains("headerDragAffordance"))
    }

    // MARK: Public registration (not DEBUG-only)

    @Test func publicPaletteAndCommandIdsRemainRegistered() {
        let contributions = ContentView.commandPaletteSidebarDockCommandContributions()
        let ids = Set(contributions.map(\.commandId))
        for commandId in SidebarDockCommand.allCommandIds {
            #expect(ids.contains(commandId), "Missing public palette contribution \(commandId)")
        }
        #expect(SidebarDockCommand.allCommandIds.count == 6)
    }

    @Test func dropHandlerSourceRoutesThroughMoveTabToNewSection() throws {
        let root = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        let dropURL = root
            .appendingPathComponent("Sources")
            .appendingPathComponent("Sidebar")
            .appendingPathComponent("SidebarDockDropHandler.swift")
        let source = try String(contentsOf: dropURL, encoding: .utf8)
        #expect(source.contains("moveTabToNewSection"))
        #expect(source.contains("isHorizontalRefuseBand"))
        #expect(source.contains("SidebarDockPlacementMatrix"))
    }

    // MARK: DEBUG namespace registration

    @Test func debugSidebarDockMethodsAreRegisteredInDebugCatalog() throws {
#if DEBUG
        let names = TerminalController.v2DebugMethodNames
        for method in TerminalController.sidebarDockDebugMethodNames {
            #expect(names.contains(method), "Missing debug method \(method)")
            #expect(method.hasPrefix("debug.sidebar_dock."))
        }
        #expect(TerminalController.sidebarDockDebugMethodNames.count == 8)
        #expect(TerminalController.sidebarDockDebugMethodNames.contains("debug.sidebar_dock.reorder_tab"))
#else
        // Release builds omit the DEBUG catalog; registration is DEBUG-gated by design.
        #expect(Bool(true))
#endif
    }

    @Test func debugSidebarDockMethodSchemasAreDocumentedInSource() throws {
        let root = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        let debugURL = root
            .appendingPathComponent("Sources")
            .appendingPathComponent("TerminalController+SidebarDockDebug.swift")
        let source = try String(contentsOf: debugURL, encoding: .utf8)
        for method in [
            "debug.sidebar_dock.inspect",
            "debug.sidebar_dock.perform_command",
            "debug.sidebar_dock.simulate_drop",
            "debug.sidebar_dock.reorder_section",
            "debug.sidebar_dock.reorder_tab",
            "debug.sidebar_dock.divider_drag",
            "debug.sidebar_dock.resize_rail",
            "debug.sidebar_dock.refuse_paths",
        ] {
            #expect(source.contains(method), "Schema/source missing \(method)")
        }
        // Mutations must call production bridges, not a parallel path.
        #expect(source.contains("SidebarDockActionInvoker.perform"))
        #expect(source.contains("handleTabEdgeBandDrop"))
        #expect(source.contains("handleSectionHeaderReorder"))
        #expect(source.contains("updateRailContentHeight"))
        #expect(source.contains("store.reorderTab") || source.contains(".reorderTab("))
        #expect(source.contains("resolveSidebarDockLiveTab"))
    }

    // MARK: Inspect snapshot (no store below boundary)

    @Test func inspectSnapshotIsValueTypeWithoutStoreReference() throws {
        let (store, tabs) = try multiTabStore()
        #expect(store.moveTabToNewSection(tabs[1], position: .bottom))
        let edge = store.inspectEdgeSnapshot()
        #expect(edge.edge == "right")
        #expect(edge.sectionCount == 2)
        #expect(edge.sections.count == 2)
        #expect(edge.sections[0].tabTitles.isEmpty == false)
        // Snapshot is a pure value — no Observable store property on the type.
        let root = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        let snapURL = root
            .appendingPathComponent("Sources")
            .appendingPathComponent("Sidebar")
            .appendingPathComponent("SidebarDockInspectSnapshot.swift")
        let source = try String(contentsOf: snapURL, encoding: .utf8)
        #expect(!source.contains("@ObservedObject"))
        #expect(!source.contains("@EnvironmentObject"))
        #expect(source.contains("struct SidebarDockInspectSnapshot"))
    }

    // MARK: Divider / resize via store helpers used by DEBUG

    @Test func dividerLifecycleAndRailResizeHelpersAreReachable() throws {
        let (store, tabs) = try multiTabStore()
        #expect(store.moveTabToNewSection(tabs[1], position: .bottom))
        #expect(store.moveTabToNewSection(tabs[2], position: .bottom))
        let panes = store.orderedSectionPaneIds()
        #expect(store.collapseSection(paneId: panes[0]))
        #expect(store.debugBeginDividerDrag(adjacentTo: panes[0]))
        // DEBUG begin must arm the production Bonsplit drag session.
        #expect(store.bonsplitController.isDividerDragActive)
        // After begin adjacent to collapsed, imposition cleared / expanded.
        store.debugEndDividerDrag()
        #expect(!store.bonsplitController.isDividerDragActive)
        store.updateRailContentHeight(600)
        #expect(abs(store.railContentHeight - 600) <= 0.5)
    }
}
