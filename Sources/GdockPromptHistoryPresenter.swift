import AppKit

/// The single entrypoint every surface uses to show the prompt-history overlay.
///
/// The chord and the command palette both call here rather than driving the
/// panel themselves — one shared action path, per `CLAUDE.md`.
@MainActor
enum GdockPromptHistoryPresenter {
    /// Shows the overlay for as long as `holdModifiers` stay down. Pass `nil`
    /// (the palette's case, where there is no chord to release) to keep it up
    /// until Escape, a click, or the app deactivating.
    static func present(holdModifiers: NSEvent.ModifierFlags?) {
        GdockPromptHistoryWindowController.shared.present(holdModifiers: holdModifiers)
    }

    static func dismiss() {
        GdockPromptHistoryWindowController.shared.dismiss()
    }

    static var isVisible: Bool {
        GdockPromptHistoryWindowController.shared.isVisible
    }
}
