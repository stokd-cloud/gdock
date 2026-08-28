import Bonsplit
import CmuxTerminal
import Foundation

/// Shared gdock Grid Mode shape mutation.
///
/// Restructures a workspace into the enforced `rows × cols` grid: every
/// surface is collapsed into the focused pane, the grid is dealt back out
/// rows-first (`V(row, V(row, …))` of `H(cell, H(cell, …))`), existing
/// surfaces lead cells in tree order, and cells with no surface receive an
/// **unactivated placeholder terminal** — a real `TerminalPanel` whose
/// runtime is held (`heldForStartupRestoreAdmission`) until the user focuses
/// the cell. Surfaces beyond the cell count are returned as overflow for the
/// caller to relocate; Grid Mode never hides a surface behind another.
///
/// Focus ends back on the cell that led the restructure (the previously
/// focused surface), and dividers are equalized.
@MainActor
enum GdockGridSplitAction {
    enum Veto: String, Equatable, Sendable {
        case allowSplitsDisabled
        case noninteractive
        case crossPaneTabMoveDisabled
        case canvasMode
        case remoteWorkspace
        case emptyWorkspace
    }

    enum Outcome: Equatable, Sendable {
        /// The grid was produced; `overflowPanelIds` remain as trailing tabs
        /// of the first cell until the caller relocates them.
        case success(overflowPanelIds: [UUID])
        /// The workspace already matched the shape with one surface per cell.
        case alreadyShaped
        case vetoed(Veto)
        /// Unexpected inconsistency after mutation began.
        case lateFailure(step: String)
    }

    /// Lossless preflight. Grid Mode does not run against remote-mirror or
    /// canvas workspaces.
    static func preflight(workspace: Workspace) -> Veto? {
        let controller = workspace.bonsplitController
        guard controller.configuration.allowSplits else { return .allowSplitsDisabled }
        guard controller.isInteractive else { return .noninteractive }
        guard controller.configuration.allowCrossPaneTabMove else { return .crossPaneTabMoveDisabled }
        if workspace.layoutMode == .canvas { return .canvasMode }
        if workspace.isRemoteTmuxMirror || workspace.remoteConfiguration != nil {
            return .remoteWorkspace
        }
        return nil
    }

    /// Whether the workspace already is a perfect `shape` grid with exactly
    /// one surface per pane (nothing hidden behind tabs).
    static func matchesShape(_ shape: GdockGridShape, workspace: Workspace) -> Bool {
        let controller = workspace.bonsplitController
        guard GdockGridSplitPlanner.matchesGrid(
            treeShape(controller.treeSnapshot()),
            shape: shape
        ) else {
            return false
        }
        return controller.allPaneIds.allSatisfy { controller.tabs(inPane: $0).count == 1 }
    }

