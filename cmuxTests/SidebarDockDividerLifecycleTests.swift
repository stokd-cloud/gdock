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
private final class DividerRailPanel: Panel {
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

/// VAL-RAIL-006 divider lifecycle via the DEBUG dogfood bridge (D-32 / R3).
///
/// R3 defect: `debug.sidebar_dock.divider_drag` begin/set/end never entered the
/// production Bonsplit drag session, so `isDividerDragActive` stayed false,
/// collapse during "drag" applied immediately, and deferral could not be proven.
/// These tests exercise the same store helpers the DEBUG bridge calls — not a
/// parallel fake flag.
@MainActor
@Suite("SidebarDock divider lifecycle DEBUG bridge VAL-RAIL-006", .serialized)
struct SidebarDockDividerLifecycleTests {
    private func seeded(
        titles: [String],
        height: CGFloat = 900
    ) throws -> (SidebarDockStore, [TabID]) {
        let store = SidebarDockStore(edge: .right, windowId: UUID(), collapsedSectionHeight: 28)
        store.updateRailContentHeight(height)
        var tabs: [TabID] = []
        for title in titles {
            let tab = try #require(store.attachPanel(DividerRailPanel(title)))
            tabs.append(tab)
        }
        return (store, tabs)
    }

    private func stackBottom(_ store: SidebarDockStore, tabs: [TabID]) {
        for tab in tabs.dropFirst() {
            #expect(store.moveTabToNewSection(tab, position: .bottom))
        }
    }

    private func allExtentsPositive(_ store: SidebarDockStore) -> Bool {
        store.orderedSectionPaneIds().allSatisfy { pane in
            guard let extent = store.sectionExtent(forPane: pane) else { return false }
            if store.isSectionCollapsed(paneId: pane) {
                return abs(extent - store.collapsedSectionHeight) <= 0.5
            }
            return extent > 0.5
        }
    }

    /// begin must arm the real controller session; collapse defers; set resizes;
    /// end deactivates and flushes once; no zero-extent expanded section.
    @Test func debugDividerBeginSetEndArmsSessionDefersCollapseAndFlushes() throws {
        let (store, tabs) = try seeded(titles: ["A", "B", "C"])
        stackBottom(store, tabs: tabs)
        #expect(store.sectionCount == 3)
        let panes = store.orderedSectionPaneIds()

        // Equalize first boundary so extents start positive.
        #expect(store.resizeBoundary(firstChildPane: panes[0], firstChildExtent: 300))
        #expect(allExtentsPositive(store))

        #expect(!store.bonsplitController.isDividerDragActive)
        #expect(store.debugBeginDividerDrag(adjacentTo: panes[0]))
        #expect(
            store.bonsplitController.isDividerDragActive,
            "DEBUG begin must drive production noteDividerDragSession, not a fake inspect flag"
        )

        let midExtent = try #require(store.sectionExtent(forPane: panes[0]))
        // Collapse mid-drag must defer (return false; still expanded).
        #expect(store.collapseSection(paneId: panes[1]) == false)
        #expect(!store.isSectionCollapsed(paneId: panes[1]))
        #expect(store.bonsplitController.isDividerDragActive)

        // set resizes while session stays active.
        let target: CGFloat = 220
        #expect(store.debugSetDividerExtent(firstChildPane: panes[0], firstChildExtent: target))
        #expect(store.bonsplitController.isDividerDragActive)
        let afterSet = try #require(store.sectionExtent(forPane: panes[0]))
        #expect(abs(afterSet - target) <= 1.5 || abs(afterSet - midExtent) > 0.5)
        #expect(allExtentsPositive(store))

        store.debugEndDividerDrag()
        #expect(!store.bonsplitController.isDividerDragActive)
        // Deferred collapse flushed exactly by end (production drag-end path).
        #expect(store.isSectionCollapsed(paneId: panes[1]))
        #expect(allExtentsPositive(store))
    }

