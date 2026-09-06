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
    /// A workspace's agent-session cards, as one selection-ringed stack that
    /// stands in for that workspace's ordinary row.
    ///
    /// It replaces the row rather than sitting beneath it: the mockup shows one
    /// ringed container of cards where the workspace row used to be, and
    /// drawing both would show the same workspace twice.
    case panelCardStack(workspaceId: UUID, panelIds: [UUID])

    var id: SidebarWorkspaceRenderItemID {
        switch self {
        case .groupHeader(let groupId, _):
            return .group(groupId)
        case .workspace(let workspaceId):
            return .workspace(workspaceId)
        case .panelCardStack(let workspaceId, _):
            return .panelCardStack(workspaceId)
        }
    }

    var rowWorkspaceId: UUID {
        switch self {
        case .groupHeader(_, let anchorWorkspaceId):
            return anchorWorkspaceId
        case .workspace(let workspaceId):
            return workspaceId
        case .panelCardStack(let workspaceId, _):
            return workspaceId
        }
    }

    /// Whether this item is a real, reorderable sidebar row.
    ///
    /// The card stack counts: it *is* the focused workspace's row, so keeping it
    /// in the reorder id list is what preserves drop-indicator placement and
    /// workspace numbering. Excluding it would silently renumber every
    /// workspace after it and shift Cmd-N shortcuts.
    var isReorderableRow: Bool {
        true
    }

    /// The workspace this item numbers, if it is a numbered workspace row.
    var numberedWorkspaceId: UUID? {
        switch self {
        case .workspace(let workspaceId):
            return workspaceId
        case .panelCardStack(let workspaceId, _):
            return workspaceId
        case .groupHeader:
            return nil
        }
    }

    /// Render items with per-pane cards inserted under the focused workspace.
    ///
    /// Cards are additive: with `panelCardPanelIds` empty — which is what every
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
        panelCardPanelIds: [UUID]
    ) -> [SidebarWorkspaceRenderItem] {
        var byWorkspace: [UUID: [UUID]] = [:]
        if let focusedWorkspaceId, !panelCardPanelIds.isEmpty {
            byWorkspace[focusedWorkspaceId] = panelCardPanelIds
        }
        return renderItems(
            tabs: tabs,
            groupsById: groupsById,
            panelCardPanelIdsByWorkspaceId: byWorkspace
        )
    }

    /// Same replacement rule as the focused-workspace overload, applied to
    /// every workspace that has cards — the current-repo listing.
    static func renderItems(
        tabs: [Workspace],
        groupsById: [UUID: WorkspaceGroup],
        panelCardPanelIdsByWorkspaceId: [UUID: [UUID]]
    ) -> [SidebarWorkspaceRenderItem] {
        let base = renderItems(tabs: tabs, groupsById: groupsById)
        let carded = panelCardPanelIdsByWorkspaceId.filter { !$0.value.isEmpty }
        guard !carded.isEmpty else { return base }

        var result: [SidebarWorkspaceRenderItem] = []
        result.reserveCapacity(base.count)
        for item in base {
            switch item {
            case .workspace(let workspaceId):
                if let panelIds = carded[workspaceId] {
                    result.append(.panelCardStack(workspaceId: workspaceId, panelIds: panelIds))
                } else {
                    result.append(item)
                }
            case .groupHeader(_, let anchorWorkspaceId):
                result.append(item)
                if let panelIds = carded[anchorWorkspaceId] {
                    result.append(.panelCardStack(workspaceId: anchorWorkspaceId, panelIds: panelIds))
                }
            case .panelCardStack:
                result.append(item)
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
        renderItems.compactMap(\.numberedWorkspaceId)
    }

    static func numberedWorkspaceIndexById(
        from renderItems: [SidebarWorkspaceRenderItem]
    ) -> [UUID: Int] {
        var result: [UUID: Int] = [:]
        result.reserveCapacity(renderItems.count)
        for item in renderItems {
            guard let workspaceId = item.numberedWorkspaceId else { continue }
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