    /// Applies `shape` to `workspace`. See the type doc for the recipe.
    static func applyShape(_ shape: GdockGridShape, to workspace: Workspace) -> Outcome {
        if let veto = preflight(workspace: workspace) {
            return .vetoed(veto)
        }
        if matchesShape(shape, workspace: workspace) {
            return .alreadyShaped
        }

        let panes = QuadSplitAction.orderedPaneSnapshots(workspace: workspace)
        let plan = GdockGridSplitPlanner.plan(
            panes: panes,
            focusedPaneId: workspace.bonsplitController.focusedPaneId?.id,
            shape: shape
        )
        guard let anchorPanelId = plan.cellPanelIds.first ?? nil else {
            return .vetoed(.emptyWorkspace)
        }

        workspace.isApplyingGdockGridShape = true
        defer { workspace.isApplyingGdockGridShape = false }
        workspace.clearSplitZoom()

        // Collapse every surface into the anchor pane so the deal-out below
        // starts from a single leaf regardless of the previous tree.
        for panelId in panes.flatMap(\.panelIds) where panelId != anchorPanelId {
            guard let anchorPane = workspace.paneId(forPanelId: anchorPanelId),
                  workspace.moveSurface(panelId: panelId, toPane: anchorPane, focus: false) else {
                return .lateFailure(step: "collapse")
            }
        }
        guard let anchorPane = workspace.paneId(forPanelId: anchorPanelId) else {
            return .lateFailure(step: "anchorUnresolved")
        }

        // Deal out rows-first: each row leads with its first cell's surface,
        // then the row is split into columns left to right.
        var rowLeadPanes: [PaneID] = [anchorPane]
        for row in 1..<shape.rows {
            let cellIndex = row * shape.cols
            guard let rowPane = realizeCell(
                plan.cellPanelIds[cellIndex],
                from: rowLeadPanes[row - 1],
                orientation: .vertical,
                workspace: workspace
            ) else {
                return .lateFailure(step: "row\(row)")
            }
            rowLeadPanes.append(rowPane)
        }
        for row in 0..<shape.rows {
            var previousPane = rowLeadPanes[row]
            for col in 1..<shape.cols {
                let cellIndex = row * shape.cols + col
                guard let cellPane = realizeCell(
                    plan.cellPanelIds[cellIndex],
                    from: previousPane,
                    orientation: .horizontal,
                    workspace: workspace
                ) else {
                    return .lateFailure(step: "cell\(row)x\(col)")
                }
                previousPane = cellPane
            }
        }

        _ = workspace.owningTabManager?.equalizeSplits(tabId: workspace.id)

        // Leave focus where the user was: the anchor cell's lead surface.
        if let finalAnchorPane = workspace.paneId(forPanelId: anchorPanelId) {
            workspace.bonsplitController.focusPane(finalAnchorPane)
        }
        workspace.focusPanel(anchorPanelId)
        workspace.scheduleTerminalGeometryReconcile()

        return .success(overflowPanelIds: plan.overflowPanelIds)
    }

    /// Splits `sourcePane` to create one cell: moves the planned surface in,
    /// or creates an unactivated placeholder terminal when the plan has none.
    private static func realizeCell(
        _ leadPanelId: UUID?,
        from sourcePane: PaneID,
        orientation: SplitOrientation,
        workspace: Workspace
    ) -> PaneID? {
        if let leadPanelId,
           let tabId = workspace.surfaceIdFromPanelId(leadPanelId) {
            return workspace.bonsplitController.splitPane(
                sourcePane,
                orientation: orientation,
                movingTab: tabId,
                insertFirst: false
            )
        }
        guard let panel = workspace.splitPaneWithNewTerminal(
            targetPane: sourcePane,
            orientation: orientation,
            insertFirst: false,
            workingDirectory: nil,
            initialInput: nil,
            runtimeSpawnPolicy: .heldForStartupRestoreAdmission
        ) else {
            return nil
        }
        workspace.gdockGridPlaceholderPanelIds.insert(panel.id)
        return workspace.paneId(forPanelId: panel.id)
    }

    /// Converts a live Bonsplit snapshot into the planner's structural mirror.
    static func treeShape(_ node: ExternalTreeNode) -> GdockGridSplitPlanner.TreeShape {
        switch node {
        case .pane:
            return .pane
        case .split(let split):
            // ExternalSplitNode.orientation is the raw string "horizontal"/"vertical".
            return .split(
                isVertical: split.orientation == "vertical",
                first: treeShape(split.first),
                second: treeShape(split.second)
            )
        }
    }
}

// MARK: - Placeholder activation

extension Workspace {
    /// Whether `panelId` is an unactivated Grid Mode cell.
    func isGdockGridPlaceholder(panelId: UUID) -> Bool {
        gdockGridPlaceholderPanelIds.contains(panelId)
    }

    /// Starts the held terminal runtime of a Grid Mode placeholder cell.
    ///
    /// Idempotent; no-ops for non-placeholder panels and while a shape apply
    /// is restructuring the tree (split creation focus churn must not
    /// activate the cells it just created).
    func activateGdockGridPlaceholderIfNeeded(panelId: UUID) {
        guard !isApplyingGdockGridShape,
              gdockGridPlaceholderPanelIds.contains(panelId),
              let terminalPanel = panels[panelId] as? TerminalPanel else {
            return
        }
        gdockGridPlaceholderPanelIds.remove(panelId)
        terminalPanel.surface.admitStartupRestoreRuntime()
        terminalPanel.surface.requestInputDemandSurfaceStartIfNeeded()
    }
}
