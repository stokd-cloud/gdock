import AppKit
import Bonsplit
import Foundation

/// Shared Auto Split mutation used by Cmd+Y, `palette.gdock.autoSplit`, and
/// the force-mode last split-tab-bar button.
///
/// `2×2` on a workspace delegates to ``QuadSplitAction`` so flatten/planner
/// behavior stays identical to Split Quad. Other shapes replace the focused
/// leaf with a nested `rows × columns` grid of new terminals, original
/// surface top-left, focus bottom-right. Dock is always leaf-local.
///
/// `1×1` is a no-op. Grid Mode workspaces veto so Auto Split does not fight
/// the grid enforcer. Known Quad Split vetoes are reused.
@MainActor
enum AutoSplitAction {
    enum Outcome: Equatable, Sendable {
        case success
        case noop
        case vetoed(QuadSplitAction.Veto)
        case gridMode
        case lateFailure
    }

    @discardableResult
    static func perform(
        inPane paneId: PaneID,
        workspace: Workspace,
        shape: GdockAutoSplitterSettings.Shape = GdockAutoSplitterSettings.shape()
    ) -> Bool {
        switch performDetailed(inPane: paneId, workspace: workspace, shape: shape) {
        case .success:
            return true
        case .noop, .vetoed, .gridMode, .lateFailure:
            return false
        }
    }

    static func performDetailed(
        inPane paneId: PaneID,
        workspace: Workspace,
        shape: GdockAutoSplitterSettings.Shape
    ) -> Outcome {
        if GdockGridModeSettings.isEnabled() {
            return .gridMode
        }
        if shape.isNoOp {
            return .noop
        }
        if let veto = QuadSplitAction.preflight(inPane: paneId, workspace: workspace) {
            return .vetoed(veto)
        }
        if shape.isQuad {
            switch QuadSplitAction.performDetailed(inPane: paneId, workspace: workspace) {
            case .success:
                return .success
            case .vetoed(let veto):
                return .vetoed(veto)
            case .lateFailure:
                return .lateFailure
            }
        }
        return performNestedGrid(inPane: paneId, workspace: workspace, shape: shape)
    }

    @discardableResult
    static func perform(
        inPane paneId: PaneID,
        dock: DockSplitStore,
        shape: GdockAutoSplitterSettings.Shape = GdockAutoSplitterSettings.shape()
    ) -> Bool {
        switch performDetailed(inPane: paneId, dock: dock, shape: shape) {
        case .success:
            return true
        case .noop, .vetoed, .gridMode, .lateFailure:
            return false
        }
    }

    static func performDetailed(
        inPane paneId: PaneID,
        dock: DockSplitStore,
        shape: GdockAutoSplitterSettings.Shape
    ) -> Outcome {
        if shape.isNoOp {
            return .noop
        }
        if let veto = QuadSplitAction.preflight(inPane: paneId, dock: dock) {
            return .vetoed(veto)
        }
        if shape.isQuad {
            switch QuadSplitAction.performDetailed(inPane: paneId, dock: dock) {
            case .success:
                return .success
            case .vetoed(let veto):
                return .vetoed(veto)
            case .lateFailure:
                return .lateFailure
            }
        }
        return performNestedGrid(inPane: paneId, dock: dock, shape: shape)
    }

    /// Overlay Auto Split presentation onto a split-button list when force is on.
    /// Keeps `cmux.splitQuad` ids so custom configs and remote-tmux filters stay stable.
    static func presentSplitButtons(
        _ buttons: [BonsplitConfiguration.SplitActionButton],
        forceEnabled: Bool = GdockAutoSplitterSettings.isForceEnabled(),
        shape: GdockAutoSplitterSettings.Shape = GdockAutoSplitterSettings.shape()
    ) -> [BonsplitConfiguration.SplitActionButton] {
        guard forceEnabled else { return buttons }
        return buttons.map { button in
            guard isSplitQuadButton(button) else { return button }
            return BonsplitConfiguration.SplitActionButton(
                id: button.id,
                systemImage: "square.grid.3x3",
                tooltip: GdockAutoSplitterSettings.autoSplitTooltip(shape: shape),
                action: button.action
            )
        }
    }

    static func isSplitQuadIdentifier(_ identifier: String) -> Bool {
        identifier == QuadSplitAction.customActionIdentifier
            || identifier == "splitQuad"
            || CmuxSurfaceTabBarBuiltInAction(configID: identifier) == .splitQuad
    }

