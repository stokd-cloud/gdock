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
    /// Rename an existing repository group to `name`.
    ///
    /// A group header cannot move itself into another group, so an anchor that
    /// is its group's only workspace re-identifies the group instead of
    /// relocating: the container follows the repository the user is in.
    case renameGroup(groupId: UUID, name: String)
}

/// Pure planner for Auto Workspace Group Mode.
///
/// Resolves desired `owner/repo` membership from workspace and panel cwds and
/// emits the minimum rename/create/add/extract mutations. A group anchor is
/// never moved into another group — it *is* its group's header — but it is not
/// exempt from the feature: a one-workspace group follows its anchor by being
/// renamed, and an anchor with siblings gives up its retargeted panels the same
/// way a member does.
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
        /// Grid Mode unactivated cells. Auto-group must not extract these into
        /// new workspaces (AX-GDOCK-AUTO-GROUP-SPAWN-BOUNDED).
        let isGridPlaceholder: Bool

        init(id: UUID, currentDirectory: String, isGridPlaceholder: Bool = false) {
            self.id = id
            self.currentDirectory = currentDirectory
            self.isGridPlaceholder = isGridPlaceholder
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
    /// - Returns: Ordered mutations — group renames, then panel extractions,
    ///   then group creates/adds in slug encounter order.
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

        var renames: [GdockAutoWorkspaceGroupMutation] = []
        var extractions: [GdockAutoWorkspaceGroupMutation] = []
        var memberIdsBySlug: [String: [UUID]] = [:]
        var slugOrder: [String] = []
        var workspaceById: [UUID: WorkspaceSnapshot] = [:]
        for workspace in workspaces { workspaceById[workspace.id] = workspace }

        // Two groups may not answer to the same repository, so a rename only
        // lands on a slug nothing else already carries.
        var claimedSlugs = Set(groups.compactMap { repositorySlug(from: $0.name) })

        // Pass 1 — group anchors. The header cannot move, so either the group
        // re-identifies (it owns nothing but the anchor) or the anchor sheds the
        // panels that wandered off, keeping at least one so the header survives.
        for workspace in workspaces where workspace.isGroupAnchor {
            guard let groupId = workspace.groupId,
                  let homeSlug = groupNameById[groupId].flatMap(repositorySlug(from:)) else {
                continue
            }

            let panelSlugs = Set(workspace.panels.compactMap { normalizedSlug($0.currentDirectory) })
            let ownsNothingElse = workspaces.filter { $0.groupId == groupId }.count == 1

            if ownsNothingElse {
                // One agreed-on repo across the anchor's panels re-identifies the
                // group. Panels split across repos do not: renaming would mis-name
                // the ones that stayed, so they are extracted instead.
                let target: String?
                if panelSlugs.count == 1 {
                    target = panelSlugs.first
                } else if panelSlugs.isEmpty {
                    target = normalizedSlug(workspace.currentDirectory)
                } else {
                    target = nil
                }
                if let target, target != homeSlug, !claimedSlugs.contains(target) {
                    renames.append(.renameGroup(groupId: groupId, name: target))
                    claimedSlugs.remove(homeSlug)
                    claimedSlugs.insert(target)
                    groupNameById[groupId] = target
                    continue
                }
            }

            let extractable = workspace.panels.filter { !$0.isGridPlaceholder }
            guard extractable.count > 1 else { continue }
            let divergent = extractable.compactMap { panel -> (UUID, String)? in
                guard let slug = normalizedSlug(panel.currentDirectory), slug != homeSlug else {
                    return nil
                }
                return (panel.id, slug)
            }
            // Emptying the anchor would take the group's header with it, so the
            // trailing divergent panel stays behind.
            for (panelId, slug) in divergent.prefix(extractable.count - 1) {
                extractions.append(
                    .extractPanel(panelId: panelId, fromWorkspaceId: workspace.id, slug: slug)
                )
            }
        }

        // Pass 2 — everything that is not a header.
        for workspace in workspaces {
            guard !workspace.isGroupAnchor else { continue }

            // A workspace already grouped under a repo slug treats that slug as
            // its home, so a retargeted panel — not the workspace — is what moves.
            let extractable = workspace.panels.filter { !$0.isGridPlaceholder }
            if let homeSlug = workspace.groupId.flatMap({ groupNameById[$0] }).flatMap(repositorySlug(from:)),
               extractable.count > 1 {
                let divergent = extractable.compactMap { panel -> (UUID, String)? in
                    guard let slug = normalizedSlug(panel.currentDirectory), slug != homeSlug else {
                        return nil
                    }
                    return (panel.id, slug)
                }
                // Every panel moving means the workspace itself moved; fall through
                // to the whole-workspace path rather than emptying it panel by panel.
                if !divergent.isEmpty, divergent.count < extractable.count {
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

        var mutations = renames + extractions
        for slug in slugOrder {
            guard let memberIds = memberIdsBySlug[slug], !memberIds.isEmpty else { continue }
            // Match on the planned name so members route into a group this same
            // plan renamed rather than creating a duplicate beside it.
            if let existing = groups.first(where: { groupNameById[$0.id] == slug }) {
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
