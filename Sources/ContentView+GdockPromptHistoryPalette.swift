import AppKit
import CmuxCommandPalette
import Foundation

/// Palette entrypoint for the prompt-history overlay.
///
/// The chord and the palette drive the same action path, per the shared-behavior
/// rule in `CLAUDE.md`. The palette has no chord to release, so it presents the
/// sticky variant: Escape, a click, or leaving the app closes it.
extension ContentView {
    static let commandPaletteGdockShowPromptHistoryCommandId = "palette.gdock.showPromptHistory"

    static func commandPaletteGdockPromptHistoryCommandContributions() -> [CommandPaletteCommandContribution] {
        [
            CommandPaletteCommandContribution(
                commandId: commandPaletteGdockShowPromptHistoryCommandId,
                title: { _ in
                    String(
                        localized: "command.gdock.showPromptHistory.title",
                        defaultValue: "Show Prompt History"
                    )
                },
                subtitle: { _ in
                    String(
                        localized: "command.gdock.promptHistory.subtitle",
                        defaultValue: "Sessions"
                    )
                },
                keywords: ["prompt", "prompts", "history", "asked", "session", "recent", "gdock"]
            )
        ]
    }

    func registerGdockPromptHistoryCommandHandlers(_ registry: inout CommandPaletteHandlerRegistry) {
        registry.register(commandId: Self.commandPaletteGdockShowPromptHistoryCommandId) {
            GdockPromptHistoryPresenter.present(holdModifiers: nil)
        }
    }
}
