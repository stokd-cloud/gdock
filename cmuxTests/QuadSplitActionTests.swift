import AppKit
import Bonsplit
import Foundation
import Testing
import XCTest

#if canImport(cmux_DEV)
@testable import cmux_DEV
#elseif canImport(cmux)
@testable import cmux
#endif

/// VAL-QUAD-001 / VAL-QUAD-004 / VAL-QUAD-006: shared quad mutation, topology,
/// focus, leaf replacement, preflight veto catalog, and late failure.
@Suite("Quad split action", .serialized)
struct QuadSplitActionTests {
    @Test("perform is callable on a workspace")
    @MainActor
    func performIsCallableOnWorkspace() throws {
        let manager = TabManager()
        let workspace = try #require(manager.selectedWorkspace)
        let pane = try #require(workspace.bonsplitController.allPaneIds.first)
        // Smoke: call does not trap.
        _ = QuadSplitAction.perform(inPane: pane, workspace: workspace)
    }

    @Test("one-pane fixture becomes four panes with one terminal each")
    @MainActor
    func quadSplitProducesFourPanes() throws {
        let manager = TabManager()
        let workspace = try #require(manager.selectedWorkspace)
        let rootPane = try #require(workspace.bonsplitController.allPaneIds.first)
        let originalPanelId = try #require(workspace.focusedPanelId)
        #expect(workspace.bonsplitController.allPaneIds.count == 1)

        #expect(QuadSplitAction.perform(inPane: rootPane, workspace: workspace))
        #expect(workspace.bonsplitController.allPaneIds.count == 4)

        for pane in workspace.bonsplitController.allPaneIds {
            let tabs = workspace.bonsplitController.tabs(inPane: pane)
            #expect(tabs.count == 1)
            let tabId = try #require(tabs.first?.id)
            let panelId = try #require(workspace.panelIdFromSurfaceId(tabId))
            #expect(workspace.terminalPanel(for: panelId) != nil)
        }
        #expect(workspace.panels[originalPanelId] != nil)
    }

    @Test("true 2x2 topology: H(V,V) with focus on bottom-right")
    @MainActor
    func quadSplitProducesTrueTwoByTwoTopology() throws {
        let manager = TabManager()
        let workspace = try #require(manager.selectedWorkspace)
        let rootPane = try #require(workspace.bonsplitController.allPaneIds.first)
        let originalPanelId = try #require(workspace.focusedPanelId)

        #expect(QuadSplitAction.perform(inPane: rootPane, workspace: workspace))

        let tree = workspace.bonsplitController.treeSnapshot()
        guard case .split(let root) = tree else {
            Issue.record("expected root split, got \(tree)")
            return
        }
        #expect(root.orientation == "horizontal")
        guard case .split(let left) = root.first else {
            Issue.record("expected left vertical split")
            return
        }
        guard case .split(let right) = root.second else {
            Issue.record("expected right vertical split")
            return
        }
        #expect(left.orientation == "vertical")
        #expect(right.orientation == "vertical")

        guard case .pane(let topLeft) = left.first,
              case .pane = left.second,
              case .pane = right.first,
              case .pane(let bottomRight) = right.second else {
            Issue.record("expected four leaf panes under H(V,V)")
            return
        }

        // Original content stays top-left.
        let topLeftSelected = topLeft.selectedTabId ?? topLeft.tabs.first?.id
        if let topLeftSelected,
           let tabUUID = UUID(uuidString: topLeftSelected) {
            let panelId = workspace.panelIdFromSurfaceId(TabID(uuid: tabUUID))
            #expect(panelId == originalPanelId)
        }

        // Final focus is bottom-right (B).
        let focusedPane = try #require(workspace.bonsplitController.focusedPaneId)
        #expect(focusedPane.id.uuidString == bottomRight.id)
        #expect(workspace.focusedPanelId != originalPanelId)
    }

    @Test("allowSplits false is an atomic veto")
    @MainActor
    func quadSplitRespectsAllowSplitsFalse() throws {
        let manager = TabManager()
        let workspace = try #require(manager.selectedWorkspace)
        let rootPane = try #require(workspace.bonsplitController.allPaneIds.first)
        var configuration = workspace.bonsplitController.configuration
        configuration.allowSplits = false
        workspace.bonsplitController.configuration = configuration

        let outcome = QuadSplitAction.performDetailed(inPane: rootPane, workspace: workspace)
        #expect(outcome == .vetoed(.allowSplitsDisabled))
        #expect(workspace.bonsplitController.allPaneIds.count == 1)
    }

