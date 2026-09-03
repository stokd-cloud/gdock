import Foundation
import Testing
import CmuxSettings
import CmuxTerminalCore

#if canImport(cmux_DEV)
@testable import cmux_DEV
#elseif canImport(cmux)
@testable import cmux
#endif

/// Pure coverage for gdock Grid Mode: shape codec, cell planning, grid
/// signature matching, and the fork's settings/palette prefix conventions.
@Suite struct GdockGridModeTests {
    // MARK: - GdockGridShape codec

    @Test func parsesAndEncodesShape() throws {
        let shape = try #require(GdockGridShape(encoded: "3x2"))
        #expect(shape.rows == 3)
        #expect(shape.cols == 2)
        #expect(shape.cellCount == 6)
        #expect(shape.encoded == "3x2")
    }

    @Test func clampsShapeToBounds() {
        let oversized = GdockGridShape(rows: 99, cols: 0)
        #expect(oversized.rows == GdockGridShape.maxRows)
        #expect(oversized.cols == 1)
        let parsed = GdockGridShape(encoded: "9x9")
        #expect(parsed == GdockGridShape(rows: GdockGridShape.maxRows, cols: GdockGridShape.maxCols))
    }

    @Test func rejectsMalformedShapeStrings() {
        #expect(GdockGridShape(encoded: "") == nil)
        #expect(GdockGridShape(encoded: "2") == nil)
        #expect(GdockGridShape(encoded: "2x") == nil)
        #expect(GdockGridShape(encoded: "x2") == nil)
        #expect(GdockGridShape(encoded: "-1x2") == nil)
        #expect(GdockGridShape(encoded: "axb") == nil)
        #expect(GdockGridShape(encoded: "2x2x2") == nil)
    }

    // MARK: - Cell planning

    private func pane(_ paneId: UUID, panels: [UUID], selected: UUID? = nil) -> QuadSplitPlanner.PaneSnapshot {
        QuadSplitPlanner.PaneSnapshot(paneId: paneId, panelIds: panels, selectedPanelId: selected)
    }

    @Test func focusedPaneLeadsCellAssignment() {
        let paneA = UUID(), paneB = UUID()
        let panelA = UUID(), panelB = UUID()
        let plan = GdockGridSplitPlanner.plan(
            panes: [pane(paneA, panels: [panelA]), pane(paneB, panels: [panelB])],
            focusedPaneId: paneB,
            shape: GdockGridShape(rows: 2, cols: 2)
        )
        #expect(plan.cellPanelIds == [panelB, panelA, nil, nil])
        #expect(plan.overflowPanelIds.isEmpty)
    }

    @Test func displayedSurfaceLeadsItsPane() {
        let paneA = UUID()
        let background = UUID(), displayed = UUID()
        let plan = GdockGridSplitPlanner.plan(
            panes: [pane(paneA, panels: [background, displayed], selected: displayed)],
            focusedPaneId: paneA,
            shape: GdockGridShape(rows: 1, cols: 2)
        )
        #expect(plan.cellPanelIds == [displayed, background])
    }

    @Test func backgroundTabsFromEveryPaneBecomeVisibleCellsBeforeOverflow() {
        let paneA = UUID(), paneB = UUID()
        let a1 = UUID(), a2 = UUID(), b1 = UUID(), b2 = UUID()
        let plan = GdockGridSplitPlanner.plan(
            panes: [
                pane(paneA, panels: [a1, a2], selected: a2),
                pane(paneB, panels: [b1, b2], selected: b1),
            ],
            focusedPaneId: paneA,
            shape: GdockGridShape(rows: 2, cols: 2)
        )
        #expect(plan.cellPanelIds == [a2, a1, b1, b2])
        #expect(plan.overflowPanelIds.isEmpty)
    }

    @Test func surplusSurfacesOverflowInsteadOfHiding() {
        let paneA = UUID()
        let panels = (0..<5).map { _ in UUID() }
        let plan = GdockGridSplitPlanner.plan(
            panes: [pane(paneA, panels: panels)],
            focusedPaneId: paneA,
            shape: GdockGridShape(rows: 1, cols: 3)
        )
        #expect(plan.cellPanelIds == [panels[0], panels[1], panels[2]])
        #expect(plan.overflowPanelIds == [panels[3], panels[4]])
    }

    @Test func emptyCellsArePlaceholders() {
        let paneA = UUID()
        let panelA = UUID()
        let plan = GdockGridSplitPlanner.plan(
            panes: [pane(paneA, panels: [panelA])],
            focusedPaneId: nil,
            shape: GdockGridShape(rows: 2, cols: 2)
        )
        #expect(plan.cellPanelIds == [panelA, nil, nil, nil])
    }

