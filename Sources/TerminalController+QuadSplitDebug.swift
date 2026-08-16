import AppKit
import Bonsplit
import CmuxCore
import Foundation

#if DEBUG
/// DEBUG-only `debug.quad.*` tagged-socket surface for named-adapter dogfood
/// (VAL-QUAD-002 / VAL-QUAD-003) and running-app late-failure / veto observation
/// (VAL-QUAD-004 / D-34).
///
/// Adapter methods re-enter production adapters. Failure/veto methods configure
/// the existing ``QuadSplitAction`` injection seam and invoke the real shared
/// preflight/action path — never a parallel test-only split algorithm.
extension TerminalController {
    nonisolated static let quadSplitDebugMethodNames: [String] = [
        "debug.quad.adapter_perform",
        "debug.quad.adapters",
        "debug.quad.fail_after",
        "debug.quad.reset_hooks",
        "debug.quad.perform",
        "debug.quad.stage_fixture",
    ]

    /// Dispatch one `debug.quad.*` method. Returns `nil` when outside the
    /// namespace so the legacy switch can fall through.
    func v2DebugQuadSplit(method: String, params: [String: Any]) -> V2CallResult? {
        switch method {
        case "debug.quad.adapter_perform":
            return v2QuadAdapterPerform(params: params)
        case "debug.quad.adapters":
            return v2QuadAdaptersList(params: params)
        case "debug.quad.fail_after":
            return v2QuadFailAfterConfigure(params: params)
        case "debug.quad.reset_hooks":
            return v2QuadResetHooks(params: params)
        case "debug.quad.perform":
            return v2QuadPerformDogfood(params: params)
        case "debug.quad.stage_fixture":
            return v2QuadStageFixture(params: params)
        default:
            return nil
        }
    }

    // MARK: - adapters list

    /// Schema:
    /// ```
    /// debug.quad.adapters
    /// params: {}
    /// result: { adapters: [string] }
    /// ```
    private func v2QuadAdaptersList(params: [String: Any]) -> V2CallResult {
        .ok([
            "adapters": QuadSplitAdapters.allAdapterIds.map(\.rawValue),
        ])
    }

    // MARK: - fail_after configure

    /// Schema:
    /// ```
    /// debug.quad.fail_after
    /// params: {
    ///   completed_splits?: int|null,  // 1 or 2 to inject; null/0/omit clears
    ///   reset?: bool                  // when true, clear all testing hooks first
    /// }
    /// result: {
    ///   configured: true,
    ///   fail_after: int|null
    /// }
    /// ```
    private func v2QuadFailAfterConfigure(params: [String: Any]) -> V2CallResult {
        if v2Bool(params, "reset") == true {
            QuadSplitAction.resetTestingHooks()
        }
        let raw = params["completed_splits"] ?? params["fail_after"] ?? params["after"]
        let value: Int? = {
            if raw == nil || raw is NSNull { return nil }
            if let i = raw as? Int { return i }
            if let n = raw as? NSNumber { return n.intValue }
            if let s = raw as? String {
                let t = s.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
                if t.isEmpty || t == "null" || t == "nil" || t == "none" { return nil }
                return Int(t)
            }
            return v2Int(params, "completed_splits") ?? v2Int(params, "fail_after")
        }()
        if let value {
            guard value == 1 || value == 2 else {
                return .err(
                    code: "invalid_params",
                    message: "completed_splits must be 1, 2, or null",
                    data: ["completed_splits": value]
                )
            }
            QuadSplitAction.testingFailAfterCompletedSplits = value
        } else {
            QuadSplitAction.testingFailAfterCompletedSplits = nil
        }
        return .ok([
            "configured": true,
            "fail_after": QuadSplitAction.testingFailAfterCompletedSplits.map { $0 as Any }
                ?? NSNull(),
        ])
    }

    // MARK: - reset_hooks

    /// Schema:
    /// ```
    /// debug.quad.reset_hooks
    /// params: {}
    /// result: { reset: true, fail_after: null }
    /// ```
    private func v2QuadResetHooks(params: [String: Any]) -> V2CallResult {
        QuadSplitAction.resetTestingHooks()
        return .ok([
            "reset": true,
            "fail_after": NSNull(),
        ])
    }

