import AppKit
import Bonsplit
import CMUXAgentLaunch
import CmuxAppKitSupportUI
import CmuxFoundation
import CmuxSettings
import CmuxSettingsUI
import SwiftUI

private func rightSidebarDebugResponder(_ responder: NSResponder?) -> String {
    guard let responder else { return "nil" }
    return String(describing: type(of: responder))
}

/// Mode shown in the right sidebar (the panel toggled by ⌘⌥B).
enum RightSidebarMode: String, CaseIterable, Codable, Sendable {
    case files
    case find
    case sessions
    case feed
    case dock
    /// Stokd Work — right-rail tool tab (raw value stable for persistence).
    case stokdWork
    case customSidebar = "custom-sidebar"
    /// Stokd Worktrees — left-rail section.
    case stokdWorktrees
    /// Stokd Global Config — left-rail section.
    case stokdGlobalConfig
    /// Stokd Usage — left-rail section.
    case stokdUsage

    var label: String {
        switch self {
        case .files: return String(localized: "rightSidebar.mode.files", defaultValue: "Files")
        case .find: return String(localized: "rightSidebar.mode.find", defaultValue: "Find")
        case .sessions: return String(localized: "rightSidebar.mode.sessions", defaultValue: "Vault")
        case .feed: return String(localized: "rightSidebar.mode.feed", defaultValue: "Feed")
        case .dock: return String(localized: "rightSidebar.mode.dock", defaultValue: "Dock")
        case .stokdWork: return String(localized: "rightSidebar.mode.stokdWork", defaultValue: "Work")
        case .customSidebar: return String(localized: "rightSidebar.mode.customSidebar", defaultValue: "Custom")
        case .stokdWorktrees, .stokdGlobalConfig, .stokdUsage:
            return StokdRailPanelKind(rightSidebarMode: self)?.displayTitle
                ?? rawValue
        }
    }

    var symbolName: String {
        switch self {
        case .files: return "folder"
        case .find: return "magnifyingglass"
        case .sessions: return "books.vertical"
        case .feed: return "dot.radiowaves.left.and.right"
        case .dock: return "dock.rectangle"
        case .stokdWork: return "checklist"
        case .customSidebar: return "wand.and.stars"
        case .stokdWorktrees, .stokdGlobalConfig, .stokdUsage:
            return StokdRailPanelKind(rightSidebarMode: self)?.symbolName ?? "square.grid.2x2"
        }
    }

    var shortcutAction: KeyboardShortcutSettings.Action? {
        switch self {
        case .files: return .switchRightSidebarToFiles
        case .find: return .switchRightSidebarToFind
        case .sessions: return .switchRightSidebarToSessions
        case .feed: return .switchRightSidebarToFeed
        case .dock: return .switchRightSidebarToDock
        case .stokdWork, .customSidebar, .stokdWorktrees, .stokdGlobalConfig, .stokdUsage:
            return nil
        }
    }
}

extension RightSidebarMode {
    static let paneModes: [RightSidebarMode] = [.files, .find, .sessions]

    var canOpenAsPane: Bool {
        Self.paneModes.contains(self)
    }
}

enum RightSidebarContentMountPolicy {
    static func shouldMountContent(isRightSidebarVisible: Bool, hasMountedContent: Bool) -> Bool {
        isRightSidebarVisible || hasMountedContent
    }
}

enum RightSidebarDockPresentationPolicy {
    /// Stacked (accordion) sections follow `gdock.rightSidebarStackedTabs`
    /// alone; the sidebar-dock beta gate no longer participates.
    static func usesStackedTabs(stackedTabsEnabled: Bool) -> Bool {
        stackedTabsEnabled
    }
}

extension RightSidebarMode {
    /// Tools that can live as collapsible sections in the stacked right sidebar.
    static let stackableModes: [RightSidebarMode] = [.files, .find, .sessions, .stokdWork]

    var canStackAsSection: Bool {
        Self.stackableModes.contains(self)
    }
}

enum FileExplorerRootSyncPolicy {
    static func shouldSyncFileExplorerStore(isRightSidebarVisible: Bool, mode: RightSidebarMode) -> Bool {
        guard isRightSidebarVisible else { return false }
        switch mode {
        case .files, .find:
            return true
        case .sessions, .feed, .dock, .stokdWork, .customSidebar,
             .stokdWorktrees, .stokdGlobalConfig, .stokdUsage:
            return false
        }
    }
}

