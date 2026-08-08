import Foundation
import CmuxGit

extension TabManager {
    /// Debounced entry point: schedule a full Auto Workspace Group reconcile.
    func scheduleGdockAutoWorkspaceGroupReconcile() {
        guard GdockAutoWorkspaceGroupModeSettings.isEnabled() else { return }
        gdockAutoWorkspaceGroupReconcileWorkItem?.cancel()
        let workItem = DispatchWorkItem { [weak self] in
            self?.reconcileGdockAutoWorkspaceGroupsNow()
        }
        gdockAutoWorkspaceGroupReconcileWorkItem = workItem
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.25, execute: workItem)
    }

    /// Immediately re-group non-anchor workspaces by GitHub `owner/repo` when the mode is on.
    func reconcileGdockAutoWorkspaceGroupsNow() {
        guard GdockAutoWorkspaceGroupModeSettings.isEnabled() else { return }

        let anchorIds = Set(workspaceGroups.map(\.anchorWorkspaceId))
        let workspaceSnapshots = tabs.map { tab in
            // Panel order follows `panels` keyed order only loosely; sort by id so
            // planning is deterministic across reconciles.
            let panels = tab.panelDirectories
                .compactMap { panelId, directory -> GdockAutoWorkspaceGroupReconciler.PanelSnapshot? in
                    let trimmed = directory.trimmingCharacters(in: .whitespacesAndNewlines)
                    guard !trimmed.isEmpty, tab.panels[panelId] != nil else { return nil }
                    return GdockAutoWorkspaceGroupReconciler.PanelSnapshot(
                        id: panelId,
                        currentDirectory: trimmed
                    )
                }
                .sorted { $0.id.uuidString < $1.id.uuidString }

            return GdockAutoWorkspaceGroupReconciler.WorkspaceSnapshot(
                id: tab.id,
                currentDirectory: tab.currentDirectory,
                groupId: tab.groupId,
                isGroupAnchor: anchorIds.contains(tab.id),
                panels: panels
            )
        }
        let groupSnapshots = workspaceGroups.map { group in
            GdockAutoWorkspaceGroupReconciler.GroupSnapshot(id: group.id, name: group.name)
        }

        let plan = GdockAutoWorkspaceGroupReconciler.plan(
            workspaces: workspaceSnapshots,
            groups: groupSnapshots,
            slugForDirectory: { directory in
                GitMetadataService.primaryGitHubRepositorySlug(for: directory)
            }
        )

        guard !plan.isEmpty else { return }

        for mutation in plan {
            switch mutation {
            case .createGroup(let name, let memberWorkspaceIds):
                _ = createWorkspaceGroup(
                    name: name,
                    childWorkspaceIds: memberWorkspaceIds,
                    selectAnchor: false,
                    collapseSidebarSelection: false
                )
            case .addToGroup(let workspaceId, let groupId):
                addWorkspaceToGroup(workspaceId: workspaceId, groupId: groupId)
            case .extractPanel(let panelId, _, let slug):
                extractGdockAutoWorkspaceGroupPanel(panelId: panelId, slug: slug)
            }
        }
    }

    /// Moves one retargeted panel into its own workspace under `slug`'s group.
    ///
    /// Focus and window activation are deliberately suppressed: this runs off a
    /// debounced cwd notification, and stealing focus mid-keystroke would be
    /// worse than the mis-grouping it fixes.
    private func extractGdockAutoWorkspaceGroupPanel(panelId: UUID, slug: String) {
        guard let appDelegate = AppDelegate.shared,
              appDelegate.canMoveSurfaceToNewWorkspace(panelId: panelId),
              let move = appDelegate.moveSurfaceToNewWorkspace(
                  panelId: panelId,
                  focus: false,
                  focusWindow: false
              ) else {
            return
        }

        if let existing = workspaceGroups.first(where: { $0.name == slug }) {
            addWorkspaceToGroup(workspaceId: move.destinationWorkspaceId, groupId: existing.id)
        } else {
            _ = createWorkspaceGroup(
                name: slug,
                childWorkspaceIds: [move.destinationWorkspaceId],
                selectAnchor: false,
                collapseSidebarSelection: false
            )
        }
    }

    /// Observe mode toggles and re-run reconcile when the setting turns on.
    func gdockAutoWorkspaceGroupModeSettingsDidChange() {
        let enabled = GdockAutoWorkspaceGroupModeSettings.isEnabled()
        defer { lastGdockAutoWorkspaceGroupModeEnabled = enabled }
        guard enabled else { return }
        if lastGdockAutoWorkspaceGroupModeEnabled == true {
            // Still on; a value write of the same bool can fire UserDefaults noise.
            // Full reconcile is cheap enough when we only schedule on true edge + cwd.
        }
        scheduleGdockAutoWorkspaceGroupReconcile()
    }
}
