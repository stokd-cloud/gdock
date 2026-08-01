import AppKit
import Bonsplit
import Foundation

#if DEBUG
/// DEBUG-only `debug.sidebar_dock.*` tagged-socket surface for rail dogfood.
///
/// Dogfood scaffolding only — not a substitute for public palette/context/drag
/// controls. Every mutation routes through the same store/invoker/drop-handler
/// paths production UI uses.
extension TerminalController {
    /// Registered DEBUG method names under the `debug.sidebar_dock` namespace.
    nonisolated static let sidebarDockDebugMethodNames: [String] = [
        "debug.sidebar_dock.inspect",
        "debug.sidebar_dock.perform_command",
        "debug.sidebar_dock.simulate_drop",
        "debug.sidebar_dock.reorder_section",
        "debug.sidebar_dock.divider_drag",
        "debug.sidebar_dock.resize_rail",
        "debug.sidebar_dock.refuse_paths",
    ]

    /// Dispatch one `debug.sidebar_dock.*` method. Returns `nil` when the
    /// method is outside the namespace so the legacy switch can fall through.
    func v2DebugSidebarDock(method: String, params: [String: Any]) -> V2CallResult? {
        switch method {
        case "debug.sidebar_dock.inspect":
            return v2SidebarDockInspect(params: params)
        case "debug.sidebar_dock.perform_command":
            return v2SidebarDockPerformCommand(params: params)
        case "debug.sidebar_dock.simulate_drop":
            return v2SidebarDockSimulateDrop(params: params)
        case "debug.sidebar_dock.reorder_section":
            return v2SidebarDockReorderSection(params: params)
        case "debug.sidebar_dock.divider_drag":
            return v2SidebarDockDividerDrag(params: params)
        case "debug.sidebar_dock.resize_rail":
            return v2SidebarDockResizeRail(params: params)
        case "debug.sidebar_dock.refuse_paths":
            return v2SidebarDockRefusePaths(params: params)
        default:
            return nil
        }
    }

    // MARK: - inspect

    /// Schema:
    /// ```
    /// debug.sidebar_dock.inspect
    /// params: { window_id?: uuid, edge?: "left"|"right" }
    /// result: SidebarDockInspectSnapshot dictionary (both edges, or one when edge set)
    /// ```
    private func v2SidebarDockInspect(params: [String: Any]) -> V2CallResult {
        guard let resolved = resolveSidebarDockRegistry(params: params) else {
            return .err(code: "not_found", message: "No sidebar dock registry for window", data: nil)
        }
        let dockEnabled = RightSidebarBetaFeatureSettings.isSidebarDockEnabled()
        var snapshot = SidebarDockInspectBuilder.build(
            registry: resolved.registry,
            windowId: resolved.windowId,
            dockEnabled: dockEnabled
        )
        if let edge = v2SidebarDockEdge(params) {
            snapshot.edges = snapshot.edges.filter { $0.edge == edge.rawValue }
        }
        return .ok(snapshot.asDictionary())
    }

    // MARK: - perform_command

