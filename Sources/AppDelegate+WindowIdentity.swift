import AppKit
import Foundation

@MainActor
extension AppDelegate {
    func mainWindow(for windowId: UUID) -> NSWindow? {
        windowForMainWindowId(windowId)
    }

    func windowForMainWindowId(_ windowId: UUID) -> NSWindow? {
        if let ctx = mainWindowContexts.values.first(where: { $0.windowId == windowId }),
           let window = ctx.window {
            return window
        }
        let expectedIdentifier = "cmux.main.\(windowId.uuidString)"
        return NSApp.windows.first(where: { $0.identifier?.rawValue == expectedIdentifier })
    }

    /// The stable window id for a main window: the registered context when the
    /// window is known, otherwise the id encoded in its `cmux.main.<uuid>`
    /// identifier. Returns nil for anything that is not a cmux main window.
    func registeredMainWindowId(for window: NSWindow) -> UUID? {
        if let context = mainWindowContexts[ObjectIdentifier(window)] {
            return context.windowId
        }
        guard let raw = window.identifier?.rawValue,
              raw.hasPrefix("cmux.main.") else { return nil }
        return UUID(uuidString: String(raw.dropFirst("cmux.main.".count)))
    }

    func startupPrimaryWindowIdForInitialMainWindow() -> UUID? {
        guard !didAttemptStartupSessionRestore else { return nil }
        guard !didHandleExplicitOpenIntentAtStartup else { return nil }
        return startupSessionSnapshot?.windows.first?.windowId
    }

    func availableWindowIdForNewMainWindow(preferredWindowId: UUID?) -> UUID? {
        guard let preferredWindowId else { return nil }
        guard !mainWindowContexts.values.contains(where: { $0.windowId == preferredWindowId }) else { return nil }
        return preferredWindowId
    }

    func refreshWindowTitlesAcrossMainWindows() {
        var seenManagers = Set<ObjectIdentifier>()
        for context in mainWindowContexts.values {
            let identifier = ObjectIdentifier(context.tabManager)
            guard seenManagers.insert(identifier).inserted else { continue }
            context.tabManager.refreshWindowTitle()
        }
    }
}
