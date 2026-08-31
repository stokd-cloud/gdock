import AppKit

extension AppDelegate {
    /// Routes the session-cycler chords (Cmd+Shift+] / Cmd+Shift+[ by default).
    ///
    /// App-scoped rather than window- or dock-scoped: the cycler lists sessions
    /// in every window, so it must not be resolved against whichever pane or
    /// dock happens to hold focus (AX-GDOCK-SESSION-CYCLER).
    func handleGdockSessionCyclerShortcut(event: NSEvent) -> Bool {
        if matchConfiguredShortcut(event: event, action: .gdockCycleSessionsNext) {
#if DEBUG
            cmuxDebugLog("shortcut.action name=gdockCycleSessionsNext")
#endif
            GdockSessionCyclerPresenter.cycle(by: 1)
            return true
        }
        if matchConfiguredShortcut(event: event, action: .gdockCycleSessionsPrev) {
#if DEBUG
            cmuxDebugLog("shortcut.action name=gdockCycleSessionsPrev")
#endif
            GdockSessionCyclerPresenter.cycle(by: -1)
            return true
        }
        return false
    }
}
