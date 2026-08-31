import Foundation
import Testing

#if canImport(cmux_DEV)
@testable import cmux_DEV
#elseif canImport(cmux)
@testable import cmux
#endif

/// One card per visible pane of the focused workspace (AC7).
@Suite struct GdockWorkspacePanelCardBuilderTests {
    private typealias Builder = GdockWorkspacePanelCardBuilder
    private typealias Pane = GdockWorkspacePanelCardBuilder.PaneInput

    private func pane(_ title: String, directory: String = "/repo") -> Pane {
        Pane(paneId: UUID(), title: title, directory: directory)
    }

    @Test func onePaneProducesOneCard() {
        let only = pane("zsh")

        let cards = Builder.cards(panes: [only], focusedPaneId: only.paneId)

        #expect(cards.count == 1)
        #expect(cards[0].isSelected)
        #expect(cards[0].index == 0)
    }

    @Test func fourPanesProduceFourCardsInPaneOrder() {
        let panes = [pane("worktree"), pane("project"), pane("task"), pane("todo")]

        let cards = Builder.cards(panes: panes, focusedPaneId: panes[2].paneId)

        #expect(cards.map(\.title) == ["worktree", "project", "task", "todo"])
        #expect(cards.map(\.index) == [0, 1, 2, 3])
        #expect(cards.map(\.id) == panes.map(\.paneId))
    }

    @Test func exactlyOneCardIsSelected() {
        let panes = [pane("a"), pane("b"), pane("c")]

        let cards = Builder.cards(panes: panes, focusedPaneId: panes[1].paneId)

        #expect(cards.filter(\.isSelected).count == 1)
        #expect(cards[1].isSelected)
    }

    /// The sidebar must never render a workspace with nothing highlighted, so a
    /// stale or absent focus falls back to the first pane rather than to none.
    @Test func absentFocusFallsBackToTheFirstPane() {
        let panes = [pane("a"), pane("b")]

        for focus in [nil, UUID()] {
            let cards = Builder.cards(panes: panes, focusedPaneId: focus)
            #expect(cards.filter(\.isSelected).count == 1)
            #expect(cards[0].isSelected)
        }
    }

    @Test func noPanesProducesNoCards() {
        #expect(Builder.cards(panes: [], focusedPaneId: nil).isEmpty)
    }

    @Test func attachesTheWorkItemMatchingThePaneDirectory() {
        let gdock = pane("gdock", directory: "/opt/gdock")
        let mono = pane("mono", directory: "/opt/mono")
        let item = GdockWorkspacePanelCard.WorkItem(
            kind: .task,
            title: "Repo command surface",
            status: "in_progress",
            hashShort: "404e878"
        )

        let cards = Builder.cards(
            panes: [gdock, mono],
            focusedPaneId: gdock.paneId,
            workItemsByDirectory: ["/opt/gdock": item]
        )

        #expect(cards[0].workItem == item)
        #expect(cards[1].workItem == nil)
    }

    @Test func carriesPaneMetadataThrough() {
        let input = Pane(
            paneId: UUID(),
            title: "claude",
            directory: "/opt/gdock",
            branch: "project/404e878",
            sessionState: "Running"
        )

        let cards = Builder.cards(panes: [input], focusedPaneId: input.paneId)

        #expect(cards[0].branch == "project/404e878")
        #expect(cards[0].sessionState == "Running")
        #expect(cards[0].directory == "/opt/gdock")
    }

    // MARK: - Session summaries (AC6)

    private func summary(_ sessionID: String, kind: String = "fixed") -> StokdSessionOutcomeSummary {
        StokdSessionOutcomeSummary(
            sessionID: sessionID,
            latestKindRaw: kind,
            headline: "Did the thing",
            countsByKind: [kind: 1],
            entryCount: 1,
            updatedAt: Date(timeIntervalSince1970: 1_788_000_000),
            disposition: nil,
            isRunning: true
        )
    }

    /// Summaries are keyed by pane, not by directory: two panes in one
    /// directory routinely run different sessions.
    @Test func attachesTheSummaryToTheKeyedPaneOnly() {
        let withSession = pane("claude", directory: "/opt/gdock")
        let plainShell = pane("zsh", directory: "/opt/gdock")
        let expected = summary("interactive-claude-1-2")

        let cards = Builder.cards(
            panes: [withSession, plainShell],
            focusedPaneId: withSession.paneId,
            summariesByPaneId: [withSession.paneId: expected]
        )

        #expect(cards[0].sessionSummary == expected)
        #expect(cards[1].sessionSummary == nil)
    }

    /// The gate-off path and every pre-existing call site go through this
    /// default, so it must reproduce the old output exactly.
    @Test func withoutSummariesTheOutputIsUnchanged() {
        let panes = [pane("a"), pane("b"), pane("c")]

        let cards = Builder.cards(panes: panes, focusedPaneId: panes[1].paneId)

        #expect(cards.allSatisfy { $0.sessionSummary == nil })
        #expect(cards == Builder.cards(
            panes: panes,
            focusedPaneId: panes[1].paneId,
            summariesByPaneId: [:]
        ))
    }

    /// A summary keyed to a pane that is not visible must not leak onto some
    /// other card.
    @Test func aSummaryForAnAbsentPaneIsIgnored() {
        let visible = pane("claude")

        let cards = Builder.cards(
            panes: [visible],
            focusedPaneId: visible.paneId,
            summariesByPaneId: [UUID(): summary("stranger")]
        )

        #expect(cards.count == 1)
        #expect(cards[0].sessionSummary == nil)
    }

    @Test func summariesAndWorkItemsCoexistOnOneCard() {
        let only = pane("claude", directory: "/opt/gdock")
        let item = GdockWorkspacePanelCard.WorkItem(
            kind: .task,
            title: "Panel card summaries",
            status: "in_progress",
            hashShort: "635127d"
        )
        let expected = summary("interactive-claude-3-4", kind: "blocked")

        let cards = Builder.cards(
            panes: [only],
            focusedPaneId: only.paneId,
            workItemsByDirectory: ["/opt/gdock": item],
            summariesByPaneId: [only.paneId: expected]
        )

        #expect(cards[0].workItem == item)
        #expect(cards[0].sessionSummary?.latestKindRaw == "blocked")
    }
}
