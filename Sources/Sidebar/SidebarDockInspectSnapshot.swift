import Foundation

/// Immutable per-window rail inspection payload for DEBUG dogfood / validators.
///
/// Built only from store + Bonsplit layout reads — never holds an Observable
/// store reference for list/row projection (snapshot-boundary safe).
struct SidebarDockInspectSnapshot: Equatable, Sendable {
    var windowId: String
    var dockEnabled: Bool
    var lastFocusedEdge: String?
    var edges: [Edge]

    struct Edge: Equatable, Sendable {
        var edge: String
        var sectionCount: Int
        var soleSectionCollapsed: Bool
        var railContentHeight: Double
        var isDividerDragActive: Bool
        /// Authoritative focused section (Bonsplit focused pane).
        var focusedPaneId: String?
        /// Selected tab in the focused section — window-edge selection authority.
        var focusedSelectedTabId: String?
        /// Tool mode for the focused selected tab (right rail only).
        var focusedToolMode: String?
        var sections: [Section]
    }

    struct Section: Equatable, Sendable {
        var index: Int
        var paneId: String
        var tabIds: [String]
        var tabTitles: [String]
        var selectedTabId: String?
        var isCollapsed: Bool
        var extent: Double?
        var imposedCollapsedExtent: Double?
        var rememberedExtent: Double?
        var frame: Frame?
    }

    struct Frame: Equatable, Sendable {
        var x: Double
        var y: Double
        var width: Double
        var height: Double
    }

    /// JSON-ready dictionary for socket responses.
    func asDictionary() -> [String: Any] {
        [
            "window_id": windowId,
            "dock_enabled": dockEnabled,
            "last_focused_edge": lastFocusedEdge ?? NSNull(),
            "edges": edges.map { edge in edge.asEdgeDictionary() },
        ]
    }
}

extension SidebarDockInspectSnapshot.Edge {
    func asEdgeDictionary() -> [String: Any] {
        var dict: [String: Any] = [
            "edge": edge,
            "section_count": sectionCount,
            "sole_section_collapsed": soleSectionCollapsed,
            "rail_content_height": railContentHeight,
            "is_divider_drag_active": isDividerDragActive,
            "sections": sections.map { section in
                var sectionDict: [String: Any] = [
                    "index": section.index,
                    "pane_id": section.paneId,
                    "tab_ids": section.tabIds,
                    "tab_titles": section.tabTitles,
                    "is_collapsed": section.isCollapsed,
                ]
                if let selectedTabId = section.selectedTabId {
                    sectionDict["selected_tab_id"] = selectedTabId
                }
                if let extent = section.extent {
                    sectionDict["extent"] = extent
                }
                if let imposed = section.imposedCollapsedExtent {
                    sectionDict["imposed_collapsed_extent"] = imposed
                }
                if let remembered = section.rememberedExtent {
                    sectionDict["remembered_extent"] = remembered
                }
                if let frame = section.frame {
                    sectionDict["frame"] = [
                        "x": frame.x,
                        "y": frame.y,
                        "width": frame.width,
                        "height": frame.height,
                    ]
                }
                return sectionDict
            },
        ]
        // Edge-level authority (VAL-RAIL-007/009). `selected_tab_id` mirrors the
        // focused section's selection so dogfood can compare one authoritative id.
        if let focusedPaneId {
            dict["focused_pane_id"] = focusedPaneId
        }
        if let focusedSelectedTabId {
            dict["focused_selected_tab_id"] = focusedSelectedTabId
            dict["selected_tab_id"] = focusedSelectedTabId
        }
        if let focusedToolMode {
            dict["focused_tool_mode"] = focusedToolMode
        }
        return dict
    }
}

@MainActor
enum SidebarDockInspectBuilder {
    /// Capture both edges for a window registry.
    static func build(
        registry: SidebarDockStoreRegistry,
        windowId: UUID,
        dockEnabled: Bool
    ) -> SidebarDockInspectSnapshot {
        SidebarDockInspectSnapshot(
            windowId: windowId.uuidString,
            dockEnabled: dockEnabled,
            lastFocusedEdge: registry.lastFocusedEdge?.rawValue,
            edges: [
                buildEdge(store: registry.left),
                buildEdge(store: registry.right),
            ]
        )
    }

    static func buildEdge(store: SidebarDockStore) -> SidebarDockInspectSnapshot.Edge {
        let layout = store.bonsplitController.layoutSnapshot()
        let frameByPane: [String: SidebarDockInspectSnapshot.Frame] = Dictionary(
            uniqueKeysWithValues: layout.panes.map { pane in
                (
                    pane.paneId,
                    SidebarDockInspectSnapshot.Frame(
                        x: pane.frame.x,
                        y: pane.frame.y,
                        width: pane.frame.width,
                        height: pane.frame.height
                    )
                )
            }
        )
        let panes = store.orderedSectionPaneIds()
        let sections: [SidebarDockInspectSnapshot.Section] = panes.enumerated().map { index, pane in
            let tabs = store.bonsplitController.tabs(inPane: pane)
            let selected = store.bonsplitController.selectedTab(inPane: pane)?.id
            return SidebarDockInspectSnapshot.Section(
                index: index,
                paneId: pane.id.uuidString,
                // TabID exposes public `uuid`; package-internal `id` is not reachable here.
                tabIds: tabs.map { $0.id.uuid.uuidString },
                tabTitles: tabs.map(\.title),
                selectedTabId: selected?.uuid.uuidString,
                isCollapsed: store.isSectionCollapsed(paneId: pane),
                extent: store.sectionExtent(forPane: pane).map(Double.init),
                imposedCollapsedExtent: store.imposedCollapsedExtent(forPane: pane).map(Double.init),
                rememberedExtent: store.rememberedExtent(forPane: pane).map(Double.init),
                frame: frameByPane[pane.id.uuidString]
            )
        }
        let focusedPane = store.bonsplitController.focusedPaneId
            ?? panes.first
        let focusedSelected = focusedPane.flatMap { store.bonsplitController.selectedTab(inPane: $0)?.id }
        let focusedMode: String? = {
            guard store.edge == .right else { return nil }
            return store.focusedToolMode()?.rawValue
        }()
        return SidebarDockInspectSnapshot.Edge(
            edge: store.edge.rawValue,
            sectionCount: store.sectionCount,
            soleSectionCollapsed: store.isSoleSectionCollapsed,
            railContentHeight: Double(store.railContentHeight),
            isDividerDragActive: store.bonsplitController.isDividerDragActive,
            focusedPaneId: focusedPane?.id.uuidString,
            focusedSelectedTabId: focusedSelected?.uuid.uuidString,
            focusedToolMode: focusedMode,
            sections: sections
        )
    }
}
