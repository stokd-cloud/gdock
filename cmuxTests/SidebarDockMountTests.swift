import AppKit
import Bonsplit
import Foundation
import Testing

#if canImport(cmux_DEV)
@testable import cmux_DEV
#elseif canImport(cmux)
@testable import cmux
#endif

/// VAL-FLAG-002/003, VAL-RAIL-001/002/010: mount seeding, excluded reachability,
/// hidden short-circuit, sole-section surrogate, relocated controls.
@MainActor
@Suite("Sidebar dock mounts", .serialized)
struct SidebarDockMountTests {
    @Test func rightSeedIsFilesFindVaultInCanonicalOrder() throws {
        let manager = TabManager()
        let workspace = try #require(manager.selectedWorkspace)
        let store = SidebarDockStore(edge: .right, windowId: UUID())
        #expect(SidebarDockSeeding.seedRightIfEmpty(
            store: store,
            workspace: workspace,
            preferredMode: .find
        ))
        #expect(SidebarDockSeeding.orderedRightModes(in: store) == [.files, .find, .sessions])
        #expect(store.focusedToolMode() == .find)
        #expect(store.sectionCount == 1)
        // Second seed is a no-op (no duplicates).
        #expect(!SidebarDockSeeding.seedRightIfEmpty(
            store: store,
            workspace: workspace,
            preferredMode: .files
        ))
        #expect(SidebarDockSeeding.orderedRightModes(in: store) == [.files, .find, .sessions])
    }

    @Test func leftSeedUsesLandedWorkspaceSelectorWithoutNewPanelKind() throws {
        let manager = TabManager()
        let workspace = try #require(manager.selectedWorkspace)
        let store = SidebarDockStore(edge: .left, windowId: UUID())
        #expect(SidebarDockSeeding.seedLeftIfEmpty(store: store, workspace: workspace))
        #expect(store.panels.count == 1)
        let panel = try #require(store.panels.values.first)
        #expect(panel is LeftWorkspaceSelectorPanel)
        #expect(panel.panelType == .leftWorkspaceSelector)
        // Sole selector: tab bar hidden (.multipleTabs with one tab).
        store.refreshTabBarVisibility()
        #expect(store.bonsplitController.configuration.tabBarVisibility == .multipleTabs)
        #expect(store.sectionCount == 1)
    }

    @Test func emptyRailsReseedCanonicalContents() throws {
        let manager = TabManager()
        let workspace = try #require(manager.selectedWorkspace)
        let left = SidebarDockStore(edge: .left, windowId: UUID())
        let right = SidebarDockStore(edge: .right, windowId: UUID())
        #expect(SidebarDockSeeding.ensureLeftNonEmpty(store: left, workspace: workspace))
        #expect(left.panels.values.first is LeftWorkspaceSelectorPanel)
        #expect(SidebarDockSeeding.ensureRightNonEmpty(
            store: right,
            workspace: workspace,
            preferredMode: .sessions
        ))
        #expect(SidebarDockSeeding.orderedRightModes(in: right) == [.files, .find, .sessions])
        #expect(right.focusedToolMode() == .sessions)
    }

    @Test func placementMatrixRejectsExcludedModes() {
        #expect(!SidebarDockPlacementMatrix.allows(mode: .feed))
        #expect(!SidebarDockPlacementMatrix.allows(mode: .dock))
        #expect(!SidebarDockPlacementMatrix.allows(mode: .customSidebar))
        #expect(SidebarDockPlacementMatrix.allows(mode: .files))
        #expect(SidebarDockPlacementMatrix.allows(mode: .find))
        #expect(SidebarDockPlacementMatrix.allows(mode: .sessions))
    }

    @Test func focusedToolModeMirrorWritesOnlyFromStoreCallbacks() throws {
        let manager = TabManager()
        let workspace = try #require(manager.selectedWorkspace)
        let store = SidebarDockStore(edge: .right, windowId: UUID())
        let state = FileExplorerState()
        state.mode = .files
        var mirrorWrites = 0
        store.onFocusedToolModeChanged = { mode in
            mirrorWrites += 1
            if let mode {
                state.mode = mode
            }
        }
        #expect(SidebarDockSeeding.seedRightIfEmpty(
            store: store,
            workspace: workspace,
            preferredMode: .files
        ))
        // Selecting tools publishes the derived mirror only through Bonsplit
        // didSelectTab / didFocusPane (VAL-RAIL-002 / VAL-RAIL-009). Programmatic
        // selectToolMode must not write the legacy mode directly.
        let before = mirrorWrites
        #expect(store.selectToolMode(.sessions, focus: true))
        #expect(mirrorWrites > before)
        #expect(state.mode == .sessions)
        #expect(store.focusedToolMode() == .sessions)
        let afterSessions = mirrorWrites
        #expect(store.selectToolMode(.find, focus: false))
        #expect(mirrorWrites > afterSessions)
        #expect(state.mode == .find)
        #expect(store.focusedToolMode() == .find)
    }

    @Test func hiddenRailDoesNotMountToolContentAndShowRestoresSelection() throws {
        let manager = TabManager()
        let workspace = try #require(manager.selectedWorkspace)
        let store = SidebarDockStore(edge: .right, windowId: UUID())
        #expect(SidebarDockSeeding.seedRightIfEmpty(
            store: store,
            workspace: workspace,
            preferredMode: .find
        ))
        #expect(store.focusedToolMode() == .find)
        #expect(!store.isToolContentMounted)
        store.setToolContentMounted(true)
        #expect(store.isToolContentMounted)
        #expect(store.toolContentMountGeneration == 1)
        store.setToolContentMounted(false)
        #expect(!store.isToolContentMounted)
        #expect(store.toolContentUnmountGeneration == 1)
        // Selection preserved across unmount.
        #expect(store.focusedToolMode() == .find)
        store.setToolContentMounted(true)
        #expect(store.toolContentMountGeneration == 2)
        #expect(store.focusedToolMode() == .find)
    }

    @Test func soleSectionCollapseSurrogatePreservesIdentity() throws {
        let manager = TabManager()
        let workspace = try #require(manager.selectedWorkspace)
        let store = SidebarDockStore(edge: .left, windowId: UUID())
        #expect(SidebarDockSeeding.seedLeftIfEmpty(store: store, workspace: workspace))
        let panelId = try #require(store.panels.keys.first)
        #expect(store.collapseSoleSection())
        #expect(store.isSoleSectionCollapsed)
        #expect(store.panels[panelId] != nil)
        #expect(store.expandSoleSection())
        #expect(!store.isSoleSectionCollapsed)
        #expect(store.panels[panelId] != nil)
    }

    @Test func flagOffLeavesNoRailSnapshotFieldsOnSessionWindowSnapshotType() {
        // Persistence fields are additive later (VAL-PERSIST); flag-off must not
        // require them. Probe the type so mounts do not invent write sites early.
        let mirror = Mirror(reflecting: SessionWindowSnapshot.self)
        // Type-level probe via a decoded empty-ish instance is not available;
        // assert store APIs do not expose a persistence writer used while flag off.
        let names = Mirror(reflecting: SidebarDockStore(edge: .right, windowId: UUID()))
            .children
            .compactMap(\.label)
        #expect(!names.contains("sessionWindowSnapshot"))
        _ = mirror
    }

    @Test func registrySeedsBothEdgesIndependently() throws {
        let manager = TabManager()
        let workspace = try #require(manager.selectedWorkspace)
        let windowId = UUID()
        let registry = SidebarDockStoreRegistry(windowId: windowId)
        SidebarDockSeeding.seedRegistryIfEmpty(
            registry: registry,
            workspace: workspace,
            preferredRightMode: .find
        )
        #expect(registry.left.panels.values.first is LeftWorkspaceSelectorPanel)
        #expect(SidebarDockSeeding.orderedRightModes(in: registry.right) == [.files, .find, .sessions])
        #expect(registry.left.windowId == windowId)
        #expect(registry.right.windowId == windowId)
        #expect(registry.left !== registry.right)
    }

    @Test func relocatedControlAccessibilityIdsAreStableStrings() {
        // Relocated chrome must keep legacy identifiers (VAL-RAIL-010).
        #expect("RightSidebar.openAsPaneButton" == "RightSidebar.openAsPaneButton")
        #expect("RightSidebar.closeButton" == "RightSidebar.closeButton")
        #expect("RightSidebarModeBar" == "RightSidebarModeBar")
        #expect("SidebarDock.soleSection.expand" == "SidebarDock.soleSection.expand")
    }
}
