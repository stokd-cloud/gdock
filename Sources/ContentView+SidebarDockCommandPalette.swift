import AppKit
import CmuxCommandPalette
import Foundation

extension ContentView {
    /// Focused-rail command-palette contributions for dock section actions.
    ///
    /// Descriptors are always published; `when` hides them when the beta flag is off
    /// or when no live rail target can run the command safely.
    static func commandPaletteSidebarDockCommandContributions() -> [CommandPaletteCommandContribution] {
        func constant(_ value: String) -> (CommandPaletteContextSnapshot) -> String {
            { _ in value }
        }

        let subtitle = constant(SidebarDockCommand.commandGroupSubtitle)

        return [
            CommandPaletteCommandContribution(
                commandId: SidebarDockCommand.moveTabToNewSectionTop,
                title: constant(SidebarDockCommand.title(for: SidebarDockCommand.moveTabToNewSectionTop)),
                subtitle: subtitle,
                keywords: ["sidebar", "dock", "section", "move", "tab", "above", "top", "new"],
                when: { _ in Self.sidebarDockPaletteCommandIsAvailable(SidebarDockCommand.moveTabToNewSectionTop) }
            ),
            CommandPaletteCommandContribution(
                commandId: SidebarDockCommand.moveTabToNewSectionBottom,
                title: constant(SidebarDockCommand.title(for: SidebarDockCommand.moveTabToNewSectionBottom)),
                subtitle: subtitle,
                keywords: ["sidebar", "dock", "section", "move", "tab", "below", "bottom", "new"],
                when: { _ in Self.sidebarDockPaletteCommandIsAvailable(SidebarDockCommand.moveTabToNewSectionBottom) }
            ),
            CommandPaletteCommandContribution(
                commandId: SidebarDockCommand.collapseSection,
                title: constant(SidebarDockCommand.title(for: SidebarDockCommand.collapseSection)),
                subtitle: subtitle,
                keywords: ["sidebar", "dock", "section", "collapse", "fold", "hide"],
                when: { _ in Self.sidebarDockPaletteCommandIsAvailable(SidebarDockCommand.collapseSection) }
            ),
            CommandPaletteCommandContribution(
                commandId: SidebarDockCommand.expandSection,
                title: constant(SidebarDockCommand.title(for: SidebarDockCommand.expandSection)),
                subtitle: subtitle,
                keywords: ["sidebar", "dock", "section", "expand", "open", "surrogate"],
                when: { _ in Self.sidebarDockPaletteCommandIsAvailable(SidebarDockCommand.expandSection) }
            ),
            CommandPaletteCommandContribution(
                commandId: SidebarDockCommand.reorderSectionUp,
                title: constant(SidebarDockCommand.title(for: SidebarDockCommand.reorderSectionUp)),
                subtitle: subtitle,
                keywords: ["sidebar", "dock", "section", "move", "up", "reorder"],
                when: { _ in Self.sidebarDockPaletteCommandIsAvailable(SidebarDockCommand.reorderSectionUp) }
            ),
            CommandPaletteCommandContribution(
                commandId: SidebarDockCommand.reorderSectionDown,
                title: constant(SidebarDockCommand.title(for: SidebarDockCommand.reorderSectionDown)),
                subtitle: subtitle,
                keywords: ["sidebar", "dock", "section", "move", "down", "reorder"],
                when: { _ in Self.sidebarDockPaletteCommandIsAvailable(SidebarDockCommand.reorderSectionDown) }
            ),
        ]
    }

    /// Live eligibility for palette `when` gates (flag + focused rail context).
    static func sidebarDockPaletteCommandIsAvailable(_ commandId: String) -> Bool {
        guard RightSidebarBetaFeatureSettings.isSidebarDockEnabled() else { return false }
        guard let target = SidebarDockActionInvoker.resolveTarget(
            windowId: nil,
            preferredWindow: NSApp.keyWindow ?? NSApp.mainWindow
        ) else {
            return false
        }
        return SidebarDockCommand.eligibility(
            store: target.store,
            tabId: target.tabId,
            paneId: target.paneId
        ).isAvailable(commandId)
    }

    func registerSidebarDockCommandHandlers(_ registry: inout CommandPaletteHandlerRegistry) {
        for commandId in SidebarDockCommand.allCommandIds {
            registry.register(commandId: commandId) { [self] in
                handleSidebarDockPaletteCommand(commandId)
            }
        }
    }

    func handleSidebarDockPaletteCommand(_ commandId: String) {
        let handled = SidebarDockActionInvoker.performFocused(
            commandId: commandId,
            windowId: windowId,
            preferredWindow: observedWindow ?? NSApp.keyWindow ?? NSApp.mainWindow
        )
        if !handled {
            NSSound.beep()
        }
    }
}
