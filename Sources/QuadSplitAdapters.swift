import AppKit
import Bonsplit
import CmuxControlSocket
import Foundation

/// Named production adapters for Split Quad (VAL-QUAD-002 / VAL-QUAD-003).
///
/// Every inventory entrypoint is one adapter id. DEBUG dogfood and tests must
/// invoke the adapter's registered production handler — never call
/// ``QuadSplitAction/perform`` as an adapter substitute.
@MainActor
enum QuadSplitAdapters {
    /// Stable adapter inventory matching the user-approved surface list.
    enum ID: String, CaseIterable, Sendable {
        case tabButton = "tab_button"
        case viewMenu = "view_menu"
        case primaryPalette = "primary_palette"
        case dockPalette = "dock_palette"
        case contextMenu = "context_menu"
        case shortcut = "shortcut"
        case cliV2 = "cli_v2"
        case cliLegacy = "cli_legacy"
    }

    /// Owner of a resolved quad target after earliest Dock/main resolution.
    enum Owner: Equatable {
        case dock(windowId: UUID, paneId: UUID, surfaceId: UUID?)
        case main(workspaceId: UUID, paneId: UUID, surfaceId: UUID)
    }

    /// Result of invoking one named production adapter.
    struct InvokeResult: Equatable {
        var adapterId: String
        var ownerKind: String
        var success: Bool
        var error: String?
        var mainPaneCountBefore: Int
        var mainPaneCountAfter: Int
        var dockPaneCountBefore: Int
        var dockPaneCountAfter: Int
        var resolvedSurfaceId: String?
        var resolvedPaneId: String?
        var resolvedWindowId: String?
    }

    /// Topology snapshot for before/after dogfood.
    struct TopologySnapshot: Equatable {
        var mainPaneCount: Int
        var dockPaneCount: Int
        var mainPaneIds: [UUID]
        var dockPaneIds: [UUID]
        var dockSurfaceIds: [UUID]
    }

    // MARK: - Inventory

    /// Every named production adapter id (stable order).
    static var allAdapterIds: [ID] { ID.allCases }

    static func parseAdapterId(_ raw: String) -> ID? {
        let token = raw.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        return ID(rawValue: token)
            ?? ID.allCases.first { $0.rawValue.replacingOccurrences(of: "_", with: "") == token.replacingOccurrences(of: "_", with: "")
                || $0.rawValue.replacingOccurrences(of: "_", with: "-") == token }
    }

    // MARK: - Topology

    static func captureTopology(
        main: Workspace?,
        dock: DockSplitStore?
    ) -> TopologySnapshot {
        let mainPanes = main?.bonsplitController.allPaneIds ?? []
        let dockPanes = dock?.bonsplitController.allPaneIds ?? []
        let dockSurfaces: [UUID] = {
            guard let dock else { return [] }
            return dock.panels.keys.sorted { $0.uuidString < $1.uuidString }
        }()
        return TopologySnapshot(
            mainPaneCount: mainPanes.count,
            dockPaneCount: dockPanes.count,
            mainPaneIds: mainPanes.map(\.id),
            dockPaneIds: dockPanes.map(\.id),
            dockSurfaceIds: dockSurfaces
        )
    }

    // MARK: - Shared focus/menu/palette/shortcut path

    /// Single shared UI path used by View menu, primary palette, Dock palette
    /// (configured action), and Settings-bound shortcut. Dock is tri-state:
    /// an applicable Dock failure never falls through to main.
    @discardableResult
    static func performSharedFocusPath(
        preferredWindow: NSWindow?,
        tabManager: TabManager?
    ) -> Bool {
        let window = preferredWindow ?? NSApp.keyWindow ?? NSApp.mainWindow
        if let appDelegate = AppDelegate.shared {
            switch appDelegate.routeQuadToFocusedDock(preferredWindow: window) {
            case .handled(let success):
                return success
            case .notApplicable:
                break
            }
            if appDelegate.performQuadSplitShortcut(preferredWindow: window) {
                return true
            }
        }
        return tabManager?.createQuadSplit(focus: true) == true
    }

