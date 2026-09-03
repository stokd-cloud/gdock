import AppKit
import SwiftUI

/// Hosts the prompt-history overlay in its own floating panel.
///
/// A panel rather than an in-window overlay, and a *non-activating* one: the
/// chord is a glance while the operator keeps typing, so the terminal must keep
/// key focus the whole time it is up (`cmux-socket-policy`: never steal focus).
///
/// Two presentation modes share this one controller: held (the chord, dismissed
/// when its modifiers come up) and sticky (the palette, dismissed by Escape, a
/// click elsewhere, or the app deactivating).
@MainActor
final class GdockPromptHistoryWindowController: NSObject, NSWindowDelegate {
    static let shared = GdockPromptHistoryWindowController()

    /// How many pages of persisted history to page in before giving up. The
    /// in-memory ring is dominated by tool telemetry, so a busy session's older
    /// prompts routinely sit one or two pages back.
    private static let maxBackfillPages = 3

    private let model = GdockPromptHistoryViewModel()
    private var panel: NSPanel?
    private var flagsMonitor: Any?
    private var keyMonitor: Any?
    private var mouseMonitor: Any?
    private var backfillTask: Task<Void, Never>?
    /// Modifiers whose release closes the overlay; nil in sticky mode.
    private var holdModifiers: NSEvent.ModifierFlags?
    private weak var referenceWindow: NSWindow?

    var isVisible: Bool { panel?.isVisible == true }

    // MARK: - Presenting

    /// Shows the overlay, or refreshes it when it is already up.
    ///
    /// - Parameter holdModifiers: The chord's modifiers, so releasing them
    ///   dismisses. `nil` presents until Escape or a click elsewhere.
    func present(holdModifiers: NSEvent.ModifierFlags?) {
        if isVisible {
            // Auto-repeat from a held chord lands here; refresh rather than
            // rebuild so the panel does not flicker under the operator's hand.
            self.holdModifiers = holdModifiers ?? self.holdModifiers
            reload()
            return
        }

        self.holdModifiers = holdModifiers
        referenceWindow = NSApp.keyWindow ?? NSApp.mainWindow
        model.reset()
        show()
        reload()
        scheduleBackfill()
    }

    func dismiss() {
        backfillTask?.cancel()
        backfillTask = nil
        removeMonitors()
        holdModifiers = nil
        panel?.orderOut(nil)
        referenceWindow = nil
    }

    // MARK: - Data

    private func reload() {
        guard let panel else { return }
        let metrics = GdockPromptHistoryLayout.Metrics.standard
        let contentHeight = panel.contentLayoutRect.height

        guard let focus = currentFocus() else {
            model.apply(visible: [], totalCount: 0, sessionTitle: "")
            return
        }

        let items = FeedCoordinator.shared.store?.items ?? []
        let entries = GdockPromptHistoryCollector.entries(
            items: items,
            focus: focus.identity,
            resolveTarget: resolveTarget(workstreamId:)
        )
        model.apply(
            visible: GdockPromptHistoryLayout.visibleEntries(
                entries,
                contentHeight: contentHeight,
                metrics: metrics
            ),
            totalCount: entries.count,
            sessionTitle: focus.title
        )
    }

    /// Pages older persisted history in until the panel is full.
    ///
    /// The Feed store loads a bounded window at launch, and tool telemetry
    /// crowds prompts out of it; without this the overlay looks empty for a
    /// session that has been running all day.
    private func scheduleBackfill() {
        backfillTask?.cancel()
        backfillTask = Task { @MainActor [weak self] in
            guard let store = FeedCoordinator.shared.store else { return }
            for _ in 0..<Self.maxBackfillPages {
                guard let self, self.isVisible, !Task.isCancelled else { return }
                guard self.model.hiddenCount == 0, store.hasMorePersistedItems else { return }
                await store.loadOlderItems()
                guard self.isVisible, !Task.isCancelled else { return }
                self.reload()
            }
        }
    }

    private struct FocusedSession {
        let identity: GdockPromptHistoryFocus
        let title: String
    }

    /// The pane whose prompts the overlay shows: the focused panel of the
    /// selected workspace in the window the operator came from.
    private func currentFocus() -> FocusedSession? {
        let contexts = AppDelegate.shared?.mainWindowContexts.values
        guard let context = contexts?.first(where: { $0.window === referenceWindow })
            ?? contexts?.first(where: { $0.window?.isKeyWindow == true })
            ?? contexts?.first else { return nil }

        let tabManager = context.tabManager
        guard let selectedId = tabManager.selectedTabId,
              let workspace = tabManager.tabs.first(where: { $0.id == selectedId }),
              let panelId = workspace.focusedPanelId else { return nil }

        let panelTitle = workspace.panelTitles[panelId]?
            .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return FocusedSession(
            identity: GdockPromptHistoryFocus(
                workspaceId: workspace.id,
                panelId: panelId,
                directory: workspace.panelDirectories[panelId]
            ),
            title: panelTitle.isEmpty ? workspace.title : panelTitle
        )
    }