    // MARK: - adapter_perform

    /// Schema:
    /// ```
    /// debug.quad.adapter_perform
    /// params: {
    ///   adapter: string,          // tab_button|view_menu|primary_palette|dock_palette|
    ///                             // context_menu|shortcut|cli_v2|cli_legacy
    ///   window_id?: uuid,
    ///   surface_id?: uuid,
    ///   focus?: bool
    /// }
    /// result: {
    ///   adapter_id, owner_kind, success, error?,
    ///   main_pane_count_before/after, dock_pane_count_before/after,
    ///   resolved_surface_id?, resolved_pane_id?, resolved_window_id?,
    ///   topology: { main_pane_ids, dock_pane_ids, dock_surface_ids }
    /// }
    /// ```
    private func v2QuadAdapterPerform(params: [String: Any]) -> V2CallResult {
        guard let adapterRaw = v2String(params, "adapter") ?? v2String(params, "adapter_id"),
              let adapter = QuadSplitAdapters.parseAdapterId(adapterRaw) else {
            return .err(
                code: "invalid_params",
                message: "Missing or unknown adapter id",
                data: [
                    "known": QuadSplitAdapters.allAdapterIds.map(\.rawValue),
                    "adapter": (params["adapter"] as? String)
                        ?? (params["adapter_id"] as? String)
                        ?? "",
                ]
            )
        }

        let windowId = v2UUID(params, "window_id")
        let surfaceId = v2UUID(params, "surface_id")
        let preferredWindow: NSWindow? = {
            if let windowId {
                return AppDelegate.shared?.mainWindow(for: windowId)
            }
            return NSApp.keyWindow ?? NSApp.mainWindow
        }()
        let tabManager: TabManager? = {
            if let windowId, let manager = AppDelegate.shared?.tabManagerFor(windowId: windowId) {
                return manager
            }
            if let preferredWindow,
               let context = AppDelegate.shared?.contextForMainWindow(preferredWindow) {
                return context.tabManager
            }
            return self.tabManager ?? AppDelegate.shared?.tabManager
        }()

        let result = QuadSplitAdapters.invokeProductionAdapter(
            adapter,
            preferredWindow: preferredWindow,
            tabManager: tabManager,
            explicitSurfaceId: surfaceId
        )

        let dock = AppDelegate.shared?.focusedDockStoreForShortcut(preferredWindow: preferredWindow)
            ?? (tabManager.flatMap { AppDelegate.shared?.existingWindowDock(for: $0) })
        let main = tabManager?.selectedWorkspace ?? tabManager?.tabs.first
        let topology = QuadSplitAdapters.captureTopology(main: main, dock: dock)

        var payload: [String: Any] = [
            "adapter_id": result.adapterId,
            "owner_kind": result.ownerKind,
            "success": result.success,
            "main_pane_count_before": result.mainPaneCountBefore,
            "main_pane_count_after": result.mainPaneCountAfter,
            "dock_pane_count_before": result.dockPaneCountBefore,
            "dock_pane_count_after": result.dockPaneCountAfter,
            "topology": topologyPayload(topology),
        ]
        if let error = result.error {
            payload["error"] = error
        }
        if let surface = result.resolvedSurfaceId {
            payload["resolved_surface_id"] = surface
        }
        if let pane = result.resolvedPaneId {
            payload["resolved_pane_id"] = pane
        }
        if let window = result.resolvedWindowId {
            payload["resolved_window_id"] = window
        }
        return .ok(payload)
    }

    // MARK: - stage_fixture

