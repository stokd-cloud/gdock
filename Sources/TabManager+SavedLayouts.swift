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
        // Apply UUID-free rail definitions to the target window only (VAL-LAYOUT-001).
        if let dock = layout.workspace.sidebarDock {
            applySidebarDockLayout(dock, to: workspace)
        }
        return workspace
    }

    /// Apply a named-layout rail definition to this window's explicit registry ownership.
    ///
    /// Registry is window-scoped and injected on ``sidebarDockRegistry`` — never resolved
    /// by scanning AppDelegate contexts (VAL-LAYOUT-001 / VAL-CROSS-001 / D-15).
    func applySidebarDockLayout(
        _ definition: CmuxSidebarDockDefinition,
        to workspace: Workspace,
        preferredLegacyMode: RightSidebarMode? = nil
    ) {
        guard RightSidebarBetaFeatureSettings.isSidebarDockEnabled() else { return }
        guard let registry = sidebarDockRegistry else { return }
        _ = registry.applyNamedLayoutDefinition(
            definition,
            workspace: workspace,
            preferredLegacyMode: preferredLegacyMode
        )
    }

    /// Reattach rail tool panels when the selected workspace changes (VAL-CROSS-001).
    func reattachSidebarDockAdapters(to workspace: Workspace) {
        guard RightSidebarBetaFeatureSettings.isSidebarDockEnabled() else { return }
        guard let registry = sidebarDockRegistry else { return }
        registry.left.reattachAllPanels(to: workspace)
        registry.right.reattachAllPanels(to: workspace)
    }
}
