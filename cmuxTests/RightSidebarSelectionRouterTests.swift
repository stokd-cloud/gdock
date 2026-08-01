import AppKit
import Foundation
import Testing

#if canImport(cmux_DEV)
@testable import cmux_DEV
#elseif canImport(cmux)
@testable import cmux
#endif

/// VAL-RAIL-009: one window-scoped selection router for the exhaustive inventory.
@MainActor
@Suite("Right sidebar selection router", .serialized)
struct RightSidebarSelectionRouterTests {
    @Test func inventoryCoversEveryVALRAIL009Source() {
        let required: Set<RightSidebarSelectionSource> = [
            .modeTabClick,
            .shortcutApp,
            .shortcutWindow,
            .shortcutTerminal,
            .shortcutFileExplorer,
            .shortcutDock,
            .paletteFiles,
            .paletteFind,
            .paletteVault,
            .paletteFeed,
            .paletteDock,
            .findInDirectory,
            .contextualFind,
            .remoteSet,
            .remoteSetNoFocus,
            .debugFocus,
            .debugReveal,
            .dockPlacementReveal,
            .availabilityClamp,
            .railTabSelect,
            .railPaneFocus,
            .sessionRestore,
            .namedLayoutApply,
            .crossRailMove,
        ]
        #expect(Set(RightSidebarSelectionRouter.inventorySources) == required)
        #expect(RightSidebarSelectionSource.allCases.count == required.count)
    }

    @Test func flagOffRoutesToLegacyModeWrite() {
        let state = FileExplorerState()
        state.mode = .files
        var context = RightSidebarSelectionContext(
            windowId: UUID(),
            fileExplorerState: state,
            rightStore: nil,
            isDockEnabled: false
        )
        let route = RightSidebarSelectionRouter.apply(
            RightSidebarSelectionRequest(mode: .find, focus: false, source: .modeTabClick),
            in: &context
        )
        #expect(route == .legacyModeWrite)
        #expect(state.mode == .find)
    }

