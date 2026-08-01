import AppKit
import Bonsplit
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

    // MARK: - VAL-RAIL-007 / 009 selection authority (D-32 R3 regression)

    /// R3 defect: mode focus must make the corresponding rail tab the authoritative
    /// selected tab (focused pane + selected tab + focused tool mode), including
    /// multi-section layouts and multi-tab sections.
    @Test func multiSectionModeFocusUpdatesAuthoritativeSelectedTab() throws {
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
            preferredMode: .sessions
        ))
        // Stack Files / Find / Vault into three sections (R3 multi-section fixture).
        let modes: [RightSidebarMode] = [.files, .find, .sessions]
        var tabByMode: [RightSidebarMode: TabID] = [:]
        for mode in modes {
            let panel = try #require(
                store.panels.values
                    .compactMap { $0 as? RightSidebarToolPanel }
                    .first(where: { $0.mode == mode })
            )
            let tab = try #require(store.surfaceId(forPanelId: panel.id))
            tabByMode[mode] = tab
        }
        let findTab = try #require(tabByMode[.find])
        let vaultTab = try #require(tabByMode[.sessions])
        #expect(store.moveTabToNewSection(findTab, position: .bottom))
        #expect(store.moveTabToNewSection(vaultTab, position: .bottom))
        #expect(store.sectionCount == 3)

        var context = RightSidebarSelectionContext(
            windowId: store.windowId,
            fileExplorerState: state,
            rightStore: store,
            isDockEnabled: true
        )
        for mode in modes {
            mirrorModes.removeAll()
            let route = RightSidebarSelectionRouter.apply(
                RightSidebarSelectionRequest(mode: mode, focus: true, source: .modeTabClick),
                in: &context
            )
            #expect(route == .railStoreSelect, "mode=\(mode.rawValue)")
            #expect(store.focusedToolMode() == mode, "focusedToolMode after \(mode.rawValue)")
            let tab = try #require(tabByMode[mode])
            let pane = try #require(store.paneId(forTabId: tab))
            #expect(store.bonsplitController.focusedPaneId == pane, "focused pane for \(mode.rawValue)")
            #expect(
                store.bonsplitController.selectedTab(inPane: pane)?.id == tab,
                "selected tab for \(mode.rawValue)"
            )
            #expect(state.mode == mode, "callback mirror for \(mode.rawValue)")
            #expect(mirrorModes.contains(mode), "mirror published for \(mode.rawValue)")

            // Dogfood inspect must expose the same authoritative selection.
            let edge = store.inspectEdgeSnapshot()
            let dict = edge.asEdgeDictionary()
            #expect(dict["focused_tool_mode"] as? String == mode.rawValue)
            #expect(dict["focused_pane_id"] as? String == pane.id.uuidString)
            #expect(dict["focused_selected_tab_id"] as? String == tab.uuid.uuidString)
            #expect(dict["selected_tab_id"] as? String == tab.uuid.uuidString)
        }

        // Multi-tab section: combine Vault into Files pane, switch selection by mode.
        let filesTab = try #require(tabByMode[.files])
        let filesPane = try #require(store.paneId(forTabId: filesTab))
        #expect(store.moveTab(vaultTab, toPane: filesPane))
        #expect(store.sectionCount == 2)
        RightSidebarSelectionRouter.apply(
            RightSidebarSelectionRequest(mode: .sessions, focus: true, source: .paletteVault),
            in: &context
        )
        #expect(store.focusedToolMode() == .sessions)
        #expect(store.bonsplitController.selectedTab(inPane: filesPane)?.id == vaultTab)
        RightSidebarSelectionRouter.apply(
            RightSidebarSelectionRequest(mode: .files, focus: true, source: .paletteFiles),
            in: &context
        )
        #expect(store.focusedToolMode() == .files)
        #expect(store.bonsplitController.selectedTab(inPane: filesPane)?.id == filesTab)
        #expect(state.mode == .files)
    }

    /// Window-scoped authority: two rails never share selection state.
    @Test func twoWindowsHaveIndependentSelectionAuthority() throws {
        let manager = TabManager()
        let workspace = try #require(manager.selectedWorkspace)
        let windowA = UUID()
        let windowB = UUID()
        let storeA = SidebarDockStore(edge: .right, windowId: windowA)
        let storeB = SidebarDockStore(edge: .right, windowId: windowB)
        let stateA = FileExplorerState()
        let stateB = FileExplorerState()
        stateA.mode = .files
        stateB.mode = .files
        storeA.onFocusedToolModeChanged = { mode in if let mode { stateA.mode = mode } }
        storeB.onFocusedToolModeChanged = { mode in if let mode { stateB.mode = mode } }
        #expect(SidebarDockSeeding.seedRightIfEmpty(store: storeA, workspace: workspace, preferredMode: .files))
        #expect(SidebarDockSeeding.seedRightIfEmpty(store: storeB, workspace: workspace, preferredMode: .files))

        var ctxA = RightSidebarSelectionContext(
            windowId: windowA,
            fileExplorerState: stateA,
            rightStore: storeA,
            isDockEnabled: true
        )
        var ctxB = RightSidebarSelectionContext(
            windowId: windowB,
            fileExplorerState: stateB,
            rightStore: storeB,
            isDockEnabled: true
        )
        #expect(
            RightSidebarSelectionRouter.apply(
                RightSidebarSelectionRequest(mode: .find, focus: true, source: .shortcutWindow),
                in: &ctxA
            ) == .railStoreSelect
        )
        #expect(
            RightSidebarSelectionRouter.apply(
                RightSidebarSelectionRequest(mode: .sessions, focus: true, source: .shortcutWindow),
                in: &ctxB
            ) == .railStoreSelect
        )
        #expect(storeA.focusedToolMode() == .find)
        #expect(storeB.focusedToolMode() == .sessions)
        #expect(stateA.mode == .find)
        #expect(stateB.mode == .sessions)
        // Cross-window request against A is rejected and leaves A unchanged.
        #expect(
            RightSidebarSelectionRouter.apply(
                RightSidebarSelectionRequest(
                    mode: .sessions,
                    focus: true,
                    source: .remoteSet,
                    windowId: windowB
                ),
                in: &ctxA
            ) == .rejected
        )
        #expect(storeA.focusedToolMode() == .find)
        #expect(stateA.mode == .find)
    }

    /// Competing scalar-only mode writes must not be treated as selection authority;
    /// only router → selectToolMode → Bonsplit callbacks update the rail tab.
    @Test func scalarModeWriteDoesNotSelectRailTabWithoutRouter() throws {
        let manager = TabManager()
        let workspace = try #require(manager.selectedWorkspace)
        let store = SidebarDockStore(edge: .right, windowId: UUID())
        let state = FileExplorerState()
        state.mode = .files
        store.onFocusedToolModeChanged = { mode in if let mode { state.mode = mode } }
        #expect(SidebarDockSeeding.seedRightIfEmpty(
            store: store,
            workspace: workspace,
            preferredMode: .files
        ))
        #expect(store.focusedToolMode() == .files)

        // R3-style competing write: only touch the legacy scalar.
        state.mode = .sessions
        #expect(store.focusedToolMode() == .files, "scalar write must not move rail selection")
        #expect(state.mode == .sessions)

        // Router is the sole public selection seam that updates authority.
        var context = RightSidebarSelectionContext(
            windowId: store.windowId,
            fileExplorerState: state,
            rightStore: store,
            isDockEnabled: true
        )
        #expect(
            RightSidebarSelectionRouter.apply(
                RightSidebarSelectionRequest(mode: .sessions, focus: true, source: .debugFocus),
                in: &context
            ) == .railStoreSelect
        )
        #expect(store.focusedToolMode() == .sessions)
        #expect(state.mode == .sessions)
    }

    /// Production adapters must route selection before keyboard focus so mode focus
    /// cannot land as a scalar-only write (VAL-RAIL-009 / D-32 R3).
    @Test func productionEntrypointsRouteSelectionBeforeFocus() throws {
        let root = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        let panelURL = root
            .appendingPathComponent("Sources")
            .appendingPathComponent("RightSidebarPanelView.swift")
        let panelSource = try String(contentsOf: panelURL, encoding: .utf8)
        // Mode bar must select through the router path, not only focusRightSidebar.
        #expect(panelSource.contains("selectMode(mode)"))
        #expect(
            panelSource.contains("routeRightSidebarSelection")
                || panelSource.contains("RightSidebarSelectionRouter.apply")
        )
        // Must not gate selectMode on focus failure (the R3 bypass).
        #expect(!panelSource.contains(") != true {\n                        selectMode(mode)"))
        #expect(panelSource.contains("Selection authority first"))

        let appURL = root
            .appendingPathComponent("Sources")
            .appendingPathComponent("AppDelegate.swift")
        let appSource = try String(contentsOf: appURL, encoding: .utf8)
        // Dock-on focus / show / debug reveal must ensure rail selection authority.
        #expect(appSource.contains("routeRightSidebarSelection"))
        #expect(appSource.contains("ensureRightSidebarRailSelection"))
        #expect(appSource.contains("source: .railPaneFocus"))

        let focusURL = root
            .appendingPathComponent("Sources")
            .appendingPathComponent("MainWindowFocusController.swift")
        let focusSource = try String(contentsOf: focusURL, encoding: .utf8)
        // No competing scalar mode write for dock rail tools.
        #expect(focusSource.contains("SidebarDockPlacementMatrix.allows"))
        #expect(focusSource.contains("isSidebarDockEnabled"))

        let inspectURL = root
            .appendingPathComponent("Sources")
            .appendingPathComponent("Sidebar")
            .appendingPathComponent("SidebarDockInspectSnapshot.swift")
        let inspectSource = try String(contentsOf: inspectURL, encoding: .utf8)
        #expect(inspectSource.contains("focused_tool_mode"))
        #expect(inspectSource.contains("focused_pane_id"))
        #expect(inspectSource.contains("focused_selected_tab_id"))
        #expect(inspectSource.contains("selected_tab_id"))
    }
}
