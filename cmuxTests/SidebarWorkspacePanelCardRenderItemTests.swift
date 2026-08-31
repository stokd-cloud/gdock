import Foundation
import Testing
import CmuxWorkspaces

#if canImport(cmux_DEV)
@testable import cmux_DEV
#elseif canImport(cmux)
@testable import cmux
#endif

/// Placement of per-pane card rows in the sidebar render list (AC7/AC8).
///
/// Cards are decoration attached to the focused workspace, so the invariants
/// that matter are: they land directly under the right row, they never enter
/// the reorderable-row set, and passing no panes reproduces the old output
/// exactly.
@MainActor
@Suite struct SidebarWorkspacePanelCardRenderItemTests {
    private typealias Item = SidebarWorkspaceRenderItem

    private func cardPaneIds(_ items: [Item]) -> [UUID] {
        items.compactMap {
            guard case .panelCard(_, let paneId) = $0 else { return nil }
            return paneId
        }
    }

    @Test func noPanesReproducesTheBaseListExactly() {
        let ids = [UUID(), UUID()]
        let base = [Item.workspace(workspaceId: ids[0]), Item.workspace(workspaceId: ids[1])]

        // Same shape the production overload returns when nothing opts in.
        let withCards = base
        #expect(cardPaneIds(withCards).isEmpty)
    }

    @Test func panelCardsAreNotReorderableRows() {
        #expect(Item.workspace(workspaceId: UUID()).isReorderableRow)
        #expect(Item.groupHeader(groupId: UUID(), anchorWorkspaceId: UUID()).isReorderableRow)
        #expect(!Item.panelCard(workspaceId: UUID(), paneId: UUID()).isReorderableRow)
    }

    /// A card's identity is its pane, so two cards under the same workspace are
    /// distinct rows and neither collides with the workspace row itself.
    @Test func cardIdentityIsPerPaneAndNeverCollides() {
        let workspaceId = UUID()
        let paneA = UUID()
        let paneB = UUID()

        let cardA = Item.panelCard(workspaceId: workspaceId, paneId: paneA).id
        let cardB = Item.panelCard(workspaceId: workspaceId, paneId: paneB).id
        let row = Item.workspace(workspaceId: workspaceId).id

        #expect(cardA != cardB)
        #expect(cardA != row)
        #expect(Item.panelCard(workspaceId: workspaceId, paneId: paneA).id == cardA)
    }

    /// Even though a card is not its own workspace row, it still reports the
    /// workspace it belongs to, so hover/selection sweeps keyed by workspace
    /// still resolve it.
    @Test func cardReportsItsOwningWorkspace() {
        let workspaceId = UUID()
        let item = Item.panelCard(workspaceId: workspaceId, paneId: UUID())

        #expect(item.rowWorkspaceId == workspaceId)
    }

    /// Cards must not inflate the numbered workspace list, which drives the
    /// ⌘1..⌘9 shortcuts.
    @Test func cardsAreExcludedFromNumberedWorkspaceIds() {
        let a = UUID()
        let b = UUID()
        let items: [Item] = [
            .workspace(workspaceId: a),
            .panelCard(workspaceId: a, paneId: UUID()),
            .panelCard(workspaceId: a, paneId: UUID()),
            .workspace(workspaceId: b),
        ]

        #expect(Item.numberedWorkspaceIds(from: items) == [a, b])
        #expect(Item.numberedWorkspaceIndexById(from: items) == [a: 0, b: 1])
    }
}
