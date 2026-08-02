import Foundation

extension TabManager {
    @discardableResult
    func openWorkspace(fromSavedLayout layout: CmuxSavedLayout, cwdOverride: String?, focus: Bool) -> Workspace? {
        let baseCwd = FileManager.default.homeDirectoryForCurrentUser.path
        let resolvedCwd = CmuxConfigStore.resolveCwd(cwdOverride ?? layout.workspace.cwd, relativeTo: baseCwd)
        let workspace = addWorkspace(
            title: layout.workspace.name ?? layout.name,
            workingDirectory: resolvedCwd,
            workspaceEnvironment: layout.workspace.env ?? [:],
            inheritWorkingDirectory: false,
            select: focus
        )
        if let color = layout.workspace.color {
            workspace.setCustomColor(color)
        }
        if let layoutNode = layout.workspace.layout {
            workspace.applyCustomLayout(layoutNode, baseCwd: resolvedCwd)
        }
        return workspace
    }
    /// RED stub: apply is a no-op until green wires the shared registry path.
    func applySidebarDockLayout(
        _ definition: CmuxSidebarDockDefinition,
        to workspace: Workspace,
        preferredLegacyMode: RightSidebarMode? = nil
    ) {
        _ = definition
        _ = workspace
        _ = preferredLegacyMode
    }

    /// RED stub: reattachment is a no-op.
    func reattachSidebarDockAdapters(to workspace: Workspace) {
        _ = workspace
    }
}
