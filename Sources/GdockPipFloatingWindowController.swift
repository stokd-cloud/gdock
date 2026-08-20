import AppKit
import Foundation
import Observation

/// Persisted "which windows are pinned" state for gdock PIP mode.
///
/// Keyed by the main window's stable `windowId` (the same UUID session restore
/// uses), so a window the user pinned comes back pinned after a relaunch. The
/// UserDefaults id carries the fork-required `gdock.` prefix (see CLAUDE.md) so
/// it can never collide with an upstream cmux key.
@MainActor
final class GdockPipFloatingWindowStore {
    static let userDefaultsKey = "gdock.pipFloatingWindowIds"

    private let defaults: UserDefaults

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    func isPinned(windowId: UUID) -> Bool {
        pinnedWindowIds().contains(windowId)
    }

    func pinnedWindowIds() -> Set<UUID> {
        // `stringArray(forKey:)` returns nil for any non-array value, so a
        // corrupted or hand-edited key degrades to "nothing pinned" instead of
        // trapping at launch.
        let raw = defaults.stringArray(forKey: Self.userDefaultsKey) ?? []
        return Set(raw.compactMap(UUID.init(uuidString:)))
    }

    /// Flips the pinned state for `windowId` and returns the new state.
    @discardableResult
    func togglePinned(windowId: UUID) -> Bool {
        let pinned = !isPinned(windowId: windowId)
        setPinned(pinned, windowId: windowId)
        return pinned
    }

    func setPinned(_ pinned: Bool, windowId: UUID) {
        var ids = pinnedWindowIds()
        if pinned {
            ids.insert(windowId)
        } else {
            ids.remove(windowId)
        }
        // Sorted so the persisted value is stable across writes.
        defaults.set(ids.map(\.uuidString).sorted(), forKey: Self.userDefaultsKey)
    }
}

/// Owns gdock "Keep Window on Top" (PIP) mode: the single path that pins a cmux
/// main window above its siblings and shows it on every Space, and the single
/// path that puts it back.
///
/// Every entrypoint (command palette, Window menu, and any future shortcut or
/// socket verb) routes through ``togglePinned(window:)`` rather than touching
/// `NSWindow.level` itself. That is what keeps the pin/unpin transition
/// reversible: this controller captures the window's level and collection
/// behavior *before* pinning and replays that snapshot on unpin, so a pinned
/// window can never be stranded floating with a guessed-at behavior — the class
/// of bug ``NSWindow/adoptCmuxPeerWindowLevel()`` documents (issue #5081).
@MainActor
final class GdockPipFloatingWindowController {
    static let shared = GdockPipFloatingWindowController()

    /// Fork convention (CLAUDE.md): gdock one-shot palette commands are
    /// namespaced `palette.gdock.*`.
    static let commandId = "palette.gdock.togglePipFloatingWindow"

    /// Posted after any pin/unpin so menu check state can refresh.
    static let didChangeNotification = Notification.Name("gdock.pipFloatingWindow.didChange")

    private struct WindowSnapshot {
        let level: NSWindow.Level
        let collectionBehavior: NSWindow.CollectionBehavior
    }

    private let store: GdockPipFloatingWindowStore
    private let notificationCenter: NotificationCenter

    /// Pre-pin window state, keyed by window id and held only while pinned.
    private var snapshots: [UUID: WindowSnapshot] = [:]

    // Defaults are nil rather than concrete values because default arguments are
    // evaluated in a nonisolated context, and both the store and `.shared` are
    // MainActor-isolated.
    init(
        store: GdockPipFloatingWindowStore? = nil,
        notificationCenter: NotificationCenter = .default
    ) {
        self.store = store ?? GdockPipFloatingWindowStore()
        self.notificationCenter = notificationCenter
    }

    // MARK: - Queries

    func isPinned(windowId: UUID) -> Bool {
        store.isPinned(windowId: windowId)
    }

    func isPinned(window: NSWindow) -> Bool {
        guard let windowId = resolvedWindowId(for: window) else { return false }
        return isPinned(windowId: windowId)
    }

    /// Whether the window the user is currently working in is pinned; drives the
    /// menu item's check state.
    func isFocusedWindowPinned() -> Bool {
        guard let window = focusedMainWindow() else { return false }
        return isPinned(window: window)
    }

    /// A PIP toggle only makes sense when there is a main window to pin.
    func canToggleFocusedWindow() -> Bool {
        focusedMainWindow() != nil
    }

    // MARK: - The single mutation path

    /// Flips PIP mode for `window` and returns the new pinned state, or nil when
    /// the window is not a cmux main window.
    @discardableResult
    func togglePinned(window: NSWindow) -> Bool? {
        guard let windowId = resolvedWindowId(for: window) else { return nil }
        let pinned = !store.isPinned(windowId: windowId)
        store.setPinned(pinned, windowId: windowId)
        applyPinnedState(pinned, to: window, windowId: windowId)
        notificationCenter.post(name: Self.didChangeNotification, object: window)
        return pinned
    }

    /// Entrypoint for surfaces that act on "the window I'm working in" — the
    /// command palette and the Window menu. Returns the new pinned state, or nil
    /// when no main window could be resolved.
    @discardableResult
    func toggleFocusedWindow() -> Bool? {
        guard let window = focusedMainWindow() else { return nil }
        return togglePinned(window: window)
    }

    /// Re-applies persisted PIP state to a main window that was just created or
    /// restored, so a pinned window comes back pinned after a relaunch.
    ///
    /// Takes the window id explicitly because a freshly created main window has
    /// not been given its `cmux.main.<uuid>` identifier yet at call time.
    func applyPersistedState(to window: NSWindow, windowId: UUID) {
        guard store.isPinned(windowId: windowId) else { return }
        applyPinnedState(true, to: window, windowId: windowId)
    }

