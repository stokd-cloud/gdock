import Foundation
import AppKit
import Bonsplit
import CmuxCanvas
import CmuxCanvasUI
import CmuxDockable
import CmuxWorkspaces

extension Notification.Name {
    /// Posted (object = the `Workspace`) whenever its `layoutMode` changes,
    /// so window chrome can reflect canvas vs splits without observing the
    /// workspace directly.
    static let workspaceLayoutModeDidChange = Notification.Name("cmux.workspaceLayoutModeDidChange")
}

/// Canvas-layout behavior for `Workspace`. The workspace stays the owner of
/// panels, focus, and bonsplit bookkeeping; canvas mode only changes how the
/// same panel set is presented.
extension Workspace {
    /// Switches the workspace between split and canvas layout.
    ///
    /// Entering canvas mode seeds pane frames from the current bonsplit
    /// geometry so the canvas initially looks identical to the splits. The
    /// split tree itself is left untouched, so switching back restores it.
    func setLayoutMode(_ mode: WorkspaceLayoutMode) {
        guard mode != layoutMode else { return }
        if mode == .canvas {
            canvasModel.seedFromSplitFrames(splitPaneFramesByPanelId())
        }
        layoutMode = mode
        // The rendered-panel set changes shape with the mode (canvas hosts each
        // pane's selected terminal directly in the pane hierarchy; splits host
        // every selected tab through the window portal), so re-derive portal
        // visibility immediately instead of waiting for the next layout event.
        //
        // Entering canvas: clear the terminal portal layer now. Otherwise the
        // split-mode terminal surfaces keep floating at their old split frames
        // (over the canvas) during the async SwiftUI mount, and stay there
        // until some later layout event happens to reconcile them — the ghost
        // terminal artifacts Aziz reported on toggle. The canvas mount re-shows
        // each visible pane's selected terminal via its portal-detach path.
        // Leaving canvas: reconcile to the split-mode rendered set so the
        // re-attached terminals show at the correct split frames.
        if mode == .canvas {
            hideAllTerminalPortalViews()
        } else {
            reconcileTerminalPortalVisibilityForCurrentRenderedLayout()
        }
        reconcileBrowserPortalVisibilityForCurrentRenderedLayout(
            reason: "workspace.setLayoutMode.\(mode.rawValue)"
        )
        // Let chrome (the toolbar mode toggle) reflect the change regardless
        // of which entrypoint drove it (shortcut, palette, menu, toolbar).
        NotificationCenter.default.post(name: .workspaceLayoutModeDidChange, object: self)
    }

    /// Toggles between split and canvas layout.
    func toggleCanvasLayout() {
        setLayoutMode(layoutMode == .canvas ? .splits : .canvas)
    }

    /// Canvas-mode directional focus: nearest pane spatially, then reveal it.
    func moveCanvasFocus(direction: NavigationDirection) {
        guard let from = focusedPanelId ?? orderedPanelIds.first else { return }
        guard let target = canvasModel.pane(direction.canvasDirection, from: from) else { return }
        focusPanel(target)
        canvasModel.viewport?.revealPane(target, animated: true)
    }

    /// The bonsplit pane currently containing the panel's tab, used by
    /// canvas panes that host split-mode SwiftUI panel views.
    func bonsplitPaneId(forPanelId panelId: UUID) -> PaneID? {
        guard let tabId = surfaceIdFromPanelId(panelId) else { return nil }
        for paneId in bonsplitController.allPaneIds {
            if bonsplitController.tabs(inPane: paneId).contains(where: { $0.id == tabId }) {
                return paneId
            }
        }
        return nil
    }

    /// Called by the canvas after a user gesture commits a frame change.
    func noteCanvasLayoutChanged() {
        // Session persistence snapshots read `canvasModel` directly; nothing
        // else needs to react to pure geometry changes today.
    }

    // MARK: - Session persistence

    /// Canvas panes (frames, tabs, selection) in z-order for the session
    /// snapshot; `nil` when the workspace has never entered canvas mode.
    func canvasSessionPaneSnapshots() -> [SessionCanvasPaneSnapshot]? {
        let snapshots: [SessionCanvasPaneSnapshot] = canvasModel.persistablePanes.map { pane in
            SessionCanvasPaneSnapshot(
                panelId: pane.paneId,
                x: pane.frame.origin.x,
                y: pane.frame.origin.y,
                width: pane.frame.width,
                height: pane.frame.height,
                panelIds: pane.panelIds,
                selectedPanelId: pane.selectedPanelId
            )
        }
        return snapshots.isEmpty ? nil : snapshots
    }