    @Test("remote mirror is preflighted without side effects")
    @MainActor
    func remoteMirrorVetoIsAtomic() throws {
        let manager = TabManager()
        let workspace = try #require(manager.selectedWorkspace)
        let rootPane = try #require(workspace.bonsplitController.allPaneIds.first)
        workspace.isRemoteTmuxMirror = true

        let outcome = QuadSplitAction.performDetailed(inPane: rootPane, workspace: workspace)
        #expect(outcome == .vetoed(.remoteMirror))
        #expect(workspace.bonsplitController.allPaneIds.count == 1)
    }

    @Test("canvas mode is a known veto")
    @MainActor
    func canvasModeVetoIsAtomic() throws {
        let manager = TabManager()
        let workspace = try #require(manager.selectedWorkspace)
        let rootPane = try #require(workspace.bonsplitController.allPaneIds.first)
        workspace.layoutMode = .canvas

        let outcome = QuadSplitAction.performDetailed(inPane: rootPane, workspace: workspace)
        #expect(outcome == .vetoed(.canvasMode))
        #expect(workspace.bonsplitController.allPaneIds.count == 1)
    }

    @Test("missing target pane is a known veto")
    @MainActor
    func missingTargetVetoIsAtomic() throws {
        let manager = TabManager()
        let workspace = try #require(manager.selectedWorkspace)
        let bogus = PaneID()
        let before = workspace.bonsplitController.allPaneIds.count
        let outcome = QuadSplitAction.performDetailed(inPane: bogus, workspace: workspace)
        #expect(outcome == .vetoed(.missingTarget))
        #expect(workspace.bonsplitController.allPaneIds.count == before)
    }

    @Test("noninteractive controller is a known veto")
    @MainActor
    func noninteractiveVetoIsAtomic() throws {
        let manager = TabManager()
        let workspace = try #require(manager.selectedWorkspace)
        let rootPane = try #require(workspace.bonsplitController.allPaneIds.first)
        workspace.bonsplitController.isInteractive = false
        let outcome = QuadSplitAction.performDetailed(inPane: rootPane, workspace: workspace)
        #expect(outcome == .vetoed(.noninteractive))
        #expect(workspace.bonsplitController.allPaneIds.count == 1)
    }

    @Test("quad replaces only the targeted leaf in an existing topology")
    @MainActor
    func quadReplacesOnlyTargetLeaf() throws {
        let manager = TabManager()
        let workspace = try #require(manager.selectedWorkspace)
        let leftPanelId = try #require(workspace.focusedPanelId)
        // Build L | R first, then quad the right leaf so left branch is unrelated.
        let rightPanel = try #require(
            workspace.newTerminalSplit(from: leftPanelId, orientation: .horizontal, focus: false)
        )
        let rightPane = try #require(workspace.paneId(forPanelId: rightPanel.id))
        let leftPane = try #require(workspace.paneId(forPanelId: leftPanelId))
        let panesBefore = workspace.bonsplitController.allPaneIds.count
        #expect(panesBefore == 2)

        #expect(QuadSplitAction.perform(inPane: rightPane, workspace: workspace))
        // +3 panes from the target leaf replacement.
        #expect(workspace.bonsplitController.allPaneIds.count == panesBefore + 3)
        // Unrelated left leaf preserved with original content.
        #expect(workspace.paneId(forPanelId: leftPanelId) == leftPane)
        #expect(workspace.panels[leftPanelId] != nil)
        // Original right content still exists (top-left of the replaced subtree).
        #expect(workspace.panels[rightPanel.id] != nil)
    }

    @Test("recipe source shape is pinned: three splits, no outer programmatic guard")
    func quadRecipeShapeIsPinned() throws {
        let sourceURL = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .appendingPathComponent("Sources/QuadSplitAction.swift")
        let source = try String(contentsOf: sourceURL, encoding: .utf8)
        let splitCount = source.components(separatedBy: "splitPaneWithNewTerminal").count - 1
        #expect(splitCount == 3)
        #expect(!source.contains("isProgrammaticSplit"))
    }

    @Test("createQuadSplit on TabManager shares the action")
    @MainActor
    func tabManagerCreateQuadSplitSharesAction() throws {
        let manager = TabManager()
        let workspace = try #require(manager.selectedWorkspace)
        let panelId = try #require(workspace.focusedPanelId)
        #expect(manager.createQuadSplit(tabId: workspace.id, surfaceId: panelId, focus: true))
        #expect(workspace.bonsplitController.allPaneIds.count == 4)
    }
}