    /// Schema:
    /// ```
    /// debug.quad.stage_fixture
    /// params: {
    ///   fixture: string,   // local|local_success|dock|canvas|empty_dock|
    ///                      // remote_connecting|remote_disconnected|remote_unresolved|
    ///                      // missing_target
    ///   window_id?: uuid,
    ///   workspace_id?: uuid
    /// }
    /// result: {
    ///   fixture, owner_kind, surface_id?, pane_id?, workspace_id?, window_id?,
    ///   staged: true
    /// }
    /// ```
    private func v2QuadStageFixture(params: [String: Any]) -> V2CallResult {
        guard let fixtureRaw = v2String(params, "fixture") ?? v2String(params, "name") else {
            return .err(
                code: "invalid_params",
                message: "Missing fixture name",
                data: [
                    "known": Self.quadFixtureNames,
                ]
            )
        }
        let fixture = fixtureRaw.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
            .replacingOccurrences(of: "-", with: "_")

        let windowId = v2UUID(params, "window_id")
        let preferredWindow: NSWindow? = {
            if let windowId { return AppDelegate.shared?.mainWindow(for: windowId) }
            return NSApp.keyWindow ?? NSApp.mainWindow
        }()
        let tabManager: TabManager? = {
            if let windowId, let manager = AppDelegate.shared?.tabManagerFor(windowId: windowId) {
                return manager
            }
            if let preferredWindow,
               let context = AppDelegate.shared?.contextForMainWindow(preferredWindow) {
                return context.tabManager
            }
            return self.tabManager ?? AppDelegate.shared?.tabManager
        }()
        guard let tabManager else {
            return .err(code: "not_found", message: "No tab manager for fixture staging", data: nil)
        }

        let workspaceId = v2UUID(params, "workspace_id")
        let workspace: Workspace? = {
            if let workspaceId {
                return tabManager.tabs.first(where: { $0.id == workspaceId })
            }
            return tabManager.selectedWorkspace ?? tabManager.tabs.first
        }()
        guard let workspace else {
            return .err(code: "not_found", message: "Workspace not found for fixture", data: nil)
        }

        let resolvedWindowId = windowId
            ?? AppDelegate.shared?.windowId(for: tabManager)
        let dock = {
            if let resolvedWindowId {
                return AppDelegate.shared?.existingWindowDock(forWindowId: resolvedWindowId)
                    ?? AppDelegate.shared?.windowDock(forWindowId: resolvedWindowId)
            }
            return AppDelegate.shared?.existingWindowDock(for: tabManager)
        }()

        switch fixture {
        case "local", "local_success":
            // Ensure a focused local terminal surface.
            if workspace.focusedPanelId == nil,
               let pane = workspace.bonsplitController.allPaneIds.first {
                _ = workspace.newTerminalSurface(
                    inPane: pane,
                    inheritWorkingDirectoryFallback: true
                )
            }
            workspace.layoutMode = .splits
            workspace.remoteConfiguration = nil
            workspace.remoteConnectionState = .disconnected
            workspace.isRemoteTmuxMirror = false
            guard let surface = workspace.focusedPanelId,
                  let pane = workspace.bonsplitController.focusedPaneId
                    ?? workspace.bonsplitController.allPaneIds.first else {
                return .err(code: "failed", message: "Could not stage local surface", data: nil)
            }
            return .ok([
                "fixture": fixture,
                "owner_kind": "main",
                "surface_id": surface.uuidString,
                "pane_id": pane.id.uuidString,
                "workspace_id": workspace.id.uuidString,
                "window_id": resolvedWindowId.map { $0.uuidString as Any } ?? NSNull(),
                "staged": true,
            ])

        case "dock":
            guard let dock else {
                return .err(code: "not_found", message: "Dock store not available", data: nil)
            }
            let root = dock.bonsplitController.allPaneIds.first
            guard let root else {
                return .err(code: "failed", message: "Dock has no root pane", data: nil)
            }
            let surface: UUID = {
                if let existing = dock.focusedPanelId
                    ?? dock.resolveSourcePanelId(nil, preferredPaneId: root) {
                    return existing
                }
                return dock.newSurface(kind: .terminal, inPane: root, focus: true)
                    ?? dock.focusedPanelId
                    ?? UUID()
            }()
            guard dock.containsPanel(surface),
                  let pane = dock.paneId(forPanelId: surface) else {
                return .err(code: "failed", message: "Could not stage dock surface", data: nil)
            }
            if let window = preferredWindow {
                AppDelegate.shared?.noteRightSidebarKeyboardFocusIntent(mode: .dock, in: window)
            }
            return .ok([
                "fixture": fixture,
                "owner_kind": "dock",
                "surface_id": surface.uuidString,
                "pane_id": pane.id.uuidString,
                "workspace_id": dock.workspaceId.uuidString,
                "window_id": resolvedWindowId.map { $0.uuidString as Any } ?? NSNull(),
                "staged": true,
            ])

        case "empty_dock":
            guard let dock else {
                return .err(code: "not_found", message: "Dock store not available", data: nil)
            }
            // Strip all surfaces so preflight returns emptyDockSource on the root pane.
            dock.removeAllPanels()
            let root = dock.bonsplitController.allPaneIds.first
            guard let root else {
                return .err(code: "failed", message: "Dock has no root pane after empty stage", data: nil)
            }
            if let window = preferredWindow {
                AppDelegate.shared?.noteRightSidebarKeyboardFocusIntent(mode: .dock, in: window)
            }
            return .ok([
                "fixture": fixture,
                "owner_kind": "dock",
                "surface_id": NSNull(),
                "pane_id": root.id.uuidString,
                "workspace_id": dock.workspaceId.uuidString,
                "window_id": resolvedWindowId.map { $0.uuidString as Any } ?? NSNull(),
                "staged": true,
                "empty": true,
            ])

        case "canvas":
            workspace.layoutMode = .canvas
            workspace.remoteConfiguration = nil
            workspace.remoteConnectionState = .disconnected
            workspace.isRemoteTmuxMirror = false
            guard let surface = workspace.focusedPanelId,
                  let pane = workspace.bonsplitController.focusedPaneId
                    ?? workspace.bonsplitController.allPaneIds.first else {
                return .err(code: "failed", message: "Could not stage canvas surface", data: nil)
            }
            return .ok([
                "fixture": fixture,
                "owner_kind": "main",
                "surface_id": surface.uuidString,
                "pane_id": pane.id.uuidString,
                "workspace_id": workspace.id.uuidString,
                "window_id": resolvedWindowId.map { $0.uuidString as Any } ?? NSNull(),
                "staged": true,
                "layout_mode": "canvas",
            ])

        case "remote_connecting":
            workspace.layoutMode = .splits
            workspace.isRemoteTmuxMirror = false
            workspace.remoteConfiguration = Self.quadDebugRemoteConfiguration()
            workspace.remoteConnectionState = .connecting
            guard let surface = workspace.focusedPanelId,
                  let pane = workspace.bonsplitController.focusedPaneId
                    ?? workspace.bonsplitController.allPaneIds.first else {
                return .err(code: "failed", message: "Could not stage remote connecting surface", data: nil)
            }
            return .ok([
                "fixture": fixture,
                "owner_kind": "main",
                "surface_id": surface.uuidString,
                "pane_id": pane.id.uuidString,
                "workspace_id": workspace.id.uuidString,
                "window_id": resolvedWindowId.map { $0.uuidString as Any } ?? NSNull(),
                "staged": true,
                "remote_state": "connecting",
            ])

        case "remote_disconnected":
            workspace.layoutMode = .splits
            workspace.isRemoteTmuxMirror = false
            workspace.remoteConfiguration = Self.quadDebugRemoteConfiguration()
            workspace.remoteConnectionState = .disconnected
            guard let surface = workspace.focusedPanelId,
                  let pane = workspace.bonsplitController.focusedPaneId
                    ?? workspace.bonsplitController.allPaneIds.first else {
                return .err(code: "failed", message: "Could not stage remote disconnected surface", data: nil)
            }
            return .ok([
                "fixture": fixture,
                "owner_kind": "main",
                "surface_id": surface.uuidString,
                "pane_id": pane.id.uuidString,
                "workspace_id": workspace.id.uuidString,
                "window_id": resolvedWindowId.map { $0.uuidString as Any } ?? NSNull(),
                "staged": true,
                "remote_state": "disconnected",
            ])

        case "remote_unresolved":
            workspace.layoutMode = .splits
            workspace.isRemoteTmuxMirror = false
            workspace.remoteConfiguration = Self.quadDebugRemoteConfiguration()
            workspace.remoteConnectionState = .connected
            guard let surface = workspace.focusedPanelId,
                  let pane = workspace.bonsplitController.focusedPaneId
                    ?? workspace.bonsplitController.allPaneIds.first else {
                return .err(code: "failed", message: "Could not stage remote unresolved surface", data: nil)
            }
            workspace.trackRemoteTerminalSurface(surface)
            return .ok([
                "fixture": fixture,
                "owner_kind": "main",
                "surface_id": surface.uuidString,
                "pane_id": pane.id.uuidString,
                "workspace_id": workspace.id.uuidString,
                "window_id": resolvedWindowId.map { $0.uuidString as Any } ?? NSNull(),
                "staged": true,
                "remote_state": "connected",
                "remote_unresolved": true,
            ])

        case "missing_target":
            // Staging only records a bogus id; caller must pass surface_id.
            return .ok([
                "fixture": fixture,
                "owner_kind": "main",
                "surface_id": UUID().uuidString,
                "pane_id": NSNull(),
                "workspace_id": workspace.id.uuidString,
                "window_id": resolvedWindowId.map { $0.uuidString as Any } ?? NSNull(),
                "staged": true,
                "bogus": true,
            ])

        default:
            return .err(
                code: "invalid_params",
                message: "Unknown fixture",
                data: [
                    "fixture": fixture,
                    "known": Self.quadFixtureNames,
                ]
            )
        }
    }

