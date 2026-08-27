import CmuxWorkspaces
import Foundation

/// Stable value identity for one drawable item in the workspace sidebar.
///
/// Keep live `Workspace` / `WorkspaceGroup` references out of this value. A
/// `LazyVStack` copies and diffs its `ForEach` data while placing rows; carrying
/// the models through that path made scrolling copy the live sidebar graph and
/// blurred the ownership boundary between layout data and observed state.
/// Models are resolved from the parent-owned render context only when SwiftUI
/// asks to realize a row.
@MainActor
enum SidebarWorkspaceRenderItem {
    case groupHeader(groupId: UUID, anchorWorkspaceId: UUID)
    case workspace(workspaceId: UUID)
    /// A card for one visible pane of the focused workspace, emitted directly
    /// beneath that workspace's own row.
    case panelCard(workspaceId: UUID, paneId: UUID)

    var id: SidebarWorkspaceRenderItemID {
        switch self {
        case .groupHeader(let groupId, _):
            return .group(groupId)
        case .workspace(let workspaceId):
            return .workspace(workspaceId)
        case .panelCard(_, let paneId):
            return .panelCard(paneId)
        }
    }

    var rowWorkspaceId: UUID {
        switch self {
        case .groupHeader(_, let anchorWorkspaceId):
            return anchorWorkspaceId
        case .workspace(let workspaceId):
            return workspaceId
        case .panelCard(let workspaceId, _):
            return workspaceId
        }
    }

    /// Whether this item is a real, reorderable sidebar row.
    ///
    /// Panel cards are decoration attached to the focused workspace: they are
    /// not drag sources, not drop targets, and must not appear in the reorder
    /// id list, where their workspace id would duplicate the row they sit under
    /// and corrupt drop-indicator placement.
    var isReorderableRow: Bool {
        switch self {
        case .groupHeader, .workspace:
            return true
        case .panelCard:
            return false
        }
    }

    /// Render items with per-pane cards inserted under the focused workspace.
    ///
    /// Cards are additive: with `panelCardPaneIds` empty — which is what every
    /// caller that does not opt in passes — the output is byte-identical to
    /// ``renderItems(tabs:groupsById:)``.
    ///
    /// A card row is emitted after the workspace's own row, or after the group
    /// header when the focused workspace is its group's anchor (the anchor has
    /// no row of its own). A focused workspace hidden inside a collapsed group
    /// contributes no cards, because there is no visible row to attach them to.
    static func renderItems(
        tabs: [Workspace],
        groupsById: [UUID: WorkspaceGroup],
        focusedWorkspaceId: UUID?,
        panelCardPaneIds: [UUID]
    ) -> [SidebarWorkspaceRenderItem] {
        let base = renderItems(tabs: tabs, groupsById: groupsById)
        guard let focusedWorkspaceId, !panelCardPaneIds.isEmpty else { return base }

        let cards = panelCardPaneIds.map {
            SidebarWorkspaceRenderItem.panelCard(workspaceId: focusedWorkspaceId, paneId: $0)
        }

        var result: [SidebarWorkspaceRenderItem] = []
        result.reserveCapacity(base.count + cards.count)
        var inserted = false
        for item in base {
            result.append(item)
            guard !inserted else { continue }
            switch item {
            case .workspace(let workspaceId) where workspaceId == focusedWorkspaceId:
                result.append(contentsOf: cards)
                inserted = true
            case .groupHeader(_, let anchorWorkspaceId) where anchorWorkspaceId == focusedWorkspaceId:
                result.append(contentsOf: cards)
                inserted = true
            default:
                continue
            }
        }
        return result
    }

    static func renderItems(
        tabs: [Workspace],
        groupsById: [UUID: WorkspaceGroup]
    ) -> [SidebarWorkspaceRenderItem] {
        guard !tabs.isEmpty else { return [] }
        var items: [SidebarWorkspaceRenderItem] = []
        items.reserveCapacity(tabs.count + groupsById.count)
        var lastEmittedGroupId: UUID? = nil
        var emittedHeaders: Set<UUID> = []
        var collapsedByGroupId: [UUID: Bool] = [:]
        var skipChildrenUntilNextGroup = false
        for tab in tabs {
            let groupId = tab.groupId
            if groupId != lastEmittedGroupId {
                lastEmittedGroupId = groupId
                skipChildrenUntilNextGroup = false
                if let groupId, let group = groupsById[groupId] {
                    if !emittedHeaders.contains(groupId) {
                        items.append(.groupHeader(
                            groupId: group.id,
                            anchorWorkspaceId: group.anchorWorkspaceId
                        ))
                        emittedHeaders.insert(groupId)
                        collapsedByGroupId[groupId] = group.isCollapsed
                    }
                    // If legacy reorder paths ever leave a group's members in
                    // two runs, keep honoring the same collapse decision.
                    skipChildrenUntilNextGroup = collapsedByGroupId[groupId] ?? false
                }
            }
            // Anchor workspaces are represented exclusively by the group header.
            if let groupId, let group = groupsById[groupId], group.anchorWorkspaceId == tab.id {
                continue
            }
            if groupId == nil || !skipChildrenUntilNextGroup {
                items.append(.workspace(workspaceId: tab.id))
            }
        }
        return items
    }

    /// Workspace ids represented by ordinary rows, in their rendered order.
    ///
    /// Group headers represent their anchor workspace for interaction, but are
    /// containers rather than numbered workspace rows.
    static func numberedWorkspaceIds(
        from renderItems: [SidebarWorkspaceRenderItem]
    ) -> [UUID] {
        renderItems.compactMap { item in
            guard case .workspace(let workspaceId) = item else { return nil }
            return workspaceId
        }
    }

    static func numberedWorkspaceIndexById(
        from renderItems: [SidebarWorkspaceRenderItem]
    ) -> [UUID: Int] {
        var result: [UUID: Int] = [:]
        result.reserveCapacity(renderItems.count)
        for item in renderItems {
            guard case .workspace(let workspaceId) = item else { continue }
            result[workspaceId] = result.count
        }
        return result
    }

    static func numberedWorkspaceIds(
        tabs: [Workspace],
        groupsById: [UUID: WorkspaceGroup]
    ) -> [UUID] {
        numberedWorkspaceIds(from: renderItems(tabs: tabs, groupsById: groupsById))
    }

    static func memberWorkspaceIdsByGroupId(tabs: [Workspace]) -> [UUID: [UUID]] {
        var result: [UUID: [UUID]] = [:]
        for tab in tabs {
            if let groupId = tab.groupId {
                result[groupId, default: []].append(tab.id)
            }
        }
        return result
    }
}