    @Test func placeholderTemplateRemovesLaunchPayloadButKeepsAppearanceAndEnvironment() {
        var inherited = CmuxSurfaceConfigTemplate()
        inherited.setFontSize(15, isExplicitOverride: true)
        inherited.workingDirectory = "/tmp/gdock-grid"
        inherited.command = "stokd task"
        inherited.initialInput = "dangerous inherited input"
        inherited.environmentVariables = ["TERM_THEME": "night"]
        inherited.waitAfterCommand = true

        let clean = GdockGridSplitAction.placeholderConfigTemplate(from: inherited)

        #expect(clean.fontSize == 15)
        #expect(clean.workingDirectory == "/tmp/gdock-grid")
        #expect(clean.environmentVariables == ["TERM_THEME": "night"])
        #expect(clean.command == nil)
        #expect(clean.initialInput == nil)
        #expect(!clean.waitAfterCommand)
    }

    @Test @MainActor
    func appliedGridUsesOneFullWidthTitleHeaderPerPane() throws {
        let manager = TabManager()
        let workspace = try #require(manager.selectedWorkspace)

        let outcome = GdockGridSplitAction.applyShape(.quad, to: workspace)
        guard case .success = outcome else {
            Issue.record("expected Grid Mode to shape the workspace, got \(outcome)")
            return
        }

        #expect(workspace.bonsplitController.allPaneIds.count == 4)
        for paneId in workspace.bonsplitController.allPaneIds {
            #expect(workspace.bonsplitController.tabs(inPane: paneId).count == 1)
            #expect(workspace.bonsplitController.isFullWidthTabMode(inPane: paneId))
        }
    }

    // MARK: - New surface routing and workspace compaction

    @Test func newSurfaceActivatesPlaceholderBeforeRollingOverARealPanel() {
        let first = UUID(), placeholder = UUID(), third = UUID()
        let route = GdockGridNewSurfacePlanner.route(
            orderedPanelIds: [first, placeholder, third],
            placeholderPanelIds: [placeholder],
            touchOrder: [first: 2, third: 1]
        )
        #expect(route == .activatePlaceholder(placeholder))
    }

    @Test func fullGridRollsOverTheLeastRecentlyTouchedRealPanel() {
        let first = UUID(), oldest = UUID(), newest = UUID()
        let route = GdockGridNewSurfacePlanner.route(
            orderedPanelIds: [first, oldest, newest],
            placeholderPanelIds: [],
            touchOrder: [first: 8, oldest: 2, newest: 13]
        )
        #expect(route == .rollOver(oldest))
    }

    @Test func untouchedPanelIsOlderThanTouchedPanelsWithSpatialOrderAsTieBreaker() {
        let untouchedFirst = UUID(), untouchedSecond = UUID(), touched = UUID()
        let route = GdockGridNewSurfacePlanner.route(
            orderedPanelIds: [untouchedFirst, untouchedSecond, touched],
            placeholderPanelIds: [],
            touchOrder: [touched: 1]
        )
        #expect(route == .rollOver(untouchedFirst))
    }

    @Test func regularGridCompactionUsesTheMinimumWorkspaceCountOverall() {
        let workspaceA = UUID(), workspaceB = UUID(), workspaceC = UUID()
        let groupA = UUID(), groupB = UUID()
        let panels = (0..<5).map { _ in UUID() }
        let placeholder = UUID()
        let plan = GdockGridWorkspaceCompactionPlanner.plan(
            workspaces: [
                .init(id: workspaceA, groupId: groupA, panelIds: [panels[0], panels[1]], placeholderPanelIds: []),
                .init(id: workspaceB, groupId: groupB, panelIds: [panels[2], placeholder], placeholderPanelIds: [placeholder]),
                .init(id: workspaceC, groupId: nil, panelIds: [panels[3], panels[4]], placeholderPanelIds: []),
            ],
            capacity: 4,
            groupByRepository: false
        )

        #expect(plan.scopes.count == 1)
        #expect(plan.scopes[0].retainedWorkspaceIds == [workspaceA, workspaceB])
        #expect(plan.scopes[0].surplusWorkspaceIds == [workspaceC])
        #expect(plan.scopes[0].panelAssignments.flatMap(\.panelIds) == panels)
    }

