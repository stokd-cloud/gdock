import Foundation

/// One membership mutation produced by ``GdockAutoWorkspaceGroupReconciler``.
enum GdockAutoWorkspaceGroupMutation: Equatable, Sendable {
    /// Create a new group named `name` and attach the given non-anchor members.
    case createGroup(name: String, memberWorkspaceIds: [UUID])
    /// Move/add an existing workspace into an existing group.
    case addToGroup(workspaceId: UUID, groupId: UUID)
    /// Split one panel out of its workspace into a new workspace grouped under `slug`.
    ///
    /// Emitted when a single panel is retargeted at a different repository than
    /// the workspace it lives in: only that panel relocates, its siblings stay.
    case extractPanel(panelId: UUID, fromWorkspaceId: UUID, slug: String)
}

/// Pure planner for Auto Workspace Group Mode.
///
/// Resolves desired `owner/repo` membership from workspace and panel cwds and
/// emits the minimum create/add/extract mutations. Never plans moves for group
/// anchors.
///
/// Granularity matters here. Re-grouping whole workspaces by their reported cwd
/// meant that `cd`-ing one panel into a different repo dragged every unrelated
/// sibling panel along with it. A workspace already grouped under a repo slug
/// keeps that slug as its home, and only the panels that diverge from it are
/// extracted.
enum GdockAutoWorkspaceGroupReconciler {
    struct PanelSnapshot: Equatable, Sendable {
        let id: UUID
        let currentDirectory: String

        init(id: UUID, currentDirectory: String) {
            self.id = id
            self.currentDirectory = currentDirectory
        }
    }

    struct WorkspaceSnapshot: Equatable, Sendable {
        let id: UUID
        let currentDirectory: String
        let groupId: UUID?
        let isGroupAnchor: Bool
        /// Panels with a known cwd, in workspace order.
        let panels: [PanelSnapshot]

        init(
            id: UUID,
            currentDirectory: String,
            groupId: UUID?,
            isGroupAnchor: Bool,
            panels: [PanelSnapshot] = []
        ) {
            self.id = id
            self.currentDirectory = currentDirectory
            self.groupId = groupId
            self.isGroupAnchor = isGroupAnchor
            self.panels = panels
        }
    }

    struct GroupSnapshot: Equatable, Sendable {
        let id: UUID
        let name: String

        init(id: UUID, name: String) {
            self.id = id
            self.name = name
        }
    }

    /// Plans group create/add/extract mutations for the given snapshot.
    ///
    /// - Parameters:
    ///   - workspaces: Current workspaces (membership + cwd + anchor bit + panels).
    ///   - groups: Current groups (id + display name).
    ///   - slugForDirectory: Returns the primary GitHub `owner/repo` for a cwd, or nil.
    /// - Returns: Ordered mutations — panel extractions first, then group
    ///   creates/adds in slug encounter order.
    static func plan(
        workspaces: [WorkspaceSnapshot],
        groups: [GroupSnapshot],
        slugForDirectory: (String) -> String?
    ) -> [GdockAutoWorkspaceGroupMutation] {
        var groupNameById: [UUID: String] = [:]
        for group in groups { groupNameById[group.id] = group.name }

        func normalizedSlug(_ directory: String) -> String? {
            guard let slug = slugForDirectory(directory)?
                .trimmingCharacters(in: .whitespacesAndNewlines),
                !slug.isEmpty else {
                return nil
            }
            return slug
        }

        var extractions: [GdockAutoWorkspaceGroupMutation] = []
        var memberIdsBySlug: [String: [UUID]] = [:]
        var slugOrder: [String] = []
        var workspaceById: [UUID: WorkspaceSnapshot] = [:]

        for workspace in workspaces {
            workspaceById[workspace.id] = workspace
            guard !workspace.isGroupAnchor else { continue }

            // A workspace already grouped under a repo slug treats that slug as
            // its home, so a retargeted panel — not the workspace — is what moves.
            if let homeSlug = workspace.groupId.flatMap({ groupNameById[$0] }).flatMap(repositorySlug(from:)),
               workspace.panels.count > 1 {
                let divergent = workspace.panels.compactMap { panel -> (UUID, String)? in
                    guard let slug = normalizedSlug(panel.currentDirectory), slug != homeSlug else {
                        return nil
                    }
                    return (panel.id, slug)
                }
                // Every panel moving means the workspace itself moved; fall through
                // to the whole-workspace path rather than emptying it panel by panel.
                if !divergent.isEmpty, divergent.count < workspace.panels.count {
                    for (panelId, slug) in divergent {
                        extractions.append(
                            .extractPanel(panelId: panelId, fromWorkspaceId: workspace.id, slug: slug)
                        )
                    }
                    continue
                }
            }

            guard let slug = normalizedSlug(workspace.currentDirectory) else { continue }
            if memberIdsBySlug[slug] == nil {
                slugOrder.append(slug)
                memberIdsBySlug[slug] = []
            }
            memberIdsBySlug[slug, default: []].append(workspace.id)
        }

        var mutations = extractions
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

    /// A group name reinterpreted as an `owner/repo` slug, or `nil` when the
    /// group carries a hand-written name this feature must not reason about.
    ///
    /// Delegates to ``GdockRepoWorkspaceGroupIdentity`` so auto-grouping and
    /// every other repo-only affordance agree on what counts as a repository
    /// (AX-GDOCK-REPO-COMMAND-SURFACE, AC-A).
    static func repositorySlug(from groupName: String) -> String? {
        GdockRepoWorkspaceGroupIdentity.slug(forGroupName: groupName)
    }
}