    @Test func debugBeginAdjacentToCollapsedClearsImpositionBeforeResize() throws {
        let (store, tabs) = try seeded(titles: ["A", "B", "C"])
        stackBottom(store, tabs: tabs)
        let panes = store.orderedSectionPaneIds()
        #expect(store.collapseSection(paneId: panes[0]))
        #expect(store.isSectionCollapsed(paneId: panes[0]))
        #expect(store.imposedCollapsedExtent(forPane: panes[0]) == store.collapsedSectionHeight)

        #expect(store.debugBeginDividerDrag(adjacentTo: panes[0]))
        #expect(store.bonsplitController.isDividerDragActive)
        #expect(!store.isSectionCollapsed(paneId: panes[0]))
        #expect(store.imposedCollapsedExtent(forPane: panes[0]) == nil)

        #expect(store.debugSetDividerExtent(firstChildPane: panes[0], firstChildExtent: 260))
        let resized = try #require(store.sectionExtent(forPane: panes[0]))
        #expect(resized > store.collapsedSectionHeight + 1)
        #expect(allExtentsPositive(store))

        store.debugEndDividerDrag()
        #expect(!store.bonsplitController.isDividerDragActive)
        #expect(allExtentsPositive(store))
    }

    @Test func railResizePreservesTrailingCollapseOutsideDrag() throws {
        let (store, tabs) = try seeded(titles: ["A", "B", "C"], height: 700)
        stackBottom(store, tabs: tabs)
        let trailing = try #require(store.orderedSectionPaneIds().last)
        #expect(store.collapseSection(paneId: trailing))
        #expect(store.isSectionCollapsed(paneId: trailing))
        #expect(!store.bonsplitController.isDividerDragActive)

        store.updateRailContentHeight(900)
        #expect(store.isSectionCollapsed(paneId: trailing))
        #expect(store.imposedCollapsedExtent(forPane: trailing) == store.collapsedSectionHeight)
        #expect(allExtentsPositive(store))
    }

    @Test func endFlushesPendingCollapseOnlyOnceNoChurn() throws {
        let (store, tabs) = try seeded(titles: ["A", "B"])
        stackBottom(store, tabs: tabs)
        let panes = store.orderedSectionPaneIds()
        #expect(store.debugBeginDividerDrag(adjacentTo: panes[0]))
        #expect(store.bonsplitController.isDividerDragActive)
        #expect(store.collapseSection(paneId: panes[0]) == false)
        #expect(!store.isSectionCollapsed(paneId: panes[0]))

        store.debugEndDividerDrag()
        #expect(!store.bonsplitController.isDividerDragActive)
        #expect(store.isSectionCollapsed(paneId: panes[0]))

        // Second end must not re-toggle or churn collapse state.
        store.debugEndDividerDrag()
        #expect(!store.bonsplitController.isDividerDragActive)
        #expect(store.isSectionCollapsed(paneId: panes[0]))
        #expect(allExtentsPositive(store))
    }

    @Test func debugBridgeSourceDrivesNoteDividerDragSessionNotFakeFlag() throws {
        let root = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        let storeURL = root
            .appendingPathComponent("Sources")
            .appendingPathComponent("Sidebar")
            .appendingPathComponent("SidebarDockStore.swift")
        let source = try String(contentsOf: storeURL, encoding: .utf8)
        #expect(source.contains("func debugBeginDividerDrag"))
        #expect(source.contains("func debugEndDividerDrag"))
        // Must arm the real controller session used by pointer dragging.
        #expect(
            source.contains("noteDividerDragSession(true)")
                || source.contains("noteDividerDragSession( true )"),
            "debugBegin must call bonsplitController.noteDividerDragSession(true)"
        )
        #expect(
            source.contains("noteDividerDragSession(false)")
                || source.contains("noteDividerDragSession( false )"),
            "debugEnd must call bonsplitController.noteDividerDragSession(false)"
        )
        // Inspect must report controller state, not a parallel validation bool.
        let inspectURL = root
            .appendingPathComponent("Sources")
            .appendingPathComponent("Sidebar")
            .appendingPathComponent("SidebarDockInspectSnapshot.swift")
        let inspect = try String(contentsOf: inspectURL, encoding: .utf8)
        #expect(inspect.contains("store.bonsplitController.isDividerDragActive"))
    }
}