    // MARK: - perform (shared action + diagnostics)

    /// Schema:
    /// ```
    /// debug.quad.perform
    /// params: {
    ///   surface_id?: uuid,
    ///   pane_id?: uuid,
    ///   window_id?: uuid,
    ///   workspace_id?: uuid,
    ///   owner?: "auto"|"main"|"dock",
    ///   fail_after?: 1|2,     // atomic for this call; always reset after
    ///   fixture?: string      // optional stage_fixture first
    /// }
    /// result: {
    ///   outcome: success|vetoed|late_failure|error,
    ///   veto?, preflight_veto?, completed_splits?, error?,
    ///   owner_kind, known_vetoes,
    ///   topology_before, topology_after,
    ///   remote_command_log, late_failure_events,
    ///   fail_after_was, fail_after_after_reset,
    ///   resolved_surface_id?, resolved_pane_id?, resolved_window_id?, workspace_id?
    /// }
    /// ```
    ///
    /// Always resets testing hooks after the call (including on early error).
    private func v2QuadPerformDogfood(params: [String: Any]) -> V2CallResult {
        // Optional fixture staging shares the same process path validators use.
        if let fixture = v2String(params, "fixture"), !fixture.isEmpty {
            let staged = v2QuadStageFixture(params: params)
            if case .err = staged {
                return staged
            }
            // Merge staged surface into params when caller omitted surface_id.
            if params["surface_id"] == nil,
               case .ok(let bodyAny) = staged,
               let body = bodyAny as? [String: Any],
               let surface = body["surface_id"] as? String {
                var merged = params
                merged["surface_id"] = surface
                if params["owner"] == nil, let owner = body["owner_kind"] as? String {
                    merged["owner"] = owner
                }
                return v2QuadPerformDogfoodCore(params: merged)
            }
        }
        return v2QuadPerformDogfoodCore(params: params)
    }

