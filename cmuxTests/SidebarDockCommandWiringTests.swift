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
private final class WiringRailPanel: Panel {
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

/// VAL-RAIL-001/003/005/007/008 actor reachability: palette, context menu, invoker,
/// and sole-left collapse must route through production registrations that call
/// `SidebarDockCommand.perform` (not store-only unit paths).
@MainActor
@Suite("SidebarDock command actor wiring", .serialized)
struct SidebarDockCommandWiringTests {
    private func multiTabRightStore() throws -> (SidebarDockStore, [TabID]) {
        let store = SidebarDockStore(edge: .right, windowId: UUID(), collapsedSectionHeight: 28)
        store.updateRailContentHeight(800)
        var tabs: [TabID] = []
        for title in ["A", "B", "C", "D"] {
            let panel = WiringRailPanel(title)
            let tab = try #require(store.attachPanel(panel))
            tabs.append(tab)
        }
        return (store, tabs)
    }

    @Test func paletteContributionsRegisterAllDockCommands() {
        let contributions = ContentView.commandPaletteSidebarDockCommandContributions()
        let ids = Set(contributions.map(\.commandId))
        for commandId in SidebarDockCommand.allCommandIds {
            #expect(
                ids.contains(commandId),
                "Missing palette contribution for \(commandId)"
            )
        }
        #expect(contributions.count >= SidebarDockCommand.allCommandIds.count)
        for contribution in contributions {
            let title = contribution.title(CommandPaletteContextSnapshot())
            #expect(!title.isEmpty)
            #expect(title != contribution.commandId)
            let subtitle = contribution.subtitle(CommandPaletteContextSnapshot())
            #expect(!subtitle.isEmpty)
        }
    }