extension RightSidebarMode {
    static func modeShortcut(for event: NSEvent) -> RightSidebarMode? {
        modeShortcut(for: event, allowingAction: { _ in true })
    }

    static func modeShortcut(
        for event: NSEvent,
        allowingAction: (KeyboardShortcutSettings.Action) -> Bool
    ) -> RightSidebarMode? {
        guard event.type == .keyDown else { return nil }
        for mode in RightSidebarMode.allCases {
            guard let action = mode.shortcutAction,
                  allowingAction(action),
                  mode.isAvailable(),
                  KeyboardShortcutSettings.shortcut(for: action).matches(event: event) else {
                continue
            }
            return mode
        }
        return nil
    }
}

/// Right sidebar root view. Hosts a segmented mode picker plus the active panel.
///
/// When `sidebar.beta.dock.enabled` is on, the rail mounts ``SidebarDockPanelView``
/// seeded with Files/Find/Vault; Feed/Dock keep non-rail presentation (VAL-FLAG-003).
struct RightSidebarPanelView: View {
    @ObservedObject var tabManager: TabManager
    @ObservedObject var fileExplorerStore: FileExplorerStore
    @ObservedObject var fileExplorerState: FileExplorerState
    @ObservedObject var sessionIndexStore: SessionIndexStore
    /// Window-scoped Work model for the legacy mode-bar path. The dock rails use
    /// each ``RightSidebarToolPanel``'s own model instead.
    @ObservedObject var stokdWorkViewModel: StokdWorkPanelViewModel
    /// Re-scopes ``stokdWorkViewModel`` to the selected workspace. Invoked when the
    /// legacy Work panel appears, because a mode restored at launch never fires an
    /// `onChange` in the host.
    let onSyncStokdWorkRepository: () -> Void
    let titlebarHeight: CGFloat
    let windowAppearance: WindowAppearanceSnapshot
    let workspaceId: UUID?
    let onResumeSession: ((SessionEntry) -> Void)?
    let onOpenFilePreview: (String) -> Void
    let onOpenAsPane: (RightSidebarMode) -> Void
    let onClose: () -> Void
    /// Per-window dock registry; nil when the host has not created rails yet.
    var dockRegistry: SidebarDockStoreRegistry? = nil

    @State private var modeShortcutHintMonitor = WindowScopedShortcutHintModifierMonitor(activation: .commandOrControl) { window in
        guard let responder = window.firstResponder else { return false }
        return AppDelegate.shared?.isRightSidebarFocusResponder(responder, in: window) == true
    }
    @State private var focusShortcutHintMonitor = WindowScopedShortcutHintModifierMonitor(activation: .commandOnly)
    @State private var closeShortcutHintMonitor = WindowScopedShortcutHintModifierMonitor(activation: .commandOnly)
    @State private var hasMountedRightSidebarContent = false
    /// Tools dragged down out of the mode bar into their own stacked sections.
    /// Empty means the sidebar renders exactly as it always has.
    @State private var sectionLayout = RightSidebarSectionLayout()
    @State private var keyboardShortcutSettingsObserver = KeyboardShortcutSettingsObserver.shared
    @State private var stokdConfigurationModal: StokdModelConfigurationModalRequest?
    private let alwaysShowShortcutHints = ShortcutHintDebugSettings().alwaysShowHints
    private let closeShortcutHintXOffset = ShortcutHintDebugSettings.defaultRightSidebarCloseHintX
    private let closeShortcutHintYOffset = ShortcutHintDebugSettings.defaultRightSidebarCloseHintY
    private let focusShortcutHintXOffset = ShortcutHintDebugSettings.defaultRightSidebarFocusHintX
    private let focusShortcutHintYOffset = ShortcutHintDebugSettings.defaultRightSidebarFocusHintY
    @LiveSetting(\.shortcuts.showModifierHoldHints) private var showModifierHoldHints
    @AppStorage(RightSidebarBetaFeatureSettings.feedEnabledKey)
    private var feedEnabled = RightSidebarBetaFeatureSettings.defaultFeedEnabled
    @AppStorage(RightSidebarBetaFeatureSettings.dockEnabledKey)
    private var dockEnabled = RightSidebarBetaFeatureSettings.defaultDockEnabled
    @AppStorage(RightSidebarBetaFeatureSettings.sidebarDockEnabledKey)
    private var sidebarDockEnabled = RightSidebarBetaFeatureSettings.defaultSidebarDockEnabled
    @AppStorage(RightSidebarDockPresentationSettings.userDefaultsKey)
    private var rightSidebarStackedTabsEnabled = RightSidebarDockPresentationSettings.defaultEnabled