    /// Restores canvas panes (remapped onto the freshly minted panel ids)
    /// and the layout mode. Setting `layoutMode` directly skips the
    /// seed-from-splits path, which would overwrite the restored frames.
    func restoreCanvasState(
        from snapshot: SessionWorkspaceSnapshot,
        oldToNewPanelIds: [UUID: UUID]
    ) {
        if let canvasPanes = snapshot.canvasPanes {
            let restored: [CanvasModel.PersistablePane] = canvasPanes.compactMap { pane in
                // Pre-tab snapshots stored a single panel in `panelId`.
                let oldPanelIds = pane.panelIds ?? [pane.panelId]
                let newPanelIds = oldPanelIds.compactMap { oldId -> UUID? in
                    guard let newId = oldToNewPanelIds[oldId], panels[newId] != nil else { return nil }
                    return newId
                }
                guard !newPanelIds.isEmpty else { return nil }
                let oldSelected = pane.selectedPanelId ?? pane.panelId
                let newSelected = oldToNewPanelIds[oldSelected].flatMap { newPanelIds.contains($0) ? $0 : nil }
                return CanvasModel.PersistablePane(
                    // Pane identity follows its first surviving panel so it
                    // stays stable across the id remap.
                    paneId: newPanelIds[0],
                    frame: CGRect(x: pane.x, y: pane.y, width: pane.width, height: pane.height),
                    panelIds: newPanelIds,
                    selectedPanelId: newSelected ?? newPanelIds[0]
                )
            }
            canvasModel.restorePanes(restored)
        }
        if snapshot.layoutMode == WorkspaceLayoutMode.canvas.rawValue {
            layoutMode = .canvas
        }
    }

    /// Current split-layout frames per panel, used to seed canvas frames so
    /// entering canvas mode preserves what the user sees. Only the selected
    /// tab of each split pane has on-screen geometry; the rest are placed by
    /// the canvas placer afterwards.
    private func splitPaneFramesByPanelId() -> [UUID: CGRect] {
        let snapshot = bonsplitController.layoutSnapshot()
        var frames: [UUID: CGRect] = [:]
        for pane in snapshot.panes {
            guard let selectedTabId = pane.selectedTabId,
                  let tabUUID = UUID(uuidString: selectedTabId),
                  let panelId = panelIdFromSurfaceId(TabID(uuid: tabUUID)) else {
                continue
            }
            frames[panelId] = CGRect(
                x: pane.frame.x - snapshot.containerFrame.x,
                y: pane.frame.y - snapshot.containerFrame.y,
                width: pane.frame.width,
                height: pane.frame.height
            )
        }
        return frames
    }
}

extension NavigationDirection {
    /// Maps bonsplit's split-navigation direction onto the canvas model's.
    var canvasDirection: CanvasDirection {
        switch self {
        case .left: return .left
        case .right: return .right
        case .up: return .up
        case .down: return .down
        }
    }
}

extension Workspace {
    /// Cycles canvas surfaces by `offset` (wrapping). In canvas mode, surface
    /// shortcuts address the whole floating workspace surface order, because
    /// separate panes do not share one focused Bonsplit tab strip.
    func selectAdjacentCanvasTab(offset: Int) -> Bool {
        let surfaceIds = selectableCanvasSurfaceIds()
        guard surfaceIds.count > 1,
              let focusedPanelId,
              let index = surfaceIds.firstIndex(of: focusedPanelId) else {
            return false
        }
        let next = surfaceIds[(index + offset + surfaceIds.count) % surfaceIds.count]
        focusPanel(next)
        canvasModel.viewport?.modelDidChangeExternally(animated: false)
        canvasModel.viewport?.revealPane(next, animated: true)
        return true
    }

    /// Selects a canvas surface by zero-based workspace surface order.
    func selectCanvasTab(at index: Int) -> Bool {
        let surfaceIds = selectableCanvasSurfaceIds()
        guard surfaceIds.indices.contains(index) else { return false }
        let selected = surfaceIds[index]
        focusPanel(selected)
        canvasModel.viewport?.modelDidChangeExternally(animated: false)
        canvasModel.viewport?.revealPane(selected, animated: true)
        return true
    }

    /// Selects the last canvas surface in workspace surface order.
    func selectLastCanvasTab() -> Bool {
        guard let selected = selectableCanvasSurfaceIds().last else { return false }
        focusPanel(selected)
        canvasModel.viewport?.modelDidChangeExternally(animated: false)
        canvasModel.viewport?.revealPane(selected, animated: true)
        return true
    }

    private func selectableCanvasSurfaceIds() -> [UUID] {
        let canvasPanelIds = Set(canvasModel.layout.allPanelIds.map(\.rawValue))
        return orderedPanelIds.filter { canvasPanelIds.contains($0) && panels[$0] != nil }
    }
}

