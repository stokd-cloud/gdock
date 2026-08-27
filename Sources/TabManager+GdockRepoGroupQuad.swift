import Foundation

@MainActor
extension TabManager {
    /// Turns a repository group's anchor workspace into the stokd quad.
    ///
    /// Activating a repo group header is a request to see that repository's
    /// state: worktrees, projects, tasks, todos, all at once. The recipe
    /// deals a flat 2x2 from the anchor's leading pane — split right, then
    /// split each column down — matching the shape `QuadSplitAction` produces,
    /// so the result is a quad rather than a quad nested inside one leaf.
    ///
    /// A hand-named group launches nothing (`AX-GDOCK-REPO-COMMAND-SURFACE`,
    /// AC-B), and re-activating a group that already holds this quad re-focuses
    /// it instead of spawning a second set.
    ///
    /// - Returns: Whether a quad was launched.
    @discardableResult
    func launchGdockRepoGroupQuad(groupId: UUID) -> Bool {
        guard let group = workspaceGroups.first(where: { $0.id == groupId }),
              let anchor = tabs.first(where: { $0.id == group.anchorWorkspaceId }) else {
            return false
        }

        let plan = GdockRepoGroupQuadPlanner.plan(
            groupName: group.name,
            directory: anchor.currentDirectory,
            overrideCommands: GdockRepoGroupQuadCommandSettings.overrideCommands(),
            existingCommands: gdockRepoGroupQuadCommandsByWorkspaceId[anchor.id] ?? []
        )
        guard let plan, plan.count == GdockRepoGroupQuadPlanner.quadrantCount else {
            // Already quadded (or not a repo group): make sure activating the
            // header still brings the user to it.
            if GdockRepoWorkspaceGroupIdentity.isRepositoryGroup(name: group.name) {
                selectWorkspace(anchor)
            }
            return false
        }

        guard let topLeftPanelId = anchor.focusedPanelId ?? anchor.panels.keys.first else {
            return false
        }

        selectWorkspace(anchor)

        // The leading pane already has a live shell, so it is typed into rather
        // than replaced; the other three are born with their command.
        _ = anchor.terminalPanel(for: topLeftPanelId)?.sendText(plan[0].command + "\r")

        guard let topRightPanelId = newSplit(
            tabId: anchor.id,
            surfaceId: topLeftPanelId,
            direction: .right,
            focus: false,
            workingDirectory: plan[1].directory,
            initialCommand: plan[1].command
        ) else {
            return false
        }
        _ = newSplit(
            tabId: anchor.id,
            surfaceId: topLeftPanelId,
            direction: .down,
            focus: false,
            workingDirectory: plan[2].directory,
            initialCommand: plan[2].command
        )
        _ = newSplit(
            tabId: anchor.id,
            surfaceId: topRightPanelId,
            direction: .down,
            focus: false,
            workingDirectory: plan[3].directory,
            initialCommand: plan[3].command
        )

        gdockRepoGroupQuadCommandsByWorkspaceId[anchor.id] = plan.map(\.command)
        return true
    }

    /// Forgets a workspace's quad record so a later activation re-launches.
    func forgetGdockRepoGroupQuad(workspaceId: UUID) {
        gdockRepoGroupQuadCommandsByWorkspaceId.removeValue(forKey: workspaceId)
    }
}
