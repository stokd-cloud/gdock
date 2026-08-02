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
///
/// Identity oracle is the app-owned `sectionId` (not the Bonsplit pane host).
/// `paneId` is observational only and may change when public Bonsplit ops
/// rebuild topology (D-33 / VAL-RAIL-008).
@MainActor
private struct CompleteSectionSnapshot: Equatable {
    var sectionId: UUID
    var paneId: UUID
    var tabUUIDs: [UUID]
    var panelIds: [UUID]
    var selectedTabUUID: UUID?
    var selectedPanelId: UUID?
    var isCollapsed: Bool
    var rememberedExtent: CGFloat?

    static func == (lhs: CompleteSectionSnapshot, rhs: CompleteSectionSnapshot) -> Bool {
        // paneId intentionally excluded: host may be replaced; durable id travels.
        lhs.sectionId == rhs.sectionId
            && lhs.tabUUIDs == rhs.tabUUIDs
            && lhs.panelIds == rhs.panelIds
            && lhs.selectedTabUUID == rhs.selectedTabUUID
            && lhs.selectedPanelId == rhs.selectedPanelId
            && lhs.isCollapsed == rhs.isCollapsed
            && extentEqual(lhs.rememberedExtent, rhs.rememberedExtent)
    }

    private static func extentEqual(_ a: CGFloat?, _ b: CGFloat?) -> Bool {
        switch (a, b) {
        case (nil, nil): return true
        case let (l?, r?): return abs(l - r) <= 1.0
        default: return false
        }
    }
}