    private func v2QuadPerformDogfoodCore(params: [String: Any]) -> V2CallResult {
        let failAfterRequested: Int? = {
            let raw = params["fail_after"] ?? params["completed_splits"]
            if raw == nil || raw is NSNull { return nil }
            if let i = raw as? Int { return i }
            if let n = raw as? NSNumber { return n.intValue }
            if let s = raw as? String { return Int(s) }
            return v2Int(params, "fail_after") ?? v2Int(params, "completed_splits")
        }()

        // Snapshot logs before any mutation so vetoes prove no remote side effects.
        let remoteLogBefore = QuadSplitAction.testingRemoteCommandLog
        let lateEventsBefore = QuadSplitAction.testingLateFailureEvents

        // Atomic configure for this dogfood call; always reset in defer.
        // Skip live transient-focus geometry probe so explicit-surface dogfood is
        // not spuriously vetoed by zero-size harness / non-key windows. Catalog
        // tests still force the veto via testingForceTransientFocusSuppressed.
        QuadSplitAction.testingSkipLiveTransientFocusProbe = true
        if let failAfterRequested {
            guard failAfterRequested == 1 || failAfterRequested == 2 else {
                QuadSplitAction.resetTestingHooks()
                return .err(
                    code: "invalid_params",
                    message: "fail_after must be 1 or 2",
                    data: ["fail_after": failAfterRequested]
                )
            }
            QuadSplitAction.testingFailAfterCompletedSplits = failAfterRequested
        }
        defer {
            // Safe reset after every dogfood call (success, veto, late failure, error).
            QuadSplitAction.resetTestingHooks()
        }

        let windowId = v2UUID(params, "window_id")
        let surfaceId = v2UUID(params, "surface_id")
        let paneIdParam = v2UUID(params, "pane_id")
        let ownerToken = (v2String(params, "owner") ?? v2String(params, "owner_kind") ?? "auto")
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased()

        let preferredWindow: NSWindow? = {
            if let windowId { return AppDelegate.shared?.mainWindow(for: windowId) }
            return NSApp.keyWindow ?? NSApp.mainWindow
        }()
        let tabManager: TabManager? = {
            if let windowId, let manager = AppDelegate.shared?.tabManagerFor(windowId: windowId) {
                return manager
            }
            if let preferredWindow,
               let context = AppDelegate.shared?.contextForMainWindow(preferredWindow) {
                return context.tabManager
            }
            return self.tabManager ?? AppDelegate.shared?.tabManager
        }()

        let dockForTopo = AppDelegate.shared?.focusedDockStoreForShortcut(preferredWindow: preferredWindow)
            ?? (windowId.flatMap { AppDelegate.shared?.existingWindowDock(forWindowId: $0) })
            ?? (tabManager.flatMap { AppDelegate.shared?.existingWindowDock(for: $0) })
        let mainForTopo: Workspace? = {
            if let workspaceId = v2UUID(params, "workspace_id"),
               let tm = tabManager,
               let ws = tm.tabs.first(where: { $0.id == workspaceId }) {
                return ws
            }
            return tabManager?.selectedWorkspace ?? tabManager?.tabs.first
        }()

        let topologyBefore = QuadSplitAdapters.captureTopology(main: mainForTopo, dock: dockForTopo)

        // Resolve owner: explicit owner preference, else earliest Dock/main resolution.
        enum Resolved {
            case dock(DockSplitStore, PaneID, UUID?)
            case main(Workspace, PaneID, UUID?)
            case error(String, String) // code, message
        }

        let resolved: Resolved = {
            switch ownerToken {
            case "dock":
                guard let dock = dockForTopo
                    ?? tabManager.flatMap({ AppDelegate.shared?.existingWindowDock(for: $0) })
                    ?? (windowId.flatMap { AppDelegate.shared?.windowDock(forWindowId: $0) })
                else {
                    return .error("not_found", "Dock owner not available")
                }
                if let surfaceId, let pane = dock.paneId(forPanelId: surfaceId) {
                    return .dock(dock, pane, surfaceId)
                }
                if let paneIdParam,
                   let pane = dock.bonsplitController.allPaneIds.first(where: { $0.id == paneIdParam }) {
                    return .dock(
                        dock,
                        pane,
                        dock.resolveSourcePanelId(nil, preferredPaneId: pane) ?? dock.focusedPanelId
                    )
                }
                if let pane = dock.resolvePane(requestedPaneID: nil) {
                    return .dock(
                        dock,
                        pane,
                        dock.focusedPanelId ?? dock.resolveSourcePanelId(nil, preferredPaneId: pane)
                    )
                }
                // Empty dock: still resolve a root pane for preflight emptyDockSource.
                if let root = dock.bonsplitController.allPaneIds.first {
                    return .dock(dock, root, nil)
                }
                return .error("not_found", "No Dock pane for perform")

            case "main":
                guard let workspace = mainForTopo else {
                    return .error("not_found", "Main workspace not available")
                }
                if let surfaceId {
                    if let pane = workspace.paneId(forPanelId: surfaceId) {
                        return .main(workspace, pane, surfaceId)
                    }
                    // Explicit surface not in main — surface not found (no Dock fallthrough
                    // when owner is forced main).
                    return .error("not_found", "Surface not found in main owner")
                }
                if let paneIdParam,
                   let pane = workspace.bonsplitController.allPaneIds.first(where: { $0.id == paneIdParam }) {
                    return .main(workspace, pane, workspace.focusedPanelId)
                }
                if let pane = workspace.bonsplitController.focusedPaneId
                    ?? workspace.bonsplitController.allPaneIds.first {
                    return .main(workspace, pane, workspace.focusedPanelId)
                }
                return .error("not_found", "No main pane for perform")

            default:
                // auto: earliest Dock/main resolution (same order as CLI adapters).
                let outcome = QuadSplitAdapters.resolveOwner(
                    preferredWindow: preferredWindow,
                    tabManager: tabManager,
                    explicitSurfaceId: surfaceId
                )
                switch outcome {
                case .dock(let store, let pane, let surface):
                    return .dock(store, pane, surface)
                case .main(let workspace, let surface):
                    if let pane = workspace.paneId(forPanelId: surface)
                        ?? workspace.bonsplitController.focusedPaneId
                        ?? workspace.bonsplitController.allPaneIds.first {
                        return .main(workspace, pane, surface)
                    }
                    return .error("not_found", "Main pane unresolved for surface")
                case .surfaceNotFound(let id):
                    return .error("not_found", "Surface not found: \(id.uuidString)")
                case .noFocusedSurface:
                    return .error("not_found", "No focused surface")
                case .workspaceNotFound:
                    return .error("not_found", "Workspace not found")
                }
            }
        }()

        let knownVetoes = QuadSplitAction.Veto.allCases.map(\.rawValue)

        switch resolved {
        case .error(let code, let message):
            let topologyAfter = QuadSplitAdapters.captureTopology(main: mainForTopo, dock: dockForTopo)
            return .ok([
                "outcome": "error",
                "error": message,
                "error_code": code,
                "veto": NSNull(),
                "preflight_veto": NSNull(),
                "completed_splits": NSNull(),
                "owner_kind": "none",
                "known_vetoes": knownVetoes,
                "topology_before": topologyPayload(topologyBefore),
                "topology_after": topologyPayload(topologyAfter),
                "remote_command_log": remoteLogBefore,
                "late_failure_events": lateEventsBefore,
                "fail_after_was": failAfterRequested.map { $0 as Any } ?? NSNull(),
                "fail_after_after_reset": NSNull(),
            ])

        case .dock(let dock, let pane, let surface):
            let preflight = QuadSplitAction.preflight(inPane: pane, dock: dock)
            let outcome = QuadSplitAction.performDetailed(inPane: pane, dock: dock)
            let topologyAfter = QuadSplitAdapters.captureTopology(
                main: mainForTopo,
                dock: dock
            )
            return .ok(buildPerformPayload(
                outcome: outcome,
                preflight: preflight,
                ownerKind: "dock",
                knownVetoes: knownVetoes,
                topologyBefore: topologyBefore,
                topologyAfter: topologyAfter,
                remoteLogBefore: remoteLogBefore,
                lateEventsBefore: lateEventsBefore,
                failAfterWas: failAfterRequested,
                surfaceId: surface,
                paneId: pane.id,
                windowId: dock.workspaceId,
                workspaceId: dock.workspaceId
            ))

        case .main(let workspace, let pane, let surface):
            let preflight = QuadSplitAction.preflight(inPane: pane, workspace: workspace)
            let outcome = QuadSplitAction.performDetailed(inPane: pane, workspace: workspace)
            let topologyAfter = QuadSplitAdapters.captureTopology(
                main: workspace,
                dock: dockForTopo
            )
            let winId = windowId ?? tabManager.flatMap { AppDelegate.shared?.windowId(for: $0) }
            return .ok(buildPerformPayload(
                outcome: outcome,
                preflight: preflight,
                ownerKind: "main",
                knownVetoes: knownVetoes,
                topologyBefore: topologyBefore,
                topologyAfter: topologyAfter,
                remoteLogBefore: remoteLogBefore,
                lateEventsBefore: lateEventsBefore,
                failAfterWas: failAfterRequested,
                surfaceId: surface,
                paneId: pane.id,
                windowId: winId,
                workspaceId: workspace.id
            ))
        }
    }

