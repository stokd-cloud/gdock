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
            CommandPaletteCommandContribution(
                commandId: SidebarDockCommand.moveTabToOtherRailSelected,
                title: constant(SidebarDockCommand.title(for: SidebarDockCommand.moveTabToOtherRailSelected)),
                subtitle: subtitle,
                keywords: ["sidebar", "dock", "rail", "cross", "move", "tab", "other", "left", "right"],
                when: { _ in
                    Self.sidebarDockPaletteCommandIsAvailable(
                        SidebarDockCommand.moveTabToOtherRailSelected,
                        windowId: boundWindowId
                    )
                }
            ),
            CommandPaletteCommandContribution(
                commandId: SidebarDockCommand.moveTabToOtherRailTop,
                title: constant(SidebarDockCommand.title(for: SidebarDockCommand.moveTabToOtherRailTop)),
                subtitle: subtitle,
                keywords: ["sidebar", "dock", "rail", "cross", "move", "tab", "top", "other"],
                when: { _ in
                    Self.sidebarDockPaletteCommandIsAvailable(
                        SidebarDockCommand.moveTabToOtherRailTop,
                        windowId: boundWindowId
                    )
                }
            ),
            CommandPaletteCommandContribution(
                commandId: SidebarDockCommand.moveTabToOtherRailBottom,
                title: constant(SidebarDockCommand.title(for: SidebarDockCommand.moveTabToOtherRailBottom)),
                subtitle: subtitle,
                keywords: ["sidebar", "dock", "rail", "cross", "move", "tab", "bottom", "other"],
                when: { _ in
                    Self.sidebarDockPaletteCommandIsAvailable(
                        SidebarDockCommand.moveTabToOtherRailBottom,
                        windowId: boundWindowId
                    )
                }
            ),
            CommandPaletteCommandContribution(
                commandId: SidebarDockCommand.moveSectionToOtherRailTop,
                title: constant(SidebarDockCommand.title(for: SidebarDockCommand.moveSectionToOtherRailTop)),
                subtitle: subtitle,
                keywords: ["sidebar", "dock", "rail", "cross", "move", "section", "top", "other"],
                when: { _ in
                    Self.sidebarDockPaletteCommandIsAvailable(
                        SidebarDockCommand.moveSectionToOtherRailTop,
                        windowId: boundWindowId
                    )
                }
            ),
            CommandPaletteCommandContribution(
                commandId: SidebarDockCommand.moveSectionToOtherRailBottom,
                title: constant(SidebarDockCommand.title(for: SidebarDockCommand.moveSectionToOtherRailBottom)),
                subtitle: subtitle,
                keywords: ["sidebar", "dock", "rail", "cross", "move", "section", "bottom", "other"],
                when: { _ in
                    Self.sidebarDockPaletteCommandIsAvailable(
                        SidebarDockCommand.moveSectionToOtherRailBottom,
                        windowId: boundWindowId
                    )
                }
            ),
        ]
    }

    /// Pure availability for tests and DEBUG dogfood (flag + explicit rail target).
    ///
    /// Does not weaken the eligibility predicate: unsafe commands stay hidden
    /// even when the flag is on and a rail exists.
    static func sidebarDockPaletteCommandIsAvailable(
        _ commandId: String,
        flagEnabled: Bool,
        target: SidebarDockActionInvoker.Target?
    ) -> Bool {
        guard flagEnabled else { return false }
        guard let target else { return false }
        return SidebarDockCommand.eligibility(
            store: target.store,
            tabId: target.tabId,
            paneId: target.paneId
        ).isAvailable(commandId)
    }

    /// Live eligibility for palette `when` gates (flag + window-scoped rail).
    ///
    /// Prefer `windowId` from the presenting ContentView so availability does
    /// not require `NSApp.keyWindow` (tagged-socket dogfood often leaves it nil).
    static func sidebarDockPaletteCommandIsAvailable(
        _ commandId: String,
        windowId: UUID? = nil
    ) -> Bool {
        let flagEnabled = RightSidebarBetaFeatureSettings.isSidebarDockEnabled()
        let preferredWindow: NSWindow? = {
            if windowId != nil { return nil }
            return NSApp.keyWindow ?? NSApp.mainWindow
        }()
        let target = SidebarDockActionInvoker.resolveTarget(
            windowId: windowId,
            preferredWindow: preferredWindow
        )
        return sidebarDockPaletteCommandIsAvailable(
            commandId,
            flagEnabled: flagEnabled,
            target: target
        )
    }

    /// Production registry search over dock contributions (title/keywords/ids).
    ///
    /// Uses the same contribution descriptors and `when` semantics as the live
    /// palette, scored with the production fuzzy matcher so a typed query can
    /// surface `sidebarDock.*` results that sit late in empty-query rank order.
    static func sidebarDockPaletteRegistryResults(
        query: String,
        flagEnabled: Bool,
        target: SidebarDockActionInvoker.Target?,
        limit: Int = 48
    ) -> [SidebarDockPaletteRegistryResult] {
        let contributions = commandPaletteSidebarDockCommandContributions(windowId: nil)
        let context = CommandPaletteContextSnapshot()
        var corpus: [CommandPaletteSearchCorpusEntry<String>] = []
        corpus.reserveCapacity(contributions.count)
        var rank = 0
        for contribution in contributions {
            // Evaluate eligibility against the explicit target rather than live
            // AppDelegate state so tests and dogfood share one pure path.
            guard sidebarDockPaletteCommandIsAvailable(
                contribution.commandId,
                flagEnabled: flagEnabled,
                target: target
            ) else { continue }
            // Keep contribution `when` contract for flag-off / no-target cases
            // when callers pass live nil targets (still false via pure evaluator).
            _ = contribution.when
            _ = context
            let title = contribution.title(context)
            var searchable = [title, contribution.subtitle(context), contribution.commandId]
            searchable.append(contentsOf: contribution.keywords)
            corpus.append(
                CommandPaletteSearchCorpusEntry(
                    payload: contribution.commandId,
                    rank: rank,
                    title: title,
                    searchableTexts: searchable
                )
            )
            rank += 1
        }
        guard !corpus.isEmpty else { return [] }

        let matchingQuery = Self.sidebarDockPaletteMatchingQuery(query)
        let prepared = CommandPaletteFuzzyMatcher.preparedQuery(matchingQuery)
        let queryIsEmpty = prepared.isEmpty
        let engine = CommandPaletteSearchEngine(entries: corpus)
        let hits = engine.search(
            query: matchingQuery,
            resultLimit: max(1, limit),
            historyBoost: { commandId, isEmpty in
                // When the query is empty, boost dock commands so eligible
                // actions remain discoverable above late contribution ranks.
                if isEmpty { return 5_000 }
                // Prefer exact command-id / keyword hits slightly when typing.
                if commandId.hasPrefix("sidebarDock.") { return 500 }
                return 0
            }
        )
        _ = queryIsEmpty
        return hits.map { hit in
            SidebarDockPaletteRegistryResult(
                commandId: hit.payload,
                title: hit.title,
                score: hit.score
            )
        }
    }

    /// Normalize a dogfood/user query into the matching suffix used by the
    /// production commands list (`>` prefix is optional).
    nonisolated static func sidebarDockPaletteMatchingQuery(_ query: String) -> String {
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.hasPrefix(">") {
            return String(trimmed.dropFirst()).trimmingCharacters(in: .whitespacesAndNewlines)
        }
        return trimmed
    }

    /// Registered-handler shape for palette activation (returns handled).
    ///
    /// Routes through `SidebarDockActionInvoker.perform` → `SidebarDockCommand.perform`
    /// so palette dogfood and UI share one mutation path. Callers (tests /
    /// `debug.command_palette.query_run`) must not touch the store directly.
    static func sidebarDockPaletteRegisteredHandler(
        commandId: String,
        store: SidebarDockStore,
        tabId: TabID?,
        paneId: PaneID?
    ) -> () -> Bool {
        {
            SidebarDockActionInvoker.perform(
                commandId: commandId,
                store: store,
                tabId: tabId,
                paneId: paneId
            )
        }
    }

    /// Live registered-handler factory for a window-scoped target.
    static func sidebarDockPaletteRegisteredHandler(
        commandId: String,
        windowId: UUID?,
        preferredWindow: NSWindow? = nil
    ) -> () -> Bool {
        {
            SidebarDockActionInvoker.performFocused(
                commandId: commandId,
                windowId: windowId,
                preferredWindow: preferredWindow ?? NSApp.keyWindow ?? NSApp.mainWindow
            )
        }
    }

    func registerSidebarDockCommandHandlers(_ registry: inout CommandPaletteHandlerRegistry) {
        for commandId in SidebarDockCommand.allCommandIds {
            registry.register(commandId: commandId) { [self] in
                handleSidebarDockPaletteCommand(commandId)
            }
        }
    }

    func handleSidebarDockPaletteCommand(_ commandId: String) {
        // Registered handler path: window-scoped invoker (same factory dogfood uses).
        // Do not read ContentView.observedWindow — it is private to ContentView.swift.
        let handled = Self.sidebarDockPaletteRegisteredHandler(
            commandId: commandId,
            windowId: windowId,
            preferredWindow: NSApp.keyWindow ?? NSApp.mainWindow
        )()
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

