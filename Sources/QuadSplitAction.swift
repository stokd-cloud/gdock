import AppKit
import Bonsplit
import Foundation

/// Shared terminal Quad Split mutation used by every approved entrypoint.
///
/// Recipe for target leaf `L`: replace `L` with `H(V(L,A), V(R,B))` — a root
/// side-by-side split whose children are stacked pairs — then focus `B`
/// (bottom-right). Exactly three local terminal splits (workspace API) or three
/// Dock terminal splits; no outer programmatic-split guard (each split call
/// owns its own).
///
/// Known vetoes are preflighted without calling a side-effecting remote
/// delegate (D-20 / D-25). An unexpected second/third split failure is logged
/// as a late partial failure rather than rolled back.
@MainActor
enum QuadSplitAction {
    /// Stable custom-action id exposed through bonsplit `.custom(...)` (D-5).
    static let customActionIdentifier = CmuxSurfaceTabBarBuiltInAction.splitQuad.configID

    /// Known veto catalog — preflighted before any local mutation.
    enum Veto: String, Equatable, Sendable, CaseIterable {
        case missingTarget
        case invalidTarget
        case allowSplitsDisabled
        case noninteractive
        case transientFocusSuppressed
        case canvasMode
        case remoteMirror
        case remoteConnecting
        case remoteDisconnected
        case remoteUnresolved
        case remoteUnsupportedDirection
        case emptyDockSource
        case invalidDockSource
        case delegateRestriction
    }

    enum Outcome: Equatable, Sendable {
        case success
        case vetoed(Veto)
        /// Unexpected inconsistency after one or more splits already applied.
        case lateFailure(completedSplits: Int)
    }

    // MARK: - Test / injection seams (DEBUG-only; inert in Release)

    /// When set to `1` or `2`, the workspace/Dock recipe returns
    /// `.lateFailure(completedSplits:)` after that many successful splits and
    /// does not attempt rollback. DEBUG unit tests + `debug.quad.*` dogfood only
    /// (VAL-QUAD-004). Absent/inert in Release builds.
    static var testingFailAfterCompletedSplits: Int? {
        get {
            #if DEBUG
            _testingFailAfterCompletedSplits
            #else
            nil
            #endif
        }
        set {
            #if DEBUG
            _testingFailAfterCompletedSplits = newValue
            #else
            _ = newValue
            #endif
        }
    }

    #if DEBUG
    private static var _testingFailAfterCompletedSplits: Int?
    #endif

    /// Forces the transient-focus veto without needing a live key-window probe.
    static var testingForceTransientFocusSuppressed: Bool {
        get {
            #if DEBUG
            _testingForceTransientFocusSuppressed
            #else
            false
            #endif
        }
        set {
            #if DEBUG
            _testingForceTransientFocusSuppressed = newValue
            #else
            _ = newValue
            #endif
        }
    }

    #if DEBUG
    private static var _testingForceTransientFocusSuppressed = false
    #endif

    /// When true, skip the live geometry/key-window transient-focus probe.
    /// DEBUG dogfood (`debug.quad.perform`) sets this so socket/explicit-surface
    /// runs are not spuriously vetoed by zero-size harness hosting views. The
    /// force flag above still injects the veto for catalog tests.
    static var testingSkipLiveTransientFocusProbe: Bool {
        get {
            #if DEBUG
            _testingSkipLiveTransientFocusProbe
            #else
            false
            #endif
        }
        set {
            #if DEBUG
            _testingSkipLiveTransientFocusProbe = newValue
            #else
            _ = newValue
            #endif
        }
    }

    #if DEBUG
    private static var _testingSkipLiveTransientFocusProbe = false
    #endif

    /// Forces the pure delegate-restriction veto (in addition to live detection).
    static var testingForceDelegateRestriction: Bool {
        get {
            #if DEBUG
            _testingForceDelegateRestriction
            #else
            false
            #endif
        }
        set {
            #if DEBUG
            _testingForceDelegateRestriction = newValue
            #else
            _ = newValue
            #endif
        }
    }

    #if DEBUG
    private static var _testingForceDelegateRestriction = false
    #endif

    /// Append-only remote command log probe. Preflight/perform never write here;
    /// tests assert it stays unchanged across known vetoes (no side-effecting
    /// remote split delegate). Always empty/inert outside DEBUG.
    static var testingRemoteCommandLog: [String] {
        get {
            #if DEBUG
            _testingRemoteCommandLog
            #else
            []
            #endif
        }
        set {
            #if DEBUG
            _testingRemoteCommandLog = newValue
            #else
            _ = newValue
            #endif
        }
    }

