import AppKit
import Bonsplit
import CmuxCore
import CmuxSettings
import Foundation
import Testing

#if canImport(cmux_DEV)
@testable import cmux_DEV
#elseif canImport(cmux)
@testable import cmux
#endif

@Suite("Auto Split action", .serialized)
struct AutoSplitActionTests {
    @MainActor
    private func withGridModeDisabled(_ body: () throws -> Void) rethrows {
        let previous = GdockGridModeSettings.isEnabled()
        GdockGridModeSettings.setEnabled(false)
        defer { GdockGridModeSettings.setEnabled(previous) }
        try body()
    }

    @Test("2x2 Auto Split matches Split Quad pane count and focus")
    @MainActor
    func twoByTwoMatchesSplitQuad() throws {
        try withGridModeDisabled {
            let manager = TabManager()
            let workspace = try #require(manager.selectedWorkspace)
            let rootPane = try #require(workspace.bonsplitController.allPaneIds.first)
            let originalPanelId = try #require(workspace.focusedPanelId)
            let shape = GdockAutoSplitterSettings.Shape.clamped(rows: 2, cols: 2)
            #expect(AutoSplitAction.perform(inPane: rootPane, workspace: workspace, shape: shape))
            #expect(workspace.bonsplitController.allPaneIds.count == 4)
            #expect(workspace.panels[originalPanelId] != nil)
            #expect(workspace.focusedPanelId != originalPanelId)
        }
    }

    @Test(arguments: [
        (1, 2, 2),
        (2, 1, 2),
        (2, 3, 6),
        (3, 2, 6),
    ])
    @MainActor
    func nestedShapesProduceExpectedPaneCount(_ spec: (Int, Int, Int)) throws {
        try withGridModeDisabled {
            let manager = TabManager()
            let workspace = try #require(manager.selectedWorkspace)
            let rootPane = try #require(workspace.bonsplitController.allPaneIds.first)
            let originalPanelId = try #require(workspace.focusedPanelId)
            let shape = GdockAutoSplitterSettings.Shape.clamped(rows: spec.0, cols: spec.1)
            #expect(AutoSplitAction.perform(inPane: rootPane, workspace: workspace, shape: shape))
            #expect(workspace.bonsplitController.allPaneIds.count == spec.2)
            #expect(workspace.panels[originalPanelId] != nil)
            #expect(workspace.focusedPanelId != originalPanelId)
        }
    }

    @Test("1x1 is a no-op")
    @MainActor
    func oneByOneDoesNotMutate() throws {
        try withGridModeDisabled {
            let manager = TabManager()
            let workspace = try #require(manager.selectedWorkspace)
            let rootPane = try #require(workspace.bonsplitController.allPaneIds.first)
            let before = workspace.bonsplitController.allPaneIds.count
            let outcome = AutoSplitAction.performDetailed(
                inPane: rootPane,
                workspace: workspace,
                shape: .clamped(rows: 1, cols: 1)
            )
            #expect(outcome == .noop)
            #expect(workspace.bonsplitController.allPaneIds.count == before)
        }
    }

    @Test("canvas veto is atomic")
    @MainActor
    func canvasVetoIsAtomic() throws {
        try withGridModeDisabled {
            let manager = TabManager()
            let workspace = try #require(manager.selectedWorkspace)
            let rootPane = try #require(workspace.bonsplitController.allPaneIds.first)
            workspace.layoutMode = .canvas
            let outcome = AutoSplitAction.performDetailed(
                inPane: rootPane,
                workspace: workspace,
                shape: .clamped(rows: 2, cols: 3)
            )
            #expect(outcome == .vetoed(.canvasMode))
            #expect(workspace.bonsplitController.allPaneIds.count == 1)
        }
    }

    @Test("TabManager.createAutoSplit shares the action")
    @MainActor
    func tabManagerCreateAutoSplitSharesAction() throws {
        try withGridModeDisabled {
            let manager = TabManager()
            let workspace = try #require(manager.selectedWorkspace)
            let panelId = try #require(workspace.focusedPanelId)
            #expect(manager.createAutoSplit(tabId: workspace.id, surfaceId: panelId, focus: true))
            #expect(workspace.bonsplitController.allPaneIds.count == 4)
        }
    }

    @Test("Grid Mode vetoes Auto Split so the enforcer is not fought")
    @MainActor
    func gridModeVetoesAutoSplit() throws {
        let previous = GdockGridModeSettings.isEnabled()
        GdockGridModeSettings.setEnabled(true)
        defer { GdockGridModeSettings.setEnabled(previous) }
        let manager = TabManager()
        let workspace = try #require(manager.selectedWorkspace)
        let rootPane = try #require(workspace.bonsplitController.allPaneIds.first)
        let outcome = AutoSplitAction.performDetailed(
            inPane: rootPane,
            workspace: workspace,
            shape: .clamped(rows: 2, cols: 2)
        )
        #expect(outcome == .gridMode)
        #expect(workspace.bonsplitController.allPaneIds.count == 1)
    }
}
