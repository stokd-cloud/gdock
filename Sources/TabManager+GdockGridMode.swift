import Bonsplit
import Foundation

extension TabManager {
    // MARK: - Reconcile

    /// Debounced entry point: schedule a Grid Mode shape reconcile across
    /// this window's workspaces.
    func scheduleGdockGridModeReconcile() {
        guard GdockGridModeSettings.isEnabled() else { return }
        gdockGridModeReconcileTask?.cancel()
        gdockGridModeReconcileTask = Task { @MainActor [weak self] in
            try? await Task.sleep(nanoseconds: 250_000_000)
            guard !Task.isCancelled else { return }
            self?.reconcileGdockGridModeNow()
        }
    }

    /// Immediately enforce the configured grid shape on every workspace.
    ///
    /// Workspaces the shape apply vetoes (canvas, remote) are left alone.
    /// Overflow surfaces spill into new workspaces — created in the source
    /// workspace's group when it has one — which are themselves shaped, so a
    /// shrink never hides or closes a running terminal.
    func reconcileGdockGridModeNow() {
        guard GdockGridModeSettings.isEnabled() else { return }
        let shape = GdockGridModeSettings.shape()

        var pending = tabs
        var visited = Set<UUID>()
        while let workspace = pending.first {
            pending.removeFirst()
            guard visited.insert(workspace.id).inserted else { continue }
            if let spill = applyGdockGridShapeAndSpill(shape, to: workspace) {
                pending.append(spill)
            }
        }
    }

    /// Applies `shape` to one workspace and relocates its overflow surfaces
    /// into a new workspace. Returns the spill workspace when one was made.
    @discardableResult
    func applyGdockGridShapeAndSpill(
        _ shape: GdockGridShape,
        to workspace: Workspace
    ) -> Workspace? {
        let outcome = GdockGridSplitAction.applyShape(shape, to: workspace)
        guard case .success(let overflowPanelIds) = outcome,
              !overflowPanelIds.isEmpty,
              let appDelegate = AppDelegate.shared else {
            return nil
        }

        let spill: Workspace?
        if let groupId = workspace.groupId {
            spill = createWorkspaceInGroup(groupId: groupId, select: false)
        } else {
            spill = addWorkspace(select: false)
        }
        guard let spill else { return nil }

        for panelId in overflowPanelIds {
            _ = appDelegate.moveSurface(
                panelId: panelId,
                toWorkspace: spill.id,
                focus: false,
                focusWindow: false
            )
        }
        return spill
    }

    /// Observe mode/shape changes; reconcile while the mode is on.
    ///
    /// `force` is used by the dedicated change notification (an explicit user
    /// action always re-enforces). The `UserDefaults.didChangeNotification`
    /// path passes `false` so unrelated defaults writes do not repeatedly
    /// restructure workspaces the user has hand-adjusted.
    func gdockGridModeSettingsDidChange(force: Bool = false) {
        let enabled = GdockGridModeSettings.isEnabled()
        let shape = GdockGridModeSettings.shape()
        defer {
            lastGdockGridModeEnabled = enabled
            lastGdockGridModeShape = shape
        }
        guard enabled else { return }
        if !force, lastGdockGridModeEnabled == true, lastGdockGridModeShape == shape {
            return
        }
        scheduleGdockGridModeReconcile()
    }

    // MARK: - Cmd+T routing

    /// Grid Mode's Cmd+T: fill the next unactivated cell of the selected
    /// workspace, or create a new (shaped) workspace when the grid is full.
    ///
    /// Returns `false` when the mode is off or the workspace vetoes shaping
    /// (canvas, remote), in which case the legacy new-surface path runs.
    func gdockGridModeRouteNewSurface() -> Bool {
        guard GdockGridModeSettings.isEnabled(),
              let workspace = selectedWorkspace,
              GdockGridSplitAction.preflight(workspace: workspace) == nil else {
            return false
        }

        for paneUUID in workspace.spatiallyOrderedPaneIds {
            let paneId = PaneID(id: paneUUID)
            guard let tab = workspace.bonsplitController.selectedTab(inPane: paneId)
                ?? workspace.bonsplitController.tabs(inPane: paneId).first,
                let panelId = workspace.panelIdFromSurfaceId(tab.id),
                workspace.isGdockGridPlaceholder(panelId: panelId) else {
                continue
            }
            workspace.clearSplitZoom()
            workspace.bonsplitController.focusPane(paneId)
            workspace.focusPanel(panelId)
            workspace.activateGdockGridPlaceholderIfNeeded(panelId: panelId)
            return true
        }

        // Every cell is occupied: navigate to a fresh workspace instead of
        // hiding a surface behind a tab.
        let shape = GdockGridModeSettings.shape()
        let created: Workspace?
        if let groupId = workspace.groupId {
            created = createWorkspaceInGroup(groupId: groupId, select: true)
        } else {
            created = addWorkspace(select: true)
        }
        guard let created else { return false }
        _ = applyGdockGridShapeAndSpill(shape, to: created)
        return true
    }
}
