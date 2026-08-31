import CmuxSettings
import Foundation
import Testing

#if canImport(cmux_DEV)
@testable import cmux_DEV
#elseif canImport(cmux)
@testable import cmux
#endif

/// The cycler owns Cmd+Shift+] / Cmd+Shift+[ outright, in both the app's
/// shortcut table and the `CmuxSettings` mirror (AX-GDOCK-SESSION-CYCLER).
///
/// Those strokes were upstream's `nextSurface` / `prevSurface` defaults. In this
/// fork the cycler takes them and surface navigation ships unbound-by-default,
/// still bindable in Settings — so the assertion that no *other* action claims
/// either stroke is the guard that the handover actually happened rather than
/// leaving two actions fighting over one chord.
@Suite struct GdockSessionCyclerShortcutTests {
    private typealias Action = KeyboardShortcutSettings.Action

    private static let forwardStroke = StoredShortcut(
        key: "]",
        command: true,
        shift: true,
        option: false,
        control: false
    )
    private static let backwardStroke = StoredShortcut(
        key: "[",
        command: true,
        shift: true,
        option: false,
        control: false
    )

    // MARK: - Identity

    @Test func actionIdsCarryTheForkPrefix() {
        #expect(Action.gdockCycleSessionsNext.rawValue == "gdock.cycleSessionsNext")
        #expect(Action.gdockCycleSessionsPrev.rawValue == "gdock.cycleSessionsPrev")
    }

    // MARK: - Defaults

    @Test func cyclerActionsDefaultToCommandShiftBrackets() {
        #expect(Action.gdockCycleSessionsNext.defaultShortcut == Self.forwardStroke)
        #expect(Action.gdockCycleSessionsPrev.defaultShortcut == Self.backwardStroke)
    }

    @Test func noOtherActionDefaultBindsEitherBracketChord() {
        let claimed = [Self.forwardStroke, Self.backwardStroke]
        let cyclerActions: Set<Action> = [.gdockCycleSessionsNext, .gdockCycleSessionsPrev]

        let collisions = Action.allCases
            .filter { !cyclerActions.contains($0) }
            .filter { claimed.contains($0.defaultShortcut) }

        #expect(collisions.isEmpty, "actions colliding with the cycler chord: \(collisions.map(\.rawValue))")
    }

    /// The explicit fork divergence: surface navigation keeps its actions and
    /// its Settings row, but no longer holds the chord.
    @Test func surfaceNavigationShipsUnboundByDefault() {
        #expect(Action.nextSurface.defaultShortcut.isUnbound)
        #expect(Action.prevSurface.defaultShortcut.isUnbound)
    }

    // MARK: - CmuxSettings mirror

    @Test func settingsPackageMirrorsTheSameDefaults() {
        let next = ShortcutAction(rawValue: "gdock.cycleSessionsNext")
        let previous = ShortcutAction(rawValue: "gdock.cycleSessionsPrev")

        #expect(next?.defaultStroke == ShortcutStroke(key: "]", command: true, shift: true))
        #expect(previous?.defaultStroke == ShortcutStroke(key: "[", command: true, shift: true))
    }

    @Test func settingsPackageDropsTheSurfaceNavigationDefaults() {
        #expect(ShortcutAction.nextSurface.defaultStroke == nil)
        #expect(ShortcutAction.prevSurface.defaultStroke == nil)
    }

    // MARK: - Palette reachability

    @Test func paletteCommandIdsCarryTheForkPrefix() {
        #expect(ContentView.commandPaletteGdockCycleSessionsNextCommandId == "palette.gdock.cycleSessionsNext")
        #expect(ContentView.commandPaletteGdockCycleSessionsPrevCommandId == "palette.gdock.cycleSessionsPrev")
    }
}
