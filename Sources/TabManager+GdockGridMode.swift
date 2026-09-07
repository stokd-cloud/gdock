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
        guard GdockGridModeSettings.isEnabled(), !isReconcilingGdockGridMode else { return }
        isReconcilingGdockGridMode = true
        defer { isReconcilingGdockGridMode = false }
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
        let wasReconciling = isReconcilingGdockGridMode
        isReconcilingGdockGridMode = true
        defer { isReconcilingGdockGridMode = wasReconciling }
        let outcome = GdockGridSplitAction.applyShape(shape, to: workspace)
        guard case .success(let overflowPanelIds) = outcome,
              let firstPanelId = overflowPanelIds.first,
              overflowPanelIds.count == 1 || AppDelegate.shared != nil else {
            return nil
        }

        guard let spill = gdockGridCreateWorkspace(moving: firstPanelId, from: workspace) else { return nil }

        for panelId in overflowPanelIds.dropFirst() {
            guard AppDelegate.shared?.moveSurface(
                panelId: panelId,
                toWorkspace: spill.id,
                focus: false,
                focusWindow: false
            ) == true else { break }
        }
        return spill
    }

    private func gdockGridCreateWorkspace(moving panelId: UUID, from workspace: Workspace) -> Workspace? {
        let sourcePane = workspace.paneId(forPanelId: panelId)
        let sourceIndex = workspace.indexInPane(forPanelId: panelId)
        guard let detached = workspace.detachSurface(panelId: panelId) else { return nil }
        guard let created = addWorkspace(fromDetachedSurface: detached, select: false) else {
            let pane = sourcePane.flatMap { workspace.bonsplitController.allPaneIds.contains($0) ? $0 : nil }
                ?? workspace.bonsplitController.allPaneIds.first
            if let pane {
                _ = workspace.attachDetachedSurface(detached, inPane: pane, atIndex: sourceIndex, focus: false)
            }
            return nil
        }
        if let groupId = workspace.groupId {
            addWorkspaceToGroup(workspaceId: created.id, groupId: groupId)
        }
        return created
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
        let wasReconciling = isReconcilingGdockGridMode
        isReconcilingGdockGridMode = true
        defer { isReconcilingGdockGridMode = wasReconciling }
        workspace.clearSplitZoom()
        workspace.bonsplitController.focusPane(paneId)
        let replacement = workspace.newTerminalSurface(
            inPane: paneId,
            focus: true,
            inheritWorkingDirectoryFallback: true
        )
        guard let replacement else { return false }

        let destination: Workspace
        if let existing = gdockGridRolloverDestination(from: workspace) {
            guard appDelegate.moveSurface(
                panelId: panelId,
                toWorkspace: existing.id,
                focus: false,
                focusWindow: false
            ) else {
                _ = workspace.closePanel(replacement.id, force: true)
                return false
            }
            destination = existing
        } else if let created = gdockGridCreateWorkspace(moving: panelId, from: workspace) {
            destination = created
        } else {
            _ = workspace.closePanel(replacement.id, force: true)
            return false
        }
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

    private func gdockGridRolloverDestination(from workspace: Workspace) -> Workspace? {
        let sameScope = tabs.filter { other in
            other.id != workspace.id
                && other.groupId == workspace.groupId
                && GdockGridSplitAction.preflight(workspace: other) == nil
        }
        return sameScope.first(where: { !$0.gdockGridPlaceholderPanelIds.isDisjoint(with: $0.panels.keys) })
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
                // Failed transfers must never turn a planned compaction into data loss.
                guard Set(surplus.panels.keys).isSubset(of: surplus.gdockGridPlaceholderPanelIds) else { continue }
                if workspaceGroups.contains(where: { $0.anchorWorkspaceId == surplusId }) {
                    continue
                }
                closeWorkspace(surplus, recordHistory: false)
            }
        }
    }
}