    private func buildPerformPayload(
        outcome: QuadSplitAction.Outcome,
        preflight: QuadSplitAction.Veto?,
        ownerKind: String,
        knownVetoes: [String],
        topologyBefore: QuadSplitAdapters.TopologySnapshot,
        topologyAfter: QuadSplitAdapters.TopologySnapshot,
        remoteLogBefore: [String],
        lateEventsBefore: [String],
        failAfterWas: Int?,
        surfaceId: UUID?,
        paneId: UUID?,
        windowId: UUID?,
        workspaceId: UUID?
    ) -> [String: Any] {
        let outcomeString: String
        var vetoRaw: String? = preflight?.rawValue
        var completedSplits: Int?
        var error: String?

        switch outcome {
        case .success:
            outcomeString = "success"
        case .vetoed(let veto):
            outcomeString = "vetoed"
            vetoRaw = veto.rawValue
            error = "vetoed:\(veto.rawValue)"
        case .lateFailure(let completed):
            outcomeString = "late_failure"
            completedSplits = completed
            error = "late_failure:completed_splits=\(completed)"
        }

        // Remote log / late events after the shared action (no production remote
        // delegate writes to testingRemoteCommandLog; equality proves no probe mutation).
        let remoteLogAfter = QuadSplitAction.testingRemoteCommandLog
        let lateEventsAfter = QuadSplitAction.testingLateFailureEvents
        // Include only events appended during this call for the snapshot, plus full probe.
        let newLateEvents = Array(lateEventsAfter.dropFirst(lateEventsBefore.count))

        var payload: [String: Any] = [
            "outcome": outcomeString,
            "veto": vetoRaw.map { $0 as Any } ?? NSNull(),
            "preflight_veto": preflight.map { $0.rawValue as Any } ?? NSNull(),
            "completed_splits": completedSplits.map { $0 as Any } ?? NSNull(),
            "error": error.map { $0 as Any } ?? NSNull(),
            "owner_kind": ownerKind,
            "known_vetoes": knownVetoes,
            "topology_before": topologyPayload(topologyBefore),
            "topology_after": topologyPayload(topologyAfter),
            "remote_command_log": remoteLogAfter,
            "remote_command_log_unchanged": remoteLogAfter == remoteLogBefore,
            "late_failure_events": newLateEvents.isEmpty ? lateEventsAfter : newLateEvents,
            "fail_after_was": failAfterWas.map { $0 as Any } ?? NSNull(),
            // defer resets hooks after we build the payload but before return to
            // the socket; document the post-reset contract explicitly.
            "fail_after_after_reset": NSNull(),
        ]
        if let surfaceId {
            payload["resolved_surface_id"] = surfaceId.uuidString
        }
        if let paneId {
            payload["resolved_pane_id"] = paneId.uuidString
        }
        if let windowId {
            payload["resolved_window_id"] = windowId.uuidString
        }
        if let workspaceId {
            payload["workspace_id"] = workspaceId.uuidString
        }
        return payload
    }

    private func topologyPayload(_ snap: QuadSplitAdapters.TopologySnapshot) -> [String: Any] {
        [
            "main_pane_count": snap.mainPaneCount,
            "dock_pane_count": snap.dockPaneCount,
            "main_pane_ids": snap.mainPaneIds.map(\.uuidString),
            "dock_pane_ids": snap.dockPaneIds.map(\.uuidString),
            "dock_surface_ids": snap.dockSurfaceIds.map(\.uuidString),
        ]
    }

    private static let quadFixtureNames: [String] = [
        "local",
        "local_success",
        "dock",
        "canvas",
        "empty_dock",
        "remote_connecting",
        "remote_disconnected",
        "remote_unresolved",
        "missing_target",
    ]

    private static func quadDebugRemoteConfiguration() -> WorkspaceRemoteConfiguration {
        WorkspaceRemoteConfiguration(
            destination: "cmux-quad-debug-fixture.example.invalid",
            port: nil,
            identityFile: nil,
            sshOptions: [],
            localProxyPort: nil,
            relayPort: nil,
            relayID: nil,
            relayToken: nil,
            localSocketPath: nil,
            terminalStartupCommand: nil
        )
    }
}
#endif