    @Test func autoGroupGridCompactionUsesTheMinimumCountPerRepository() {
        let groupA = UUID(), groupB = UUID()
        let workspaceA1 = UUID(), workspaceA2 = UUID(), workspaceB1 = UUID(), workspaceB2 = UUID()
        let panelA = UUID(), panelB = UUID()
        let plan = GdockGridWorkspaceCompactionPlanner.plan(
            workspaces: [
                .init(id: workspaceA1, groupId: groupA, panelIds: [panelA], placeholderPanelIds: []),
                .init(id: workspaceA2, groupId: groupA, panelIds: [], placeholderPanelIds: []),
                .init(id: workspaceB1, groupId: groupB, panelIds: [panelB], placeholderPanelIds: []),
                .init(id: workspaceB2, groupId: groupB, panelIds: [], placeholderPanelIds: []),
            ],
            capacity: 4,
            groupByRepository: true
        )

        #expect(plan.scopes.count == 2)
        #expect(plan.scopes.map(\.retainedWorkspaceIds) == [[workspaceA1], [workspaceB1]])
        #expect(plan.scopes.map(\.surplusWorkspaceIds) == [[workspaceA2], [workspaceB2]])
    }

    // MARK: - Grid signature

    private func fanShape(
        _ members: [GdockGridSplitPlanner.TreeShape],
        isVertical: Bool
    ) -> GdockGridSplitPlanner.TreeShape {
        guard var result = members.last else { return .pane }
        for member in members.dropLast().reversed() {
            result = .split(isVertical: isVertical, first: member, second: result)
        }
        return result
    }

    @Test func matchesRowsFirstGrid() {
        let row = fanShape([.pane, .pane, .pane], isVertical: false)
        let tree = fanShape([row, row], isVertical: true)
        #expect(GdockGridSplitPlanner.matchesGrid(tree, shape: GdockGridShape(rows: 2, cols: 3)))
        #expect(!GdockGridSplitPlanner.matchesGrid(tree, shape: GdockGridShape(rows: 3, cols: 2)))
    }

    @Test func matchesColumnsFirstGrid() {
        // QuadSplitAction builds H(V(TL,BL), V(TR,BR)) — columns of rows.
        let column = fanShape([.pane, .pane], isVertical: true)
        let tree = fanShape([column, column], isVertical: false)
        #expect(GdockGridSplitPlanner.matchesGrid(tree, shape: GdockGridShape(rows: 2, cols: 2)))
    }

    @Test func matchesSingleRowAndSingleColumn() {
        let rowTree = fanShape([.pane, .pane, .pane], isVertical: false)
        #expect(GdockGridSplitPlanner.matchesGrid(rowTree, shape: GdockGridShape(rows: 1, cols: 3)))
        let colTree = fanShape([.pane, .pane, .pane], isVertical: true)
        #expect(GdockGridSplitPlanner.matchesGrid(colTree, shape: GdockGridShape(rows: 3, cols: 1)))
        #expect(GdockGridSplitPlanner.matchesGrid(.pane, shape: GdockGridShape(rows: 1, cols: 1)))
    }

    @Test func rejectsRaggedTrees() {
        // V(H(p,p), p): two columns on top, one full-width pane below.
        let ragged = GdockGridSplitPlanner.TreeShape.split(
            isVertical: true,
            first: fanShape([.pane, .pane], isVertical: false),
            second: .pane
        )
        #expect(!GdockGridSplitPlanner.matchesGrid(ragged, shape: GdockGridShape(rows: 2, cols: 2)))
        #expect(!GdockGridSplitPlanner.matchesGrid(ragged, shape: GdockGridShape(rows: 2, cols: 1)))
    }

    // MARK: - Fork conventions

    @Test func settingCatalogKeysUseGdockPrefix() {
        let mode = SettingCatalog().gdock.gridMode
        #expect(mode.id == "gdock.gridMode")
        #expect(mode.userDefaultsKey == "gdock.gridMode")
        #expect(mode.defaultValue == false)

        let shape = SettingCatalog().gdock.gridModeShape
        #expect(shape.id == "gdock.gridModeShape")
        #expect(shape.userDefaultsKey == "gdock.gridModeShape")
        #expect(shape.defaultValue == "2x2")
        #expect(GdockGridShape(encoded: shape.defaultValue) == .quad)
    }

    @Test func settingsAreDeclaredAsSupportedJSONPaths() {
        #expect(CmuxSettingsFileStore.supportedSettingsJSONPaths.contains("gdock.gridMode"))
        #expect(CmuxSettingsFileStore.supportedSettingsJSONPaths.contains("gdock.gridModeShape"))
    }

    @Test func paletteToggleUsesGdockPrefixedCommandId() throws {
        let descriptor = try #require(
            CommandPaletteSettingsToggleCommands.descriptor(
                commandId: "palette.toggleSetting.gdock.gridMode"
            )
        )
        #expect(descriptor.settingsKey == "gdock.gridMode")
        #expect(descriptor.commandId.hasPrefix("palette.toggleSetting.gdock."))
    }
}
