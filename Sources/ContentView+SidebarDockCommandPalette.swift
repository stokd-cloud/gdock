import AppKit
import Bonsplit
import CmuxCommandPalette
import Foundation

/// One production command-palette registry hit for dock section actions.
struct SidebarDockPaletteRegistryResult: Equatable, Sendable {
    let commandId: String
    let title: String
    let score: Int
}

extension ContentView {
    /// Focused-rail command-palette contributions for dock section actions.
    ///
    /// Descriptors are always published; `when` hides them when the beta flag is off
    /// or when no live rail target can run the command safely.
    ///
    /// - Parameter windowId: Window that owns the rail registry. Passing the
    ///   ContentView window id keeps availability window-scoped so dogfood and
    ///   multi-window hosts do not depend on `NSApp.keyWindow`.
    static func commandPaletteSidebarDockCommandContributions(
        windowId: UUID? = nil
    ) -> [CommandPaletteCommandContribution] {
        func constant(_ value: String) -> (CommandPaletteContextSnapshot) -> String {
            { _ in value }
        }

        let subtitle = constant(SidebarDockCommand.commandGroupSubtitle)
        let boundWindowId = windowId

        return [
            CommandPaletteCommandContribution(
                commandId: SidebarDockCommand.moveTabToNewSectionTop,
                title: constant(SidebarDockCommand.title(for: SidebarDockCommand.moveTabToNewSectionTop)),
                subtitle: subtitle,
                keywords: ["sidebar", "dock", "section", "move", "tab", "above", "top", "new"],
                when: { _ in
                    Self.sidebarDockPaletteCommandIsAvailable(
                        SidebarDockCommand.moveTabToNewSectionTop,
                        windowId: boundWindowId
                    )
                }
            ),
            CommandPaletteCommandContribution(
                commandId: SidebarDockCommand.moveTabToNewSectionBottom,
                title: constant(SidebarDockCommand.title(for: SidebarDockCommand.moveTabToNewSectionBottom)),
                subtitle: subtitle,
                keywords: ["sidebar", "dock", "section", "move", "tab", "below", "bottom", "new"],
                when: { _ in
                    Self.sidebarDockPaletteCommandIsAvailable(
                        SidebarDockCommand.moveTabToNewSectionBottom,
                        windowId: boundWindowId
                    )
                }
            ),
            CommandPaletteCommandContribution(
                commandId: SidebarDockCommand.collapseSection,
                title: constant(SidebarDockCommand.title(for: SidebarDockCommand.collapseSection)),
                subtitle: subtitle,
                keywords: ["sidebar", "dock", "section", "collapse", "fold", "hide"],
                when: { _ in
                    Self.sidebarDockPaletteCommandIsAvailable(
                        SidebarDockCommand.collapseSection,
                        windowId: boundWindowId
                    )
                }
            ),
            CommandPaletteCommandContribution(
                commandId: SidebarDockCommand.expandSection,
                title: constant(SidebarDockCommand.title(for: SidebarDockCommand.expandSection)),
                subtitle: subtitle,
                keywords: ["sidebar", "dock", "section", "expand", "open", "surrogate"],
                when: { _ in
                    Self.sidebarDockPaletteCommandIsAvailable(
                        SidebarDockCommand.expandSection,
                        windowId: boundWindowId
                    )
                }
            ),
            CommandPaletteCommandContribution(
                commandId: SidebarDockCommand.reorderSectionUp,
                title: constant(SidebarDockCommand.title(for: SidebarDockCommand.reorderSectionUp)),
                subtitle: subtitle,
                keywords: ["sidebar", "dock", "section", "move", "up", "reorder"],
                when: { _ in
                    Self.sidebarDockPaletteCommandIsAvailable(
                        SidebarDockCommand.reorderSectionUp,
                        windowId: boundWindowId
                    )
                }
            ),
            CommandPaletteCommandContribution(
                commandId: SidebarDockCommand.reorderSectionDown,
                title: constant(SidebarDockCommand.title(for: SidebarDockCommand.reorderSectionDown)),
                subtitle: subtitle,
                keywords: ["sidebar", "dock", "section", "move", "down", "reorder"],
                when: { _ in
                    Self.sidebarDockPaletteCommandIsAvailable(
                        SidebarDockCommand.reorderSectionDown,
                        windowId: boundWindowId
                    )
                }
            ),
        ]
    }