    /// Drops the retained snapshot for a closed window. The persisted pinned
    /// state deliberately survives, so reopening the window restores PIP mode.
    func forgetSnapshot(windowId: UUID) {
        snapshots[windowId] = nil
    }

    // MARK: - Window mutation

    private func applyPinnedState(_ pinned: Bool, to window: NSWindow, windowId: UUID) {
        if pinned {
            // Capture once: a second pin of an already-pinned window must not
            // overwrite the original snapshot with the floating values.
            let snapshot = snapshots[windowId] ?? WindowSnapshot(
                level: window.level,
                collectionBehavior: window.collectionBehavior
            )
            snapshots[windowId] = snapshot
            window.collectionBehavior = GdockPipFloatingWindowPolicy
                .floatingCollectionBehavior(window.collectionBehavior)
            // Sanctioned `.floating` for a main window: see
            // GdockPipFloatingWindowPolicy.floatingLevel for the justification
            // required by NSWindow+CmuxPeerWindow (issue #5081). Always paired
            // with the restore below.
            window.level = GdockPipFloatingWindowPolicy.floatingLevel
        } else {
            let snapshot = snapshots.removeValue(forKey: windowId)
            window.collectionBehavior = GdockPipFloatingWindowPolicy.restoredCollectionBehavior(
                current: window.collectionBehavior,
                snapshot: snapshot?.collectionBehavior
                    // No snapshot means the window was pinned in a previous run
                    // and this process never captured one; fall back to the
                    // capability every main window is required to declare
                    // (issue #5933) rather than leaving it auxiliary-only.
                    ?? CmuxMainWindow.canonicalCollectionBehavior(window.collectionBehavior)
            )
            window.level = snapshot?.level ?? .normal
        }
    }

    // MARK: - Window resolution

    private func focusedMainWindow() -> NSWindow? {
        // `NSApp` is an implicitly-unwrapped global that is still nil while the
        // SwiftUI App value is being constructed (and in a unit-test host before
        // the application object exists), so bind it instead of dereferencing.
        guard let app = NSApp else { return nil }
        let candidates = [app.keyWindow, app.mainWindow] + app.orderedWindows
        for candidate in candidates {
            guard let candidate, candidate.isVisible else { continue }
            if resolvedWindowId(for: candidate) != nil {
                return candidate
            }
        }
        return nil
    }

    /// Prefers AppDelegate's registered window context (authoritative, and
    /// available before SwiftUI stamps the window identifier) and falls back to
    /// parsing the identifier.
    private func resolvedWindowId(for window: NSWindow) -> UUID? {
        if let windowId = AppDelegate.shared?.registeredMainWindowId(for: window) {
            return windowId
        }
        return Self.mainWindowId(for: window)
    }

    /// The stable window id encoded in a main window's identifier
    /// (`cmux.main.<uuid>`), matching `AppDelegate`'s own resolution.
    static func mainWindowId(for window: NSWindow) -> UUID? {
        guard let raw = window.identifier?.rawValue,
              raw.hasPrefix("cmux.main.") else { return nil }
        return UUID(uuidString: String(raw.dropFirst("cmux.main.".count)))
    }
}

/// Menu-facing view of PIP state.
///
/// The Window menu needs a checkmark that tracks *the focused window*, which
/// changes both when the user toggles PIP and when they switch windows. This
/// republishes those two events as observable state; it never stores whether a
/// window is pinned, it always asks ``GdockPipFloatingWindowController`` — so
/// the menu cannot drift from the controller that owns the behavior.
@MainActor
@Observable
final class GdockPipFloatingWindowMenuState {
    static let shared = GdockPipFloatingWindowMenuState()

    private(set) var isFocusedWindowPinned: Bool = false
    private(set) var canToggle: Bool = false

    @ObservationIgnored private var observers: [NSObjectProtocol] = []

    init(
        controller: GdockPipFloatingWindowController? = nil,
        notificationCenter: NotificationCenter = .default
    ) {
        let controller = controller ?? GdockPipFloatingWindowController.shared
        self.controller = controller
        self.notificationCenter = notificationCenter
        for name: Notification.Name in [
            GdockPipFloatingWindowController.didChangeNotification,
            NSWindow.didBecomeKeyNotification,
            NSWindow.didResignKeyNotification,
        ] {
            let observer = notificationCenter.addObserver(
                forName: name,
                object: nil,
                queue: .main
            ) { [weak self] _ in
                MainActor.assumeIsolated {
                    self?.refresh()
                }
            }
            observers.append(observer)
        }
        // Deliberately no refresh() here: this singleton is constructed while
        // the SwiftUI App value is initializing, before NSApp exists. The first
        // menu read (or any window/pin notification) resolves the real state.
    }

    // No deinit: this is an app-lifetime singleton, so its observers are
    // intentionally never torn down (matching the other *Controller.shared
    // observers in the app).

    @ObservationIgnored private let controller: GdockPipFloatingWindowController
    @ObservationIgnored private let notificationCenter: NotificationCenter

    func refresh() {
        isFocusedWindowPinned = controller.isFocusedWindowPinned()
        canToggle = controller.canToggleFocusedWindow()
    }

    /// The single action the menu item performs; delegates to the controller so
    /// menu, palette, and any future surface share one mutation path.
    func toggleFocusedWindow() {
        controller.toggleFocusedWindow()
        refresh()
    }
}