    @discardableResult
    static func performAutoSplitSharedFocusPath(
        preferredWindow: NSWindow?,
        tabManager: TabManager?
    ) -> Bool {
        let window = preferredWindow ?? NSApp.keyWindow ?? NSApp.mainWindow
        if let appDelegate = AppDelegate.shared {
            switch appDelegate.routeAutoSplitToFocusedDock(preferredWindow: window) {
            case .handled(let success):
                return success
            case .notApplicable:
                break
            }
            if appDelegate.performAutoSplitShortcut(preferredWindow: window) {
                return true
            }
        }
        return tabManager?.createAutoSplit(focus: true) == true
    }

    @discardableResult
    static func performNextQuadPaneSharedFocusPath(
        preferredWindow: NSWindow?,
        tabManager: TabManager?
    ) -> Bool {
        let window = preferredWindow ?? NSApp.keyWindow ?? NSApp.mainWindow
        if let appDelegate = AppDelegate.shared,
           appDelegate.performNextQuadPaneShortcut(preferredWindow: window) {
            return true
        }
        return tabManager?.createNextQuadPane(focus: true) == true
    }

    @discardableResult
    static func performQuadPaneWorkspacesSharedFocusPath(
        preferredWindow: NSWindow?,
        tabManager: TabManager?
    ) -> Bool {
        let window = preferredWindow ?? NSApp.keyWindow ?? NSApp.mainWindow
        if let appDelegate = AppDelegate.shared,
           appDelegate.performQuadPaneWorkspacesShortcut(preferredWindow: window) {
            return true
        }
        return tabManager?.createQuadPaneWorkspaces(focus: true) == true
    }

    // MARK: - Earliest owner resolution (CLI / socket / explicit surface)

    /// Resolves the earliest window/surface owner for a quad request.
    ///
    /// Order:
    /// 1. Explicit surface id in a Dock panel → Dock only (never main fallthrough)
    /// 2. Explicit surface id in a main workspace → main
    /// 3. Focused Dock (keyboard / right-sidebar dock mode) → Dock only
    /// 4. Focused main workspace surface → main
    ///
    /// Invalid explicit targets return an error result without mutating either tree.
    enum ResolveOutcome {
        case dock(store: DockSplitStore, pane: PaneID, surfaceId: UUID?)
        case main(workspace: Workspace, surfaceId: UUID)
        case surfaceNotFound(UUID)
        case noFocusedSurface
        case workspaceNotFound
    }

    static func resolveOwner(
        preferredWindow: NSWindow?,
        tabManager: TabManager?,
        explicitSurfaceId: UUID?,
        appDelegate: AppDelegate? = AppDelegate.shared
    ) -> ResolveOutcome {
        // 1–2. Explicit surface: Dock first (earliest owner), then main workspaces.
        if let surfaceId = explicitSurfaceId {
            if let dock = appDelegate?.windowDockContainingPanel(surfaceId)
                ?? DockSplitStore.liveStores.first(where: { $0.containsPanel(surfaceId) }),
               let pane = dock.paneId(forPanelId: surfaceId) {
                return .dock(store: dock, pane: pane, surfaceId: surfaceId)
            }
            if let tabManager {
                for workspace in tabManager.tabs where workspace.panels[surfaceId] != nil {
                    return .main(workspace: workspace, surfaceId: surfaceId)
                }
            }
            // Global search across registered windows for main surfaces.
            if let appDelegate {
                for context in appDelegate.allMainWindowContextsForTesting() {
                    for workspace in context.tabManager.tabs where workspace.panels[surfaceId] != nil {
                        return .main(workspace: workspace, surfaceId: surfaceId)
                    }
                }
            }
            return .surfaceNotFound(surfaceId)
        }

        // 3. Focused Dock — applicable Dock never falls through to main.
        if let dock = appDelegate?.focusedDockStoreForShortcut(preferredWindow: preferredWindow) {
            if let pane = dock.resolvePane(requestedPaneID: nil) {
                let surface = dock.focusedPanelId
                    ?? dock.selectedPanelId(inPane: pane)
                return .dock(store: dock, pane: pane, surfaceId: surface)
            }
            return .noFocusedSurface
        }

        // 4. Focused main workspace surface.
        guard let tabManager else { return .workspaceNotFound }
        guard let workspace = tabManager.selectedWorkspace
            ?? tabManager.tabs.first(where: { $0.id == tabManager.selectedTabId })
            ?? tabManager.tabs.first else {
            return .workspaceNotFound
        }
        guard let surfaceId = workspace.focusedPanelId else {
            return .noFocusedSurface
        }
        return .main(workspace: workspace, surfaceId: surfaceId)
    }