    /// Schema:
    /// ```
    /// debug.sidebar_dock.perform_command
    /// params: {
    ///   window_id?: uuid,
    ///   edge?: "left"|"right",
    ///   command_id: string,   // SidebarDockCommand ids
    ///   tab_id?: uuid,
    ///   pane_id?: uuid
    /// }
    /// result: { handled: bool, command_id, edge, section_count }
    /// ```
    private func v2SidebarDockPerformCommand(params: [String: Any]) -> V2CallResult {
        guard let commandId = v2String(params, "command_id"), !commandId.isEmpty else {
            return .err(code: "invalid_params", message: "Missing command_id", data: nil)
        }
        guard SidebarDockCommand.allCommandIds.contains(commandId) else {
            return .err(
                code: "invalid_params",
                message: "Unknown sidebar dock command_id",
                data: ["command_id": commandId, "known": SidebarDockCommand.allCommandIds]
            )
        }
        guard let resolved = resolveSidebarDockRegistry(params: params) else {
            return .err(code: "not_found", message: "No sidebar dock registry for window", data: nil)
        }
        let edge = v2SidebarDockEdge(params) ?? resolved.registry.lastFocusedEdge ?? .right
        let store = resolved.registry.store(for: edge)
        let tabId = v2UUID(params, "tab_id").map { TabID(id: $0) }
        let paneId = v2UUID(params, "pane_id").map { PaneID(id: $0) }
        let handled = SidebarDockActionInvoker.perform(
            commandId: commandId,
            store: store,
            tabId: tabId,
            paneId: paneId
        )
        return .ok([
            "handled": handled,
            "command_id": commandId,
            "edge": edge.rawValue,
            "section_count": store.sectionCount,
            "inspect": SidebarDockInspectBuilder.buildEdge(store: store).asEdgeDictionary(),
        ])
    }

    // MARK: - simulate_drop

    /// Schema:
    /// ```
    /// debug.sidebar_dock.simulate_drop
    /// params: {
    ///   window_id?: uuid,
    ///   edge: "left"|"right",
    ///   tab_id: uuid,
    ///   zone: "top"|"bottom"|"left"|"right"|"center",
    ///   target_pane_id?: uuid,
    ///   // optional geometry probe instead of zone:
    ///   location_x?: number, location_y?: number,
    ///   size_width?: number, size_height?: number
    /// }
    /// result: { outcome, reason, section_count, inspect }
    /// ```
    private func v2SidebarDockSimulateDrop(params: [String: Any]) -> V2CallResult {
        guard let resolved = resolveSidebarDockRegistry(params: params) else {
            return .err(code: "not_found", message: "No sidebar dock registry for window", data: nil)
        }
        guard let edge = v2SidebarDockEdge(params) else {
            return .err(code: "invalid_params", message: "Missing or invalid edge", data: nil)
        }
        guard let tabUUID = v2UUID(params, "tab_id") else {
            return .err(code: "invalid_params", message: "Missing or invalid tab_id", data: nil)
        }
        let store = resolved.registry.store(for: edge)
        let zone: SidebarDockEdgeBand.Zone
        if let zoneRaw = v2String(params, "zone"),
           let parsed = SidebarDockEdgeBand.Zone(rawValue: zoneRaw) {
            zone = parsed
        } else if let x = v2Double(params, "location_x"),
                  let y = v2Double(params, "location_y"),
                  let w = v2Double(params, "size_width"),
                  let h = v2Double(params, "size_height"),
                  w > 0, h > 0 {
            zone = SidebarDockEdgeBand.resolveZone(
                location: CGPoint(x: x, y: y),
                size: CGSize(width: w, height: h)
            )
        } else {
            return .err(
                code: "invalid_params",
                message: "Provide zone or location_x/y + size_width/height",
                data: nil
            )
        }
        let targetPane = v2UUID(params, "target_pane_id").map { PaneID(id: $0) }
        let before = store.sectionSnapshots()
        let outcome = store.handleTabEdgeBandDrop(
            tabId: TabID(id: tabUUID),
            zone: zone,
            targetPaneId: targetPane
        )
        let after = store.sectionSnapshots()
        return .ok([
            "outcome": outcome.reasonCode,
            "success": outcome.isSuccess,
            "zone": zone.rawValue,
            "edge": edge.rawValue,
            "section_count": store.sectionCount,
            "lossless_on_refuse": !outcome.isSuccess && before == after,
            "inspect": SidebarDockInspectBuilder.buildEdge(store: store).asEdgeDictionary(),
        ])
    }

    // MARK: - reorder_section

