import Foundation
import Testing

#if canImport(cmux_DEV)
@testable import cmux_DEV
#elseif canImport(cmux)
@testable import cmux
#endif

/// One card per *agent-session* pane of the focused workspace (AC2), carrying
/// the mockup's content (AC5/AC6).
@Suite struct GdockWorkspacePanelCardBuilderTests {
    private typealias Builder = GdockWorkspacePanelCardBuilder
    private typealias Pane = GdockWorkspacePanelCardBuilder.PaneInput

    /// A pane running an agent. `agentKindRaw` is what makes a pane eligible.
    private func agentPane(
        _ title: String,
        directory: String = "/repo",
        kind: String = "claude"
    ) -> Pane {
        Pane(paneId: UUID(), title: title, directory: directory, agentKindRaw: kind)
    }

    /// A plain shell pane: no agent, therefore no card.
    private func shellPane(_ title: String, directory: String = "/repo") -> Pane {
        Pane(paneId: UUID(), title: title, directory: directory)
    }

    private func summary(
        _ sessionID: String,
        kind: String = "fixed",
        counts: [String: Int] = ["fixed": 1],
        entries: Int = 1,
        updatedAt: Date = Date(timeIntervalSince1970: 1_788_000_000),
        startedAt: Date? = nil,
        isRunning: Bool = true,
        disposition: String? = nil
    ) -> StokdSessionOutcomeSummary {
        StokdSessionOutcomeSummary(
            sessionID: sessionID,
            latestKindRaw: kind,
            headline: "Did the thing",
            countsByKind: counts,
            entryCount: entries,
            updatedAt: updatedAt,
            startedAt: startedAt,
            disposition: disposition,
            isRunning: isRunning
        )
    }

    // MARK: - Agent-session gating (AC2)

    /// The core rule: a four-pane workspace with one agent shows one card, not
    /// four rows of nothing.
    @Test func onlyAgentPanesProduceCards() {
        let agent = agentPane("claude")
        let panes = [shellPane("zsh"), agent, shellPane("zsh"), shellPane("zsh")]

        let cards = Builder.cards(panes: panes, focusedPaneId: agent.paneId)

        #expect(cards.count == 1)
        #expect(cards[0].id == agent.paneId)
        #expect(cards[0].isSelected)
    }

    @Test func aWorkspaceWithNoAgentPanesProducesNoCards() {
        let panes = [shellPane("a"), shellPane("b"), shellPane("c")]

        #expect(Builder.cards(panes: panes, focusedPaneId: panes[0].paneId).isEmpty)
    }

    @Test func noPanesProducesNoCards() {
        #expect(Builder.cards(panes: [], focusedPaneId: nil).isEmpty)
    }

    /// A blank or whitespace agent kind is not an agent.
    @Test func aBlankAgentKindDoesNotQualify() {
        for kind in ["", "   "] {
            let pane = Pane(paneId: UUID(), title: "t", directory: "/repo", agentKindRaw: kind)
            #expect(Builder.cards(panes: [pane], focusedPaneId: pane.paneId).isEmpty)
        }
    }

    @Test func agentPanesKeepPaneTreeOrderAndAreIndexedContiguously() {
        let first = agentPane("worktree")
        let second = agentPane("project")
        let third = agentPane("task")
        let panes = [shellPane("zsh"), first, shellPane("zsh"), second, third]

        let cards = Builder.cards(panes: panes, focusedPaneId: second.paneId)

        #expect(cards.map(\.id) == [first.paneId, second.paneId, third.paneId])
        // Indices are over the carded panes, not the original pane list, so the
        // stack numbers 0..n-1 with no gaps where shells were skipped.
        #expect(cards.map(\.index) == [0, 1, 2])
    }

    // MARK: - Selection

    @Test func exactlyOneCardIsSelected() {
        let panes = [agentPane("a"), agentPane("b"), agentPane("c")]

        let cards = Builder.cards(panes: panes, focusedPaneId: panes[1].paneId)

        #expect(cards.filter(\.isSelected).count == 1)
        #expect(cards[1].isSelected)
    }

