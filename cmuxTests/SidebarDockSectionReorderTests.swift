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
private final class ReorderRailPanel: Panel {
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

/// Complete live section snapshot used by VAL-RAIL-008 identity assertions.
@MainActor
private struct CompleteSectionSnapshot: Equatable {
    var tabUUIDs: [UUID]
    var panelIds: [UUID]
    var selectedTabUUID: UUID?
    var selectedPanelId: UUID?
    var isCollapsed: Bool
    var rememberedExtent: CGFloat?
}

/// VAL-RAIL-008 complete-snapshot whole-section reorder (D-32).
///
/// Red suite for the R3 defect: header/command reorder dropped a section (3→2),
/// recreated tab UUIDs, and lost mid-section collapse identity. Asserts first /
/// middle / last moves through the shared production path retain every live
/// section, tabs, selection, collapse, remembered extent, and identity.
@MainActor
@Suite("SidebarDock section reorder complete snapshot VAL-RAIL-008", .serialized)
struct SidebarDockSectionReorderTests {
    private func seeded(
        titles: [String],
        height: CGFloat = 900
    ) throws -> (SidebarDockStore, [TabID]) {
        let store = SidebarDockStore(edge: .right, windowId: UUID(), collapsedSectionHeight: 28)
        store.updateRailContentHeight(height)
        var tabs: [TabID] = []
        for title in titles {
            let tab = try #require(store.attachPanel(ReorderRailPanel(title)))
            tabs.append(tab)
        }
        return (store, tabs)
    }

    private func completeSnapshots(in store: SidebarDockStore) -> [CompleteSectionSnapshot] {
        store.orderedSectionPaneIds().compactMap { pane in
            let liveTabs = store.bonsplitController.tabs(inPane: pane)
                .filter { store.surfaceIdToPanelId[$0.id] != nil }
            guard !liveTabs.isEmpty else { return nil }
            let selected = store.bonsplitController.selectedTab(inPane: pane)
            let selectedLive = selected.flatMap { tab -> TabID? in
                store.surfaceIdToPanelId[tab.id] != nil ? tab.id : nil
            }
            return CompleteSectionSnapshot(
                tabUUIDs: liveTabs.map(\.id.uuid),
                panelIds: liveTabs.compactMap { store.surfaceIdToPanelId[$0.id] },
                selectedTabUUID: selectedLive?.uuid,
                selectedPanelId: selectedLive.flatMap { store.surfaceIdToPanelId[$0] },
                isCollapsed: store.isSectionCollapsed(paneId: pane),
                rememberedExtent: store.rememberedExtent(forPane: pane)
            )
        }
    }

    private func unmappedCount(in store: SidebarDockStore) -> Int {
        store.bonsplitController.allTabIds.filter { store.surfaceIdToPanelId[$0] == nil }.count
    }

    /// Empty | Vault+Files | Find-style rail with collapsed middle.
    private func threeSectionCollapsedMid() throws -> (
        store: SidebarDockStore,
        before: [CompleteSectionSnapshot]
    ) {
        // Multi-tab first (A1,A2), sole middle B, sole trailing C — mirrors R3
        // Empty|Vault+Files|Find with mid collapsed (here B is the mid section).
        let (store, tabs) = try seeded(titles: ["A1", "A2", "B", "C"])
        #expect(store.moveTabToNewSection(tabs[2], position: .bottom))
        #expect(store.moveTabToNewSection(tabs[3], position: .bottom))
        #expect(store.sectionCount == 3)
        #expect(unmappedCount(in: store) == 0)

        let panes = store.orderedSectionPaneIds()
        #expect(store.collapseSection(paneId: panes[1]))
        #expect(store.isSectionCollapsed(paneId: panes[1]))

        let before = completeSnapshots(in: store)
        #expect(before.count == 3)
        #expect(before[0].tabUUIDs.count == 2)
        #expect(before[1].isCollapsed)
        #expect(before[1].rememberedExtent != nil)
        #expect(!before[0].isCollapsed)
        #expect(!before[2].isCollapsed)
        return (store, before)
    }

