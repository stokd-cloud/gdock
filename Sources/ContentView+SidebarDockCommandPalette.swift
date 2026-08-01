import CmuxCommandPalette
import Foundation

extension ContentView {
    /// Focused-rail command-palette contributions for dock section actions.
    ///
    /// RED stub returns an empty list so wiring tests fail until production registration lands.
    static func commandPaletteSidebarDockCommandContributions() -> [CommandPaletteCommandContribution] {
        []
    }

    func registerSidebarDockCommandHandlers(_ registry: inout CommandPaletteHandlerRegistry) {
        // RED stub: no production handlers until green wiring.
        _ = registry
    }

    func handleSidebarDockPaletteCommand(_ commandId: String) {
        // RED stub: no production perform path until green wiring.
        _ = commandId
    }
}