    /// When focus sits on a shell pane the stack still highlights something,
    /// rather than rendering with nothing selected.
    @Test func focusOnANonAgentPaneFallsBackToTheFirstCard() {
        let shell = shellPane("zsh")
        let panes = [shell, agentPane("a"), agentPane("b")]

        let cards = Builder.cards(panes: panes, focusedPaneId: shell.paneId)

        #expect(cards.filter(\.isSelected).count == 1)
        #expect(cards[0].isSelected)
    }

    @Test func absentFocusFallsBackToTheFirstCard() {
        let panes = [agentPane("a"), agentPane("b")]

        for focus in [nil, UUID()] {
            let cards = Builder.cards(panes: panes, focusedPaneId: focus)
            #expect(cards.filter(\.isSelected).count == 1)
            #expect(cards[0].isSelected)
        }
    }

    // MARK: - Content (AC5)

    @Test func carriesPaneMetadataAndAgentKindThrough() {
        let input = Pane(
            paneId: UUID(),
            title: "claude",
            directory: "/opt/gdock",
            branch: "task/60c40f3",
            agentKindRaw: "codex",
            sessionState: "running"
        )

        let cards = Builder.cards(panes: [input], focusedPaneId: input.paneId)

        #expect(cards[0].title == "claude")
        #expect(cards[0].branch == "task/60c40f3")
        #expect(cards[0].directory == "/opt/gdock")
        #expect(cards[0].agentKindRaw == "codex")
        #expect(cards[0].sessionState == "running")
    }

    /// Summaries are keyed by pane, not by directory: two agents in one
    /// directory routinely run different sessions.
    @Test func attachesTheSummaryToTheKeyedPaneOnly() {
        let one = agentPane("claude", directory: "/opt/gdock")
        let two = agentPane("codex", directory: "/opt/gdock")
        let expected = summary("interactive-claude-1-2")

        let cards = Builder.cards(
            panes: [one, two],
            focusedPaneId: one.paneId,
            summariesByPaneId: [one.paneId: expected]
        )

        #expect(cards[0].sessionSummary == expected)
        #expect(cards[1].sessionSummary == nil)
    }

    @Test func aSummaryForAnAbsentPaneIsIgnored() {
        let visible = agentPane("claude")

        let cards = Builder.cards(
            panes: [visible],
            focusedPaneId: visible.paneId,
            summariesByPaneId: [UUID(): summary("stranger")]
        )

        #expect(cards.count == 1)
        #expect(cards[0].sessionSummary == nil)
    }

    @Test func workItemsResolveByDirectory() {
        let gdock = agentPane("claude", directory: "/opt/gdock")
        let mono = agentPane("codex", directory: "/opt/mono")
        let item = GdockWorkspacePanelCard.WorkItem(
            kind: .task,
            title: "Panel card mockup",
            status: "in_progress",
            hashShort: "60c40f3"
        )

        let cards = Builder.cards(
            panes: [gdock, mono],
            focusedPaneId: gdock.paneId,
            workItemsByDirectory: ["/opt/gdock": item]
        )

        #expect(cards[0].workItem == item)
        #expect(cards[1].workItem == nil)
    }

    // MARK: - Glyph resolution (AC6)

