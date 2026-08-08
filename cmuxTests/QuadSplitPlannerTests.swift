import Foundation
import Testing

#if canImport(cmux_DEV)
@testable import cmux_DEV
#elseif canImport(cmux)
@testable import cmux
#endif

/// Quadrant assignment for Quad Split.
///
/// The reported defect was that Quad Split nested a 2x2 inside the focused leaf
/// and always spawned four fresh terminals, burying whatever the workspace
/// already held. These pin the replacement contract: always exactly four
/// quadrants, existing surfaces reused before new terminals, nothing dropped.
@Suite struct QuadSplitPlannerTests {
    private typealias Planner = QuadSplitPlanner
    private typealias Pane = QuadSplitPlanner.PaneSnapshot

    private func pane(_ paneId: UUID, _ panelIds: [UUID], selected: UUID? = nil) -> Pane {
        Pane(paneId: paneId, panelIds: panelIds, selectedPanelId: selected ?? panelIds.first)
    }

    // MARK: - Shape

    @Test func alwaysPlansExactlyFourQuadrants() {
        for paneCount in 1...7 {
            let panes = (0..<paneCount).map { _ in pane(UUID(), [UUID()]) }
            let plan = Planner.plan(panes: panes, targetPaneId: panes[0].paneId)
            #expect(plan?.count == 4, "paneCount=\(paneCount)")
        }
    }

    @Test func targetPaneAlwaysLeadsTopLeft() {
        let a = UUID(), b = UUID(), c = UUID()
        let panes = [pane(UUID(), [a]), pane(UUID(), [b]), pane(UUID(), [c])]
        let plan = Planner.plan(panes: panes, targetPaneId: panes[1].paneId)
        #expect(plan?[0].leadPanelId == b)
    }

    @Test func returnsNilForUnknownOrEmptyTargetPane() {
        let panes = [pane(UUID(), [UUID()])]
        #expect(Planner.plan(panes: panes, targetPaneId: UUID()) == nil)

        let emptyPaneId = UUID()
        let withEmpty = [Pane(paneId: emptyPaneId, panelIds: [], selectedPanelId: nil)]
        #expect(Planner.plan(panes: withEmpty, targetPaneId: emptyPaneId) == nil)
    }

    // MARK: - Reuse before new terminals

    @Test func singlePaneSinglePanelSpawnsThreeNewTerminals() {
        let only = UUID()
        let panes = [pane(UUID(), [only])]
        let plan = try! #require(Planner.plan(panes: panes, targetPaneId: panes[0].paneId))

        #expect(plan[0].leadPanelId == only)
        #expect(plan.dropFirst().allSatisfy { $0.needsNewTerminal })
    }

    @Test func backgroundTabsFillQuadrantsBeforeNewTerminals() {
        // One pane holding four surfaces: the three hidden ones become quadrants
        // instead of three brand-new shells.
        let visible = UUID(), hidden1 = UUID(), hidden2 = UUID(), hidden3 = UUID()
        let panes = [pane(UUID(), [visible, hidden1, hidden2, hidden3], selected: visible)]
        let plan = try! #require(Planner.plan(panes: panes, targetPaneId: panes[0].paneId))

        #expect(plan.allSatisfy { !$0.needsNewTerminal })
        #expect(plan[0].leadPanelId == visible)
        #expect(Set(plan.compactMap(\.leadPanelId)) == [visible, hidden1, hidden2, hidden3])
    }

    @Test func existingPanesBecomeQuadrantsInTreeOrder() {
        let a = UUID(), b = UUID(), c = UUID(), d = UUID()
        let panes = [pane(UUID(), [a]), pane(UUID(), [b]), pane(UUID(), [c]), pane(UUID(), [d])]
        let plan = try! #require(Planner.plan(panes: panes, targetPaneId: panes[0].paneId))

        #expect(plan.map(\.leadPanelId) == [a, b, c, d])
        #expect(plan.allSatisfy { $0.trailingPanelIds.isEmpty })
    }

    @Test func partiallySplitWorkspaceReusesBothPanesThenFills() {
        let a = UUID(), b = UUID()
        let panes = [pane(UUID(), [a]), pane(UUID(), [b])]
        let plan = try! #require(Planner.plan(panes: panes, targetPaneId: panes[0].paneId))

        #expect(plan[0].leadPanelId == a)
        #expect(plan[1].leadPanelId == b)
        #expect(plan[2].needsNewTerminal)
        #expect(plan[3].needsNewTerminal)
    }

    // MARK: - Nothing is lost

    @Test func everyExistingSurfaceSurvivesSomewhere() {
        let panelIds = (0..<11).map { _ in UUID() }
        let panes = [
            pane(UUID(), Array(panelIds[0...3])),
            pane(UUID(), Array(panelIds[4...6])),
            pane(UUID(), Array(panelIds[7...8])),
            pane(UUID(), [panelIds[9]]),
            pane(UUID(), [panelIds[10]]),
        ]
        let plan = try! #require(Planner.plan(panes: panes, targetPaneId: panes[0].paneId))

        #expect(Set(plan.flatMap(\.allPanelIds)) == Set(panelIds))
        // No surface is placed twice.
        #expect(plan.flatMap(\.allPanelIds).count == panelIds.count)
    }

    @Test func surplusPanesFoldIntoQuadrantsAsBackgroundTabs() {
        let leads = (0..<6).map { _ in UUID() }
        let panes = leads.map { pane(UUID(), [$0]) }
        let plan = try! #require(Planner.plan(panes: panes, targetPaneId: panes[0].paneId))

        #expect(plan.map(\.leadPanelId) == Array(leads[0...3]))
        // Panes 5 and 6 survive as tabs rather than being discarded.
        #expect(plan[0].trailingPanelIds == [leads[4]])
        #expect(plan[1].trailingPanelIds == [leads[5]])
        #expect(plan.allSatisfy { !$0.needsNewTerminal })
    }

    @Test func surplusTabsStayWithTheirOwnQuadrant() {
        // Four panes already: each keeps its own hidden tabs, nothing migrates.
        let leads = (0..<4).map { _ in UUID() }
        let extras = (0..<4).map { _ in UUID() }
        let panes = (0..<4).map { pane(UUID(), [leads[$0], extras[$0]]) }
        let plan = try! #require(Planner.plan(panes: panes, targetPaneId: panes[0].paneId))

        for index in 0..<4 {
            #expect(plan[index].leadPanelId == leads[index])
            #expect(plan[index].trailingPanelIds == [extras[index]])
        }
    }

    // MARK: - Display continuity

    @Test func displayedSurfaceLeadsItsQuadrant() {
        let hidden = UUID(), visible = UUID()
        let panes = [pane(UUID(), [hidden, visible], selected: visible)]
        let plan = try! #require(Planner.plan(panes: panes, targetPaneId: panes[0].paneId))

        #expect(plan[0].leadPanelId == visible)
    }

    @Test func promotingSpreadsFromTheMostCrowdedPane() {
        // Crowded pane donates; the single-surface pane keeps its surface displayed.
        let crowded = (0..<4).map { _ in UUID() }
        let lonely = UUID()
        let panes = [pane(UUID(), crowded), pane(UUID(), [lonely])]
        let plan = try! #require(Planner.plan(panes: panes, targetPaneId: panes[0].paneId))

        #expect(plan[0].leadPanelId == crowded[0])
        #expect(plan[1].leadPanelId == lonely)
        #expect(plan.allSatisfy { !$0.needsNewTerminal })
        #expect(Set(plan.flatMap(\.allPanelIds)) == Set(crowded + [lonely]))
    }
}
