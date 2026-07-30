import Bonsplit
import CmuxCanvas
import CmuxWorkspaces
import Foundation

/// Left workspace selector pane factory: singleton openOrFocus path so canvas
/// mode can host the real selector without the fixed left column.
extension Workspace {
    @discardableResult
    func newLeftWorkspaceSelectorSurface(
        inPane paneId: PaneID,
        focus: Bool? = nil,
        targetIndex: Int? = nil
    ) -> LeftWorkspaceSelectorPanel? {
        let shouldFocusNewTab = focus ?? (bonsplitController.focusedPaneId == paneId)
        let previousFocusedPanelId = focusedPanelId
        let previousHostedView = focusedTerminalPanel?.hostedView

        let selectorPanel = LeftWorkspaceSelectorPanel(workspace: self)
        panels[selectorPanel.id] = selectorPanel
        panelTitles[selectorPanel.id] = selectorPanel.displayTitle

        guard let newTabId = bonsplitController.createTab(
            title: selectorPanel.displayTitle,
            icon: selectorPanel.displayIcon,
            kind: SurfaceKind.leftWorkspaceSelector.rawValue,
            isDirty: false,
            isLoading: false,
            isPinned: false,
            inPane: paneId
        ) else {
            panels.removeValue(forKey: selectorPanel.id)
            panelTitles.removeValue(forKey: selectorPanel.id)
            return nil
        }

        bindSurface(newTabId, toPanelId: selectorPanel.id)
        if let targetIndex {
            _ = bonsplitController.reorderTab(newTabId, toIndex: targetIndex)
        }
        publishCmuxSurfaceCreated(
            selectorPanel.id,
            paneId: paneId,
            kind: SurfaceKind.leftWorkspaceSelector.rawValue,
            origin: "left_workspace_selector_tab",
            focused: shouldFocusNewTab
        )

        if shouldFocusNewTab {
            focusPanel(selectorPanel.id)
        } else {
            preserveFocusAfterNonFocusSplit(
                preferredPanelId: previousFocusedPanelId,
                splitPanelId: selectorPanel.id,
                previousHostedView: previousHostedView
            )
        }

        return selectorPanel
    }

    func existingLeftWorkspaceSelectorPanel() -> LeftWorkspaceSelectorPanel? {
        for panel in panels.values {
            if let selector = panel as? LeftWorkspaceSelectorPanel {
                return selector
            }
        }
        return nil
    }

    var focusedPanelIsLeftWorkspaceSelector: Bool {
        guard let focusedPanelId,
              panels[focusedPanelId] is LeftWorkspaceSelectorPanel else {
            return false
        }
        return true
    }

    /// One left selector pane per workspace: focuses existing or creates in `paneId`.
    @discardableResult
    func openOrFocusLeftWorkspaceSelectorSurface(
        inPane paneId: PaneID,
        focus: Bool = true
    ) -> LeftWorkspaceSelectorPanel? {
        if let existing = existingLeftWorkspaceSelectorPanel() {
            if focus {
                focusPanel(existing.id)
            }
            return existing
        }
        return newLeftWorkspaceSelectorSurface(inPane: paneId, focus: focus)
    }

    /// Shared show path: focus singleton pane or create. Canvas free-floats a
    /// new pane; splits mode opens a tab in the focused bonsplit pane. Fixed
    /// left chrome is not required.
    @discardableResult
    func showOrFocusLeftWorkspaceSelectorPane(focus: Bool = true) -> LeftWorkspaceSelectorPanel? {
        if let existing = existingLeftWorkspaceSelectorPanel() {
            if focus {
                focusPanel(existing.id)
                if layoutMode == .canvas {
                    canvasModel.viewport?.revealPane(existing.id, animated: true)
                }
            }
            return existing
        }

        guard let paneId = bonsplitController.focusedPaneId ?? bonsplitController.allPaneIds.first else {
            return nil
        }

        if layoutMode == .canvas {
            let anchorPanelId = focusedPanelId
            let preferredSize: CanvasSize? = anchorPanelId
                .flatMap { canvasModel.frame(of: $0) }
                .map { CanvasSize(width: Double($0.width), height: Double($0.height)) }
            guard let panel = newLeftWorkspaceSelectorSurface(inPane: paneId, focus: focus) else {
                return nil
            }
            canvasModel.syncPanes(
                panelIds: orderedPanelIds,
                focusedPanelId: anchorPanelId,
                preferredDirection: nil,
                preferredNewPaneSize: preferredSize
            )
            if focus {
                focusPanel(panel.id)
                canvasModel.viewport?.modelDidChangeExternally(animated: false)
                canvasModel.viewport?.revealPane(panel.id, animated: true)
            }
            return panel
        }

        return openOrFocusLeftWorkspaceSelectorSurface(inPane: paneId, focus: focus)
    }
}