    static func performForSplitQuadIdentifier(
        _ identifier: String,
        inPane paneId: PaneID,
        workspace: Workspace
    ) -> Bool {
        guard isSplitQuadIdentifier(identifier) else { return false }
        if GdockAutoSplitterSettings.isForceEnabled() {
            return perform(inPane: paneId, workspace: workspace)
        }
        return QuadSplitAction.perform(inPane: paneId, workspace: workspace)
    }

    static func performForSplitQuadIdentifier(
        _ identifier: String,
        inPane paneId: PaneID,
        dock: DockSplitStore
    ) -> Bool {
        guard isSplitQuadIdentifier(identifier) else { return false }
        if GdockAutoSplitterSettings.isForceEnabled() {
            return perform(inPane: paneId, dock: dock)
        }
        return QuadSplitAction.perform(inPane: paneId, dock: dock)
    }

    private static func isSplitQuadButton(_ button: BonsplitConfiguration.SplitActionButton) -> Bool {
        if isSplitQuadIdentifier(button.id) { return true }
        if case .custom(let id) = button.action, isSplitQuadIdentifier(id) {
            return true
        }
        return false
    }

    private static func performNestedGrid(
        inPane paneId: PaneID,
        workspace: Workspace,
        shape: GdockAutoSplitterSettings.Shape
    ) -> Outcome {
        workspace.clearSplitZoom()
        var columnPanes: [PaneID] = [paneId]
        var current = paneId
        for _ in 1..<shape.cols {
            guard workspace.splitPaneWithNewTerminal(
                targetPane: current,
                orientation: .horizontal,
                insertFirst: false,
                workingDirectory: nil,
                initialInput: nil
            ) != nil else {
                return .lateFailure
            }
            guard let newPane = workspace.bonsplitController.focusedPaneId, newPane != current else {
                return .lateFailure
            }
            columnPanes.append(newPane)
            current = newPane
        }

        var bottomRight = columnPanes[columnPanes.count - 1]
        for (index, columnPane) in columnPanes.enumerated() {
            var rowPane = columnPane
            for _ in 1..<shape.rows {
                guard workspace.splitPaneWithNewTerminal(
                    targetPane: rowPane,
                    orientation: .vertical,
                    insertFirst: false,
                    workingDirectory: nil,
                    initialInput: nil
                ) != nil else {
                    return .lateFailure
                }
                guard let newPane = workspace.bonsplitController.focusedPaneId, newPane != rowPane else {
                    return .lateFailure
                }
                rowPane = newPane
            }
            if index == columnPanes.count - 1 {
                bottomRight = rowPane
            }
        }
        workspace.bonsplitController.focusPane(bottomRight)
        return .success
    }

    private static func performNestedGrid(
        inPane paneId: PaneID,
        dock: DockSplitStore,
        shape: GdockAutoSplitterSettings.Shape
    ) -> Outcome {
        _ = dock.bonsplitController.clearPaneZoom()
        var columnPanes: [PaneID] = [paneId]
        var current = paneId
        for _ in 1..<shape.cols {
            guard let panelId = dock.newSplit(
                kind: .terminal,
                orientation: .horizontal,
                insertFirst: false,
                sourcePanelId: dock.selectedPanelId(inPane: current),
                focus: true
            ), let newPane = dock.paneId(forPanelId: panelId), newPane != current else {
                return .lateFailure
            }
            columnPanes.append(newPane)
            current = newPane
        }

        var bottomRight = columnPanes[columnPanes.count - 1]
        for (index, columnPane) in columnPanes.enumerated() {
            var rowPane = columnPane
            for _ in 1..<shape.rows {
                guard let panelId = dock.newSplit(
                    kind: .terminal,
                    orientation: .vertical,
                    insertFirst: false,
                    sourcePanelId: dock.selectedPanelId(inPane: rowPane),
                    focus: true
                ), let newPane = dock.paneId(forPanelId: panelId), newPane != rowPane else {
                    return .lateFailure
                }
                rowPane = newPane
            }
            if index == columnPanes.count - 1 {
                bottomRight = rowPane
            }
        }
        dock.bonsplitController.focusPane(bottomRight)
        return .success
    }
}

// MARK: - Dock selected panel helper

private extension DockSplitStore {
    func selectedPanelId(inPane pane: PaneID) -> UUID? {
        guard let tab = bonsplitController.selectedTab(inPane: pane) else { return nil }
        return surfaceIdToPanelId[tab.id]
    }
}