    // MARK: - Named adapter invocation (production handlers)

    /// Invokes one named production adapter's registered handler/callback.
    ///
    /// Does **not** call ``QuadSplitAction/perform`` as a substitute for the
    /// adapter. Each branch re-enters the real production path for that surface.
    static func invokeProductionAdapter(
        _ adapter: ID,
        preferredWindow: NSWindow?,
        tabManager: TabManager?,
        explicitSurfaceId: UUID?,
        explicitDock: DockSplitStore? = nil,
        explicitWorkspace: Workspace? = nil,
        explicitPane: PaneID? = nil
    ) -> InvokeResult {
        let appDelegate = AppDelegate.shared
        let window = preferredWindow
            ?? appDelegate?.mainWindow(for: tabManager)
            ?? NSApp.keyWindow
            ?? NSApp.mainWindow
        let dock = explicitDock
            ?? appDelegate?.focusedDockStoreForShortcut(preferredWindow: window)
            ?? (tabManager.flatMap { appDelegate?.existingWindowDock(for: $0) })
            ?? (window.flatMap { win -> DockSplitStore? in
                guard let id = appDelegate?.windowId(forMainWindow: win) else { return nil }
                return appDelegate?.existingWindowDock(forWindowId: id)
            })
        let main = explicitWorkspace
            ?? tabManager?.selectedWorkspace
            ?? tabManager?.tabs.first
        let before = captureTopology(main: main, dock: dock)

        var success = false
        var error: String?
        var ownerKind = "none"
        var resolvedSurface: UUID?
        var resolvedPane: UUID?
        var resolvedWindow: UUID?

        switch adapter {
        case .tabButton:
            // Production: Workspace / Dock splitTabBar custom action callback.
            if let dock, let pane = explicitPane ?? dock.resolvePane(requestedPaneID: nil) {
                ownerKind = "dock"
                resolvedPane = pane.id
                resolvedSurface = dock.selectedPanelId(inPane: pane) ?? dock.focusedPanelId
                resolvedWindow = dock.workspaceId
                dock.splitTabBar(
                    dock.bonsplitController,
                    didRequestCustomAction: QuadSplitAction.customActionIdentifier,
                    inPane: pane
                )
                success = dock.bonsplitController.allPaneIds.count >= before.dockPaneCount + 3
                    || dock.bonsplitController.allPaneIds.count == 4
            } else if let workspace = main,
                      let pane = explicitPane
                        ?? workspace.bonsplitController.focusedPaneId
                        ?? workspace.bonsplitController.allPaneIds.first {
                ownerKind = "main"
                resolvedPane = pane.id
                resolvedSurface = workspace.focusedPanelId
                if let tabManager {
                    resolvedWindow = appDelegate?.windowId(for: tabManager)
                }
                workspace.splitTabBar(
                    workspace.bonsplitController,
                    didRequestCustomAction: QuadSplitAction.customActionIdentifier,
                    inPane: pane
                )
                success = workspace.bonsplitController.allPaneIds.count >= before.mainPaneCount + 3
                    || workspace.bonsplitController.allPaneIds.count == 4
            } else {
                error = "no_tab_button_target"
            }

        case .viewMenu, .primaryPalette, .dockPalette, .shortcut:
            // Production: shared focus path (menu / both palettes / shortcut).
            // Dock palette maps palette.terminalSplitQuad → .splitQuad configured
            // action, which uses the same tri-state Dock route.
            ownerKind = (appDelegate?.focusedDockStoreForShortcut(preferredWindow: window) != nil)
                ? "dock" : "main"
            success = performSharedFocusPath(preferredWindow: window, tabManager: tabManager)
            if let dock, ownerKind == "dock" {
                resolvedWindow = dock.workspaceId
                resolvedPane = dock.bonsplitController.focusedPaneId?.id
                resolvedSurface = dock.focusedPanelId
            } else if let main {
                if let tabManager {
                    resolvedWindow = appDelegate?.windowId(for: tabManager)
                }
                resolvedPane = main.bonsplitController.focusedPaneId?.id
                resolvedSurface = main.focusedPanelId
            }
            if !success { error = "adapter_failed" }

        case .contextMenu:
            // Production: GhosttyTerminalView.splitCurrentSurfaceQuad ownership
            // resolution — Dock-containing panel first, else workspace createQuadSplit.
            let surfaceId = explicitSurfaceId
                ?? dock?.focusedPanelId
                ?? main?.focusedPanelId
            guard let surfaceId else {
                error = "no_context_surface"
                break
            }
            resolvedSurface = surfaceId
            if let dockOwner = appDelegate?.windowDockContainingPanel(surfaceId)
                ?? DockSplitStore.liveStores.first(where: { $0.containsPanel(surfaceId) }),
               let pane = dockOwner.paneId(forPanelId: surfaceId) {
                ownerKind = "dock"
                resolvedPane = pane.id
                resolvedWindow = dockOwner.workspaceId
                // Real Dock context-menu handler body (same as GhosttyTerminalView).
                success = QuadSplitAdapters.ContextMenuHandler.performDock(
                    dock: dockOwner,
                    pane: pane
                )
            } else if let workspace = main ?? tabManager?.tabs.first(where: { $0.panels[surfaceId] != nil }),
                      let manager = tabManager ?? appDelegate?.tabManager {
                ownerKind = "main"
                resolvedPane = workspace.paneId(forPanelId: surfaceId)?.id
                resolvedWindow = appDelegate?.windowId(for: manager)
                success = QuadSplitAdapters.ContextMenuHandler.performMain(
                    tabManager: manager,
                    workspaceId: workspace.id,
                    surfaceId: surfaceId
                )
            } else {
                error = "context_surface_not_found"
            }

        case .cliV2:
            // Production: TerminalController.controlSurfaceSplit quad path.
            let controller = TerminalController.shared
            guard let manager = tabManager ?? appDelegate?.tabManager else {
                error = "tab_manager_unavailable"
                break
            }
            let surface = explicitSurfaceId
            let routing = ControlRoutingSelectors(
                hasWindowIDParam: window != nil,
                windowID: window.flatMap { appDelegate?.windowId(forMainWindow: $0) },
                groupID: nil,
                workspaceID: nil,
                surfaceID: surface,
                paneID: nil
            )
            let inputs = ControlSurfaceSplitInputs(
                directionRaw: "quad",
                typeRaw: nil,
                urlRaw: nil,
                requestedSourceSurfaceID: surface,
                workingDirectory: nil,
                initialCommand: nil,
                tmuxStartCommand: nil,
                remotePTYSessionID: nil,
                remoteContextRaw: nil,
                startupEnvironment: [:],
                clientUnsupportedRemoteTmuxOptions: [],
                requestedFocus: false,
                initialDividerPosition: nil
            )
            // Ensure active manager for resolveTabManager fallbacks.
            let previous = controller.activeTabManagerForCallerNotification()
            controller.setActiveTabManager(manager)
            defer { controller.setActiveTabManager(previous) }
            let resolution = controller.controlSurfaceSplit(routing: routing, inputs: inputs)
            switch resolution {
            case .created(_, let workspaceID, let paneID, let surfaceID, _):
                success = true
                resolvedSurface = surfaceID
                resolvedPane = paneID
                resolvedWindow = workspaceID
                // Owner kind from topology delta / dock containment.
                if let dock, dock.containsPanel(surfaceID) || dock.panels[surfaceID] != nil {
                    ownerKind = "dock"
                } else if DockSplitStore.liveStores.contains(where: { $0.containsPanel(surfaceID) }) {
                    ownerKind = "dock"
                } else {
                    ownerKind = "main"
                }
            case .requestedSurfaceNotFound(let id):
                error = "surface_not_found:\(id.uuidString)"
                ownerKind = "none"
            case .noFocusedSurface:
                error = "no_focused_surface"
            case .workspaceNotFound:
                error = "workspace_not_found"
            case .createFailed:
                error = "create_failed"
                // If dock was applicable, owner is still dock (handled failure).
                if appDelegate?.focusedDockStoreForShortcut(preferredWindow: window) != nil
                    || (surface.map { appDelegate?.windowDockContainingPanel($0) != nil } ?? false) {
                    ownerKind = "dock"
                }
            case .mirrorUnsupportedOptions:
                error = "mirror_unsupported"
            case .tabManagerUnavailable:
                error = "tab_manager_unavailable"
            case .invalidDirection:
                error = "invalid_direction"
            case .agentSessionRejected:
                error = "agent_session_rejected"
            case .browserDisabled:
                error = "browser_disabled"
            case .routedToRemote:
                error = "routed_to_remote"
            }

        case .cliLegacy:
            // Production: v1 `new_split` handler body via TerminalController.
            let controller = TerminalController.shared
            guard let manager = tabManager ?? appDelegate?.tabManager else {
                error = "tab_manager_unavailable"
                break
            }
            let previous = controller.activeTabManagerForCallerNotification()
            controller.setActiveTabManager(manager)
            defer { controller.setActiveTabManager(previous) }
            let arg: String
            if let surface = explicitSurfaceId {
                arg = "quad \(surface.uuidString)"
            } else {
                arg = "quad"
            }
            let response = controller.debugInvokeLegacyNewSplitForTests(arg)
            success = response.hasPrefix("OK")
            if !success {
                error = response
            }
            if success {
                let afterProbe = captureTopology(main: main, dock: dock)
                if afterProbe.dockPaneCount > before.dockPaneCount {
                    ownerKind = "dock"
                } else if afterProbe.mainPaneCount > before.mainPaneCount {
                    ownerKind = "main"
                } else if appDelegate?.focusedDockStoreForShortcut(preferredWindow: window) != nil {
                    ownerKind = "dock"
                } else {
                    ownerKind = "main"
                }
            }
        }

        let afterMain = explicitWorkspace
            ?? tabManager?.selectedWorkspace
            ?? tabManager?.tabs.first
            ?? main
        let afterDock = explicitDock
            ?? appDelegate?.focusedDockStoreForShortcut(preferredWindow: window)
            ?? dock
        let after = captureTopology(main: afterMain, dock: afterDock)

        return InvokeResult(
            adapterId: adapter.rawValue,
            ownerKind: ownerKind,
            success: success,
            error: error,
            mainPaneCountBefore: before.mainPaneCount,
            mainPaneCountAfter: after.mainPaneCount,
            dockPaneCountBefore: before.dockPaneCount,
            dockPaneCountAfter: after.dockPaneCount,
            resolvedSurfaceId: resolvedSurface?.uuidString,
            resolvedPaneId: resolvedPane?.uuidString,
            resolvedWindowId: resolvedWindow?.uuidString
        )
    }

