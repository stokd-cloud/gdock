import AppKit
import Foundation
import os

/// Exhaustive actor-facing selection inventory for VAL-RAIL-009.
///
/// Every production right-sidebar selection path should pass through
/// ``RightSidebarSelectionRouter/apply(_:in:)`` (or the window-bound helper on
/// ``AppDelegate``) so rail / non-rail / flag-off routing stays one seam.
enum RightSidebarSelectionSource: String, CaseIterable, Sendable {
    case modeTabClick
    case shortcutApp
    case shortcutWindow
    case shortcutTerminal
    case shortcutFileExplorer
    case shortcutDock
    case paletteFiles
    case paletteFind
    case paletteVault
    case paletteFeed
    case paletteDock
    case paletteStokdWork
    case findInDirectory
    case contextualFind
    case remoteSet
    case remoteSetNoFocus
    case debugFocus
    case debugReveal
    case dockPlacementReveal
    case availabilityClamp
    case railTabSelect
    case railPaneFocus
    case sessionRestore
    case namedLayoutApply
    case crossRailMove
}

/// One window-scoped selection request.
struct RightSidebarSelectionRequest: Equatable, Sendable {
    var mode: RightSidebarMode
    /// When false, updates selection without forcing keyboard focus / window activation
    /// (CLI `--no-focus`, remote set without focus).
    var focus: Bool
    var source: RightSidebarSelectionSource
    /// Optional target window; nil means the active / preferred main window.
    var windowId: UUID?

    init(
        mode: RightSidebarMode,
        focus: Bool = true,
        source: RightSidebarSelectionSource,
        windowId: UUID? = nil
    ) {
        self.mode = mode
        self.focus = focus
        self.source = source
        self.windowId = windowId
    }
}

/// Mutable window targets the router operates on (production or test fixtures).
@MainActor
struct RightSidebarSelectionContext {
    let windowId: UUID
    var fileExplorerState: FileExplorerState
    var rightStore: SidebarDockStore?
    var isDockEnabled: Bool
    /// Invoked for feed/dock (and flag-off focus) when `focus` is true.
    var focusRightSidebar: ((RightSidebarMode) -> Bool)?
    /// Invoked when a rail tool should also receive keyboard focus.
    var focusRailTool: ((RightSidebarMode) -> Bool)?
    /// Ensures the right rail host is visible when selection requires presentation.
    var ensureVisible: (() -> Void)?

    init(
        windowId: UUID,
        fileExplorerState: FileExplorerState,
        rightStore: SidebarDockStore? = nil,
        isDockEnabled: Bool = false,
        focusRightSidebar: ((RightSidebarMode) -> Bool)? = nil,
        focusRailTool: ((RightSidebarMode) -> Bool)? = nil,
        ensureVisible: (() -> Void)? = nil
    ) {
        self.windowId = windowId
        self.fileExplorerState = fileExplorerState
        self.rightStore = rightStore
        self.isDockEnabled = isDockEnabled
        self.focusRightSidebar = focusRightSidebar
        self.focusRailTool = focusRailTool
        self.ensureVisible = ensureVisible
    }
}

/// Outcome of a routed selection.
enum RightSidebarSelectionRoute: Equatable, Sendable {
    /// Flag-off: legacy `FileExplorerState.mode` write path.
    case legacyModeWrite
    /// Flag-on rail tool: store select/focus; mirror comes from Bonsplit callbacks only.
    case railStoreSelect
    /// Flag-on excluded mode: preserved non-rail presentation (Feed / Dock / custom).
    case nonRailPresentation
    /// Request could not be applied (unavailable mode, missing store, wrong window).
    case rejected
}

/// Single window-scoped selection seam (VAL-RAIL-009).
@MainActor
enum RightSidebarSelectionRouter {
    private static let logger = Logger(subsystem: "ai.manaflow.cmux", category: "RightSidebarSelectionRouter")