    // Re-reading the observable store inside modeBar causes SwiftUI to
    // track the pending count so the badge updates live when hooks push
    // new items.
    private var feedPendingCount: Int {
        FeedCoordinator.shared.store?.pending.count ?? 0
    }

    private var availableModes: [RightSidebarMode] {
        RightSidebarMode.availableModes(
            feedEnabled: feedEnabled,
            dockEnabled: dockEnabled
        )
    }

    private var modeBarItems: [RightSidebarModeBarItem] {
        availableModes.map { RightSidebarModeBarItem(kind: .mode($0)) }
    }

    private var focusShortcutHintAnimationValue: Bool {
        alwaysShowShortcutHints || (showModifierHoldHints && focusShortcutHintMonitor.isModifierPressed)
    }

    private func startShortcutHintMonitorsIfNeeded() {
        guard showModifierHoldHints else {
            stopShortcutHintMonitors()
            return
        }
        modeShortcutHintMonitor.start()
        focusShortcutHintMonitor.start()
        closeShortcutHintMonitor.start()
    }

    private func stopShortcutHintMonitors() {
        modeShortcutHintMonitor.stop()
        focusShortcutHintMonitor.stop()
        closeShortcutHintMonitor.stop()
    }

    private var usesStackedTabsPresentation: Bool {
        RightSidebarDockPresentationPolicy.usesStackedTabs(
            stackedTabsEnabled: rightSidebarStackedTabsEnabled
        )
    }

    var body: some View {
        Group {
            if usesStackedTabsPresentation, let registry = dockRegistry {
                dockRailBody(registry: registry)
            } else {
                legacyModeBarBody
            }
        }
        .sheet(item: $stokdConfigurationModal) { request in
            StokdModelConfigurationModalView(
                initialTab: request.initialTab,
                directory: stokdModelConfigurationDirectory
            )
        }
        .shortcutHintVisibilityAnimation(value: focusShortcutHintAnimationValue)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(
            RightSidebarKeyboardFocusBridge()
            .frame(width: 1, height: 1)
        )
        .background(
            WindowAccessor(refreshID: showModifierHoldHints) { window in
                let hintWindow = showModifierHoldHints ? window : nil
                modeShortcutHintMonitor.setHostWindow(hintWindow)
                focusShortcutHintMonitor.setHostWindow(hintWindow)
                closeShortcutHintMonitor.setHostWindow(hintWindow)
            }
            .frame(width: 0, height: 0)
        )
        .accessibilityIdentifier("RightSidebar")
        .onAppear {
            startShortcutHintMonitorsIfNeeded()
            if fileExplorerState.isVisible { hasMountedRightSidebarContent = true }
            fileExplorerState.refreshModeAvailability()
            seedDockRailsIfNeeded()
        }
        .onDisappear {
            stopShortcutHintMonitors()
        }
        .onChange(of: showModifierHoldHints) { _, _ in
            startShortcutHintMonitorsIfNeeded()
        }
        .onChange(of: fileExplorerState.isVisible) { _, visible in
            if visible { hasMountedRightSidebarContent = true }
        }
        .onChange(of: feedEnabled) { _, _ in refreshModeAvailabilityAndFocusIfNeeded() }
        .onChange(of: dockEnabled) { _, _ in refreshModeAvailabilityAndFocusIfNeeded() }
        .onChange(of: sidebarDockEnabled) { _, enabled in
            refreshModeAvailabilityAndFocusIfNeeded()
            if enabled, usesStackedTabsPresentation {
                seedDockRailsIfNeeded()
            }
        }
        .onChange(of: rightSidebarStackedTabsEnabled) { _, enabled in
            refreshModeAvailabilityAndFocusIfNeeded()
            if enabled {
                seedDockRailsIfNeeded()
            }
        }
    }

