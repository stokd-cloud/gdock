import AppKit
import Combine
import CmuxAppKitSupportUI
import CmuxNotifications
import CmuxSidebarInterpreterClient
import CmuxSidebarRemoteRender
import CmuxUpdater
import SwiftUI

/// Dockable host for the **real** left workspace/session selector chrome
/// (`VerticalTabsSidebar`), so canvas mode can hide the fixed left column
/// without losing the selector. Singleton via
/// `Workspace.openOrFocusLeftWorkspaceSelectorSurface` /
/// `showOrFocusLeftWorkspaceSelectorPane`.
@MainActor
final class LeftWorkspaceSelectorPanel: Panel, ObservableObject {
    let id: UUID
    let stableSurfaceIdentity = PanelStableSurfaceIdentity()
    let panelType: PanelType = .leftWorkspaceSelector

    @Published private(set) var focusFlashToken: Int = 0

    private weak var workspace: Workspace?
    private weak var focusAnchorView: RightSidebarToolFocusAnchorView?

    init(workspace: Workspace) {
        self.id = UUID()
        self.workspace = workspace
    }

    var displayTitle: String {
        String(localized: "leftWorkspaceSelectorPane.title", defaultValue: "Workspaces")
    }

    var displayIcon: String? { "sidebar.left" }

    var isFocusedInWorkspace: Bool {
        workspace?.focusedPanelId == id
    }

    func reattach(to workspace: Workspace) {
        self.workspace = workspace
    }

    func attachFocusAnchor(_ anchor: RightSidebarToolFocusAnchorView?) {
        focusAnchorView = anchor
    }

    func close() {
        focusAnchorView = nil
    }

    func focus() {
        guard let anchor = focusAnchorView,
              let window = anchor.window else { return }
        _ = window.makeFirstResponder(anchor)
    }

    func unfocus() {}

    func triggerFlash(reason: WorkspaceAttentionFlashReason) {
        _ = reason
        guard NotificationPaneFlashSettings.isEnabled() else { return }
        focusFlashToken += 1
    }

    func ownedFocusIntent(for responder: NSResponder, in window: NSWindow) -> PanelFocusIntent? {
        _ = window
        guard focusAnchorView?.ownsKeyboardFocus(responder) == true else { return nil }
        return .panel
    }
}

/// Hosts the real left selector list UI (`VerticalTabsSidebar`) inside a pane.
struct LeftWorkspaceSelectorPanelView: View {
    @ObservedObject var panel: LeftWorkspaceSelectorPanel
    let tabManager: TabManager
    let sidebarUnread: SidebarUnreadModel
    let fileExplorerState: FileExplorerState
    let updateViewModel: UpdateStateModel
    let windowId: UUID
    let observedWindowReference: WeakWindowReference
    let isFocused: Bool
    let isVisibleInUI: Bool
    let appearance: PanelAppearance
    let windowAppearance: WindowAppearanceSnapshot
    let onRequestPanelFocus: () -> Void
    let onToggleFixedLeft: () -> Void
    let onSendFeedback: () -> Void
    let onNewTab: () -> Void

    @State private var selection: SidebarSelection = .tabs
    @State private var selectedTabIds: Set<UUID> = []
    @State private var lastSidebarSelectionIndex: Int?
    @State private var sidebarRenderWorkerClient: RenderWorkerClient?
    @State private var focusFlashOpacity: Double = 0.0
    @State private var focusFlashAnimationGeneration: Int = 0
    @EnvironmentObject private var cmuxConfigStore: CmuxConfigStore
    /// This pane is not the window titlebar; it only needs a layout model to satisfy
    /// `VerticalTabsSidebar`. Mirrors ContentView's `?? TitlebarControlsLayoutModel()` fallback.
    @State private var titlebarControlsLayoutModel = TitlebarControlsLayoutModel()

    var body: some View {
        Group {
            if isVisibleInUI {
                VerticalTabsSidebar(
                    updateViewModel: updateViewModel,
                    fileExplorerState: fileExplorerState,
                    sidebarUnread: sidebarUnread,
                    titlebarControlsLayoutModel: titlebarControlsLayoutModel,
                    windowId: windowId,
                    onSendFeedback: onSendFeedback,
                    onToggleSidebar: onToggleFixedLeft,
                    onNewTab: onNewTab,
                    observedWindowReference: observedWindowReference,
                    selection: $selection,
                    selectedTabIds: $selectedTabIds,
                    lastSidebarSelectionIndex: $lastSidebarSelectionIndex,
                    sidebarRenderWorkerClient: $sidebarRenderWorkerClient
                )
                .environmentObject(tabManager)
                .environmentObject(cmuxConfigStore)
                .environment(\.colorScheme, windowAppearance.sidebarContentColorScheme)
            } else {
                Color.clear
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color(nsColor: appearance.backgroundColor))
        .background(
            RightSidebarToolFocusAnchor(onViewChange: panel.attachFocusAnchor)
                .frame(width: 0, height: 0)
        )
        .overlay {
            WorkspaceAttentionFlashRingView(opacity: focusFlashOpacity)
        }
        .simultaneousGesture(TapGesture().onEnded { requestPanelFocusIfNeeded() })
        .onAppear {
            syncSelectionFromTabManager()
        }
        .onChange(of: tabManager.selectedTabId) { _, _ in
            syncSelectionFromTabManager()
        }
        .onChange(of: panel.focusFlashToken) { _, _ in
            triggerFocusFlashAnimation()
        }
        .onDisappear {
            shutdownRenderWorkerClient()
        }
    }

    private func syncSelectionFromTabManager() {
        if let selected = tabManager.selectedTabId {
            selectedTabIds = [selected]
            if let index = tabManager.tabs.firstIndex(where: { $0.id == selected }) {
                lastSidebarSelectionIndex = index
            }
        }
    }

    private func requestPanelFocusIfNeeded() {
        guard !panel.isFocusedInWorkspace else { return }
        onRequestPanelFocus()
    }

    private func shutdownRenderWorkerClient() {
        guard let client = sidebarRenderWorkerClient else { return }
        sidebarRenderWorkerClient = nil
        Task { await client.shutdown() }
    }

    private func triggerFocusFlashAnimation() {
        focusFlashAnimationGeneration &+= 1
        let generation = focusFlashAnimationGeneration
        focusFlashOpacity = FocusFlashPattern.values.first ?? 0

        for segment in FocusFlashPattern.segments {
            DispatchQueue.main.asyncAfter(deadline: .now() + segment.delay) {
                guard focusFlashAnimationGeneration == generation else { return }
                withAnimation(focusFlashAnimation(for: segment.curve, duration: segment.duration)) {
                    focusFlashOpacity = segment.targetOpacity
                }
            }
        }
    }

    private func focusFlashAnimation(for curve: FocusFlashCurve, duration: TimeInterval) -> Animation {
        switch curve {
        case .easeIn:
            return .easeIn(duration: duration)
        case .easeOut:
            return .easeOut(duration: duration)
        }
    }
}