    #if DEBUG
    private static var _testingRemoteCommandLog: [String] = []
    #endif

    /// Captured late-failure log events (`quad.lateFailure …`).
    static var testingLateFailureEvents: [String] {
        get {
            #if DEBUG
            _testingLateFailureEvents
            #else
            []
            #endif
        }
        set {
            #if DEBUG
            _testingLateFailureEvents = newValue
            #else
            _ = newValue
            #endif
        }
    }

    #if DEBUG
    private static var _testingLateFailureEvents: [String] = []
    #endif

    static func resetTestingHooks() {
        #if DEBUG
        _testingFailAfterCompletedSplits = nil
        _testingForceTransientFocusSuppressed = false
        _testingSkipLiveTransientFocusProbe = false
        _testingForceDelegateRestriction = false
        _testingRemoteCommandLog = []
        _testingLateFailureEvents = []
        #endif
    }

    // MARK: - Workspace

    /// Performs a quad split on a workspace pane. Returns `true` only on full success.
    @discardableResult
    static func perform(inPane paneId: PaneID, workspace: Workspace) -> Bool {
        switch performDetailed(inPane: paneId, workspace: workspace) {
        case .success:
            return true
        case .vetoed, .lateFailure:
            return false
        }
    }

    static func performDetailed(inPane paneId: PaneID, workspace: Workspace) -> Outcome {
        if let veto = preflight(inPane: paneId, workspace: workspace) {
            return .vetoed(veto)
        }

        workspace.clearSplitZoom()

        // 1. side-by-side: left (L) | right (R)
        guard workspace.splitPaneWithNewTerminal(
            targetPane: paneId,
            orientation: .horizontal,
            insertFirst: false,
            workingDirectory: nil,
            initialInput: nil
        ) != nil else {
            return .lateFailure(completedSplits: 0)
        }
        if shouldInjectLateFailure(afterCompletedSplits: 1) {
            logLateFailure(surface: "workspace", completedSplits: 1, detail: "injected failure after step 1")
            return .lateFailure(completedSplits: 1)
        }
        guard let rightPaneId = workspace.bonsplitController.focusedPaneId,
              rightPaneId != paneId else {
            logLateFailure(surface: "workspace", completedSplits: 1, detail: "rightPane unresolved after horizontal split")
            return .lateFailure(completedSplits: 1)
        }

        // 2. stack the left column: top (L) / bottom (A)
        guard workspace.splitPaneWithNewTerminal(
            targetPane: paneId,
            orientation: .vertical,
            insertFirst: false,
            workingDirectory: nil,
            initialInput: nil
        ) != nil else {
            logLateFailure(surface: "workspace", completedSplits: 1, detail: "left vertical split failed")
            return .lateFailure(completedSplits: 1)
        }
        if shouldInjectLateFailure(afterCompletedSplits: 2) {
            logLateFailure(surface: "workspace", completedSplits: 2, detail: "injected failure after step 2")
            return .lateFailure(completedSplits: 2)
        }

        // 3. stack the right column: top (R) / bottom (B) — focus ends on B
        guard workspace.splitPaneWithNewTerminal(
            targetPane: rightPaneId,
            orientation: .vertical,
            insertFirst: false,
            workingDirectory: nil,
            initialInput: nil
        ) != nil else {
            logLateFailure(surface: "workspace", completedSplits: 2, detail: "right vertical split failed")
            return .lateFailure(completedSplits: 2)
        }

        return .success
    }

