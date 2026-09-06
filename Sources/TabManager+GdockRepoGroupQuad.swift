import Bonsplit
import Foundation

@MainActor
extension TabManager {
    /// Turns a repository group's anchor workspace into the stokd quad.
    ///
    /// Activating a repo group header is a request to see that repository's
    /// state: worktrees, projects, tasks, todos, all at once. The recipe
    /// flattens the anchor to the target grid (current Grid Mode shape, or a
    /// 2x2 when Grid Mode is off) and writes the planned commands into those
    /// cells. It never splits a leaf of an existing quad, so the TUIs become
    /// the workspace rather than nesting inside one pane.
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

        selectWorkspace(anchor)

        let targetShape = GdockGridModeSettings.isEnabled()
            ? GdockGridModeSettings.shape()
            : .quad
        _ = applyGdockGridShapeAndSpill(targetShape, to: anchor)

        let paneIds = anchor.spatiallyOrderedPaneIds
        for (index, paneUUID) in paneIds.prefix(plan.count).enumerated() {
            overlayGdockRepoGroupCommand(plan[index], onto: PaneID(id: paneUUID), in: anchor)
        }

        gdockRepoGroupQuadCommandsByWorkspaceId[anchor.id] = plan.map(\.command)
        return true
    }

    /// Types the planned command into an existing cell. Placeholders are
    /// activated first so the TUI is not born as a stacked tab or a nested split.
    private func overlayGdockRepoGroupCommand(
        _ quadrant: GdockRepoGroupQuadPlanner.Quadrant,
        onto paneId: PaneID,
        in workspace: Workspace
    ) {
        guard let tab = workspace.bonsplitController.selectedTab(inPane: paneId)
            ?? workspace.bonsplitController.tabs(inPane: paneId).first,
              let panelId = workspace.panelIdFromSurfaceId(tab.id) else {
            return
        }
        if workspace.isGdockGridPlaceholder(panelId: panelId) {
            workspace.activateGdockGridPlaceholderIfNeeded(panelId: panelId)
        }
        _ = workspace.terminalPanel(for: panelId)?.sendText(quadrant.command + "\r")
    }

    /// Forgets a workspace's quad record so a later activation re-launches.
    func forgetGdockRepoGroupQuad(workspaceId: UUID) {
        gdockRepoGroupQuadCommandsByWorkspaceId.removeValue(forKey: workspaceId)
    }
}
