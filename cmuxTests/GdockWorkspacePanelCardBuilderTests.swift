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
}
