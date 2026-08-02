import Foundation
import Testing

#if canImport(cmux_DEV)
@testable import cmux_DEV
#elseif canImport(cmux)
@testable import cmux
#endif

/// VAL-FLAG-004 + VAL-CROSS-001 behavioral identity: flag reversibility,
/// per-window isolation, workspace reattachment, named-layout target window.
@MainActor
@Suite("Sidebar dock flag/layout/cross-window", .serialized)
struct SidebarDockFlagLayoutCrossTests {
    @Test func flagOffOmitsRailFieldsAndOnAgainRestoresLoadableArrangement() throws {
        let manager = TabManager()
        let workspace = try #require(manager.selectedWorkspace)
        let registry = SidebarDockStoreRegistry(windowId: UUID())
        SidebarDockSeeding.seedRegistryIfEmpty(
            registry: registry,
            workspace: workspace,
            preferredRightMode: .find
        )
        // Nontrivial: two right sections.
        let find = try #require(
            registry.right.panels.values.compactMap { $0 as? RightSidebarToolPanel }.first { $0.mode == .find }
        )
        if let tab = registry.right.surfaceId(forPanelId: find.id) {
            _ = registry.right.moveTabToNewSection(tab, position: .bottom)
        }
        let saved = registry.sessionWindowRailSnapshots(flagEnabled: true)
        #expect(saved.right != nil)
        #expect(saved.left != nil)

        // Flag off: capture must omit fields.
        let off = registry.sessionWindowRailSnapshots(flagEnabled: false)
        #expect(off.left == nil)
        #expect(off.right == nil)

        // Legacy defaults untouched (seed path never writes rightSidebar.mode).
        let defaults = UserDefaults.standard
        let modeBefore = defaults.string(forKey: "rightSidebar.mode")
        // Re-enable: saved arrangement is still loadable.
        let reload = SidebarDockStoreRegistry(windowId: UUID())
        let leftResult = reload.left.restoreSessionSnapshot(saved.left, workspace: workspace)
        let rightResult = reload.right.restoreSessionSnapshot(saved.right, workspace: workspace)
        #expect(!leftResult.didReseedCanonical || reload.left.sectionCount >= 1)
        #expect(!rightResult.didReseedCanonical)
        #expect(reload.right.sectionCount == registry.right.sectionCount)
        #expect(defaults.string(forKey: "rightSidebar.mode") == modeBefore)
    }

    @Test func twoWindowsIsolateRailStoresAndFingerprints() throws {
        let manager = TabManager()
        let workspace = try #require(manager.selectedWorkspace)
        let a = SidebarDockStoreRegistry(windowId: UUID())
        let b = SidebarDockStoreRegistry(windowId: UUID())
        SidebarDockSeeding.seedRegistryIfEmpty(registry: a, workspace: workspace, preferredRightMode: .files)
        SidebarDockSeeding.seedRegistryIfEmpty(registry: b, workspace: workspace, preferredRightMode: .sessions)
        #expect(a.left !== b.left)
        #expect(a.right !== b.right)
        #expect(a.windowId != b.windowId)
        #expect(a.right.focusedToolMode() == .files)
        #expect(b.right.focusedToolMode() == .sessions)

        // Mutate A only.
        if let find = a.right.panels.values.compactMap({ $0 as? RightSidebarToolPanel }).first(where: { $0.mode == .find }),
           let tab = a.right.surfaceId(forPanelId: find.id) {
            _ = a.right.moveTabToNewSection(tab, position: .bottom)
        }
        #expect(a.right.sectionCount == 2)
        #expect(b.right.sectionCount == 1)
        #expect(a.sessionAutosaveFingerprint() != b.sessionAutosaveFingerprint())
    }

    @Test func workspaceReattachmentUpdatesToolRootsWithoutCrossWindowMutation() throws {
        let manager = TabManager()
        let first = try #require(manager.selectedWorkspace)
        let second = manager.addWorkspace(
            title: "Second",
            workingDirectory: FileManager.default.temporaryDirectory.path,
            inheritWorkingDirectory: false,
            select: false
        )
        let registry = SidebarDockStoreRegistry(windowId: UUID())
        SidebarDockSeeding.seedRegistryIfEmpty(
            registry: registry,
            workspace: first,
            preferredRightMode: .files
        )
        let other = SidebarDockStoreRegistry(windowId: UUID())
        SidebarDockSeeding.seedRegistryIfEmpty(
            registry: other,
            workspace: first,
            preferredRightMode: .find
        )
        let otherModesBefore = SidebarDockSeeding.orderedRightModes(in: other.right)

        registry.left.reattachAllPanels(to: second)
        registry.right.reattachAllPanels(to: second)
        // Arrangement unchanged; peer window untouched.
        #expect(registry.right.sectionCount == 1)
        #expect(SidebarDockSeeding.orderedRightModes(in: other.right) == otherModesBefore)
        #expect(other.right.focusedToolMode() == .find)
    }

    @Test func namedLayoutApplyTargetsOnlyChosenRegistry() throws {
        let manager = TabManager()
        let workspace = try #require(manager.selectedWorkspace)
        let source = SidebarDockStoreRegistry(windowId: UUID())
        let peer = SidebarDockStoreRegistry(windowId: UUID())
        SidebarDockSeeding.seedRegistryIfEmpty(registry: source, workspace: workspace, preferredRightMode: .files)
        SidebarDockSeeding.seedRegistryIfEmpty(registry: peer, workspace: workspace, preferredRightMode: .sessions)
        if let find = source.right.panels.values.compactMap({ $0 as? RightSidebarToolPanel }).first(where: { $0.mode == .find }),
           let tab = source.right.surfaceId(forPanelId: find.id) {
            _ = source.right.moveTabToNewSection(tab, position: .bottom)
        }
        let definition = source.captureNamedLayoutDefinition()
        let peerCountBefore = peer.right.sectionCount
        let appliedNamedLayout = source.applyNamedLayoutDefinition(definition, workspace: workspace)
        #expect(appliedNamedLayout)
        // Peer untouched.
        #expect(peer.right.sectionCount == peerCountBefore)
        #expect(peer.right.focusedToolMode() == .sessions)
        #expect(source.right.sectionCount == 2)
    }

    @Test func tabManagerUsesExplicitRegistryWithoutAppDelegateScan() throws {
        let manager = TabManager()
        let workspace = try #require(manager.selectedWorkspace)
        let registry = SidebarDockStoreRegistry(windowId: UUID())
        SidebarDockSeeding.seedRegistryIfEmpty(
            registry: registry,
            workspace: workspace,
            preferredRightMode: .files
        )
        manager.sidebarDockRegistry = registry
        let definition = CmuxSidebarDockDefinition(
            left: .init(sections: [
                .init(panels: ["workspaceSelector"], selected: "workspaceSelector"),
            ]),
            right: .init(sections: [
                .init(panels: ["find"], selected: "find"),
                .init(panels: ["sessions"], selected: "sessions"),
            ])
        )
        manager.applySidebarDockLayout(definition, to: workspace)
        #expect(registry.right.sectionCount == 2)
        #expect(registry.right.focusedToolMode() == .find)

        // Capture uses the same explicit ownership.
        workspace.owningTabManager = manager
        let capture = try workspace.captureLayoutDefinition(sidebarDockRegistry: registry)
        #expect(capture.workspace.sidebarDock?.right?.sections.count == 2)
        let tokens = capture.workspace.sidebarDock?.right?.sections.flatMap(\.panels) ?? []
        for token in tokens {
            #expect(UUID(uuidString: token) == nil)
        }
    }
}
