import AppKit
import Foundation

/// Reduces live windows, workspaces and panels into the value snapshot the
/// cycler renders.
///
/// Runs entirely above the overlay's list boundary: it reads stores here, and
/// everything below only ever sees ``GdockCyclableSession`` values (CLAUDE.md;
/// cmux issue 2586).
@MainActor
enum GdockSessionCyclerCollector {
    /// Every panel currently running an agent, across every main window.
    ///
    /// "Running an agent" is the workspace's own `agentPIDKeysByPanelId`
    /// bookkeeping — the same source the sidebar's agent badges and the pane
    /// cards use — so the cycler cannot list a session the rest of the app does
    /// not believe in.
    static func sessions(
        tabManagers: [TabManager],
        outcomes: StokdSessionOutcomesStore = .shared
    ) -> [GdockCyclableSession] {
        var sessions: [GdockCyclableSession] = []
        var directories: [String] = []

        for tabManager in tabManagers {
            let groupNamesById = Dictionary(
                tabManager.workspaceGroups.map { ($0.id, $0.name) },
                uniquingKeysWith: { first, _ in first }
            )

            for workspace in tabManager.tabs {
                let repoSlug = workspace.groupId
                    .flatMap { groupNamesById[$0] }
                    .flatMap(GdockRepoWorkspaceGroupIdentity.slug(forGroupName:))
                let branch = workspace.gitBranch?.branch
                let paneOrder = paneOrderIndexes(in: workspace)

                let panelIds = workspace.agentPIDKeysByPanelId
                    .filter { !$0.value.isEmpty && workspace.panels[$0.key] != nil }
                    .keys
                    .sorted { lhs, rhs in
                        let lhsOrder = paneOrder[lhs] ?? Int.max
                        let rhsOrder = paneOrder[rhs] ?? Int.max
                        if lhsOrder != rhsOrder { return lhsOrder < rhsOrder }
                        return lhs.uuidString < rhs.uuidString
                    }

                for panelId in panelIds {
                    let pidKeys = Array(workspace.agentPIDKeysByPanelId[panelId] ?? [])
                    let statusKeys = pidKeys.map { workspace.agentStatusKey(forAgentPIDKey: $0) }
                    let agentPIDs = pidKeys.compactMap { workspace.agentPIDs[$0] }
                    let directory = workspace.panelDirectories[panelId] ?? ""
                    if !directory.isEmpty { directories.append(directory) }

                    let summary = directory.isEmpty
                        ? nil
                        : outcomes.summary(forDirectory: directory, agentPIDs: agentPIDs)
                    let badge = GdockSessionAgentBadge.badge(forStatusKeys: statusKeys)
                    let panelTitle = workspace.panelTitles[panelId]?
                        .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""

                    sessions.append(
                        GdockCyclableSession(
                            panelId: panelId,
                            workspaceId: workspace.id,
                            workspaceName: workspace.title,
                            repoSlug: repoSlug,
                            title: panelTitle.isEmpty ? workspace.title : panelTitle,
                            branch: branch,
                            agentAssetName: badge?.assetName,
                            agentDisplayName: badge?.displayName ?? "",
                            summary: summary,
                            lastActivity: summary?.updatedAt
                        )
                    )
                }
            }
        }

        // Reads above used the last published snapshot; this feeds the next one.
        // All filesystem work happens off the main thread inside the store, and
        // its interval guard collapses repeat calls.
        outcomes.refreshIfNeeded(directories: directories)
        return sessions
    }

    /// The repository the operator is currently in, or nil when the selected
    /// workspace is not in a repository group.
    static func currentRepoSlug(tabManager: TabManager?) -> String? {
        guard let tabManager,
              let selectedId = tabManager.selectedTabId,
              let workspace = tabManager.tabs.first(where: { $0.id == selectedId }),
              let groupId = workspace.groupId,
              let name = tabManager.workspaceGroups.first(where: { $0.id == groupId })?.name else {
            return nil
        }
        return GdockRepoWorkspaceGroupIdentity.slug(forGroupName: name)
    }

    /// Pane-tree position of each visible panel, so rows read top-to-bottom in
    /// the order the operator sees on screen.
    private static func paneOrderIndexes(in workspace: Workspace) -> [UUID: Int] {
        var order: [UUID: Int] = [:]
        for (index, paneId) in workspace.bonsplitController.allPaneIds.enumerated() {
            guard let panelId = workspace.bonsplitController.selectedTab(inPane: paneId)?.id.uuid else {
                continue
            }
            order[panelId] = index
        }
        return order
    }
}