    /// Lossless preflight for a workspace target. Never invokes the remote
    /// tmux mirror split delegate (side-effecting).
    static func preflight(inPane paneId: PaneID, workspace: Workspace) -> Veto? {
        let controller = workspace.bonsplitController
        guard controller.configuration.allowSplits else {
            return .allowSplitsDisabled
        }
        guard controller.isInteractive else {
            return .noninteractive
        }
        guard controller.allPaneIds.contains(where: { $0 == paneId }) else {
            return .missingTarget
        }
        // Pane exists but is not a valid split source (no tabs / unmapped panel).
        let tabs = controller.tabs(inPane: paneId)
        guard let sourceTab = controller.selectedTab(inPane: paneId) ?? tabs.first else {
            return .invalidTarget
        }
        guard workspace.panelIdFromSurfaceId(sourceTab.id) != nil else {
            return .invalidTarget
        }
        if workspace.layoutMode == .canvas {
            return .canvasMode
        }
        if testingForceTransientFocusSuppressed {
            return .transientFocusSuppressed
        }
        if !testingSkipLiveTransientFocusProbe,
           isTransientFocusSuppressed(workspace: workspace, paneId: paneId) {
            return .transientFocusSuppressed
        }
        if testingForceDelegateRestriction
            || workspace.remoteTmuxMirrorMutations.suppressesFocusActivation {
            // Pure equivalent of a known delegate restriction (focus-neutral
            // remote-tmux mutation transaction) without calling shouldSplitPane.
            return .delegateRestriction
        }
        // Remote / mirror catalog — inspect local state only; do not call the
        // side-effecting remote split delegate used by shouldSplitPane.
        if workspace.isRemoteTmuxMirror {
            return .remoteMirror
        }
        switch workspace.remoteConnectionState {
        case .connecting, .reconnecting, .suspended:
            return .remoteConnecting
        case .disconnected, .error:
            // Only veto when a remote configuration is present; a pure local
            // workspace is normally `.disconnected` and must still split.
            if workspace.remoteConfiguration != nil {
                return .remoteDisconnected
            }
        case .connected:
            break
        }
        // Unresolved remote PTY surfaces that still live in a local tree.
        if let panelId = workspace.panelIdFromSurfaceId(sourceTab.id),
           workspace.isRemoteTerminalSurface(panelId) {
            return .remoteUnresolved
        }
        // Connected remote workspace: "quad" is not a supported remote direction
        // / option set (left|right|up|down only). Detected without calling the
        // side-effecting remote split delegate.
        if workspace.remoteConfiguration != nil,
           workspace.remoteConnectionState == .connected {
            return .remoteUnsupportedDirection
        }
        return nil
    }

    // MARK: - Dock

    /// Performs a quad split inside a Dock controller. Returns `true` only on full success.
    @discardableResult
    static func perform(inPane paneId: PaneID, dock: DockSplitStore) -> Bool {
        switch performDetailed(inPane: paneId, dock: dock) {
        case .success:
            return true
        case .vetoed, .lateFailure:
            return false
        }
    }

    static func performDetailed(inPane paneId: PaneID, dock: DockSplitStore) -> Outcome {
        if let veto = preflight(inPane: paneId, dock: dock) {
            return .vetoed(veto)
        }

        _ = dock.bonsplitController.clearPaneZoom()

        // 1. side-by-side
        guard let rightPanelId = dock.newSplit(
            kind: .terminal,
            orientation: .horizontal,
            insertFirst: false,
            sourcePanelId: dock.selectedPanelId(inPane: paneId),
            focus: true
        ) else {
            return .lateFailure(completedSplits: 0)
        }
        if shouldInjectLateFailure(afterCompletedSplits: 1) {
            logLateFailure(surface: "dock", completedSplits: 1, detail: "injected failure after step 1")
            return .lateFailure(completedSplits: 1)
        }
        guard let rightPaneId = dock.paneId(forPanelId: rightPanelId),
              rightPaneId != paneId else {
            logLateFailure(surface: "dock", completedSplits: 1, detail: "rightPane unresolved after horizontal split")
            return .lateFailure(completedSplits: 1)
        }

        // 2. stack left column
        guard dock.newSplit(
            kind: .terminal,
            orientation: .vertical,
            insertFirst: false,
            sourcePanelId: dock.selectedPanelId(inPane: paneId),
            focus: true
        ) != nil else {
            logLateFailure(surface: "dock", completedSplits: 1, detail: "left vertical split failed")
            return .lateFailure(completedSplits: 1)
        }
        if shouldInjectLateFailure(afterCompletedSplits: 2) {
            logLateFailure(surface: "dock", completedSplits: 2, detail: "injected failure after step 2")
            return .lateFailure(completedSplits: 2)
        }

        // 3. stack right column — ends focused on B
        guard dock.newSplit(
            kind: .terminal,
            orientation: .vertical,
            insertFirst: false,
            sourcePanelId: dock.selectedPanelId(inPane: rightPaneId),
            focus: true
        ) != nil else {
            logLateFailure(surface: "dock", completedSplits: 2, detail: "right vertical split failed")
            return .lateFailure(completedSplits: 2)
        }

        return .success
    }

