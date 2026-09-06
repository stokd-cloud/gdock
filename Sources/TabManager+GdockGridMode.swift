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
    /// shrink never hides or closes a running terminal. After shaping, real
    /// panels are packed into the fewest workspaces that can hold them.
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
        compactGdockGridWorkspaces(shape: shape)
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
        for workspace in tabs {
            workspace.applyGdockGridLockChrome()
        }
        guard enabled else { return }
        if !force, lastGdockGridModeEnabled == true, lastGdockGridModeShape == shape {
            return
        }
        scheduleGdockGridModeReconcile()
    }

    // MARK: - Cmd+T routing

    /// Grid Mode's Cmd+T: fill the next unactivated cell of the selected
    /// workspace, or roll the least-recently-touched real panel into another
    /// workspace when the grid is full.
    ///
    /// Returns `false` when the mode is off or the workspace vetoes shaping
    /// (canvas, remote), in which case the legacy new-surface path runs.
    func gdockGridModeRouteNewSurface() -> Bool {
        guard GdockGridModeSettings.isEnabled(),
              let workspace = selectedWorkspace,
              GdockGridSplitAction.preflight(workspace: workspace) == nil else {
            return false
        }

        let orderedPanelIds = gdockGridOrderedPanelIds(in: workspace)
        let route = GdockGridNewSurfacePlanner.route(
            orderedPanelIds: orderedPanelIds,
            placeholderPanelIds: Array(workspace.gdockGridPlaceholderPanelIds),
            touchOrder: gdockGridPanelTouchOrder
        )

        switch route {
        case .activatePlaceholder(let panelId):
            guard let paneId = workspace.paneId(forPanelId: panelId) else { return false }
            workspace.clearSplitZoom()
            workspace.bonsplitController.focusPane(paneId)
            workspace.focusPanel(panelId)
            workspace.activateGdockGridPlaceholderIfNeeded(panelId: panelId)
            noteGdockGridPanelTouch(panelId)
            return true

        case .rollOver(let panelId):
            return gdockGridRollOver(panelId: panelId, in: workspace)
        }
    }

    func noteGdockGridPanelTouch(_ panelId: UUID) {
        gdockGridPanelTouchSeq += 1
        gdockGridPanelTouchOrder[panelId] = gdockGridPanelTouchSeq
    }

    private func gdockGridOrderedPanelIds(in workspace: Workspace) -> [UUID] {
        workspace.spatiallyOrderedPaneIds.compactMap { paneUUID in
            let paneId = PaneID(id: paneUUID)
            guard let tab = workspace.bonsplitController.selectedTab(inPane: paneId)
                ?? workspace.bonsplitController.tabs(inPane: paneId).first else {
                return nil
            }
            return workspace.panelIdFromSurfaceId(tab.id)
        }
    }

    /// Creates a clean terminal in the LRU cell, moves the LRU panel into a
    /// same-scope workspace (existing with room, or a new one that already
    /// holds that real panel), then packs the scope.
    private func gdockGridRollOver(panelId: UUID, in workspace: Workspace) -> Bool {
        guard let paneId = workspace.paneId(forPanelId: panelId),
              let appDelegate = AppDelegate.shared else {
            return false
        }
        workspace.clearSplitZoom()
        workspace.bonsplitController.focusPane(paneId)
        let replacement = workspace.newTerminalSurface(
            inPane: paneId,
            focus: true,
            inheritWorkingDirectoryFallback: true
        )
        guard let replacement else { return false }

        let destination = gdockGridRolloverDestination(from: workspace)
        _ = appDelegate.moveSurface(
            panelId: panelId,
            toWorkspace: destination.id,
            focus: false,
            focusWindow: false
        )
        let shape = GdockGridModeSettings.shape()
        _ = applyGdockGridShapeAndSpill(shape, to: destination)
        compactGdockGridWorkspaces(shape: shape)

        if let pane = workspace.paneId(forPanelId: replacement.id) {
            workspace.bonsplitController.focusPane(pane)
        }
        workspace.focusPanel(replacement.id)
        noteGdockGridPanelTouch(replacement.id)
        if selectedTabId != workspace.id {
            selectTab(workspace)
        }
        return true
    }

    private func gdockGridRolloverDestination(from workspace: Workspace) -> Workspace {
        let sameScope = tabs.filter { other in
            other.id != workspace.id
                && other.groupId == workspace.groupId
                && GdockGridSplitAction.preflight(workspace: other) == nil
        }
        if let existing = sameScope.first(where: { !$0.gdockGridPlaceholderPanelIds.isEmpty }) {
            return existing
        }
        if let groupId = workspace.groupId,
           let created = createWorkspaceInGroup(groupId: groupId, select: false) {
            return created
        }
        return addWorkspace(select: false)
    }

    private func compactGdockGridWorkspaces(shape: GdockGridShape) {
        let capacity = shape.cellCount
        let eligible = tabs.filter { GdockGridSplitAction.preflight(workspace: $0) == nil }
        let anchorIds = Set(workspaceGroups.map(\.anchorWorkspaceId))
        let snapshots = eligible.map { workspace in
            GdockGridWorkspaceCompactionPlanner.WorkspaceSnapshot(
                id: workspace.id,
                groupId: workspace.groupId,
                isGroupAnchor: anchorIds.contains(workspace.id),
                panelIds: gdockGridOrderedPanelIds(in: workspace),
                placeholderPanelIds: Array(workspace.gdockGridPlaceholderPanelIds)
            )
        }
        let plan = GdockGridWorkspaceCompactionPlanner.plan(
            workspaces: snapshots,
            capacity: capacity,
            groupByRepository: GdockAutoWorkspaceGroupModeSettings.isEnabled()
        )
        guard let appDelegate = AppDelegate.shared else { return }
        let workspaceById = Dictionary(uniqueKeysWithValues: tabs.map { ($0.id, $0) })

        for scope in plan.scopes {
            for assignment in scope.panelAssignments {
                guard let destination = workspaceById[assignment.workspaceId] else { continue }
                for panelId in assignment.panelIds {
                    guard let source = tabs.first(where: { $0.panels[panelId] != nil }),
                          source.id != destination.id else {
                        continue
                    }
                    _ = appDelegate.moveSurface(
                        panelId: panelId,
                        toWorkspace: destination.id,
                        focus: false,
                        focusWindow: false
                    )
                }
                _ = applyGdockGridShapeAndSpill(shape, to: destination)
            }
            for surplusId in scope.surplusWorkspaceIds {
                guard let surplus = workspaceById[surplusId], tabs.count > 1 else { continue }
                if workspaceGroups.contains(where: { $0.anchorWorkspaceId == surplusId }) {
                    continue
                }
                closeWorkspace(surplus, recordHistory: false)
            }
        }
    }
}