    /// Classic path: legacy mode bar + single content host (VAL-FLAG-002).
    @ViewBuilder
    private var legacyModeBarBody: some View {
        VStack(spacing: 0) {
            modeBar
                .rightSidebarChromeBottomBorder()
            contentForMode
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .onDrop(of: [.text], delegate: RightSidebarSectionDropDelegate(
                    layout: $sectionLayout,
                    selectedMode: fileExplorerState.mode
                ))
        }
    }

    /// Stacked-tabs path: dock rail for tools; feed/dock keep non-rail content.
    @ViewBuilder
    private func dockRailBody(registry: SidebarDockStoreRegistry) -> some View {
        let store = registry.right
        let showingExcludedNonRail =
            fileExplorerState.mode == .feed
            || fileExplorerState.mode == .dock
            || fileExplorerState.mode == .customSidebar

        VStack(spacing: 0) {
            if showingExcludedNonRail {
                // Preserved non-rail entrypoints (D-19): feed/dock still use
                // the classic content host while tools live in the rail.
                contentForMode
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                SidebarDockPanelView(
                    store: store,
                    isRailVisible: fileExplorerState.isVisible,
                    contentForTab: { tabId, _ in
                        AnyView(dockToolContent(for: tabId, store: store))
                    },
                    openAsPaneMode: store.focusedToolMode() ?? fileExplorerState.mode,
                    onOpenAsPane: { mode in onOpenAsPane(mode) },
                    onClose: onClose,
                    shortCircuitHiddenContent: true
                )
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .onAppear {
            wireMirror(store: store)
            seedDockRailsIfNeeded()
        }
    }

    @ViewBuilder
    private func dockToolContent(for tabId: TabID, store: SidebarDockStore) -> some View {
        if let tool = store.panel(for: tabId) as? RightSidebarToolPanel {
            switch tool.mode {
            case .files:
                FileExplorerPanelView(
                    store: fileExplorerStore,
                    state: fileExplorerState,
                    onOpenFilePreview: onOpenFilePreview,
                    presentation: .files
                )
            case .find:
                FileExplorerPanelView(
                    store: fileExplorerStore,
                    state: fileExplorerState,
                    onOpenFilePreview: onOpenFilePreview,
                    presentation: .find
                )
            case .sessions:
                SessionIndexView(store: sessionIndexStore, onResume: onResumeSession)
                    .onAppear {
                        sessionIndexStore.setCurrentDirectoryIfChanged(sessionIndexDirectory)
                    }
            case .stokdWork:
                StokdWorkPanelView(model: tool.stokdWorkViewModel)
            case .stokdWorktrees, .stokdGlobalConfig, .stokdUsage:
                if let kind = StokdRailPanelKind(rightSidebarMode: tool.mode) {
                    StokdRailPanelPlaceholderView(kind: kind)
                } else {
                    Color.clear
                }
            case .feed, .dock, .customSidebar:
                Color.clear
            }
        } else {
            Color.clear
        }
    }

    private func wireMirror(store: SidebarDockStore) {
        store.onFocusedToolModeChanged = { [fileExplorerState] mode in
            guard let mode else { return }
            // Derived mirror only — rail tools never write mode from views.
            if fileExplorerState.mode != mode {
                fileExplorerState.mode = mode
            }
        }
    }

    private func seedDockRailsIfNeeded() {
        guard usesStackedTabsPresentation, let registry = dockRegistry else { return }
        guard let workspace = tabManager.selectedWorkspace
                ?? tabManager.tabs.first else { return }
        // Wire mirror before seed so selectToolMode → didSelectTab owns the
        // derived legacy mode write (VAL-RAIL-009). Never assign mode here.
        wireMirror(store: registry.right)
        AppDelegate.shared?.mainWindowContexts.values
            .first(where: { $0.windowId == registry.windowId })?
            .restorePendingSidebarDockSnapshots(
                into: registry,
                workspace: workspace,
                includeStokdWork: true
            )
        SidebarDockSeeding.seedRegistryIfEmpty(
            registry: registry,
            workspace: workspace,
            preferredRightMode: fileExplorerState.mode,
            includeStokdWork: true
        )
        // Seed no-op (already populated): re-drive selection through the store so
        // Bonsplit callbacks refresh a stale scalar without a competing write.
        if let mode = registry.right.focusedToolMode(),
           SidebarDockPlacementMatrix.allows(mode: mode),
           fileExplorerState.mode != mode,
           fileExplorerState.mode != .feed,
           fileExplorerState.mode != .dock,
           fileExplorerState.mode != .customSidebar {
            _ = registry.right.selectToolMode(mode, focus: false)
        }
    }

    private var modeBar: some View {
        let _ = keyboardShortcutSettingsObserver.revision
        return ZStack {
            WindowDragHandleView()

            HStack(spacing: RightSidebarChromeMetrics.headerControlSpacing) {
                ForEach(modeBarItems) { item in
                    let shortcut = item.shortcutAction.map { KeyboardShortcutSettings.shortcut(for: $0) } ?? .unbound
                    ModeBarButton(
                        item: item,
                        isSelected: item.isSelected(
                            mode: fileExplorerState.mode
                        ),
                        badgeCount: item.mode == .feed ? feedPendingCount : 0,
                        shortcutHint: shortcut,
                        showsShortcutHint: ShortcutHintTitlebarPolicy.shouldShow(
                            shortcut: shortcut,
                            alwaysShowShortcutHints: alwaysShowShortcutHints,
                            modifierPressed: modeShortcutHintMonitor.isModifierPressed,
                            modifierHoldHintsEnabled: showModifierHoldHints
                        )
                    ) {
                        let mode = item.mode
                        // Selection authority first (router → selectToolMode → callbacks),
                        // then keyboard focus. Never skip selectMode when focus succeeds
                        // (D-32 R3: focus-only left selected_tab_id stale).
                        selectMode(mode)
                        _ = AppDelegate.shared?.focusRightSidebarInActiveMainWindow(
                            mode: mode,
                            focusFirstItem: true,
                            preferredWindow: NSApp.keyWindow ?? NSApp.mainWindow
                        )
                    }
                    .onDrag {
                        // Plain text payload: no custom UTType to declare in
                        // Info.plist for a prototype drag.
                        NSItemProvider(object: item.mode.rawValue as NSString)
                    }
                }
                Spacer(minLength: 0)
                stokdModelConfigurationButtons
                if fileExplorerState.mode.canOpenAsPane {
                    openAsPaneButton(mode: fileExplorerState.mode)
                }
                closeButton
            }
        }
        .rightSidebarChromeBar(leadingPadding: 4, trailingPadding: 6, height: titlebarHeight)
        .overlay(alignment: .topLeading) {
            focusShortcutHintOverlay
        }
        .background(TitlebarDoubleClickMonitorView())
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("RightSidebarModeBar")
        .reportRightSidebarChromeGeometryForBonsplitUITest(
            isVisible: true,
            titlebarHeight: titlebarHeight
        )
    }

    private var stokdModelConfigurationButtons: some View {
        HStack(spacing: RightSidebarChromeMetrics.headerControlSpacing) {
            ForEach(StokdModelConfigurationLaunchBar.actions) { action in
                Button {
                    stokdConfigurationModal = StokdModelConfigurationModalRequest(initialTab: action.initialTab)
                } label: {
                    HeaderChromeIconStyle.symbol(action.symbolName)
                }
                .buttonStyle(RightSidebarHeaderIconButtonStyle(iconGeometryKeyPrefix: "rightSidebarHeader\(action.id)Icon"))
                .frame(
                    width: RightSidebarChromeMetrics.headerControlSize,
                    height: RightSidebarChromeMetrics.headerControlSize
                )
                .rightSidebarHeaderControlAlignment()
                .safeHelp(action.title)
                .accessibilityLabel(action.title)
                .accessibilityIdentifier("RightSidebar.\(action.id)")
                .titlebarInteractiveControl()
            }
        }
    }

    private func openAsPaneButton(mode: RightSidebarMode) -> some View {
        Button {
            onOpenAsPane(mode)
        } label: {
            HeaderChromeIconStyle.symbol("rectangle.split.2x1")
        }
        .buttonStyle(RightSidebarHeaderIconButtonStyle(iconGeometryKeyPrefix: "rightSidebarHeaderOpenAsPaneIcon"))
        .frame(
            width: RightSidebarChromeMetrics.headerControlSize,
            height: RightSidebarChromeMetrics.headerControlSize
        )
        .reportRightSidebarChromeNamedGeometryForBonsplitUITest(
            keyPrefix: "rightSidebarHeaderOpenAsPane",
            isVisible: true
        )
        .rightSidebarHeaderControlAlignment()
        .safeHelp(String(localized: "rightSidebar.openAsPane.tooltip", defaultValue: "Open as pane"))
        .accessibilityLabel(
            String.localizedStringWithFormat(
                String(localized: "rightSidebar.openAsPane.accessibilityLabel", defaultValue: "Open %@ as Pane"),
                mode.label
            )
        )
        .accessibilityIdentifier("RightSidebar.openAsPaneButton")
        .titlebarInteractiveControl()
    }

    private var closeButton: some View {
        let _ = keyboardShortcutSettingsObserver.revision
        let shortcut = KeyboardShortcutSettings.shortcut(for: .toggleRightSidebar)
        let showsShortcutHint = ShortcutHintTitlebarPolicy.shouldShow(
            shortcut: shortcut,
            alwaysShowShortcutHints: alwaysShowShortcutHints,
            modifierPressed: closeShortcutHintMonitor.isModifierPressed,
            modifierHoldHintsEnabled: showModifierHoldHints
        )
        return ZStack {
            Button(action: onClose) {
                HeaderChromeIconStyle.symbol("xmark")
            }
            .buttonStyle(RightSidebarHeaderIconButtonStyle(iconGeometryKeyPrefix: "rightSidebarHeaderCloseIcon"))
            .frame(
                width: RightSidebarChromeMetrics.headerControlSize,
                height: RightSidebarChromeMetrics.headerControlSize
            )
            .reportRightSidebarChromeNamedGeometryForBonsplitUITest(
                keyPrefix: "rightSidebarHeaderClose",
                isVisible: true
            )
            .safeHelp(
                KeyboardShortcutSettings.Action.toggleRightSidebar.tooltip(
                    String(localized: "rightSidebar.toggle.tooltip", defaultValue: "Toggle right sidebar")
                )
            )
            .accessibilityLabel(String(localized: "rightSidebar.close.accessibilityLabel", defaultValue: "Close Right Sidebar"))
            .accessibilityIdentifier("RightSidebar.closeButton")
        }
        .frame(
            width: RightSidebarChromeMetrics.headerControlSize,
            height: RightSidebarChromeMetrics.headerControlSize
        )
        .overlay(alignment: .top) {
            if showsShortcutHint {
                ShortcutHintPill(shortcut: shortcut, fontSize: 9, emphasis: 1.05)
                    .fixedSize(horizontal: true, vertical: false)
                    .offset(
                        x: CGFloat(ShortcutHintDebugSettings.clamped(closeShortcutHintXOffset)),
                        y: CGFloat(ShortcutHintDebugSettings.clamped(closeShortcutHintYOffset))
                    )
                    .shortcutHintTransition()
                    .accessibilityIdentifier("rightSidebarCloseShortcutHint")
                    .allowsHitTesting(false)
                    .zIndex(10)
            }
        }
        .rightSidebarHeaderControlAlignment()
        .shortcutHintVisibilityAnimation(value: showsShortcutHint)
        .titlebarInteractiveControl()
    }

    @ViewBuilder
    private var focusShortcutHintOverlay: some View {
        let _ = keyboardShortcutSettingsObserver.revision
        let shortcut = KeyboardShortcutSettings.shortcut(for: .focusRightSidebar)
        let showsFocusShortcutHint = ShortcutHintTitlebarPolicy.shouldShow(
            shortcut: shortcut,
            alwaysShowShortcutHints: alwaysShowShortcutHints,
            modifierPressed: focusShortcutHintMonitor.isModifierPressed,
            modifierHoldHintsEnabled: showModifierHoldHints
        )
        if showsFocusShortcutHint {
            ShortcutHintPill(
                shortcut: shortcut,
                fontSize: 9,
                emphasis: 1.05
            )
                .padding(.leading, 6)
                .padding(.top, 5)
                .offset(
                    x: CGFloat(ShortcutHintDebugSettings.clamped(focusShortcutHintXOffset)),
                    y: CGFloat(ShortcutHintDebugSettings.clamped(focusShortcutHintYOffset))
                )
                .shortcutHintTransition()
                .accessibilityIdentifier("rightSidebarFocusShortcutHint")
                .allowsHitTesting(false)
                .zIndex(10)
        }
    }

    @ViewBuilder
    private var contentForMode: some View {
        if RightSidebarContentMountPolicy.shouldMountContent(isRightSidebarVisible: fileExplorerState.isVisible, hasMountedContent: hasMountedRightSidebarContent) {
            if sectionLayout.isEmpty {
                toolContent(for: fileExplorerState.mode)
            } else {
                stackedContent
            }
        } else {
            Color.clear
        }
    }

    /// The view a tool renders, independent of whether it is shown as the single
    /// sidebar tool or as one section of a stack. Sections re-parent these exact
    /// views; nothing is re-hosted.
    @ViewBuilder
    private func toolContent(for mode: RightSidebarMode) -> some View {
        switch mode {
        case .files:
            FileExplorerPanelView(
                store: fileExplorerStore,
                state: fileExplorerState,
                onOpenFilePreview: onOpenFilePreview,
                presentation: .files
            )
        case .find:
            FileExplorerPanelView(
                store: fileExplorerStore,
                state: fileExplorerState,
                onOpenFilePreview: onOpenFilePreview,
                presentation: .find
            )
        case .sessions:
            SessionIndexView(store: sessionIndexStore, onResume: onResumeSession)
                .onAppear {
                    sessionIndexStore.setCurrentDirectoryIfChanged(sessionIndexDirectory)
                }
        case .feed:
            FeedPanelView()
        case .dock:
            dockPanel(windowAppearance: windowAppearance)
        case .stokdWork:
            StokdWorkPanelView(model: stokdWorkViewModel)
                .onAppear { onSyncStokdWorkRepository() }
        case .stokdWorktrees, .stokdGlobalConfig, .stokdUsage:
            if let kind = StokdRailPanelKind(rightSidebarMode: mode) {
                StokdRailPanelPlaceholderView(kind: kind)
            } else {
                EmptyView()
            }
        case .customSidebar:
            EmptyView()
        }
    }

    /// Sidebar split into sections: the still-selected tool on top, then each
    /// tool that has been dragged down out of the mode bar.
    private var stackedContent: some View {
        VStack(spacing: 0) {
            if !sectionLayout.contains(fileExplorerState.mode) {
                toolContent(for: fileExplorerState.mode)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                Rectangle()
                    .fill(Color.primary.opacity(0.12))
                    .frame(height: 1)
            }
            RightSidebarSectionStack(
                layout: $sectionLayout,
                onReturnToModeBar: { mode in
                    sectionLayout.remove(mode)
                },
                content: { mode in
                    toolContent(for: mode)
                }
            )
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }

    private var sessionIndexDirectory: String? {
        sessionIndexStore.currentDirectory
    }

    private var stokdModelConfigurationDirectory: String {
        sessionIndexDirectory
            ?? tabManager.selectedWorkspace?.currentDirectory
            ?? FileManager.default.currentDirectoryPath
    }

    /// Renders this window's own Dock (created lazily on first show); no
    /// window ever defers to a Dock rendered elsewhere.
    @ViewBuilder
    private func dockPanel(windowAppearance: WindowAppearanceSnapshot) -> some View {
        if let app = AppDelegate.shared, let dock = app.windowDock(for: tabManager) {
            DockPanelView(
                store: dock,
                isSidebarVisible: fileExplorerState.isVisible,
                mode: fileExplorerState.mode,
                rootDirectory: nil,
                windowAppearance: windowAppearance,
                rightSidebarOwnsInputFocus: fileExplorerState.rightSidebarOwnsInputFocus,
                unreadSource: TerminalNotificationStore.shared.sidebarUnread
            )
            .id("dock.window.\(dock.workspaceId.uuidString)")
        } else {
            Color.clear
        }
    }

    private func selectMode(_ mode: RightSidebarMode) {
        // Single window-scoped selection seam (VAL-RAIL-009).
        if let registry = dockRegistry, usesStackedTabsPresentation {
            var context = RightSidebarSelectionContext(
                windowId: registry.windowId,
                fileExplorerState: fileExplorerState,
                rightStore: registry.right,
                isDockEnabled: true,
                ensureVisible: {
                    if !fileExplorerState.isVisible {
                        fileExplorerState.setVisible(true)
                    }
                }
            )
            _ = RightSidebarSelectionRouter.apply(
                RightSidebarSelectionRequest(mode: mode, focus: false, source: .modeTabClick),
                in: &context
            )
        } else if let app = AppDelegate.shared {
            _ = app.routeRightSidebarSelection(
                RightSidebarSelectionRequest(mode: mode, focus: false, source: .modeTabClick)
            )
        } else {
            fileExplorerState.mode = mode
        }
        if fileExplorerState.mode == .sessions {
            sessionIndexStore.setCurrentDirectoryIfChanged(sessionIndexDirectory)
            if sessionIndexStore.entries.isEmpty {
                sessionIndexStore.reload()
            }
        }
    }

    private func refreshModeAvailabilityAndFocusIfNeeded() {
        let previousMode = fileExplorerState.mode
        fileExplorerState.refreshModeAvailability()
        let mode = fileExplorerState.mode
        // The Dock manages its own lifecycle from DockPanelView, so no dock sync
        // is needed here when the mode is unchanged.
        guard previousMode != mode,
              fileExplorerState.isVisible,
              let window = NSApp.keyWindow ?? NSApp.mainWindow
        else { return }
        _ = AppDelegate.shared?.focusRightSidebarInActiveMainWindow(
            mode: fileExplorerState.mode,
            focusFirstItem: false,
            preferredWindow: window
        )
    }
}

private struct RightSidebarKeyboardFocusBridge: NSViewRepresentable {
    func makeNSView(context: Context) -> RightSidebarKeyboardFocusView {
        let view = RightSidebarKeyboardFocusView(frame: NSRect(x: 0, y: 0, width: 1, height: 1))
        return view
    }

    func updateNSView(_ nsView: RightSidebarKeyboardFocusView, context: Context) {
        nsView.registerWithKeyboardFocusCoordinatorIfNeeded()
    }
}

final class RightSidebarKeyboardFocusView: NSView {
    override var acceptsFirstResponder: Bool { true }
    override var canBecomeKeyView: Bool { true }

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        guard let window else { return }
        AppDelegate.shared?.keyboardFocusCoordinator(for: window)?.registerRightSidebarHost(self)
#if DEBUG
        dlog(
            "rs.focus.host.attach win=\(window.windowNumber) canAccept=\(cmuxCanAcceptRightSidebarKeyboardFocus ? 1 : 0) " +
            "fr=\(rightSidebarDebugResponder(window.firstResponder))"
        )
#endif
    }

    func registerWithKeyboardFocusCoordinatorIfNeeded() {
        guard let window else { return }
        AppDelegate.shared?.keyboardFocusCoordinator(for: window)?.registerRightSidebarHost(self)
    }

    override func layout() {
        super.layout()
        registerWithKeyboardFocusCoordinatorIfNeeded()
    }

    override func keyDown(with event: NSEvent) {
        if let mode = AppDelegate.shared?.rightSidebarModeShortcut(for: event) {
            _ = AppDelegate.shared?.focusRightSidebarInActiveMainWindow(
                mode: mode,
                focusFirstItem: true,
                preferredWindow: window
            )
            return
        }
        if event.keyCode == 53 {
            if let window,
               AppDelegate.shared?.keyboardFocusCoordinator(for: window)?.focusTerminal() == true {
                return
            }
            window?.makeFirstResponder(nil)
            return
        }
        if let characters = event.charactersIgnoringModifiers, !characters.isEmpty {
            return
        }
        super.keyDown(with: event)
    }

    func focusHostFromCoordinator() -> Bool {
        guard let window else {
#if DEBUG
            dlog("rs.focus.host.focus result=0 reason=noWindow")
#endif
            return false
        }
        let result = window.makeFirstResponder(self)
#if DEBUG
        dlog(
            "rs.focus.host.focus result=\(result ? 1 : 0) win=\(window.windowNumber) " +
            "fr=\(rightSidebarDebugResponder(window.firstResponder))"
        )
#endif
        return result
    }
}

extension NSView {
    var cmuxCanAcceptRightSidebarKeyboardFocus: Bool {
        guard window != nil, !isHiddenOrHasHiddenAncestor else { return false }
        var view: NSView? = self
        while let current = view {
            if current.bounds.width <= 0.5 || current.bounds.height <= 0.5 {
                return false
            }
            view = current.superview
        }
        return true
    }
}