    /// Schema:
    /// ```
    /// debug.sidebar_dock.reorder_section
    /// params: { window_id?, edge, from_index: int, to_index: int }
    /// result: { handled, from_index, to_index, section_count, inspect }
    /// ```
    private func v2SidebarDockReorderSection(params: [String: Any]) -> V2CallResult {
        guard let resolved = resolveSidebarDockRegistry(params: params) else {
            return .err(code: "not_found", message: "No sidebar dock registry for window", data: nil)
        }
        guard let edge = v2SidebarDockEdge(params) else {
            return .err(code: "invalid_params", message: "Missing or invalid edge", data: nil)
        }
        guard let fromIndex = v2Int(params, "from_index"),
              let toIndex = v2Int(params, "to_index") else {
            return .err(code: "invalid_params", message: "Missing from_index/to_index", data: nil)
        }
        let store = resolved.registry.store(for: edge)
        let handled = store.handleSectionHeaderReorder(from: fromIndex, to: toIndex)
        return .ok([
            "handled": handled,
            "from_index": fromIndex,
            "to_index": toIndex,
            "edge": edge.rawValue,
            "section_count": store.sectionCount,
            "inspect": SidebarDockInspectBuilder.buildEdge(store: store).asEdgeDictionary(),
        ])
    }

    // MARK: - divider_drag

    /// Schema:
    /// ```
    /// debug.sidebar_dock.divider_drag
    /// params: {
    ///   window_id?, edge,
    ///   phase: "begin"|"set"|"end",
    ///   first_child_pane_id?: uuid,
    ///   first_child_extent?: number
    /// }
    /// result: { phase, handled, is_divider_drag_active, inspect }
    /// ```
    private func v2SidebarDockDividerDrag(params: [String: Any]) -> V2CallResult {
        guard let resolved = resolveSidebarDockRegistry(params: params) else {
            return .err(code: "not_found", message: "No sidebar dock registry for window", data: nil)
        }
        guard let edge = v2SidebarDockEdge(params) else {
            return .err(code: "invalid_params", message: "Missing or invalid edge", data: nil)
        }
        guard let phase = v2String(params, "phase") else {
            return .err(code: "invalid_params", message: "Missing phase", data: nil)
        }
        let store = resolved.registry.store(for: edge)
        var handled = false
        switch phase {
        case "begin":
            let paneId = v2UUID(params, "first_child_pane_id").map { PaneID(id: $0) }
                ?? store.orderedSectionPaneIds().first
            if let paneId {
                handled = store.debugBeginDividerDrag(adjacentTo: paneId)
            }
        case "set":
            guard let paneUUID = v2UUID(params, "first_child_pane_id"),
                  let extent = v2Double(params, "first_child_extent") else {
                return .err(
                    code: "invalid_params",
                    message: "set requires first_child_pane_id and first_child_extent",
                    data: nil
                )
            }
            handled = store.debugSetDividerExtent(
                firstChildPane: PaneID(id: paneUUID),
                firstChildExtent: CGFloat(extent)
            )
        case "end":
            store.debugEndDividerDrag()
            handled = true
        default:
            return .err(
                code: "invalid_params",
                message: "phase must be begin|set|end",
                data: ["phase": phase]
            )
        }
        return .ok([
            "phase": phase,
            "handled": handled,
            "edge": edge.rawValue,
            "is_divider_drag_active": store.bonsplitController.isDividerDragActive,
            "inspect": SidebarDockInspectBuilder.buildEdge(store: store).asEdgeDictionary(),
        ])
    }

    // MARK: - resize_rail

    /// Schema:
    /// ```
    /// debug.sidebar_dock.resize_rail
    /// params: { window_id?, edge, height: number }
    /// result: { edge, height, inspect }
    /// ```
    private func v2SidebarDockResizeRail(params: [String: Any]) -> V2CallResult {
        guard let resolved = resolveSidebarDockRegistry(params: params) else {
            return .err(code: "not_found", message: "No sidebar dock registry for window", data: nil)
        }
        guard let edge = v2SidebarDockEdge(params) else {
            return .err(code: "invalid_params", message: "Missing or invalid edge", data: nil)
        }
        guard let height = v2Double(params, "height"), height >= 0 else {
            return .err(code: "invalid_params", message: "height must be a non-negative number", data: nil)
        }
        let store = resolved.registry.store(for: edge)
        store.updateRailContentHeight(CGFloat(height))
        return .ok([
            "edge": edge.rawValue,
            "height": height,
            "inspect": SidebarDockInspectBuilder.buildEdge(store: store).asEdgeDictionary(),
        ])
    }