    static func preflight(inPane paneId: PaneID?, dock: DockSplitStore) -> Veto? {
        let controller = dock.bonsplitController
        guard controller.configuration.allowSplits else {
            return .allowSplitsDisabled
        }
        guard controller.isInteractive else {
            return .noninteractive
        }
        let panes = controller.allPaneIds
        guard !panes.isEmpty else {
            return .emptyDockSource
        }
        guard let paneId else {
            return .invalidDockSource
        }
        guard panes.contains(where: { $0 == paneId }) else {
            return .invalidDockSource
        }
        // Empty Dock source: pane exists but has no tab/panel to split from
        // (Dock seeds an empty root until a surface is created).
        let tabs = controller.tabs(inPane: paneId)
        guard !tabs.isEmpty else {
            return .emptyDockSource
        }
        let sourceTab = controller.selectedTab(inPane: paneId) ?? tabs.first
        guard let sourceTab, dock.panel(for: sourceTab.id) != nil else {
            return .invalidDockSource
        }
        if testingForceTransientFocusSuppressed {
            return .transientFocusSuppressed
        }
        if testingForceDelegateRestriction {
            return .delegateRestriction
        }
        return nil
    }

    static func preflight(inPane paneId: PaneID, dock: DockSplitStore) -> Veto? {
        preflight(inPane: Optional(paneId), dock: dock)
    }

    // MARK: - Helpers

    /// True when `direction` is the accepted quad token (not a compass direction).
    /// Nonisolated so CLI/socket token checks can run off the main actor.
    nonisolated static func isQuadDirectionToken(_ raw: String) -> Bool {
        switch raw.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() {
        case "quad", "q":
            return true
        default:
            return false
        }
    }

    /// Default/fallback surface-tab-bar button list ending with Split Quad.
    static var defaultSplitActionButtons: [BonsplitConfiguration.SplitActionButton] {
        var buttons = BonsplitConfiguration.SplitActionButton.defaults
        buttons.append(quadSplitActionButton)
        return buttons
    }

    static var quadSplitActionButton: BonsplitConfiguration.SplitActionButton {
        BonsplitConfiguration.SplitActionButton(
            id: customActionIdentifier,
            systemImage: CmuxSurfaceTabBarBuiltInAction.splitQuad.defaultIcon,
            tooltip: String(
                localized: "workspace.tooltip.splitQuad",
                defaultValue: "Split Quad"
            ),
            action: .custom(customActionIdentifier)
        )
    }

    private static func shouldInjectLateFailure(afterCompletedSplits completed: Int) -> Bool {
        #if DEBUG
        testingFailAfterCompletedSplits == completed
        #else
        false
        #endif
    }

    /// Live transient-focus probe shared with shortcut routing semantics.
    private static func isTransientFocusSuppressed(workspace: Workspace, paneId: PaneID) -> Bool {
        guard let tab = workspace.bonsplitController.selectedTab(inPane: paneId)
            ?? workspace.bonsplitController.tabs(inPane: paneId).first,
              let panelId = workspace.panelIdFromSurfaceId(tab.id),
              let terminal = workspace.terminalPanel(for: panelId) else {
            return false
        }
        let hosted = terminal.hostedView
        let firstResponderIsWindow = NSApp.keyWindow?.firstResponder is NSWindow
        return shouldSuppressSplitShortcutForTransientTerminalFocusInputs(
            firstResponderIsWindow: firstResponderIsWindow,
            hostedSize: hosted.bounds.size,
            hostedHiddenInHierarchy: hosted.isHiddenOrHasHiddenAncestor,
            hostedAttachedToWindow: terminal.surface.isViewInWindow
        )
    }

    private static func logLateFailure(surface: String, completedSplits: Int, detail: String) {
        let message =
            "quad.lateFailure surface=\(surface) completedSplits=\(completedSplits) detail=\(detail)"
        #if DEBUG
        testingLateFailureEvents.append(message)
        cmuxDebugLog(message)
        print(message)
        #endif
    }
}

// MARK: - Dock selected panel helper

private extension DockSplitStore {
    func selectedPanelId(inPane pane: PaneID) -> UUID? {
        guard let tab = bonsplitController.selectedTab(inPane: pane) else { return nil }
        return surfaceIdToPanelId[tab.id]
    }
}
