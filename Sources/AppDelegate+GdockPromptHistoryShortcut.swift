import AppKit

extension AppDelegate {
    /// Routes the prompt-history chord (Cmd+Option+P by default).
    ///
    /// App-scoped rather than dock- or pane-scoped for the same reason as the
    /// session cycler: it reads whichever pane is focused app-wide
    /// (AX-GDOCK-PROMPT-HISTORY).
    func handleGdockPromptHistoryShortcut(event: NSEvent) -> Bool {
        guard matchConfiguredShortcut(event: event, action: .gdockShowPromptHistory) else {
            return false
        }
#if DEBUG
        cmuxDebugLog("shortcut.action name=gdockShowPromptHistory")
#endif
        // The event's own modifiers define the hold, so a rebound chord keeps
        // hold-to-view semantics without re-reading Settings here.
        GdockPromptHistoryPresenter.present(
            holdModifiers: event.modifierFlags.intersection(.deviceIndependentFlagsMask)
        )
        return true
    }
}
