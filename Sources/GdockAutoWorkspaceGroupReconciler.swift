import Foundation

/// One membership mutation produced by ``GdockAutoWorkspaceGroupReconciler``.
enum GdockAutoWorkspaceGroupMutation: Equatable, Sendable {
    /// Create a new group named `name` and attach the given non-anchor members.
    case createGroup(name: String, memberWorkspaceIds: [UUID])
    /// Move/add an existing workspace into an existing group.
    case addToGroup(workspaceId: UUID, groupId: UUID)
}

/// Pure planner for Auto Workspace Group Mode.
///
/// Resolves desired `owner/repo` membership from workspace cwds and emits the
/// minimum create/add mutations. Never plans moves for group anchors.
enum GdockAutoWorkspaceGroupReconciler {
    struct WorkspaceSnapshot: Equatable, Sendable {
        let id: UUID
        let currentDirectory: String
        let groupId: UUID?
        let isGroupAnchor: Bool
    }

    struct GroupSnapshot: Equatable, Sendable {
        let id: UUID
        let name: String
    }

    /// Plans group create/add mutations for the given workspace/group snapshot.
    ///
    /// - Parameters:
    ///   - workspaces: Current workspaces (membership + cwd + anchor bit).
    ///   - groups: Current groups (id + display name).
    ///   - slugForDirectory: Returns the primary GitHub `owner/repo` for a cwd, or nil.
    /// - Returns: Ordered mutations (creates first per slug encounter order, then adds).
    static func plan(
        workspaces: [WorkspaceSnapshot],
        groups: [GroupSnapshot],
        slugForDirectory: (String) -> String?
    ) -> [GdockAutoWorkspaceGroupMutation] {
        var memberIdsBySlug: [String: [UUID]] = [:]
        var slugOrder: [String] = []
        var workspaceById: [UUID: WorkspaceSnapshot] = [:]

        for workspace in workspaces {
            workspaceById[workspace.id] = workspace
            guard !workspace.isGroupAnchor else { continue }
            guard let slug = slugForDirectory(workspace.currentDirectory)?
                .trimmingCharacters(in: .whitespacesAndNewlines),
                !slug.isEmpty else {
                continue
            }
            if memberIdsBySlug[slug] == nil {
                slugOrder.append(slug)
                memberIdsBySlug[slug] = []
            }
            memberIdsBySlug[slug, default: []].append(workspace.id)
        }

        var mutations: [GdockAutoWorkspaceGroupMutation] = []
        for slug in slugOrder {
            guard let memberIds = memberIdsBySlug[slug], !memberIds.isEmpty else { continue }
            if let existing = groups.first(where: { $0.name == slug }) {
                for workspaceId in memberIds {
                    guard let workspace = workspaceById[workspaceId] else { continue }
                    if workspace.groupId != existing.id {
                        mutations.append(.addToGroup(workspaceId: workspaceId, groupId: existing.id))
                    }
                }
            } else {
                mutations.append(.createGroup(name: slug, memberWorkspaceIds: memberIds))
            }
        }
        return mutations
    }
}
