import CmuxSettings
import Foundation
import Testing

#if canImport(cmux_DEV)
@testable import cmux_DEV
#elseif canImport(cmux)
@testable import cmux
#endif

/// The prompt-history overlay owns Cmd+Option+P in the app's shortcut table and
/// in the `CmuxSettings` mirror, and is app-scoped like the session cycler
/// (AX-GDOCK-PROMPT-HISTORY).
@Suite struct GdockPromptHistoryShortcutTests {
    private typealias Action = KeyboardShortcutSettings.Action

    private static let stroke = StoredShortcut(
        key: "p",
        command: true,
        shift: false,
        option: true,
        control: false
    )

    @Test func actionIdCarriesTheForkPrefix() {
        #expect(Action.gdockShowPromptHistory.rawValue == "gdock.showPromptHistory")
    }

    @Test func defaultsToCommandOptionP() {
        #expect(Action.gdockShowPromptHistory.defaultShortcut == Self.stroke)
    }

    @Test func noOtherActionDefaultBindsThatChord() {
        let collisions = Action.allCases
            .filter { $0 != .gdockShowPromptHistory }
            .filter { $0.defaultShortcut == Self.stroke }

        #expect(collisions.isEmpty, "actions colliding with Cmd+Option+P: \(collisions.map(\.rawValue))")
    }

    /// The overlay reads prompts from whichever pane is focused app-wide, so it
    /// must not be re-resolved against the focused Dock.
    @Test func routesAppScoped() {
        #expect(Action.gdockShowPromptHistory.dockShortcutRoutingDisposition == .mainContainer)
    }

    @Test func settingsPackageMirrorsTheSameDefault() {
        let action = ShortcutAction(rawValue: "gdock.showPromptHistory")
        #expect(action?.defaultStroke == ShortcutStroke(key: "p", command: true, option: true))
    }

    @Test func paletteCommandIdCarriesTheForkPrefix() {
        #expect(ContentView.commandPaletteGdockShowPromptHistoryCommandId == "palette.gdock.showPromptHistory")
    }
}