    /// Context-menu production handlers extracted so DEBUG/tests re-enter the
    /// same ownership logic as ``GhosttyTerminalView`` without substituting
    /// a direct perform-only adapter.
    @MainActor
    enum ContextMenuHandler {
        @discardableResult
        static func performDock(dock: DockSplitStore, pane: PaneID) -> Bool {
            QuadSplitAction.perform(inPane: pane, dock: dock)
        }

        @discardableResult
        static func performMain(tabManager: TabManager, workspaceId: UUID, surfaceId: UUID) -> Bool {
            tabManager.createQuadSplit(tabId: workspaceId, surfaceId: surfaceId, focus: true)
        }
    }
}

// MARK: - Dock selected panel helper (adapters)

private extension DockSplitStore {
    func selectedPanelId(inPane pane: PaneID) -> UUID? {
        guard let tab = bonsplitController.selectedTab(inPane: pane) else { return nil }
        return surfaceIdToPanelId[tab.id]
    }
}

// MARK: - AppDelegate seams for adapter owner resolution

extension AppDelegate {
    /// All registered main window contexts (window id + tab manager).
    func allMainWindowContextsForTesting() -> [(windowId: UUID, tabManager: TabManager)] {
        mainWindowContexts.values.map { ($0.windowId, $0.tabManager) }
    }

    /// Window id for a main `NSWindow`, if registered.
    func windowId(forMainWindow window: NSWindow) -> UUID? {
        contextForMainWindow(window)?.windowId
    }

    /// Main window hosting the given tab manager, if any.
    func mainWindow(for tabManager: TabManager?) -> NSWindow? {
        guard let tabManager else { return nil }
        guard let windowId = windowId(for: tabManager) else { return nil }
        return mainWindow(for: windowId)
    }
}