    /// Pure availability for tests and DEBUG dogfood (flag + explicit rail target).
    ///
    /// RED stub intentionally returns `false` so reachability regressions fail
    /// until the green wiring lands.
    static func sidebarDockPaletteCommandIsAvailable(
        _ commandId: String,
        flagEnabled: Bool,
        target: SidebarDockActionInvoker.Target?
    ) -> Bool {
        _ = commandId
        _ = flagEnabled
        _ = target
        return false
    }

    /// Live eligibility for palette `when` gates (flag + window-scoped rail).
    ///
    /// RED stub keeps the historical key-window-only path incomplete for the
    /// pure target evaluator; live path still resolves via invoker for compile.
    static func sidebarDockPaletteCommandIsAvailable(
        _ commandId: String,
        windowId: UUID? = nil
    ) -> Bool {
        guard RightSidebarBetaFeatureSettings.isSidebarDockEnabled() else { return false }
        // Prefer the ContentView window id so availability does not require the
        // window to be key (tagged-socket dogfood often leaves keyWindow nil).
        let preferredWindow: NSWindow? = {
            if windowId != nil { return nil }
            return NSApp.keyWindow ?? NSApp.mainWindow
        }()
        guard let target = SidebarDockActionInvoker.resolveTarget(
            windowId: windowId,
            preferredWindow: preferredWindow
        ) else {
            return false
        }
        // RED: force pure evaluator (stub) so tests fail until green implements it.
        return sidebarDockPaletteCommandIsAvailable(
            commandId,
            flagEnabled: true,
            target: target
        )
    }

    /// Production registry search over dock contributions (title/keywords/ids).
    ///
    /// RED stub returns no hits so query→id regressions fail until green.
    static func sidebarDockPaletteRegistryResults(
        query: String,
        flagEnabled: Bool,
        target: SidebarDockActionInvoker.Target?,
        limit: Int = 48
    ) -> [SidebarDockPaletteRegistryResult] {
        _ = query
        _ = flagEnabled
        _ = target
        _ = limit
        return []
    }

    /// Registered-handler shape for palette activation (returns handled).
    ///
    /// RED stub never mutates — regressions fail until green routes through
    /// `SidebarDockCommand.perform` via the shared invoker inside the handler.
    static func sidebarDockPaletteRegisteredHandler(
        commandId: String,
        store: SidebarDockStore,
        tabId: TabID?,
        paneId: PaneID?
    ) -> () -> Bool {
        _ = commandId
        _ = store
        _ = tabId
        _ = paneId
        return { false }
    }

    func registerSidebarDockCommandHandlers(_ registry: inout CommandPaletteHandlerRegistry) {
        for commandId in SidebarDockCommand.allCommandIds {
            registry.register(commandId: commandId) { [self] in
                handleSidebarDockPaletteCommand(commandId)
            }
        }
    }

    func handleSidebarDockPaletteCommand(_ commandId: String) {
        // Resolve via ContentView.windowId first; preferredWindow is a soft
        // fallback only. Do not read ContentView.observedWindow here — it is
        // private to ContentView.swift (same pattern as static availability).
        let handled = SidebarDockActionInvoker.performFocused(
            commandId: commandId,
            windowId: windowId,
            preferredWindow: NSApp.keyWindow ?? NSApp.mainWindow
        )
        if !handled {
            NSSound.beep()
        }
    }
}

#if DEBUG
extension TerminalController {
    /// DEBUG dogfood method under the command-palette namespace (VAL-RAIL-001/003).
    nonisolated static let commandPaletteDebugQueryRunMethodName = "debug.command_palette.query_run"
}
#endif