    private func expectIdentityPreservingReorder(
        store: SidebarDockStore,
        before: [CompleteSectionSnapshot],
        expectedOrder: [CompleteSectionSnapshot]
    ) {
        let after = completeSnapshots(in: store)
        // R3 failure: section_count 3→2 after header reorder.
        #expect(after.count == before.count)
        #expect(store.sectionCount == before.count)
        #expect(unmappedCount(in: store) == 0)

        // Complete snapshot: tab UUIDs, panels, selection, collapse, remembered extent.
        #expect(after == expectedOrder)

        // Every pre-move live tab UUID still present exactly once (no recreate).
        let beforeTabs = before.flatMap(\.tabUUIDs)
        let afterTabs = after.flatMap(\.tabUUIDs)
        #expect(Set(afterTabs) == Set(beforeTabs))
        #expect(afterTabs.count == beforeTabs.count)

        // Panel identity also retained (no panel recreation).
        let beforePanels = before.flatMap(\.panelIds)
        let afterPanels = after.flatMap(\.panelIds)
        #expect(Set(afterPanels) == Set(beforePanels))
    }

    // MARK: First → last (header production path)

    @Test func firstToLastHeaderReorderPreservesCompleteSnapshotWithCollapsedMid() throws {
        let (store, before) = try threeSectionCollapsedMid()
        // Expected: [mid B collapsed, trailing C, first A1+A2]
        let expected = [before[1], before[2], before[0]]

        #expect(store.handleSectionHeaderReorder(from: 0, to: 2))
        expectIdentityPreservingReorder(store: store, before: before, expectedOrder: expected)

        // Collapse still rides with the mid section (now index 0).
        #expect(completeSnapshots(in: store)[0].isCollapsed)
        #expect(completeSnapshots(in: store)[0].tabUUIDs == before[1].tabUUIDs)
        if let rememberedBefore = before[1].rememberedExtent,
           let rememberedAfter = completeSnapshots(in: store)[0].rememberedExtent {
            #expect(abs(rememberedAfter - rememberedBefore) <= 1.0)
        }
    }

    // MARK: Last → first

    @Test func lastToFirstReorderPreservesCompleteSnapshotWithCollapsedMid() throws {
        let (store, before) = try threeSectionCollapsedMid()
        // Expected: [trailing C, first A1+A2, mid B collapsed]
        let expected = [before[2], before[0], before[1]]

        #expect(store.reorderSection(from: 2, to: 0))
        expectIdentityPreservingReorder(store: store, before: before, expectedOrder: expected)
        #expect(completeSnapshots(in: store)[2].isCollapsed)
        #expect(completeSnapshots(in: store)[2].tabUUIDs == before[1].tabUUIDs)
    }

    // MARK: Middle moves

    @Test func middleToFirstAndLastPreserveCollapseIdentity() throws {
        let (store, before) = try threeSectionCollapsedMid()
        let mid = before[1]

        #expect(store.reorderSection(from: 1, to: 0))
        var after = completeSnapshots(in: store)
        #expect(after.count == 3)
        #expect(after[0].tabUUIDs == mid.tabUUIDs)
        #expect(after[0].isCollapsed)
        #expect(unmappedCount(in: store) == 0)

        #expect(store.reorderSection(from: 0, to: 2))
        after = completeSnapshots(in: store)
        #expect(after.count == 3)
        #expect(after[2].tabUUIDs == mid.tabUUIDs)
        #expect(after[2].isCollapsed)
        #expect(after.flatMap(\.tabUUIDs).count == before.flatMap(\.tabUUIDs).count)
    }

    // MARK: Shared command / DEBUG bridge

    @Test func commandAndHeaderShareIdentityPreservingMutation() throws {
        let (store, before) = try threeSectionCollapsedMid()
        let lastPane = try #require(store.orderedSectionPaneIds().last)

        // Deterministic command path (palette / context / header affordance).
        #expect(SidebarDockCommand.perform(
            commandId: SidebarDockCommand.reorderSectionUp,
            store: store,
            tabId: nil,
            paneId: lastPane
        ))
        var after = completeSnapshots(in: store)
        #expect(after.count == 3)
        #expect(after[1].tabUUIDs == before[2].tabUUIDs)
        #expect(Set(after.flatMap(\.tabUUIDs)) == Set(before.flatMap(\.tabUUIDs)))
        #expect(unmappedCount(in: store) == 0)

        // Header path (DEBUG reorder_section bridges here) continues without loss.
        let midBefore = after
        #expect(store.handleSectionHeaderReorder(from: 0, to: 2))
        after = completeSnapshots(in: store)
        #expect(after.count == 3)
        #expect(Set(after.flatMap(\.tabUUIDs)) == Set(midBefore.flatMap(\.tabUUIDs)))
        #expect(unmappedCount(in: store) == 0)
        // Collapsed mid (B) still present somewhere with same tab UUIDs.
        let collapsedMid = before[1]
        #expect(after.contains(where: { $0.tabUUIDs == collapsedMid.tabUUIDs && $0.isCollapsed }))
    }

}