    @Test func flagOnRailModesSelectStoreWithoutCompetingModeWriteBeforeCallback() throws {
        let manager = TabManager()
        let workspace = try #require(manager.selectedWorkspace)
        let store = SidebarDockStore(edge: .right, windowId: UUID())
        let state = FileExplorerState()
        state.mode = .files
        var mirrorModes: [RightSidebarMode] = []
        store.onFocusedToolModeChanged = { mode in
            if let mode {
                mirrorModes.append(mode)
                state.mode = mode
            }
        }
        #expect(SidebarDockSeeding.seedRightIfEmpty(
            store: store,
            workspace: workspace,
            preferredMode: .files
        ))
        mirrorModes.removeAll()
        var context = RightSidebarSelectionContext(
            windowId: store.windowId,
            fileExplorerState: state,
            rightStore: store,
            isDockEnabled: true
        )
        let route = RightSidebarSelectionRouter.apply(
            RightSidebarSelectionRequest(mode: .sessions, focus: true, source: .paletteVault),
            in: &context
        )
        #expect(route == .railStoreSelect)
        #expect(store.focusedToolMode() == .sessions)
        // Mirror updated only via Bonsplit didSelectTab/didFocusPane.
        #expect(mirrorModes.contains(.sessions))
        #expect(state.mode == .sessions)
    }

    @Test func flagOnExcludedModesUseNonRailPresentation() throws {
        let defaults = UserDefaults.standard
        let previousFeed = defaults.object(forKey: RightSidebarBetaFeatureSettings.feedEnabledKey)
        let previousDock = defaults.object(forKey: RightSidebarBetaFeatureSettings.dockEnabledKey)
        defaults.set(true, forKey: RightSidebarBetaFeatureSettings.feedEnabledKey)
        defaults.set(true, forKey: RightSidebarBetaFeatureSettings.dockEnabledKey)
        defer {
            if let previousFeed { defaults.set(previousFeed, forKey: RightSidebarBetaFeatureSettings.feedEnabledKey) }
            else { defaults.removeObject(forKey: RightSidebarBetaFeatureSettings.feedEnabledKey) }
            if let previousDock { defaults.set(previousDock, forKey: RightSidebarBetaFeatureSettings.dockEnabledKey) }
            else { defaults.removeObject(forKey: RightSidebarBetaFeatureSettings.dockEnabledKey) }
        }

        let manager = TabManager()
        let workspace = try #require(manager.selectedWorkspace)
        let store = SidebarDockStore(edge: .right, windowId: UUID())
        #expect(SidebarDockSeeding.seedRightIfEmpty(
            store: store,
            workspace: workspace,
            preferredMode: .files
        ))
        let state = FileExplorerState()
        state.mode = .files
        var context = RightSidebarSelectionContext(
            windowId: store.windowId,
            fileExplorerState: state,
            rightStore: store,
            isDockEnabled: true
        )
        let feedRoute = RightSidebarSelectionRouter.apply(
            RightSidebarSelectionRequest(mode: .feed, focus: false, source: .paletteFeed),
            in: &context
        )
        #expect(feedRoute == .nonRailPresentation)
        #expect(state.mode == .feed)
        // Rail still holds only tool panels — feed was not attached.
        #expect(SidebarDockSeeding.orderedRightModes(in: store) == [.files, .find, .sessions])

        let dockRoute = RightSidebarSelectionRouter.apply(
            RightSidebarSelectionRequest(mode: .dock, focus: false, source: .paletteDock),
            in: &context
        )
        #expect(dockRoute == .nonRailPresentation)
        #expect(state.mode == .dock)
    }

    @Test func wrongWindowIsRejected() throws {
        let manager = TabManager()
        let workspace = try #require(manager.selectedWorkspace)
        let store = SidebarDockStore(edge: .right, windowId: UUID())
        #expect(SidebarDockSeeding.seedRightIfEmpty(
            store: store,
            workspace: workspace,
            preferredMode: .files
        ))
        let state = FileExplorerState()
        var context = RightSidebarSelectionContext(
            windowId: store.windowId,
            fileExplorerState: state,
            rightStore: store,
            isDockEnabled: true
        )
        let route = RightSidebarSelectionRouter.apply(
            RightSidebarSelectionRequest(
                mode: .find,
                focus: false,
                source: .remoteSet,
                windowId: UUID()
            ),
            in: &context
        )
        #expect(route == .rejected)
        #expect(store.focusedToolMode() == .files)
    }

    @Test func noFocusRemoteSetDoesNotRequireFocusCallback() throws {
        let manager = TabManager()
        let workspace = try #require(manager.selectedWorkspace)
        let store = SidebarDockStore(edge: .right, windowId: UUID())
        #expect(SidebarDockSeeding.seedRightIfEmpty(
            store: store,
            workspace: workspace,
            preferredMode: .files
        ))
        let state = FileExplorerState()
        state.setVisible(true)
        var focusCalls = 0
        var context = RightSidebarSelectionContext(
            windowId: store.windowId,
            fileExplorerState: state,
            rightStore: store,
            isDockEnabled: true,
            focusRightSidebar: { _ in
                focusCalls += 1
                return true
            },
            focusRailTool: { _ in
                focusCalls += 1
                return true
            }
        )
        let route = RightSidebarSelectionRouter.apply(
            RightSidebarSelectionRequest(mode: .find, focus: false, source: .remoteSetNoFocus),
            in: &context
        )
        #expect(route == .railStoreSelect)
        #expect(store.focusedToolMode() == .find)
        #expect(focusCalls == 0)
    }

    @Test func parameterizedDispatchPerSourceProducesOneVerdict() throws {
        let defaults = UserDefaults.standard
        let previousFeed = defaults.object(forKey: RightSidebarBetaFeatureSettings.feedEnabledKey)
        let previousDock = defaults.object(forKey: RightSidebarBetaFeatureSettings.dockEnabledKey)
        defaults.set(true, forKey: RightSidebarBetaFeatureSettings.feedEnabledKey)
        defaults.set(true, forKey: RightSidebarBetaFeatureSettings.dockEnabledKey)
        defer {
            if let previousFeed { defaults.set(previousFeed, forKey: RightSidebarBetaFeatureSettings.feedEnabledKey) }
            else { defaults.removeObject(forKey: RightSidebarBetaFeatureSettings.feedEnabledKey) }
            if let previousDock { defaults.set(previousDock, forKey: RightSidebarBetaFeatureSettings.dockEnabledKey) }
            else { defaults.removeObject(forKey: RightSidebarBetaFeatureSettings.dockEnabledKey) }
        }

        let manager = TabManager()
        let workspace = try #require(manager.selectedWorkspace)
        let store = SidebarDockStore(edge: .right, windowId: UUID())
        #expect(SidebarDockSeeding.seedRightIfEmpty(
            store: store,
            workspace: workspace,
            preferredMode: .files
        ))
        let state = FileExplorerState()
        state.setVisible(true)

        for source in RightSidebarSelectionRouter.inventorySources {
            var context = RightSidebarSelectionContext(
                windowId: store.windowId,
                fileExplorerState: state,
                rightStore: store,
                isDockEnabled: true
            )
            // Use a rail mode for most sources; feed for paletteFeed / non-rail probes.
            let mode: RightSidebarMode
            switch source {
            case .paletteFeed:
                mode = .feed
            case .paletteDock, .shortcutDock, .dockPlacementReveal:
                mode = .dock
            case .paletteVault, .railTabSelect:
                mode = .sessions
            case .paletteFind, .findInDirectory, .contextualFind:
                mode = .find
            default:
                mode = .files
            }
            let focus = source != .remoteSetNoFocus
            let route = RightSidebarSelectionRouter.apply(
                RightSidebarSelectionRequest(mode: mode, focus: focus, source: source),
                in: &context
            )
            // Every inventory source must produce a concrete non-nil verdict.
            switch route {
            case .legacyModeWrite, .railStoreSelect, .nonRailPresentation, .rejected:
                break
            }
            if SidebarDockPlacementMatrix.allows(mode: mode) {
                #expect(route == .railStoreSelect, "source=\(source.rawValue) mode=\(mode.rawValue)")
            } else {
                #expect(route == .nonRailPresentation, "source=\(source.rawValue) mode=\(mode.rawValue)")
            }
        }
    }

    @Test func flagOffAndFlagOnDisagreeOnStoreRequirement() {
        let state = FileExplorerState()
        var off = RightSidebarSelectionContext(
            windowId: UUID(),
            fileExplorerState: state,
            rightStore: nil,
            isDockEnabled: false
        )
        #expect(
            RightSidebarSelectionRouter.apply(
                RightSidebarSelectionRequest(mode: .find, focus: false, source: .shortcutWindow),
                in: &off
            ) == .legacyModeWrite
        )

        var on = RightSidebarSelectionContext(
            windowId: UUID(),
            fileExplorerState: state,
            rightStore: nil,
            isDockEnabled: true
        )
        #expect(
            RightSidebarSelectionRouter.apply(
                RightSidebarSelectionRequest(mode: .find, focus: false, source: .shortcutWindow),
                in: &on
            ) == .rejected
        )
    }

    @Test func paletteSourceMapCoversRailAndExcludedModes() {
        #expect(RightSidebarSelectionRouter.paletteSource(for: .files) == .paletteFiles)
        #expect(RightSidebarSelectionRouter.paletteSource(for: .find) == .paletteFind)
        #expect(RightSidebarSelectionRouter.paletteSource(for: .sessions) == .paletteVault)
        #expect(RightSidebarSelectionRouter.paletteSource(for: .feed) == .paletteFeed)
        #expect(RightSidebarSelectionRouter.paletteSource(for: .dock) == .paletteDock)
    }
}
