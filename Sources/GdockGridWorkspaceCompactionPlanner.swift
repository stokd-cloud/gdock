import Foundation

/// Packs Grid Mode real panels into the fewest workspaces that can hold them.
///
/// Regular mode is one global scope. Auto Workspace Group Mode scopes packing
/// independently per repository workspace group. Placeholder-only surplus
/// workspaces are reported so the caller can close them; a workspace of only
/// unstarted cells is never retained when a sibling can hold the real panels.
enum GdockGridWorkspaceCompactionPlanner {
    struct WorkspaceSnapshot: Equatable, Sendable {
        let id: UUID
        let groupId: UUID?
        let isGroupAnchor: Bool
        let panelIds: [UUID]
        let placeholderPanelIds: [UUID]

        var realPanelIds: [UUID] {
            let placeholders = Set(placeholderPanelIds)
            return panelIds.filter { !placeholders.contains($0) }
        }

        init(
            id: UUID,
            groupId: UUID?,
            isGroupAnchor: Bool = false,
            panelIds: [UUID],
            placeholderPanelIds: [UUID]
        ) {
            self.id = id
            self.groupId = groupId
            self.isGroupAnchor = isGroupAnchor
            self.panelIds = panelIds
            self.placeholderPanelIds = placeholderPanelIds
        }
    }

    struct PanelAssignment: Equatable, Sendable {
        let workspaceId: UUID
        let panelIds: [UUID]
    }

    struct ScopePlan: Equatable, Sendable {
        let retainedWorkspaceIds: [UUID]
        let surplusWorkspaceIds: [UUID]
        let panelAssignments: [PanelAssignment]
    }

    struct Plan: Equatable, Sendable {
        let scopes: [ScopePlan]
    }

    static func plan(
        workspaces: [WorkspaceSnapshot],
        capacity: Int,
        groupByRepository: Bool
    ) -> Plan {
        let cellCapacity = max(capacity, 1)
        let groups: [[WorkspaceSnapshot]]
        if groupByRepository {
            var order: [UUID?] = []
            var buckets: [UUID?: [WorkspaceSnapshot]] = [:]
            for workspace in workspaces {
                if buckets[workspace.groupId] == nil {
                    order.append(workspace.groupId)
                }
                buckets[workspace.groupId, default: []].append(workspace)
            }
            groups = order.compactMap { buckets[$0] }
        } else {
            groups = workspaces.isEmpty ? [] : [workspaces]
        }
        return Plan(scopes: groups.map { planScope($0, capacity: cellCapacity) })
    }

    private static func planScope(
        _ workspaces: [WorkspaceSnapshot],
        capacity: Int
    ) -> ScopePlan {
        let realPanels = workspaces.flatMap(\.realPanelIds)
        let needed = realPanels.isEmpty
            ? 0
            : (realPanels.count + capacity - 1) / capacity
        let packedIds = Array(workspaces.prefix(needed).map(\.id))
        let packed = Set(packedIds)
        let anchorIds = workspaces.filter(\.isGroupAnchor).map(\.id)
        var retainedIds = packedIds
        for anchorId in anchorIds where !packed.contains(anchorId) {
            retainedIds.append(anchorId)
        }
        let retained = Set(retainedIds)
        let surplusIds = workspaces.map(\.id).filter { !retained.contains($0) }
        var assignments: [PanelAssignment] = []
        var offset = 0
        for workspaceId in packedIds {
            let slice = Array(realPanels.dropFirst(offset).prefix(capacity))
            assignments.append(PanelAssignment(workspaceId: workspaceId, panelIds: slice))
            offset += slice.count
        }
        return ScopePlan(
            retainedWorkspaceIds: retainedIds,
            surplusWorkspaceIds: surplusIds,
            panelAssignments: assignments
        )
    }
}