extension Workspace {
    /// Creates a new surface as its own free-floating canvas pane (not joined
    /// as a tab of an existing pane), the automation counterpart to the
    /// canvas "new pane" gesture. Returns the new surface/panel UUID, or `nil`
    /// when creation fails (e.g. no focused bonsplit pane, unregistered kind,
    /// missing create context, or browser disabled). Must be called in canvas mode.
    ///
    /// Creation goes through the dockable registry/bootstrap for non-terminal
    /// kinds and through the full workspace surface creators for terminal and
    /// browser so spawn/config subscriptions stay intact.
    @discardableResult
    func openNewCanvasPane(
        kind: DockableKind,
        focus: Bool = true,
        direction: CanvasDirection? = nil
    ) -> UUID? {
        guard layoutMode == .canvas else { return nil }
        guard let focusedPaneId = bonsplitController.focusedPaneId else { return nil }
        let anchorPanelId = focusedPanelId
        let preferredSize: CanvasSize? = anchorPanelId
            .flatMap { canvasModel.frame(of: $0) }
            .map { CanvasSize(width: Double($0.width), height: Double($0.height)) }

        guard let newPanelId = createCanvasDockablePanel(
            kind: kind,
            inPane: focusedPaneId,
            focus: focus
        ) else {
            return nil
        }

        // Give the new surface its own canvas pane (the placer positions it
        // near the focused pane) rather than joining it as a tab.
        canvasModel.syncPanes(
            panelIds: orderedPanelIds,
            focusedPanelId: anchorPanelId,
            preferredDirection: direction,
            preferredNewPaneSize: preferredSize
        )
        focusPanel(newPanelId)
        canvasModel.viewport?.modelDidChangeExternally(animated: false)
        canvasModel.viewport?.revealPane(newPanelId, animated: true)
        return newPanelId
    }

    /// Creates a panel of `kind` in `paneId` via registry-backed factories and
    /// existing surface installers. Returns `nil` for unregistered/fail-closed
    /// kinds without crashing.
    private func createCanvasDockablePanel(
        kind: DockableKind,
        inPane paneId: PaneID,
        focus: Bool
    ) -> UUID? {
        DockableBootstrap.registerAllIfNeeded()

        switch kind {
        case .terminal:
            return newTerminalSurface(inPane: paneId, focus: focus)?.id
        case .browser:
            return newBrowserSurface(inPane: paneId, focus: focus)?.id
        case .markdown:
            let filePath = defaultCanvasScratchMarkdownPath()
            return newMarkdownSurface(inPane: paneId, filePath: filePath, focus: focus)?.id
        case .filePreview:
            let filePath = defaultCanvasScratchMarkdownPath()
            return newFilePreviewSurface(inPane: paneId, filePath: filePath, focus: focus)?.id
        case .project:
            let projectPath = currentDirectory.isEmpty
                ? FileManager.default.temporaryDirectory.path
                : currentDirectory
            return newProjectSurface(inPane: paneId, projectPath: projectPath, focus: focus)?.id
        case .agentSession:
            return newAgentSessionSurface(
                inPane: paneId,
                rendererKind: .react,
                focus: focus
            )?.id
        case .rightSidebarTool:
            return newRightSidebarToolSurface(inPane: paneId, mode: .files, focus: focus)?.id
        case .extensionBrowser:
            return newSidebarExtensionBrowserSurface(
                inPane: paneId,
                title: String(
                    localized: "sidebar.extensions.browser.title",
                    defaultValue: "Sidebar Extensions"
                ),
                focus: focus
            )?.id
        case .workspaceTodo, .customSidebar, .cloudVMLoading:
            // Registry make + generic install for context-heavy / content-less kinds.
            return installRegistryDockable(kind: kind, inPane: paneId, focus: focus)
        }
    }