    /// Apply a selection request against an explicit context (unit-testable).
    @discardableResult
    static func apply(
        _ request: RightSidebarSelectionRequest,
        in context: inout RightSidebarSelectionContext
    ) -> RightSidebarSelectionRoute {
        if let target = request.windowId, target != context.windowId {
            let contextWindowId = context.windowId
            logger.info(
                "right-sidebar selection rejected: wrong window request=\(target.uuidString, privacy: .public) context=\(contextWindowId.uuidString, privacy: .public) source=\(request.source.rawValue, privacy: .public)"
            )
            return .rejected
        }

        if !request.mode.isAvailable(), request.source != .availabilityClamp {
            logger.info(
                "right-sidebar selection rejected: mode unavailable \(request.mode.rawValue, privacy: .public) source=\(request.source.rawValue, privacy: .public)"
            )
            return .rejected
        }

        // Flag off → byte-behavior legacy path.
        if !context.isDockEnabled {
            ensurePresentationVisibleIfNeeded(request: request, context: &context)
            context.fileExplorerState.mode = request.mode
            if request.focus {
                _ = context.focusRightSidebar?(request.mode)
            }
            return .legacyModeWrite
        }

        // Flag on + rail tool → store is sole selection source of truth.
        if SidebarDockPlacementMatrix.allows(mode: request.mode) {
            guard let store = context.rightStore, store.edge == .right else {
                logger.error("right-sidebar selection: dock enabled but no right store")
                return .rejected
            }
            ensurePresentationVisibleIfNeeded(request: request, context: &context)
            let selected = store.selectToolMode(request.mode, focus: request.focus)
            if !selected {
                // Missing panel: create rather than no-op when a workspace is available.
                if let workspace = AppDelegate.shared?
                    .tabManagerFor(windowId: context.windowId)?
                    .selectedWorkspace
                {
                    let panel = RightSidebarToolPanel(workspace: workspace, mode: request.mode)
                    if store.attachPanel(panel, select: true) == nil {
                        return .rejected
                    }
                } else {
                    // Test fixtures without AppDelegate / missing panel: refuse cleanly.
                    return .rejected
                }
            }
            if request.focus {
                _ = context.focusRailTool?(request.mode) ?? context.focusRightSidebar?(request.mode)
            }
            return .railStoreSelect
        }

        // Flag on + excluded modes: preserve non-rail entrypoints (D-19 / VAL-FLAG-003).
        ensurePresentationVisibleIfNeeded(request: request, context: &context)
        // Feed/Dock are not rail modes — presentation still uses `mode` as the host switch.
        context.fileExplorerState.mode = request.mode
        if request.focus {
            _ = context.focusRightSidebar?(request.mode)
        }
        return .nonRailPresentation
    }

    /// Map a mode to the palette source token used by VAL-RAIL-009 inventory tests.
    static func paletteSource(for mode: RightSidebarMode) -> RightSidebarSelectionSource {
        switch mode {
        case .files: return .paletteFiles
        case .find: return .paletteFind
        case .sessions: return .paletteVault
        case .feed: return .paletteFeed
        case .dock: return .paletteDock
        case .stokdWork: return .paletteStokdWork
        case .customSidebar: return .paletteDock
        // The not-yet-shipped stokd kinds share the files palette source token for
        // inventory; seed/selection is rail-command driven rather than legacy
        // mode-bar only.
        case .stokdWorktrees, .stokdGlobalConfig, .stokdUsage:
            return .paletteFiles
        }
    }

    /// Sources that participate in the exhaustive VAL-RAIL-009 inventory.
    static var inventorySources: [RightSidebarSelectionSource] {
        RightSidebarSelectionSource.allCases
    }

    private static func ensurePresentationVisibleIfNeeded(
        request: RightSidebarSelectionRequest,
        context: inout RightSidebarSelectionContext
    ) {
        // no-focus remote set on an already-visible host only changes selection;
        // when hidden, show the host so the mode is reachable without requiring
        // keyboard focus (matches existing remote set semantics).
        if !context.fileExplorerState.isVisible {
            if let ensureVisible = context.ensureVisible {
                ensureVisible()
            } else {
                context.fileExplorerState.setVisible(true)
            }
        }
        _ = request
    }
}

// MARK: - AppDelegate window seam

extension AppDelegate {
    /// Window-scoped selection entry used by every production adapter.
    @discardableResult
    func routeRightSidebarSelection(_ request: RightSidebarSelectionRequest) -> RightSidebarSelectionRoute {
        let contextPair = rightSidebarSelectionContext(for: request.windowId)
        guard var selectionContext = contextPair else {
            return .rejected
        }
        let route = RightSidebarSelectionRouter.apply(request, in: &selectionContext)
        return route
    }

    private func rightSidebarSelectionContext(
        for windowId: UUID?
    ) -> RightSidebarSelectionContext? {
        let context: MainWindowContext?
        if let windowId {
            context = mainWindowContexts.values.first(where: { $0.windowId == windowId })
        } else {
            context = preferredRegisteredMainWindowContext()
        }
        guard let context,
              let state = context.fileExplorerState ?? fileExplorerState
        else {
            return nil
        }
        let store = context.sidebarDockRegistry?.right
        let isDock =
            RightSidebarBetaFeatureSettings.isSidebarDockEnabled()
            && RightSidebarDockPresentationSettings.isStackedTabsEnabled()
        let windowIdResolved = context.windowId
        return RightSidebarSelectionContext(
            windowId: windowIdResolved,
            fileExplorerState: state,
            rightStore: store,
            isDockEnabled: isDock,
            focusRightSidebar: { [weak self] mode in
                guard let self else { return false }
                let preferred = context.window ?? self.windowForMainWindowId(windowIdResolved)
                return self.focusRightSidebarInActiveMainWindow(
                    mode: mode,
                    focusFirstItem: true,
                    preferredWindow: preferred
                )
            },
            ensureVisible: { [weak self] in
                guard let self else { return }
                if !state.isVisible {
                    let preferred = context.window ?? self.windowForMainWindowId(windowIdResolved)
                    _ = self.toggleRightSidebarInActiveMainWindow(preferredWindow: preferred)
                    if !state.isVisible {
                        state.setVisible(true)
                    }
                }
            }
        )
    }
}
