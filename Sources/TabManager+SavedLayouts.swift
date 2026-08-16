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
            setTabColor(tabId: workspace.id, color: color)
        }
        if let layoutNode = layout.workspace.layout {
            workspace.applyCustomLayout(layoutNode, baseCwd: resolvedCwd)
        }
        return workspace
    }

    /// Reattach rail tool panels when the selected workspace changes.
    ///
    /// Full rail-store reattach (left/right `reattachAllPanels`) lands with the
    /// sidebar-dock mission. Until those stores expose that API on this branch,
    /// this is a safe no-op so workspace selection still compiles and runs.
    func reattachSidebarDockAdapters(to workspace: Workspace) {
        _ = workspace
    }
}