/// VAL-RAIL-008 complete-snapshot whole-section reorder with durable section ids (D-33).
///
/// Red suite: header/command reorder that rebuilds Bonsplit pane hosts must still
/// preserve app-owned section_id + tabs + selection + collapse + remembered extent.
/// Title-only / source-pin checks are insufficient — complete stable-id snapshots
/// compare across first/middle/last and create/teardown.
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
                sectionId: store.sectionId(forPane: pane).rawValue,
                paneId: pane.id,
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
        // Durable ids are unique and present for every live section.
        let ids = before.map(\.sectionId)
        #expect(Set(ids).count == ids.count)
        #expect(ids.allSatisfy { $0 != UUID(uuidString: "00000000-0000-0000-0000-000000000000") })
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

        // Complete snapshot by durable section id + tabs/selection/collapse/extent.
        #expect(after == expectedOrder)

        // Stable section ids travel with the section (not recreated).
        #expect(after.map(\.sectionId) == expectedOrder.map(\.sectionId))
        #expect(Set(after.map(\.sectionId)) == Set(before.map(\.sectionId)))

        // Every pre-move live tab UUID still present exactly once (no recreate).
        let beforeTabs = before.flatMap(\.tabUUIDs)
        let afterTabs = after.flatMap(\.tabUUIDs)
        #expect(Set(afterTabs) == Set(beforeTabs))
        #expect(afterTabs.count == beforeTabs.count)

        // Panel identity also retained (no panel recreation).
        let beforePanels = before.flatMap(\.panelIds)
        let afterPanels = after.flatMap(\.panelIds)
        #expect(Set(afterPanels) == Set(beforePanels))

        // No duplicate section ids after topology rebuild.
        #expect(Set(after.map(\.sectionId)).count == after.count)
    }

    // MARK: First → last (header production path)

    @Test func firstToLastHeaderReorderPreservesCompleteSnapshotWithCollapsedMid() throws {
        let (store, before) = try threeSectionCollapsedMid()
        // Expected: [mid B collapsed, trailing C, first A1+A2]
        let expected = [before[1], before[2], before[0]]

        #expect(store.handleSectionHeaderReorder(from: 0, to: 2))
        expectIdentityPreservingReorder(store: store, before: before, expectedOrder: expected)

        // Collapse still rides with the mid section (now index 0) under the same section id.
        let after = completeSnapshots(in: store)
        #expect(after[0].isCollapsed)
        #expect(after[0].sectionId == before[1].sectionId)
        #expect(after[0].tabUUIDs == before[1].tabUUIDs)
        if let rememberedBefore = before[1].rememberedExtent,
           let rememberedAfter = after[0].rememberedExtent {
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
        let after = completeSnapshots(in: store)
        #expect(after[2].isCollapsed)
        #expect(after[2].sectionId == before[1].sectionId)
        #expect(after[2].tabUUIDs == before[1].tabUUIDs)
    }

    // MARK: Middle moves

    @Test func middleToFirstAndLastPreserveCollapseIdentity() throws {
        let (store, before) = try threeSectionCollapsedMid()
        let mid = before[1]

        #expect(store.reorderSection(from: 1, to: 0))
        var after = completeSnapshots(in: store)
        #expect(after.count == 3)
        #expect(after[0].sectionId == mid.sectionId)
        #expect(after[0].tabUUIDs == mid.tabUUIDs)
        #expect(after[0].isCollapsed)
        #expect(unmappedCount(in: store) == 0)
        #expect(Set(after.map(\.sectionId)) == Set(before.map(\.sectionId)))

        #expect(store.reorderSection(from: 0, to: 2))
        after = completeSnapshots(in: store)
        #expect(after.count == 3)
        #expect(after[2].sectionId == mid.sectionId)
        #expect(after[2].tabUUIDs == mid.tabUUIDs)
        #expect(after[2].isCollapsed)
        #expect(after.flatMap(\.tabUUIDs).count == before.flatMap(\.tabUUIDs).count)
        #expect(Set(after.map(\.sectionId)) == Set(before.map(\.sectionId)))
    }

    // MARK: Shared command / DEBUG bridge

    @Test func commandAndHeaderShareIdentityPreservingMutation() throws {
        let (store, before) = try threeSectionCollapsedMid()
        let lastPane = try #require(store.orderedSectionPaneIds().last)
        let lastSectionId = before[2].sectionId

        // Deterministic command path (palette / context / header affordance).
        #expect(SidebarDockCommand.perform(
            commandId: SidebarDockCommand.reorderSectionUp,
            store: store,
            tabId: nil,
            paneId: lastPane
        ))
        var after = completeSnapshots(in: store)
        #expect(after.count == 3)
        #expect(after[1].sectionId == lastSectionId)
        #expect(after[1].tabUUIDs == before[2].tabUUIDs)
        #expect(Set(after.flatMap(\.tabUUIDs)) == Set(before.flatMap(\.tabUUIDs)))
        #expect(Set(after.map(\.sectionId)) == Set(before.map(\.sectionId)))
        #expect(unmappedCount(in: store) == 0)

        // Header path (DEBUG reorder_section bridges here) continues without loss.
        let midBefore = after
        #expect(store.handleSectionHeaderReorder(from: 0, to: 2))
        after = completeSnapshots(in: store)
        #expect(after.count == 3)
        #expect(Set(after.flatMap(\.tabUUIDs)) == Set(midBefore.flatMap(\.tabUUIDs)))
        #expect(Set(after.map(\.sectionId)) == Set(midBefore.map(\.sectionId)))
        #expect(unmappedCount(in: store) == 0)
        // Collapsed mid (B) still present somewhere with same tab UUIDs + section id.
        let collapsedMid = before[1]
        #expect(after.contains(where: {
            $0.sectionId == collapsedMid.sectionId
                && $0.tabUUIDs == collapsedMid.tabUUIDs
                && $0.isCollapsed
        }))
    }

    // MARK: Create / teardown lifecycle

    @Test func createMintsDistinctSectionIdAndTeardownDropsBinding() throws {
        let (store, tabs) = try seeded(titles: ["RootA", "RootB", "Peel"])
        let rootBefore = completeSnapshots(in: store)
        #expect(rootBefore.count == 1)
        let rootId = rootBefore[0].sectionId

        #expect(store.moveTabToNewSection(tabs[2], position: .bottom))
        let afterCreate = completeSnapshots(in: store)
        #expect(afterCreate.count == 2)
        #expect(afterCreate[0].sectionId == rootId)
        #expect(afterCreate[1].sectionId != rootId)
        #expect(Set(afterCreate.map(\.sectionId)).count == 2)
        // Durable bindings track live sections (no duplicates / no orphan hosts).
        #expect(store.sectionIdentityBindingCount == store.sectionCount)

        let newSectionId = afterCreate[1].sectionId
        let peelTab = tabs[2]
        #expect(store.closeTab(peelTab))
        let afterTeardown = completeSnapshots(in: store)
        #expect(afterTeardown.count == 1)
        #expect(afterTeardown[0].sectionId == rootId)
        #expect(!afterTeardown.map(\.sectionId).contains(newSectionId))
        #expect(store.sectionIdentityBindingCount == store.sectionCount)
        #expect(unmappedCount(in: store) == 0)
    }

    // MARK: Inspect schema exposes section_id + pane_id

    @Test func inspectSnapshotExposesSectionIdAndPaneId() throws {
        let (store, before) = try threeSectionCollapsedMid()
        let edge = store.inspectEdgeSnapshot()
        #expect(edge.sections.count == 3)
        for (index, section) in edge.sections.enumerated() {
            #expect(section.sectionId == before[index].sectionId.uuidString)
            #expect(section.paneId == before[index].paneId.uuidString)
            #expect(!section.sectionId.isEmpty)
            #expect(!section.paneId.isEmpty)
        }
        let dict = edge.asEdgeDictionary()
        let sections = try #require(dict["sections"] as? [[String: Any]])
        #expect(sections.count == 3)
        for section in sections {
            #expect(section["section_id"] is String)
            #expect(section["pane_id"] is String)
            let sid = try #require(section["section_id"] as? String)
            let pid = try #require(section["pane_id"] as? String)
            #expect(UUID(uuidString: sid) != nil)
            #expect(UUID(uuidString: pid) != nil)
        }
    }
}
