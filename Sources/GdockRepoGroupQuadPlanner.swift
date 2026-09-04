import Foundation

/// Plans the four stokd surfaces a repository group's quad launch loads.
///
/// Activating a repository group header turns its anchor workspace into a 2x2
/// of stokd TUIs — worktree, project, task, todo — all pointed at that repo.
/// Per `AX-GDOCK-REPO-COMMAND-SURFACE` a hand-named group plans nothing.
///
/// Pure planner: it decides *what* the quadrants should run. Applying the
/// flatten-and-overlay stays with `TabManager.launchGdockRepoGroupQuad`, which
/// uses `GdockGridSplitAction` so an already-split workspace becomes the TUI
/// grid rather than nesting a second 2x2 inside one leaf.
enum GdockRepoGroupQuadPlanner {
    /// Quadrant order is `[topLeft, topRight, bottomLeft, bottomRight]`.
    static let defaultCommands = [
        "stokd worktree",
        "stokd project",
        "stokd task",
        "stokd todo",
    ]

    /// One quadrant of the planned 2x2.
    struct Quadrant: Equatable, Sendable {
        /// Command the quadrant's terminal runs on launch.
        let command: String
        /// Working directory for that terminal.
        let directory: String

        init(command: String, directory: String) {
            self.command = command
            self.directory = directory
        }
    }

    /// Number of quadrants, matching `QuadSplitPlanner.quadrantCount`.
    static let quadrantCount = 4

    /// Plans the quad for a group header activation.
    ///
    /// - Parameters:
    ///   - groupName: The group's display name; must resolve to an `owner/repo`
    ///     slug or nothing is planned.
    ///   - directory: The repository directory the four terminals open in.
    ///   - overrideCommands: `gdock.repoGroupQuadCommands`. Used only when it
    ///     supplies exactly `quadrantCount` non-blank commands; a partial or
    ///     malformed override falls back to the defaults rather than producing
    ///     a half-configured quad.
    ///   - existingCommands: Commands already running in the anchor workspace's
    ///     panes, in any order.
    /// - Returns: Four quadrants, or `nil` when the group is not a repository
    ///   group, the directory is blank, or the workspace already holds this
    ///   exact set of stokd surfaces.
    static func plan(
        groupName: String,
        directory: String,
        overrideCommands: [String] = [],
        existingCommands: [String] = []
    ) -> [Quadrant]? {
        guard GdockRepoWorkspaceGroupIdentity.isRepositoryGroup(name: groupName) else {
            return nil
        }
        let trimmedDirectory = directory.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedDirectory.isEmpty else { return nil }

        let commands = resolvedCommands(overrideCommands: overrideCommands)

        // Idempotence: re-activating a group that is already showing this quad
        // should re-focus it, not deal a second set of shells on top.
        if Set(commands).isSubset(of: Set(existingCommands.map(normalized))) {
            return nil
        }

        return commands.map { Quadrant(command: $0, directory: trimmedDirectory) }
    }

    /// The override when it is complete and usable, otherwise the defaults.
    private static func resolvedCommands(overrideCommands: [String]) -> [String] {
        let cleaned = overrideCommands.map(normalized).filter { !$0.isEmpty }
        guard cleaned.count == quadrantCount else { return defaultCommands }
        return cleaned
    }

    private static func normalized(_ command: String) -> String {
        command.trimmingCharacters(in: .whitespacesAndNewlines)
    }
}
