import AppKit
import Foundation

#if DEBUG
/// DEBUG-only `debug.quad.*` tagged-socket surface for named-adapter dogfood
/// (VAL-QUAD-002 / VAL-QUAD-003 / D-34).
///
/// Invokes each production adapter's registered handler/callback. Never calls
/// ``QuadSplitAction/perform`` as an adapter substitute.
extension TerminalController {
    nonisolated static let quadSplitDebugMethodNames: [String] = [
        "debug.quad.adapter_perform",
        "debug.quad.adapters",
    ]

    /// Dispatch one `debug.quad.*` method. Returns `nil` when outside the
    /// namespace so the legacy switch can fall through.
    func v2DebugQuadSplit(method: String, params: [String: Any]) -> V2CallResult? {
        switch method {
        case "debug.quad.adapter_perform":
            return v2QuadAdapterPerform(params: params)
        case "debug.quad.adapters":
            return v2QuadAdaptersList(params: params)
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
            "topology": [
                "main_pane_count": topology.mainPaneCount,
                "dock_pane_count": topology.dockPaneCount,
                "main_pane_ids": topology.mainPaneIds.map(\.uuidString),
                "dock_pane_ids": topology.dockPaneIds.map(\.uuidString),
                "dock_surface_ids": topology.dockSurfaceIds.map(\.uuidString),
            ],
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
}
#endif
