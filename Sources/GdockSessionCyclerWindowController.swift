import AppKit
import SwiftUI

/// Hosts the cycler overlay in its own floating panel.
///
/// A panel rather than an in-window overlay: sessions routinely live in other
/// windows, so the cycler is app-scoped and must outlive whichever window
/// happened to be key when it opened. Focus returns to that window on dismiss.
@MainActor
final class GdockSessionCyclerWindowController: NSObject, NSWindowDelegate {
    static let shared = GdockSessionCyclerWindowController()

    private let model = GdockSessionCyclerViewModel()
    private var panel: NSPanel?
    private var keyMonitor: Any?
    private weak var restoreKeyWindow: NSWindow?

    var isVisible: Bool { panel?.isVisible == true }

    // MARK: - Presenting

    /// Opens the cycler if it is closed, then moves the highlight by `offset`.
    ///
    /// Repeat chord presses land here, so holding the chord walks the list the
    /// way the operator expects rather than reopening the overlay each time.
    func cycle(by offset: Int) {
        if isVisible {
            reloadSessions(preservingSelection: true)
            model.moveSelection(by: offset)
            return
        }

        restoreKeyWindow = NSApp.keyWindow
        reloadSessions(preservingSelection: false)
        // The chord's first press should already be a move: opening on the
        // session you are looking at and requiring a second press reads as a
        // dead key.
        model.moveSelection(by: offset)
        show()
    }

    func dismiss() {
        removeKeyMonitor()
        panel?.orderOut(nil)
        restoreKeyWindow?.makeKeyAndOrderFront(nil)
        restoreKeyWindow = nil
    }

    // MARK: - Data

    private func reloadSessions(preservingSelection: Bool) {
        let contexts = AppDelegate.shared?.mainWindowContexts.values.map(\.tabManager) ?? []
        let keyTabManager = AppDelegate.shared?.mainWindowContexts.values
            .first(where: { $0.window === (restoreKeyWindow ?? NSApp.keyWindow) })?
            .tabManager

        model.sessions = GdockSessionCyclerCollector.sessions(tabManagers: contexts)
        model.currentRepoSlug = GdockSessionCyclerCollector.currentRepoSlug(
            tabManager: keyTabManager ?? contexts.first
        )
        model.isGroupedRepoModeEnabled = GdockAutoWorkspaceGroupModeSettings.isEnabled()
        if !preservingSelection {
            model.query = ""
            model.scope = .currentRepo
            model.selectedPanelId = focusedPanelId(in: keyTabManager)
        }
    }

    private func focusedPanelId(in tabManager: TabManager?) -> UUID? {
        guard let tabManager,
              let selectedId = tabManager.selectedTabId,
              let workspace = tabManager.tabs.first(where: { $0.id == selectedId }) else {
            return nil
        }
        return workspace.focusedPanelId
    }

    // MARK: - Window

    private func show() {
        let panel = panel ?? makePanel()
        self.panel = panel
        position(panel)
        panel.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: false)
        installKeyMonitor()
    }

    private func makePanel() -> NSPanel {
        let panel = NSPanel(
            contentRect: NSRect(x: 0, y: 0, width: 560, height: 240),
            styleMask: [.titled, .fullSizeContentView, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        panel.titleVisibility = .hidden
        panel.titlebarAppearsTransparent = true
        panel.isMovableByWindowBackground = true
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = true
        panel.level = .floating
        panel.hidesOnDeactivate = true
        panel.animationBehavior = .utilityWindow
        panel.delegate = self
        panel.standardWindowButton(.closeButton)?.isHidden = true
        panel.standardWindowButton(.miniaturizeButton)?.isHidden = true
        panel.standardWindowButton(.zoomButton)?.isHidden = true

        let host = NSHostingView(
            rootView: GdockSessionCyclerOverlayView(
                model: model,
                onActivate: { [weak self] session in self?.activate(session) },
                onDismiss: { [weak self] in self?.dismiss() }
            )
        )
        host.translatesAutoresizingMaskIntoConstraints = false
        panel.contentView = NSView()
        panel.contentView?.addSubview(host)
        if let contentView = panel.contentView {
            NSLayoutConstraint.activate([
                host.topAnchor.constraint(equalTo: contentView.topAnchor),
                host.bottomAnchor.constraint(equalTo: contentView.bottomAnchor),
                host.leadingAnchor.constraint(equalTo: contentView.leadingAnchor),
                host.trailingAnchor.constraint(equalTo: contentView.trailingAnchor),
            ])
        }
        return panel
    }

    /// Centers over the window the operator came from, or the main screen.
    private func position(_ panel: NSPanel) {
        panel.setContentSize(NSSize(width: 560, height: 320))
        guard let reference = restoreKeyWindow?.frame ?? NSScreen.main?.visibleFrame else {
            panel.center()
            return
        }
        let size = panel.frame.size
        let origin = NSPoint(
            x: reference.midX - size.width / 2,
            y: reference.midY - size.height / 2 + reference.height * 0.15
        )
        panel.setFrameOrigin(origin)
    }

    /// Clicking away closes the cycler, the way the palette does.
    ///
    /// Guarded on visibility because `dismiss()` orders the panel out, which
    /// posts this notification again.
    func windowDidResignKey(_ notification: Notification) {
        guard (notification.object as? NSWindow) === panel, isVisible else { return }
        dismiss()
    }

    // MARK: - Keys

    private func installKeyMonitor() {
        guard keyMonitor == nil else { return }
        keyMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            guard let self, self.isVisible else { return event }
            return self.handle(event) ? nil : event
        }
    }

    private func removeKeyMonitor() {
        if let keyMonitor { NSEvent.removeMonitor(keyMonitor) }
        keyMonitor = nil
    }

    /// Returns true when the event was consumed.
    private func handle(_ event: NSEvent) -> Bool {
        // While the overlay is up the chord keeps cycling, so the operator can
        // hold Cmd+Shift and tap brackets instead of reopening it per step.
        if let appDelegate = AppDelegate.shared {
            if appDelegate.matchConfiguredShortcut(event: event, action: .gdockCycleSessionsNext) {
                model.moveSelection(by: 1)
                return true
            }
            if appDelegate.matchConfiguredShortcut(event: event, action: .gdockCycleSessionsPrev) {
                model.moveSelection(by: -1)
                return true
            }
        }

        switch event.keyCode {
        case 53: // escape
            dismiss()
            return true
        case 36, 76: // return, keypad enter
            if let session = model.listing.highlightedSession { activate(session) }
            return true
        case 125: // down
            model.moveSelection(by: 1)
            return true
        case 126: // up
            model.moveSelection(by: -1)
            return true
        case 124: // right
            model.moveScope(by: 1)
            return true
        case 123: // left
            model.moveScope(by: -1)
            return true
        default:
            return false
        }
    }

    // MARK: - Activation

    private func activate(_ session: GdockCyclableSession) {
        defer { dismiss() }
        guard let context = AppDelegate.shared?.mainWindowContexts.values.first(where: { context in
            context.tabManager.tabs.contains(where: { $0.id == session.workspaceId })
        }) else { return }

        restoreKeyWindow = nil
        context.window?.makeKeyAndOrderFront(nil)
        context.tabManager.focusPanel(workspaceId: session.workspaceId, panelId: session.panelId)
    }
}
