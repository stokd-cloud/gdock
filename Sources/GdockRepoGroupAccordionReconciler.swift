import Foundation

/// Plans the accordion collapse of repository workspace groups.
///
/// Selecting a workspace inside a repository group expands that group and
/// collapses the other repository groups, so the sidebar shows one repo's work
/// at a time. Per `AX-GDOCK-REPO-COMMAND-SURFACE` this is a repo-only
/// affordance: selecting a workspace in a hand-named group plans nothing, and a
/// hand-named group is never collapsed as a side effect of someone else's
/// selection.
///
/// Pure planner — it never touches a store, so the whole policy is unit-tested
/// without a live `TabManager`.
enum GdockRepoGroupAccordionReconciler {
    /// One workspace group as it exists when the selection changes.
    struct GroupSnapshot: Equatable, Sendable {
        let id: UUID
        let name: String
        let isCollapsed: Bool
        /// A pinned group is the user saying "keep this one where I can see
        /// it", which outranks the accordion.
        let isPinned: Bool

        init(id: UUID, name: String, isCollapsed: Bool, isPinned: Bool) {
            self.id = id
            self.name = name
            self.isCollapsed = isCollapsed
            self.isPinned = isPinned
        }
    }

    /// A collapse-state change to apply. Only groups whose state actually
    /// differs appear, so applying a plan twice is a no-op.
    enum Mutation: Equatable, Sendable {
        case expand(groupId: UUID)
        case collapse(groupId: UUID)
    }

    /// Plans the accordion for a selection change.
    ///
    /// - Parameters:
    ///   - groups: Every workspace group in the window.
    ///   - selectedGroupId: The group owning the newly selected workspace, or
    ///     `nil` when the selection is an ungrouped workspace.
    ///   - isEnabled: The `gdock.repoGroupAccordion` setting.
    /// - Returns: The expand of the selected group followed by the collapse of
    ///   every other expanded, unpinned repository group. Empty when the
    ///   feature is off, the selection is ungrouped, or the selected group is
    ///   not a repository group.
    static func plan(
        groups: [GroupSnapshot],
        selectedGroupId: UUID?,
        isEnabled: Bool
    ) -> [Mutation] {
        guard isEnabled, let selectedGroupId else { return [] }

        // An ungrouped selection, or a selection inside a hand-named group,
        // leaves every group exactly as the user left it. Collapsing repo
        // groups because the user clicked something unrelated would be the
        // accordion reaching outside its own feature.
        guard let selected = groups.first(where: { $0.id == selectedGroupId }),
              GdockRepoWorkspaceGroupIdentity.isRepositoryGroup(name: selected.name) else {
            return []
        }

        var mutations: [Mutation] = []
        if selected.isCollapsed {
            mutations.append(.expand(groupId: selected.id))
        }
        for group in groups where group.id != selectedGroupId {
            guard !group.isPinned,
                  !group.isCollapsed,
                  GdockRepoWorkspaceGroupIdentity.isRepositoryGroup(name: group.name) else {
                continue
            }
            mutations.append(.collapse(groupId: group.id))
        }
        return mutations
    }
}