    @Test func paletteContributionsHiddenWhenDockFlagOff() {
        let contributions = ContentView.commandPaletteSidebarDockCommandContributions()
        // Each contribution must gate on the live dock flag via `when`.
        // Build a snapshot that does not claim the dock flag is on.
        let context = CommandPaletteContextSnapshot()
        for contribution in contributions {
            #expect(
                contribution.when(context) == false
                    || contribution.enablement(context) == false
                    || RightSidebarBetaFeatureSettings.isSidebarDockEnabled(),
                "Dock palette command \(contribution.commandId) must be unavailable when flag is off"
            )
        }
        // Stronger invariant: factory always publishes descriptors, and `when` reads the flag.
        if !RightSidebarBetaFeatureSettings.isSidebarDockEnabled() {
            for contribution in contributions {
                #expect(
                    contribution.when(context) == false,
                    "Flag-off must hide \(contribution.commandId) from the palette"
                )
            }
        }
    }

    @Test func invokerIsSoleProductionPerformBridgeAndMutatesStore() throws {
        let (store, tabs) = try multiTabRightStore()
        let before = store.sectionCount
        #expect(before == 1)
        #expect(SidebarDockActionInvoker.perform(
            commandId: SidebarDockCommand.moveTabToNewSectionBottom,
            store: store,
            tabId: tabs[1],
            paneId: store.paneId(forTabId: tabs[1])
        ))
        #expect(store.sectionCount == 2)

        let panes = store.orderedSectionPaneIds()
        #expect(SidebarDockActionInvoker.perform(
            commandId: SidebarDockCommand.collapseSection,
            store: store,
            tabId: nil,
            paneId: panes[0]
        ))
        #expect(store.isSectionCollapsed(paneId: panes[0]))

        #expect(SidebarDockActionInvoker.perform(
            commandId: SidebarDockCommand.expandSection,
            store: store,
            tabId: nil,
            paneId: panes[0]
        ))
        #expect(!store.isSectionCollapsed(paneId: panes[0]))

        // Move last tab into its own section so we have 3 for reorder.
        #expect(SidebarDockActionInvoker.perform(
            commandId: SidebarDockCommand.moveTabToNewSectionBottom,
            store: store,
            tabId: tabs[2],
            paneId: store.paneId(forTabId: tabs[2])
        ))
        #expect(store.sectionCount == 3)
        let beforeOrder = store.sectionSnapshots().map(\.tabPanelIds)
        let bottom = store.orderedSectionPaneIds().last
        #expect(SidebarDockActionInvoker.perform(
            commandId: SidebarDockCommand.reorderSectionUp,
            store: store,
            tabId: nil,
            paneId: bottom
        ))
        let afterOrder = store.sectionSnapshots().map(\.tabPanelIds)
        #expect(afterOrder != beforeOrder)
    }

    @Test func soleLeftCollapseAndExpandViaInvokerPreservesIdentity() throws {
        let manager = TabManager()
        let workspace = try #require(manager.selectedWorkspace)
        let store = SidebarDockStore(edge: .left, windowId: UUID(), collapsedSectionHeight: 28)
        store.updateRailContentHeight(400)
        #expect(SidebarDockSeeding.seedLeftIfEmpty(store: store, workspace: workspace))
        let panelId = try #require(store.panels.keys.first)
        let tabIdsBefore = store.bonsplitController.allTabIds.map(\.id)

        #expect(SidebarDockActionInvoker.perform(
            commandId: SidebarDockCommand.collapseSection,
            store: store,
            tabId: store.bonsplitController.allTabIds.first,
            paneId: store.orderedSectionPaneIds().first
        ))
        #expect(store.isSoleSectionCollapsed)
        #expect(store.panels[panelId] != nil)

        #expect(SidebarDockActionInvoker.perform(
            commandId: SidebarDockCommand.expandSection,
            store: store,
            tabId: store.bonsplitController.allTabIds.first,
            paneId: store.orderedSectionPaneIds().first
        ))
        #expect(!store.isSoleSectionCollapsed)
        #expect(store.panels[panelId] != nil)
        // Tree identity preserved (no rebuild / re-seed).
        #expect(store.sectionCount == 1)
        #expect(store.bonsplitController.allTabIds.map(\.id) == tabIdsBefore)
        #expect(store.panels[panelId] != nil)
    }

    @Test func tabContextMoveDestinationsSurfaceNewSectionCommands() throws {
        let (store, tabs) = try multiTabRightStore()
        // Production store wiring must expose destinations for the focused tab.
        let destinations = store.tabContextMoveDestinationsForActor(tabId: tabs[1])
        let ids = Set(destinations.map(\.id))
        #expect(ids.contains(SidebarDockCommand.moveTabToNewSectionTop))
        #expect(ids.contains(SidebarDockCommand.moveTabToNewSectionBottom))
        for destination in destinations {
            #expect(destination.isEnabled)
            #expect(!destination.title.isEmpty)
        }

        // Selecting a destination must go through the shared invoker path.
        #expect(store.handleTabContextMoveDestination(
            SidebarDockCommand.moveTabToNewSectionBottom,
            for: tabs[1]
        ))
        #expect(store.sectionCount == 2)
    }

    @Test func sectionContextMenuItemsIncludeCollapseAndReorderWhenEligible() throws {
        let (store, tabs) = try multiTabRightStore()
        #expect(store.moveTabToNewSection(tabs[1], position: .bottom))
        #expect(store.moveTabToNewSection(tabs[2], position: .bottom))
        #expect(store.sectionCount == 3)

        let panes = store.orderedSectionPaneIds()
        let middleItems = store.sectionContextMenuItems(for: panes[1])
        let middleIds = Set(middleItems.map(\.id))
        #expect(middleIds.contains(SidebarDockCommand.collapseSection))
        #expect(middleIds.contains(SidebarDockCommand.reorderSectionUp))
        #expect(middleIds.contains(SidebarDockCommand.reorderSectionDown))

        // Running a menu item must mutate via the invoker/shared path.
        let collapse = try #require(middleItems.first(where: { $0.id == SidebarDockCommand.collapseSection }))
        #expect(collapse.isEnabled)
        #expect(store.performSectionContextMenuCommand(
            SidebarDockCommand.collapseSection,
            paneId: panes[1]
        ))
        #expect(store.isSectionCollapsed(paneId: panes[1]))
    }

    @Test func focusedSectionHeaderControlsSnapshotIsActorReachable() throws {
        let (store, tabs) = try multiTabRightStore()
        #expect(store.moveTabToNewSection(tabs[1], position: .bottom))
        #expect(store.moveTabToNewSection(tabs[2], position: .bottom))
        let chrome = store.focusedSectionHeaderControlsSnapshot()
        #expect(chrome != nil)
        let snapshot = try #require(chrome)
        #expect(snapshot.canCollapse || snapshot.canExpand)
        #expect(snapshot.sectionCount >= 2)
        // Affordance flags feed header controls without holding the store in rows.
        #expect(snapshot.paneId != UUID())
    }

    @Test func invokerSourceRoutesThroughSidebarDockCommandPerform() throws {
        // Behavior-level source pin: production invoker must call the shared perform path.
        let root = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        let invokerURL = root
            .appendingPathComponent("Sources")
            .appendingPathComponent("Sidebar")
            .appendingPathComponent("SidebarDockActionInvoker.swift")
        let source = try String(contentsOf: invokerURL, encoding: .utf8)
        #expect(source.contains("SidebarDockCommand.perform("))
        #expect(!source.contains("Intentionally unconnected until green wiring"))
    }
}