    /// Reads the per-agent hook session stores through the same resolver the
    /// Feed uses to jump to a workstream, so a prompt lands on the pane the rest
    /// of the app agrees it belongs to.
    private func resolveTarget(workstreamId: String) -> GdockPromptHistoryTarget? {
        guard let parsed = FeedJumpResolver.parse(workstreamId),
              let target = FeedJumpResolver.lookup(agent: parsed.agent, sessionId: parsed.sessionId),
              let workspaceId = UUID(uuidString: target.workspaceId),
              let surfaceId = UUID(uuidString: target.surfaceId) else { return nil }
        return GdockPromptHistoryTarget(workspaceId: workspaceId, surfaceId: surfaceId)
    }

    // MARK: - Window

    private func show() {
        let panel = panel ?? makePanel()
        self.panel = panel
        position(panel)
        // Never `makeKey`: the operator is still typing in the terminal behind
        // this, and a held chord that stole focus would swallow their input.
        panel.orderFrontRegardless()
        installMonitors()
    }

    private func makePanel() -> NSPanel {
        let panel = NSPanel(
            contentRect: NSRect(x: 0, y: 0, width: 560, height: 280),
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = true
        panel.level = .floating
        panel.hidesOnDeactivate = true
        panel.ignoresMouseEvents = true
        panel.animationBehavior = .utilityWindow
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        panel.delegate = self

        let host = NSHostingView(rootView: GdockPromptHistoryOverlayView(model: model))
        host.translatesAutoresizingMaskIntoConstraints = false
        let container = NSView()
        container.addSubview(host)
        NSLayoutConstraint.activate([
            host.topAnchor.constraint(equalTo: container.topAnchor),
            host.bottomAnchor.constraint(equalTo: container.bottomAnchor),
            host.leadingAnchor.constraint(equalTo: container.leadingAnchor),
            host.trailingAnchor.constraint(equalTo: container.trailingAnchor),
        ])
        panel.contentView = container
        return panel
    }

    /// Sized and centered against the window the operator came from, so the
    /// overlay scales with their layout instead of being a fixed postage stamp.
    private func position(_ panel: NSPanel) {
        let reference = referenceWindow?.frame
            ?? NSScreen.main?.visibleFrame
            ?? NSRect(x: 0, y: 0, width: 1280, height: 800)
        let size = NSSize(
            width: min(max(reference.width * 0.5, 420), 760),
            height: min(max(reference.height * 0.45, 180), 520)
        )
        panel.setContentSize(size)
        panel.setFrameOrigin(
            NSPoint(
                x: reference.midX - size.width / 2,
                y: reference.midY - size.height / 2
            )
        )
    }

    // MARK: - Monitors

    private func installMonitors() {
        if flagsMonitor == nil {
            flagsMonitor = NSEvent.addLocalMonitorForEvents(matching: .flagsChanged) { [weak self] event in
                self?.handleFlagsChanged(event)
                return event
            }
        }
        if keyMonitor == nil {
            keyMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
                guard let self, self.isVisible else { return event }
                // Escape closes; every other key belongs to the terminal the
                // operator is still typing into.
                guard event.keyCode == 53 else { return event }
                self.dismiss()
                return nil
            }
        }
        if mouseMonitor == nil, holdModifiers == nil {
            mouseMonitor = NSEvent.addLocalMonitorForEvents(matching: [.leftMouseDown, .rightMouseDown]) { [weak self] event in
                self?.dismiss()
                return event
            }
        }
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(handleAppResignActive),
            name: NSApplication.didResignActiveNotification,
            object: nil
        )
    }

    private func removeMonitors() {
        for monitor in [flagsMonitor, keyMonitor, mouseMonitor].compactMap({ $0 }) {
            NSEvent.removeMonitor(monitor)
        }
        flagsMonitor = nil
        keyMonitor = nil
        mouseMonitor = nil
        NotificationCenter.default.removeObserver(
            self,
            name: NSApplication.didResignActiveNotification,
            object: nil
        )
    }

    /// Hold semantics: the overlay lives exactly as long as the chord's
    /// modifiers are down. Matching against the modifiers that opened it keeps
    /// this correct after the shortcut is rebound in Settings.
    private func handleFlagsChanged(_ event: NSEvent) {
        guard isVisible, let holdModifiers else { return }
        let active = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
        guard !active.isSuperset(of: holdModifiers) else { return }
        dismiss()
    }

    @objc private func handleAppResignActive() {
        guard isVisible else { return }
        dismiss()
    }
}