    /// Registry-backed create + bonsplit install for kinds without a dedicated
    /// `new*Surface` convenience used by canvas open.
    private func installRegistryDockable(
        kind: DockableKind,
        inPane paneId: PaneID,
        focus: Bool
    ) -> UUID? {
        var context = DockableCreateContext(workspaceId: id)
        context.workingDirectory = currentDirectory.isEmpty ? nil : currentDirectory
        context.filePath = defaultCanvasScratchMarkdownPath()
        context.projectPath = currentDirectory.isEmpty
            ? FileManager.default.temporaryDirectory.path
            : currentDirectory
        context.rightSidebarMode = .files
        if kind == .customSidebar {
            let sidebarURL = FileManager.default.temporaryDirectory
                .appendingPathComponent("canvas-\(UUID().uuidString.prefix(8)).cmuxsidebar")
            try? "".write(to: sidebarURL, atomically: true, encoding: .utf8)
            context.customSidebarName = "Canvas"
            context.customSidebarFileURL = sidebarURL
        }

        guard let dockable = DockableBootstrap.make(
            kind: kind,
            context: context,
            workspace: self
        ), let panel = dockable as? any Panel else {
            return nil
        }

        let shouldFocusNewTab = focus
        let previousFocusedPanelId = focusedPanelId
        let previousHostedView = focusedTerminalPanel?.hostedView

        panels[panel.id] = panel
        panelTitles[panel.id] = panel.displayTitle

        let surfaceKindRaw = Self.surfaceKindRawValue(for: kind)
        guard let newTabId = bonsplitController.createTab(
            title: panel.displayTitle,
            icon: panel.displayIcon,
            kind: surfaceKindRaw,
            isDirty: panel.isDirty,
            isLoading: false,
            isPinned: false,
            inPane: paneId
        ) else {
            panels.removeValue(forKey: panel.id)
            panelTitles.removeValue(forKey: panel.id)
            return nil
        }

        bindSurface(newTabId, toPanelId: panel.id)
        publishCmuxSurfaceCreated(
            panel.id,
            paneId: paneId,
            kind: Self.cmuxEventSurfaceKind(panel),
            origin: "canvas_new_pane",
            focused: shouldFocusNewTab
        )

        if shouldFocusNewTab {
            bonsplitController.focusPane(paneId)
            bonsplitController.selectTab(newTabId)
            applyTabSelection(tabId: newTabId, inPane: paneId)
        } else {
            preserveFocusAfterNonFocusSplit(
                preferredPanelId: previousFocusedPanelId,
                splitPanelId: panel.id,
                previousHostedView: previousHostedView
            )
        }
        return panel.id
    }

    /// Scratch markdown path for canvas open when no file is supplied.
    private func defaultCanvasScratchMarkdownPath() -> String {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("cmux-canvas-\(UUID().uuidString.prefix(8)).md")
        if !FileManager.default.fileExists(atPath: url.path) {
            try? "# Untitled\n".write(to: url, atomically: true, encoding: .utf8)
        }
        return url.path
    }

    /// Maps ``DockableKind`` onto bonsplit ``SurfaceKind`` wire values.
    private static func surfaceKindRawValue(for kind: DockableKind) -> String {
        switch kind {
        case .terminal: return SurfaceKind.terminal.rawValue
        case .browser: return SurfaceKind.browser.rawValue
        case .markdown: return SurfaceKind.markdown.rawValue
        case .filePreview: return SurfaceKind.filePreview.rawValue
        case .rightSidebarTool: return SurfaceKind.rightSidebarTool.rawValue
        case .customSidebar: return SurfaceKind.customSidebar.rawValue
        case .agentSession: return SurfaceKind.agentSession.rawValue
        case .project: return SurfaceKind.project.rawValue
        case .extensionBrowser: return SurfaceKind.extensionBrowser.rawValue
        case .workspaceTodo: return SurfaceKind.todo.rawValue
        case .cloudVMLoading: return SurfaceKind.cloudVMLoading.rawValue
        }
    }

    /// Makes a freshly created panel a tab of the canvas pane hosting
    /// `anchor` (the Cmd+T-in-canvas semantics). Ensures the panel exists in
    /// the canvas model first, since panel creation can run before the next
    /// descriptor sync.
    func joinNewPanelIntoCanvasPane(_ panelId: UUID, anchor: UUID) {
        guard layoutMode == .canvas else { return }
        canvasModel.syncPanes(
            panelIds: orderedPanelIds,
            focusedPanelId: anchor
        )
        canvasModel.joinPanel(panelId, withPaneContaining: anchor)
        focusPanel(panelId)
        canvasModel.viewport?.modelDidChangeExternally(animated: false)
    }
}


extension Workspace {
    /// Mirrors canvas pane z-order onto portal-hosted browser webviews so a
    /// front pane's webview stacks above a back pane's.
    func syncCanvasBrowserPortalZOrder() {
        guard layoutMode == .canvas else { return }
        let zOrder = canvasModel.layout.paneIDs
        for panel in panels.values {
            guard let browserPanel = panel as? BrowserPanel,
                  !browserPanel.canvasInlineHostingActive,
                  let paneID = canvasModel.paneID(containing: browserPanel.id),
                  let z = zOrder.firstIndex(of: paneID) else { continue }
            BrowserWindowPortalRegistry.updateEntryVisibility(
                for: browserPanel.webView,
                visibleInUI: true,
                zPriority: 2 + z
            )
        }
    }
}
