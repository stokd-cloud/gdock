import AppKit
import Bonsplit
import Foundation

/// Single production entrypoint for palette, context-menu, and section-header rail commands.
///
/// All actor surfaces must call through here so `SidebarDockCommand.perform` has real
/// production call sites (VAL-RAIL-001/003/005/007/008). Focus is resolved from the
/// existing per-window registry — never a second selection store.
@MainActor
enum SidebarDockActionInvoker {
    /// Resolved rail target for one command invocation.
    struct Target {
        let store: SidebarDockStore
        let tabId: TabID?
        let paneId: PaneID?
    }

    /// RED stub: production wiring lands in the green commit. Tests assert this routes to
    /// `SidebarDockCommand.perform` and mutates the store.
    @discardableResult
    static func perform(
        commandId: String,
        store: SidebarDockStore,
        tabId: TabID?,
        paneId: PaneID?
    ) -> Bool {
        // Intentionally unconnected until green wiring.
        _ = commandId
        _ = store
        _ = tabId
        _ = paneId
        return false
    }

    /// Resolve focused edge/pane/tab from the per-window registry without a parallel store.
    static func resolveTarget(
        registry: SidebarDockStoreRegistry,
        preferredEdge: SidebarDockEdge? = nil
    ) -> Target? {
        let edge = preferredEdge ?? registry.lastFocusedEdge ?? .right
        let preferred = registry.store(for: edge)
        let fallback = edge == .right ? registry.left : registry.right
        let store: SidebarDockStore = {
            if preferred.sectionCount > 0 { return preferred }
            if fallback.sectionCount > 0 { return fallback }
            return preferred
        }()
        guard store.sectionCount > 0 else { return nil }

        let paneId = store.bonsplitController.focusedPaneId
            ?? store.orderedSectionPaneIds().first
        let tabId: TabID? = {
            if let paneId {
                return store.bonsplitController.selectedTab(inPane: paneId)?.id
                    ?? store.bonsplitController.tabs(inPane: paneId).first?.id
            }
            return store.bonsplitController.allTabIds.first
        }()
        return Target(store: store, tabId: tabId, paneId: paneId)
    }

    /// Resolve from the live app window graph (palette / global commands).
    static func resolveTarget(
        windowId: UUID?,
        preferredWindow: NSWindow?,
        preferredEdge: SidebarDockEdge? = nil
    ) -> Target? {
        guard RightSidebarBetaFeatureSettings.isSidebarDockEnabled() else { return nil }
        guard let registry = resolveRegistry(windowId: windowId, preferredWindow: preferredWindow) else {
            return nil
        }
        return resolveTarget(registry: registry, preferredEdge: preferredEdge)
    }

    static func resolveRegistry(
        windowId: UUID?,
        preferredWindow: NSWindow?
    ) -> SidebarDockStoreRegistry? {
        guard let app = AppDelegate.shared else { return nil }
        if let windowId,
           let match = app.mainWindowContexts.values.first(where: { $0.windowId == windowId }),
           let registry = match.sidebarDockRegistry {
            return registry
        }
        let window = preferredWindow ?? NSApp.keyWindow ?? NSApp.mainWindow
        if let window,
           let match = app.mainWindowContexts.values.first(where: { $0.window === window }),
           let registry = match.sidebarDockRegistry {
            return registry
        }
        return app.mainWindowContexts.values.compactMap(\.sidebarDockRegistry).first
    }

    /// Run a command against the focused rail target for a window.
    @discardableResult
    static func performFocused(
        commandId: String,
        windowId: UUID?,
        preferredWindow: NSWindow?,
        preferredEdge: SidebarDockEdge? = nil
    ) -> Bool {
        guard let target = resolveTarget(
            windowId: windowId,
            preferredWindow: preferredWindow,
            preferredEdge: preferredEdge
        ) else {
            return false
        }
        return perform(
            commandId: commandId,
            store: target.store,
            tabId: target.tabId,
            paneId: target.paneId
        )
    }
}