    @Test func knownAgentsResolveToTheirBundledArtwork() {
        let present: (String) -> Bool = { _ in true }

        #expect(
            GdockAgentSessionGlyph.assetName(forAgentKindRaw: "claude", assetExists: present)
                == "AgentIcons/Claude"
        )
        #expect(
            GdockAgentSessionGlyph.assetName(forAgentKindRaw: "codex", assetExists: present)
                == "AgentIcons/Codex"
        )
    }

    /// The registry records no asset for grok even though the catalog has one,
    /// so the direct catalog probe is what keeps its glyph.
    @Test func anAgentMissingFromTheRegistryStillProbesTheCatalog() {
        let onlyCatalog: (String) -> Bool = { $0 == "AgentIcons/Grok" }

        #expect(
            GdockAgentSessionGlyph.assetName(forAgentKindRaw: "grok", assetExists: onlyCatalog)
                == "AgentIcons/Grok"
        )
    }

    @Test func multiWordAgentIdsMapToTheirImagesetNames() {
        let present: (String) -> Bool = { _ in true }

        for (id, asset) in [
            ("hermesagent", "AgentIcons/HermesAgent"),
            ("opencode", "AgentIcons/OpenCode"),
            ("rovodev", "AgentIcons/RovoDev"),
        ] {
            #expect(
                GdockAgentSessionGlyph.assetName(forAgentKindRaw: id, assetExists: present) == asset
            )
        }
    }

    /// An agent with no artwork anywhere resolves to nil so the view draws the
    /// fallback symbol rather than an empty image.
    @Test func anAgentWithNoArtworkResolvesToNil() {
        let none: (String) -> Bool = { _ in false }

        #expect(GdockAgentSessionGlyph.assetName(forAgentKindRaw: "kiro", assetExists: none) == nil)
        #expect(GdockAgentSessionGlyph.assetName(forAgentKindRaw: "", assetExists: none) == nil)
        #expect(!GdockAgentSessionGlyph.fallbackSymbolName.isEmpty)
    }

    @Test func agentKindLookupIsCaseInsensitive() {
        let present: (String) -> Bool = { _ in true }

        #expect(
            GdockAgentSessionGlyph.assetName(forAgentKindRaw: "CLAUDE", assetExists: present)
                == "AgentIcons/Claude"
        )
    }

    // MARK: - Metadata line (AC5)

    private static let now = Date(timeIntervalSince1970: 1_788_010_000)

    @Test func theMetadataLineCarriesElapsedCountsAndLastActivity() {
        let line = GdockAgentSessionCardMetadata.line(
            summary: summary(
                "s",
                counts: ["fixed": 38, "decided": 29],
                entries: 67,
                updatedAt: Self.now.addingTimeInterval(-240),
                startedAt: Self.now.addingTimeInterval(-8040),
                isRunning: true
            ),
            now: Self.now
        )

        #expect(line.contains("2h 14m"))
        #expect(line.contains("38 fixed"))
        #expect(line.contains("29 decided"))
        #expect(line.contains("4m"))
    }

    /// The mockup asked for "% Complete" and "Estimated Time left"; neither is
    /// recorded anywhere gdock reads, so the line must not claim them.
    @Test func theMetadataLineNeverFabricatesProgressOrETA() {
        let line = GdockAgentSessionCardMetadata.line(
            summary: summary("s", startedAt: Self.now.addingTimeInterval(-600)),
            now: Self.now
        )

        #expect(!line.contains("%"))
        #expect(!line.lowercased().contains("complete"))
        #expect(!line.lowercased().contains("estimated"))
        #expect(!line.lowercased().contains("remaining"))
    }

    /// Dominant activity leads, so the line reads usefully when truncated.
    @Test func countsAreOrderedByFrequencyThenName() {
        let text = GdockAgentSessionCardMetadata.countsText(
            ["decided": 2, "fixed": 9, "blocked": 2]
        )

        #expect(text == "9 fixed, 2 blocked, 2 decided")
    }

    @Test func zeroCountsAndEmptyCountsProduceNoCountsText() {
        #expect(GdockAgentSessionCardMetadata.countsText([:]) == nil)
        #expect(GdockAgentSessionCardMetadata.countsText(["fixed": 0]) == nil)
    }

    /// A session whose runtime record is already pruned has no start time, so
    /// the line drops the elapsed clause instead of showing a bogus duration.
    @Test func aSessionWithNoStartTimeOmitsElapsedRatherThanGuessing() {
        let line = GdockAgentSessionCardMetadata.line(
            summary: summary("s", startedAt: nil, isRunning: false),
            now: Self.now
        )

        #expect(!line.contains("ran"))
        #expect(line.contains("last"))
    }

    @Test func compactDurationScalesFromSecondsToDays() {
        let cases: [(TimeInterval, String)] = [
            (0, "0s"),
            (12, "12s"),
            (59, "59s"),
            (60, "1m"),
            (240, "4m"),
            (3600, "1h"),
            (8040, "2h 14m"),
            (86_400, "1d"),
            (97_200, "1d 3h"),
        ]

        for (seconds, expected) in cases {
            #expect(GdockAgentSessionCardMetadata.compactDuration(seconds) == expected)
        }
    }

    @Test func compactDurationNeverGoesNegative() {
        #expect(GdockAgentSessionCardMetadata.compactDuration(-500) == "0s")
    }
}
