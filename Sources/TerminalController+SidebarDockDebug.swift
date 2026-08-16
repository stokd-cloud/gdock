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
        "debug.sidebar_dock.reorder_tab",
        "debug.sidebar_dock.divider_drag",
        "debug.sidebar_dock.resize_rail",
        "debug.sidebar_dock.refuse_paths",
        "debug.sidebar_dock.transfer",
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
        case "debug.sidebar_dock.reorder_tab":
            return v2SidebarDockReorderTab(params: params)
        case "debug.sidebar_dock.divider_drag":
            return v2SidebarDockDividerDrag(params: params)
        case "debug.sidebar_dock.resize_rail":
            return v2SidebarDockResizeRail(params: params)
        case "debug.sidebar_dock.refuse_paths":
            return v2SidebarDockRefusePaths(params: params)
        case "debug.sidebar_dock.transfer":
            return v2SidebarDockTransfer(params: params)
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
        let tabId = v2UUID(params, "tab_id").map { TabID(uuid: $0) }
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
    ///   // Live tab selectors (any one). Stale Empty ids fall through to live resolve.
    ///   tab_id?: uuid,
    ///   panel_id?: uuid,
    ///   tab_title?: string,
    ///   section_index?: int, tab_index?: int,
    ///   // Representative disallowed-panel refuse (no live tab required):
    ///   panel_type?: string,  // e.g. "terminal", "browser"
    ///   zone: "top"|"bottom"|"left"|"right"|"center",
    ///   target_pane_id?: uuid,
    ///   // optional geometry probe instead of zone:
    ///   location_x?: number, location_y?: number,
    ///   size_width?: number, size_height?: number
    /// }
    /// result: { outcome, reason, section_count, inspect, resolved_tab_id? }
    /// ```
    private func v2SidebarDockSimulateDrop(params: [String: Any]) -> V2CallResult {
        guard let resolved = resolveSidebarDockRegistry(params: params) else {
            return .err(code: "not_found", message: "No sidebar dock registry for window", data: nil)
        }
        guard let edge = v2SidebarDockEdge(params) else {
            return .err(code: "invalid_params", message: "Missing or invalid edge", data: nil)
        }
        let store = resolved.registry.store(for: edge)
        let before = store.sectionSnapshots()
        let beforePanels = store.panels.count
        let beforeTabs = store.surfaceIdToPanelId.count

        // Representative disallowed-panel refuse: lossless, no live tab required.
        if let panelTypeRaw = v2String(params, "panel_type"),
           let panelType = PanelType(rawValue: panelTypeRaw),
           !SidebarDockPlacementMatrix.allows(panelType: panelType) {
            let outcome = SidebarDockDropHandler.refuseDisallowedPanel(
                store: store,
                panelType: panelType
            )
            let after = store.sectionSnapshots()
            return .ok([
                "outcome": outcome.reasonCode,
                "success": outcome.isSuccess,
                "zone": v2String(params, "zone") ?? "center",
                "edge": edge.rawValue,
                "panel_type": panelTypeRaw,
                "section_count": store.sectionCount,
                "lossless_on_refuse": !outcome.isSuccess
                    && before == after
                    && store.panels.count == beforePanels
                    && store.surfaceIdToPanelId.count == beforeTabs,
                "inspect": SidebarDockInspectBuilder.buildEdge(store: store).asEdgeDictionary(),
            ])
        }

        guard let tabId = resolveSidebarDockLiveTab(store: store, params: params) else {
            return .err(
                code: "invalid_params",
                message: "Could not resolve a live mapped tab_id/panel_id/tab_title/section_index",
                data: nil
            )
        }
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
        // Center same-pane: default target to the live tab's pane when omitted.
        let targetPane: PaneID? = {
            if let explicit = v2UUID(params, "target_pane_id") {
                return PaneID(id: explicit)
            }
            if zone == .center {
                return store.paneId(forTabId: tabId)
            }
            return nil
        }()
        let outcome = store.handleTabEdgeBandDrop(
            tabId: tabId,
            zone: zone,
            targetPaneId: targetPane
        )
        let after = store.sectionSnapshots()
        return .ok([
            "outcome": outcome.reasonCode,
            "success": outcome.isSuccess,
            "zone": zone.rawValue,
            "edge": edge.rawValue,
            "resolved_tab_id": tabId.uuid.uuidString,
            "section_count": store.sectionCount,
            "lossless_on_refuse": !outcome.isSuccess
                && before == after
                && store.panels.count == beforePanels
                && store.surfaceIdToPanelId.count == beforeTabs,
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

    // MARK: - reorder_tab

    /// Schema:
    /// ```
    /// debug.sidebar_dock.reorder_tab
    /// params: {
    ///   window_id?, edge,
    ///   tab_id?: uuid, panel_id?: uuid, tab_title?: string, section_index?: int, tab_index?: int,
    ///   to_index: int
    /// }
    /// result: { handled, to_index, resolved_tab_id, section_count, inspect }
    /// ```
    /// Routes through production `SidebarDockStore.reorderTab` → Bonsplit `reorderTab`.
    private func v2SidebarDockReorderTab(params: [String: Any]) -> V2CallResult {
        guard let resolved = resolveSidebarDockRegistry(params: params) else {
            return .err(code: "not_found", message: "No sidebar dock registry for window", data: nil)
        }
        guard let edge = v2SidebarDockEdge(params) else {
            return .err(code: "invalid_params", message: "Missing or invalid edge", data: nil)
        }
        guard let toIndex = v2Int(params, "to_index") else {
            return .err(code: "invalid_params", message: "Missing to_index", data: nil)
        }
        let store = resolved.registry.store(for: edge)
        guard let tabId = resolveSidebarDockLiveTab(store: store, params: params) else {
            return .err(
                code: "invalid_params",
                message: "Could not resolve a live mapped tab for reorder_tab",
                data: nil
            )
        }
        let handled = store.reorderTab(tabId, toIndex: toIndex)
        return .ok([
            "handled": handled,
            "to_index": toIndex,
            "resolved_tab_id": tabId.uuid.uuidString,
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
    /// params: { window_id?, edge, height?: number, width?: number }
    /// result: { edge, height?, width?, inspect }
    /// ```
    /// Height drives geometry refusal / collapse reimpose. Width is audited for
    /// narrow ≤160 dogfood; production commands ignore width (drag is unreachable).
    private func v2SidebarDockResizeRail(params: [String: Any]) -> V2CallResult {
        guard let resolved = resolveSidebarDockRegistry(params: params) else {
            return .err(code: "not_found", message: "No sidebar dock registry for window", data: nil)
        }
        guard let edge = v2SidebarDockEdge(params) else {
            return .err(code: "invalid_params", message: "Missing or invalid edge", data: nil)
        }
        let height = v2Double(params, "height")
        let width = v2Double(params, "width")
        guard height != nil || width != nil else {
            return .err(
                code: "invalid_params",
                message: "Provide height and/or width as non-negative numbers",
                data: nil
            )
        }
        if let height, height < 0 {
            return .err(code: "invalid_params", message: "height must be a non-negative number", data: nil)
        }
        if let width, width < 0 {
            return .err(code: "invalid_params", message: "width must be a non-negative number", data: nil)
        }
        let store = resolved.registry.store(for: edge)
        if let height {
            store.updateRailContentHeight(CGFloat(height))
        }
        if let width {
            store.updateRailContentWidth(CGFloat(width))
        }
        var result: [String: Any] = [
            "edge": edge.rawValue,
            "inspect": SidebarDockInspectBuilder.buildEdge(store: store).asEdgeDictionary(),
        ]
        if let height { result["height"] = height }
        if let width { result["width"] = width }
        result["rail_content_width"] = store.railContentWidth
        result["rail_content_height"] = store.railContentHeight
        return .ok(result)
    }

    // MARK: - transfer (cross-rail)

    /// Schema:
    /// ```
    /// debug.sidebar_dock.transfer
    /// params: {
    ///   window_id?: uuid,
    ///   kind: "tab"|"section",
    ///   from_edge: "left"|"right",
    ///   to_edge: "left"|"right",
    ///   // tab: panel_id | tab_id | tab_title | section_index+tab_index on from_edge
    ///   // section: section_id | section_index on from_edge
    ///   destination?: "selected"|"top"|"bottom"|"horizontal",
    /// }
    /// result: { outcome, reason, from_edge, to_edge, inspect }
    ///
    /// Bridges the production `SidebarDockTransfer` path only — never mutates
    /// stores directly. Used by R5 dogfood to move a live right tool tab into
    /// the left rail so left top/bottom multi-tab creation is reachable.
    /// ```
    private func v2SidebarDockTransfer(params: [String: Any]) -> V2CallResult {
        guard let resolved = resolveSidebarDockRegistry(params: params) else {
            return .err(code: "not_found", message: "No sidebar dock registry for window", data: nil)
        }
        guard let fromEdge = SidebarDockEdge(rawValue: v2String(params, "from_edge") ?? ""),
              let toEdge = SidebarDockEdge(rawValue: v2String(params, "to_edge") ?? "") else {
            return .err(code: "invalid_params", message: "from_edge and to_edge required", data: nil)
        }
        let kind = v2String(params, "kind") ?? "tab"
        let destRaw = v2String(params, "destination") ?? "bottom"
        let source = resolved.registry.store(for: fromEdge)
        let beforeSource = SidebarDockTransfer.completeRailFingerprint(source)
        let beforeDest = SidebarDockTransfer.completeRailFingerprint(resolved.registry.store(for: toEdge))

        let outcome: SidebarDockTransfer.Outcome
        switch kind {
        case "section":
            let sectionId: SidebarDockSectionID? = {
                if let uuid = v2UUID(params, "section_id") {
                    return SidebarDockSectionID(uuid)
                }
                if let index = v2Int(params, "section_index") {
                    let ids = source.orderedSectionIds()
                    if ids.indices.contains(index) { return ids[index] }
                }
                if let pane = source.bonsplitController.focusedPaneId
                    ?? source.orderedSectionPaneIds().first {
                    return source.sectionId(forPane: pane)
                }
                return nil
            }()
            guard let sectionId else {
                return .err(code: "invalid_params", message: "Could not resolve section_id", data: nil)
            }
            let sectionDest: SidebarDockTransfer.SectionDestination = {
                switch destRaw {
                case "top": return .top
                case "horizontal": return .horizontalSplit
                default: return .bottom
                }
            }()
            outcome = SidebarDockTransfer.moveSection(
                registry: resolved.registry,
                sectionId: sectionId,
                from: fromEdge,
                to: toEdge,
                destination: sectionDest
            )
        default:
            guard let tabId = resolveSidebarDockLiveTab(store: source, params: params),
                  let panelId = source.surfaceIdToPanelId[tabId] else {
                return .err(
                    code: "invalid_params",
                    message: "Could not resolve a live mapped tab on from_edge",
                    data: nil
                )
            }
            let tabDest: SidebarDockTransfer.TabDestination = {
                switch destRaw {
                case "selected": return .intoSelectedSection()
                case "top": return .newVerticalSection(position: .top)
                case "horizontal": return .horizontalSplit
                default: return .newVerticalSection(position: .bottom)
                }
            }()
            outcome = SidebarDockTransfer.moveTab(
                registry: resolved.registry,
                panelId: panelId,
                from: fromEdge,
                to: toEdge,
                destination: tabDest
            )
        }

        let afterSource = SidebarDockTransfer.completeRailFingerprint(source)
        let afterDest = SidebarDockTransfer.completeRailFingerprint(resolved.registry.store(for: toEdge))
        let losslessOnRefuse = !outcome.isSuccess
            && afterSource == beforeSource
            && afterDest == beforeDest

        return .ok([
            "outcome": outcome.reasonCode,
            "success": outcome.isSuccess,
            "kind": kind,
            "from_edge": fromEdge.rawValue,
            "to_edge": toEdge.rawValue,
            "destination": destRaw,
            "lossless_on_refuse": losslessOnRefuse,
            "inspect": SidebarDockInspectBuilder.build(
                registry: resolved.registry,
                windowId: resolved.windowId,
                dockEnabled: RightSidebarBetaFeatureSettings.isSidebarDockEnabled()
            ).asDictionary(),
        ])
    }

    // MARK: - refuse_paths

    /// Schema:
    /// ```
    /// debug.sidebar_dock.refuse_paths
    /// params: {
    ///   window_id?, edge,
    ///   tab_id?: uuid, panel_id?: uuid, tab_title?: string, section_index?: int,
    ///   panel_type?: string  // optional extra disallowed refuse cell
    /// }
    /// result: exercises horizontal + geometry + disallowed refusal; reports lossless recovery
    /// ```
    private func v2SidebarDockRefusePaths(params: [String: Any]) -> V2CallResult {
        guard let resolved = resolveSidebarDockRegistry(params: params) else {
            return .err(code: "not_found", message: "No sidebar dock registry for window", data: nil)
        }
        guard let edge = v2SidebarDockEdge(params) else {
            return .err(code: "invalid_params", message: "Missing or invalid edge", data: nil)
        }
        let store = resolved.registry.store(for: edge)
        guard let tabId = resolveSidebarDockLiveTab(store: store, params: params) else {
            return .err(
                code: "invalid_params",
                message: "Could not resolve a live mapped tab for refuse_paths",
                data: nil
            )
        }
        let before = store.sectionSnapshots()
        let beforePanels = store.panels.count
        let beforeTabs = store.surfaceIdToPanelId.count

        let horizontal = store.handleTabEdgeBandDrop(tabId: tabId, zone: .left)
        let afterHorizontal = store.sectionSnapshots()
        let horizontalLossless = afterHorizontal == before
            && store.panels.count == beforePanels
            && store.surfaceIdToPanelId.count == beforeTabs

        // Geometry refuse: shrink height so another header cannot fit.
        // Use a multi-tab source when possible so the refuse is geometry, not sole-tab.
        let originalHeight = store.railContentHeight
        store.updateRailContentHeight(store.collapsedSectionHeight)
        let geometry = store.handleTabEdgeBandDrop(tabId: tabId, zone: .bottom)
        let afterGeometry = store.sectionSnapshots()
        let geometryLossless = afterGeometry == before
            && store.panels.count == beforePanels
            && store.surfaceIdToPanelId.count == beforeTabs
        store.updateRailContentHeight(originalHeight)

        let disallowedTypeRaw = v2String(params, "panel_type") ?? PanelType.terminal.rawValue
        let disallowedType = PanelType(rawValue: disallowedTypeRaw) ?? .terminal
        let disallowed = SidebarDockDropHandler.refuseDisallowedPanel(
            store: store,
            panelType: disallowedType
        )
        let afterDisallowed = store.sectionSnapshots()
        let disallowedLossless = afterDisallowed == before
            && store.panels.count == beforePanels
            && store.surfaceIdToPanelId.count == beforeTabs

        let pane = store.orderedSectionPaneIds().first
        let shouldHorizontal = pane.map {
            store.splitTabBar(store.bonsplitController, shouldSplitPane: $0, orientation: .horizontal)
        } ?? false

        return .ok([
            "edge": edge.rawValue,
            "resolved_tab_id": tabId.uuid.uuidString,
            "horizontal": [
                "outcome": horizontal.reasonCode,
                "lossless": horizontalLossless,
            ],
            "geometry": [
                "outcome": geometry.reasonCode,
                "lossless": geometryLossless,
            ],
            "disallowed": [
                "outcome": disallowed.reasonCode,
                "lossless": disallowedLossless,
                "panel_type": disallowedType.rawValue,
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

    /// Resolve a live mapped tab for dogfood fixtures.
    ///
    /// Prefers explicit live `tab_id`, then `panel_id`, `tab_title`,
    /// `section_index`+`tab_index`, then focused/selected, then first live tab.
    /// Stale Empty placeholder ids are ignored so center same-pane is a true no-op.
    private func resolveSidebarDockLiveTab(
        store: SidebarDockStore,
        params: [String: Any]
    ) -> TabID? {
        if let uuid = v2UUID(params, "tab_id") {
            let tab = TabID(uuid: uuid)
            if store.surfaceIdToPanelId[tab] != nil {
                return tab
            }
            // Stale / Empty id — fall through to live selectors.
        }
        if let panelUUID = v2UUID(params, "panel_id"),
           let tab = store.surfaceId(forPanelId: panelUUID) {
            return tab
        }
        if let title = v2String(params, "tab_title"), !title.isEmpty {
            for pane in store.orderedSectionPaneIds() {
                for tab in store.bonsplitController.tabs(inPane: pane) {
                    if tab.title == title, store.surfaceIdToPanelId[tab.id] != nil {
                        return tab.id
                    }
                }
            }
        }
        if let sectionIndex = v2Int(params, "section_index") {
            let panes = store.orderedSectionPaneIds()
            if panes.indices.contains(sectionIndex) {
                let live = store.bonsplitController.tabs(inPane: panes[sectionIndex])
                    .map(\.id)
                    .filter { store.surfaceIdToPanelId[$0] != nil }
                let tabIndex = v2Int(params, "tab_index") ?? 0
                if live.indices.contains(tabIndex) {
                    return live[tabIndex]
                }
            }
        }
        // Focused selected live tab.
        if let focused = store.bonsplitController.focusedPaneId
            ?? store.orderedSectionPaneIds().first,
           let selected = store.bonsplitController.selectedTab(inPane: focused),
           store.surfaceIdToPanelId[selected.id] != nil {
            return selected.id
        }
        // First live mapped tab on the edge.
        for pane in store.orderedSectionPaneIds() {
            for tab in store.bonsplitController.tabs(inPane: pane) {
                if store.surfaceIdToPanelId[tab.id] != nil {
                    return tab.id
                }
            }
        }
        return nil
    }
}

#endif
