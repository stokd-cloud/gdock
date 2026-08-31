import AppKit
import CmuxCommandPalette
import Foundation

/// Palette entrypoints for the session cycler.
///
/// The chord and the palette drive the same action path, per the shared-behavior
/// rule in `CLAUDE.md`: both call ``GdockSessionCyclerPresenter``, neither owns
/// its own copy of the cycling logic.
extension ContentView {
    static let commandPaletteGdockCycleSessionsNextCommandId = "palette.gdock.cycleSessionsNext"
    static let commandPaletteGdockCycleSessionsPrevCommandId = "palette.gdock.cycleSessionsPrev"

    static func commandPaletteGdockSessionCyclerCommandContributions() -> [CommandPaletteCommandContribution] {
        func constant(_ value: String) -> (CommandPaletteContextSnapshot) -> String {
            { _ in value }
        }

        let subtitle = constant(String(
            localized: "command.gdock.sessionCycler.subtitle",
            defaultValue: "Sessions"
        ))

        return [
            CommandPaletteCommandContribution(
                commandId: commandPaletteGdockCycleSessionsNextCommandId,
                title: constant(String(
                    localized: "command.gdock.cycleSessionsNext.title",
                    defaultValue: "Cycle Sessions Forward"
                )),
                subtitle: subtitle,
                keywords: ["session", "sessions", "cycle", "switch", "agent", "next", "forward", "gdock"]
            ),
            CommandPaletteCommandContribution(
                commandId: commandPaletteGdockCycleSessionsPrevCommandId,
                title: constant(String(
                    localized: "command.gdock.cycleSessionsPrev.title",
                    defaultValue: "Cycle Sessions Backward"
                )),
                subtitle: subtitle,
                keywords: ["session", "sessions", "cycle", "switch", "agent", "previous", "back", "gdock"]
            ),
        ]
    }

    func registerGdockSessionCyclerCommandHandlers(_ registry: inout CommandPaletteHandlerRegistry) {
        registry.register(commandId: Self.commandPaletteGdockCycleSessionsNextCommandId) {
            GdockSessionCyclerPresenter.cycle(by: 1)
        }
        registry.register(commandId: Self.commandPaletteGdockCycleSessionsPrevCommandId) {
            GdockSessionCyclerPresenter.cycle(by: -1)
        }
    }
}
