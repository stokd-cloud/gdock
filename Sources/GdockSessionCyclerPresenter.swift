import AppKit
import Foundation

/// The single entrypoint every surface uses to move the session cycler.
///
/// The keyboard chord, the command palette, and any future socket verb all call
/// here rather than each driving the overlay themselves — one shared action
/// path, per `CLAUDE.md`.
@MainActor
enum GdockSessionCyclerPresenter {
    /// Opens the cycler if it is closed and moves the highlight by `offset`.
    static func cycle(by offset: Int) {
        GdockSessionCyclerWindowController.shared.cycle(by: offset)
    }

    static func dismiss() {
        GdockSessionCyclerWindowController.shared.dismiss()
    }

    static var isVisible: Bool {
        GdockSessionCyclerWindowController.shared.isVisible
    }
}