    // MARK: - refuse_paths

    /// Schema:
    /// ```
    /// debug.sidebar_dock.refuse_paths
    /// params: { window_id?, edge, tab_id: uuid }
    /// result: exercises horizontal + geometry refusal; reports lossless recovery
    /// ```
    private func v2SidebarDockRefusePaths(params: [String: Any]) -> V2CallResult {
        guard let resolved = resolveSidebarDockRegistry(params: params) else {
            return .err(code: "not_found", message: "No sidebar dock registry for window", data: nil)
        }
        guard let edge = v2SidebarDockEdge(params) else {
            return .err(code: "invalid_params", message: "Missing or invalid edge", data: nil)
        }
        guard let tabUUID = v2UUID(params, "tab_id") else {
            return .err(code: "invalid_params", message: "Missing or invalid tab_id", data: nil)
        }
        let store = resolved.registry.store(for: edge)
        let tabId = TabID(id: tabUUID)
        let before = store.sectionSnapshots()
        let beforePanels = store.panels.count
        let beforeTabs = store.surfaceIdToPanelId.count

        let horizontal = store.handleTabEdgeBandDrop(tabId: tabId, zone: .left)
        let afterHorizontal = store.sectionSnapshots()
        let horizontalLossless = afterHorizontal == before
            && store.panels.count == beforePanels
            && store.surfaceIdToPanelId.count == beforeTabs

        // Geometry refuse: shrink height so another header cannot fit.
        let originalHeight = store.railContentHeight
        store.updateRailContentHeight(store.collapsedSectionHeight)
        let geometry = store.handleTabEdgeBandDrop(tabId: tabId, zone: .bottom)
        let afterGeometry = store.sectionSnapshots()
        let geometryLossless = afterGeometry == before
            && store.panels.count == beforePanels
            && store.surfaceIdToPanelId.count == beforeTabs
        store.updateRailContentHeight(originalHeight)

        let pane = store.orderedSectionPaneIds().first
        let shouldHorizontal = pane.map {
            store.splitTabBar(store.bonsplitController, shouldSplitPane: $0, orientation: .horizontal)
        } ?? false

        return .ok([
            "edge": edge.rawValue,
            "horizontal": [
                "outcome": horizontal.reasonCode,
                "lossless": horizontalLossless,
            ],
            "geometry": [
                "outcome": geometry.reasonCode,
                "lossless": geometryLossless,
            ],
            "should_split_horizontal": shouldHorizontal,
            "inspect": SidebarDockInspectBuilder.buildEdge(store: store).asEdgeDictionary(),
        ])
    }

    // MARK: - Resolution helpers

    private struct ResolvedDockRegistry {
        let windowId: UUID
        let registry: SidebarDockStoreRegistry
    }

    private func resolveSidebarDockRegistry(params: [String: Any]) -> ResolvedDockRegistry? {
        let windowId = v2UUID(params, "window_id")
        if let registry = SidebarDockActionInvoker.resolveRegistry(
            windowId: windowId,
            preferredWindow: nil
        ) {
            let id = windowId ?? registry.windowId
            return ResolvedDockRegistry(windowId: id, registry: registry)
        }
        return nil
    }

    private func v2SidebarDockEdge(_ params: [String: Any]) -> SidebarDockEdge? {
        guard let raw = v2String(params, "edge") else { return nil }
        return SidebarDockEdge(rawValue: raw)
    }
}

#endif
