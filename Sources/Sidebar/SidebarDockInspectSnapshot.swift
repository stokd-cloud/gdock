import Foundation

/// RED stub: empty inspect payload until green.
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

    func asDictionary() -> [String: Any] {
        ["window_id": windowId, "dock_enabled": dockEnabled, "edges": []]
    }
}

extension SidebarDockInspectSnapshot.Edge {
    func asEdgeDictionary() -> [String: Any] {
        ["edge": edge, "section_count": sectionCount, "sections": []]
    }
}

@MainActor
enum SidebarDockInspectBuilder {
    static func build(
        registry: SidebarDockStoreRegistry,
        windowId: UUID,
        dockEnabled: Bool
    ) -> SidebarDockInspectSnapshot {
        // Intentionally empty until green.
        SidebarDockInspectSnapshot(
            windowId: windowId.uuidString,
            dockEnabled: dockEnabled,
            lastFocusedEdge: nil,
            edges: []
        )
    }

    static func buildEdge(store: SidebarDockStore) -> SidebarDockInspectSnapshot.Edge {
        SidebarDockInspectSnapshot.Edge(
            edge: store.edge.rawValue,
            sectionCount: 0,
            soleSectionCollapsed: false,
            railContentHeight: 0,
            isDividerDragActive: false,
            sections: []
        )
    }
}
