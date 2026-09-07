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

    // MARK: - Session round-trip and dormant cell admission

    @Test @MainActor
    func gridSessionRestorePreservesEverySavedPanel() throws {
        try withGridReconcileContext { _, manager in
            let source = try #require(manager.selectedWorkspace)
            let pane = try #require(source.bonsplitController.allPaneIds.first)
            for _ in 0..<3 {
                _ = try #require(source.newTerminalSurface(inPane: pane, focus: false))
            }
            #expect(GdockGridSplitAction.applyShape(.quad, to: source) == .success(overflowPanelIds: []))
            let snapshot = try roundTrip(source.sessionSnapshot(includeScrollback: false))
            let restored = Workspace()

            let mapping = restored.restoreSessionSnapshot(snapshot)

            #expect(Set(mapping.keys) == Set(snapshot.panels.map(\.id)))
            #expect(Set(mapping.values) == Set(restored.panels.keys))
            #expect(restored.panels.count == 4)
            #expect(restored.bonsplitController.allPaneIds.count == 4)
            #expect(restored.gdockGridPlaceholderPanelIds.isEmpty)
            // The internal restore exemption must not leave user splits unlocked.
            #expect(!restored.isApplyingGdockGridShape)
            let restoredPane = try #require(restored.bonsplitController.allPaneIds.first)
            #expect(!restored.splitTabBar(
                restored.bonsplitController, shouldSplitPane: restoredPane, orientation: .horizontal
            ))
        }
    }

    @Test @MainActor
    func placeholderSnapshotPayloadPersistsOnlyDormantCells() throws {
        try withGridReconcileContext { _, manager in
            let source = try #require(manager.selectedWorkspace)
            #expect(GdockGridSplitAction.applyShape(.quad, to: source) == .success(overflowPanelIds: []))
            let snapshot = try roundTrip(source.sessionSnapshot(includeScrollback: false))
            var markedIds = Set<UUID>()
            for panel in snapshot.panels {
                let terminal = try #require(panel.terminal)
                let payload = try #require(JSONSerialization.jsonObject(
                    with: JSONEncoder().encode(terminal)
                ) as? [String: Any])
                if payload["isGdockGridPlaceholder"] as? Bool == true {
                    markedIds.insert(panel.id)
                }
            }
            #expect(markedIds.count == 3)
            #expect(markedIds == source.gdockGridPlaceholderPanelIds)
        }
    }

    @Test @MainActor
    func gridSessionRoundTripKeepsUnusedCellsDormantUntilActivation() throws {
        try withGridReconcileContext { _, manager in
            let source = try #require(manager.selectedWorkspace)
            #expect(GdockGridSplitAction.applyShape(.quad, to: source) == .success(overflowPanelIds: []))
            let placeholderIds = source.gdockGridPlaceholderPanelIds
            try #require(placeholderIds.count == 3)
            let snapshot = try roundTrip(source.sessionSnapshot(includeScrollback: false))
            let restored = Workspace()

            let mapping = restored.restoreSessionSnapshot(snapshot)
            restored.terminalStartupRestoreCoordinator.commitPendingRestores()

            #expect(Set(mapping.keys) == Set(snapshot.panels.map(\.id)))
            #expect(restored.panels.count == 4)
            let restoredPlaceholderIds = Set(placeholderIds.compactMap { mapping[$0] })
            #expect(restoredPlaceholderIds == restored.gdockGridPlaceholderPanelIds)
            try #require(restored.gdockGridPlaceholderPanelIds.count == 3)
            for panelId in restoredPlaceholderIds {
                let panel = try #require(restored.terminalPanel(for: panelId))
                #expect(!panel.surface.canCreateRuntimeSurface)
            }

            let activatedId = try #require(restoredPlaceholderIds.first)
            restored.activateGdockGridPlaceholderIfNeeded(panelId: activatedId)
            #expect(!restored.isGdockGridPlaceholder(panelId: activatedId))
            #expect(try #require(restored.terminalPanel(for: activatedId)).surface.canCreateRuntimeSurface)
            for panelId in restoredPlaceholderIds.subtracting([activatedId]) {
                #expect(restored.isGdockGridPlaceholder(panelId: panelId))
                #expect(!(try #require(restored.terminalPanel(for: panelId))).surface.canCreateRuntimeSurface)
            }
        }
    }

    @Test @MainActor
    func restoredGridCellsRemainUsableWhenGridModeIsDisabled() throws {
        try withGridReconcileContext { _, manager in
            let source = try #require(manager.selectedWorkspace)
            _ = GdockGridSplitAction.applyShape(.quad, to: source)
            let snapshot = try roundTrip(source.sessionSnapshot(includeScrollback: false))
            GdockGridModeSettings.setEnabled(false)
            let restored = Workspace()

            let mapping = restored.restoreSessionSnapshot(snapshot)

            #expect(Set(mapping.keys) == Set(snapshot.panels.map(\.id)))
            #expect(restored.panels.count == 4)
            #expect(restored.gdockGridPlaceholderPanelIds.isEmpty)
            for panelId in restored.panels.keys {
                #expect(try #require(restored.terminalPanel(for: panelId)).surface.canCreateRuntimeSurface)
            }
        }
    }

    @Test @MainActor
    func legacyUnmarkedTerminalRestoresAsOrdinaryTerminal() throws {
        try withGridReconcileContext { _, manager in
            let source = try #require(manager.selectedWorkspace)
            var snapshot = source.sessionSnapshot(includeScrollback: false)
            snapshot.panels[0].terminal = try JSONDecoder().decode(
                SessionTerminalPanelSnapshot.self, from: Data("{\"isRemoteTerminal\":false}".utf8)
            )
            snapshot = try roundTrip(snapshot)
            let restored = Workspace()

            let mapping = restored.restoreSessionSnapshot(snapshot)

            #expect(Set(mapping.keys) == Set(snapshot.panels.map(\.id)))
            #expect(restored.gdockGridPlaceholderPanelIds.isEmpty)
            let panelId = try #require(mapping[snapshot.panels[0].id])
            #expect(try #require(restored.terminalPanel(for: panelId)).surface.canCreateRuntimeSurface)
        }
    }

    private func roundTrip(_ snapshot: SessionWorkspaceSnapshot) throws -> SessionWorkspaceSnapshot {
        try JSONDecoder().decode(SessionWorkspaceSnapshot.self, from: JSONEncoder().encode(snapshot))
    }

    // MARK: - New surface routing and workspace compaction

    @Test @MainActor
    func repeatedGroupedCompactionConservesRealTerminals() throws {
        try withGridReconcileContext { app, manager in
            let first = try #require(manager.selectedWorkspace)
            let second = manager.addWorkspace(select: false)
            let originalPanels = Set(manager.tabs.flatMap { $0.panels.keys })
            let groupId = try #require(manager.createWorkspaceGroup(
                name: "Grid regression",
                childWorkspaceIds: [first.id, second.id],
                selectAnchor: false,
                collapseSidebarSelection: false,
                insertDedicatedAnchor: false
            ))
            for workspace in manager.tabs {
                #expect(GdockGridSplitAction.applyShape(.quad, to: workspace) == .success(overflowPanelIds: []))
            }

            for _ in 0..<3 {
                manager.reconcileGdockGridModeNow()
                let realPanels = Set(manager.tabs.flatMap { workspace in
                    workspace.panels.keys.filter { !workspace.isGdockGridPlaceholder(panelId: $0) }
                })
                try #require(realPanels == originalPanels)
                try #require(manager.tabs.count == 1)
                let retained = try #require(manager.tabs.first)
                #expect(retained.groupId == groupId)
                #expect(GdockGridSplitAction.matchesShape(.quad, workspace: retained))
                #expect(retained.gdockGridPlaceholderPanelIds.count == 2)
            }
        }
    }

    @Test @MainActor
    func singleCellSpillMovesExistingPanelWithoutStartingAnotherTerminal() throws {
        try withGridReconcileContext { app, manager in
            let workspace = try #require(manager.selectedWorkspace)
            let pane = try #require(workspace.bonsplitController.allPaneIds.first)
            let extra = try #require(workspace.newTerminalSurface(inPane: pane, focus: false))
            let originalPanels = Set(workspace.panels.keys)
            let groupId = try #require(manager.createWorkspaceGroup(
                name: "Grid spill regression",
                childWorkspaceIds: [workspace.id],
                selectAnchor: false,
                collapseSidebarSelection: false,
                insertDedicatedAnchor: false
            ))

            let spill = try #require(manager.applyGdockGridShapeAndSpill(
                GdockGridShape(rows: 1, cols: 1), to: workspace
            ))
            #expect(spill.panels[extra.id] != nil)
            #expect(spill.panels.count == 1)
            #expect(spill.groupId == groupId)
            #expect(Set(manager.tabs.flatMap { $0.panels.keys }) == originalPanels)
        }
    }

    @Test @MainActor
    func failedSpillTransferDoesNotCreateWorkspaceOrLosePanels() throws {
        try withGridReconcileContext { app, manager in
            let workspace = try #require(manager.selectedWorkspace)
            let pane = try #require(workspace.bonsplitController.allPaneIds.first)
            _ = try #require(workspace.newTerminalSurface(inPane: pane, focus: false))
            let originalPanels = Set(workspace.panels.keys)
            // A missing source registration makes the real transfer path fail.
            app.unregisterMainWindowContextForTesting(windowId: try #require(manager.windowId))

            let spill = manager.applyGdockGridShapeAndSpill(
                GdockGridShape(rows: 1, cols: 1), to: workspace
            )
            #expect(spill == nil)
            #expect(manager.tabs.count == 1)
            #expect(Set(workspace.panels.keys) == originalPanels)
        }
    }

    @MainActor
    private func withGridReconcileContext(
        _ body: (AppDelegate, TabManager) throws -> Void
    ) rethrows {
        let previousApp = AppDelegate.shared
        let previousGrid = UserDefaults.standard.object(forKey: GdockGridModeSettings.userDefaultsKey)
        let previousGroup = UserDefaults.standard.object(forKey: GdockAutoWorkspaceGroupModeSettings.userDefaultsKey)
        let previousShape = UserDefaults.standard.object(forKey: GdockGridModeSettings.shapeUserDefaultsKey)
        GdockGridModeSettings.setEnabled(true)
        GdockAutoWorkspaceGroupModeSettings.setEnabled(true)
        GdockGridModeSettings.setShape(.quad)
        let app = AppDelegate()
        AppDelegate.shared = app
        let manager = TabManager()
        let windowId = app.registerMainWindowContextForTesting(tabManager: manager)
        defer {
            manager.gdockGridModeReconcileTask?.cancel()
            manager.gdockAutoWorkspaceGroupReconcileTask?.cancel()
            app.unregisterMainWindowContextForTesting(windowId: windowId)
            AppDelegate.shared = previousApp
            UserDefaults.standard.set(previousGrid, forKey: GdockGridModeSettings.userDefaultsKey)
            UserDefaults.standard.set(previousGroup, forKey: GdockAutoWorkspaceGroupModeSettings.userDefaultsKey)
            UserDefaults.standard.set(previousShape, forKey: GdockGridModeSettings.shapeUserDefaultsKey)
        }
        try body(app, manager)
    }

    @Test @MainActor
    func failedCompactionKeepsTheSourceRealPanels() throws {
        try withGridReconcileContext { app, manager in
            _ = manager.addWorkspace(select: false)
            let originalPanels = Set(manager.tabs.flatMap { $0.panels.keys })
            for workspace in manager.tabs {
                _ = GdockGridSplitAction.applyShape(.quad, to: workspace)
            }
            app.unregisterMainWindowContextForTesting(windowId: try #require(manager.windowId))

            manager.reconcileGdockGridModeNow()

            #expect(manager.tabs.count == 2)
            let realPanels = Set(manager.tabs.flatMap { workspace in
                workspace.panels.keys.filter { !workspace.isGdockGridPlaceholder(panelId: $0) }
            })
            #expect(realPanels == originalPanels)
        }
    }

    @Test @MainActor
    func fullGridRolloverCreatesExactlyOneNewRealTerminal() throws {
        try withGridReconcileContext { _, manager in
            let workspace = try #require(manager.selectedWorkspace)
            let pane = try #require(workspace.bonsplitController.allPaneIds.first)
            for _ in 0..<3 {
                _ = try #require(workspace.newTerminalSurface(inPane: pane, focus: false))
            }
            let originalPanels = Set(workspace.panels.keys)
            _ = GdockGridSplitAction.applyShape(.quad, to: workspace)

            #expect(manager.gdockGridModeRouteNewSurface())

            let realPanels = Set(manager.tabs.flatMap { workspace in
                workspace.panels.keys.filter { !workspace.isGdockGridPlaceholder(panelId: $0) }
            })
            #expect(originalPanels.isSubset(of: realPanels))
            #expect(realPanels.count == originalPanels.count + 1)
            #expect(manager.tabs.count == 2)
        }
    }

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
        #expect(mode.defaultValue == true)

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

    // MARK: - Grid lock (AX-GDOCK-GRID-LOCK-MODE)

    @Test func gridLockHidesSplitButtonsAndBlocksUserSplits() {
        #expect(GdockGridLock.showsSplitButtons(gridModeEnabled: true) == false)
        #expect(GdockGridLock.showsSplitButtons(gridModeEnabled: false) == true)
        #expect(
            GdockGridLock.blocksUserTreeMutation(
                gridModeEnabled: true,
                isApplyingGridShape: false
            )
        )
        #expect(
            !GdockGridLock.blocksUserTreeMutation(
                gridModeEnabled: true,
                isApplyingGridShape: true
            )
        )
        #expect(
            !GdockGridLock.blocksUserTreeMutation(
                gridModeEnabled: false,
                isApplyingGridShape: false
            )
        )
    }

    @Test func autoGroupCompactionRetainsGroupAnchors() {
        let groupA = UUID()
        let anchor = UUID(), member = UUID()
        let panel = UUID()
        let plan = GdockGridWorkspaceCompactionPlanner.plan(
            workspaces: [
                .init(
                    id: member,
                    groupId: groupA,
                    isGroupAnchor: false,
                    panelIds: [panel],
                    placeholderPanelIds: []
                ),
                .init(
                    id: anchor,
                    groupId: groupA,
                    isGroupAnchor: true,
                    panelIds: [],
                    placeholderPanelIds: []
                ),
            ],
            capacity: 4,
            groupByRepository: true
        )
        #expect(plan.scopes.count == 1)
        #expect(Set(plan.scopes[0].retainedWorkspaceIds) == [member, anchor])
        #expect(plan.scopes[0].surplusWorkspaceIds.isEmpty)
    }

    @Test @MainActor
    func gridModeWorkspaceHidesSplitChromeAndRejectsUserSplits() throws {
        let previous = GdockGridModeSettings.isEnabled()
        GdockGridModeSettings.setEnabled(true)
        defer { GdockGridModeSettings.setEnabled(previous) }

        let manager = TabManager()
        let workspace = try #require(manager.selectedWorkspace)
        let pane = try #require(workspace.bonsplitController.allPaneIds.first)
        #expect(workspace.bonsplitController.configuration.appearance.showSplitButtons == false)
        #expect(workspace.bonsplitController.configuration.appearance.splitButtons.isEmpty)
        #expect(
            workspace.splitTabBar(
                workspace.bonsplitController,
                shouldSplitPane: pane,
                orientation: .horizontal
            ) == false
        )
        let paneCount = workspace.bonsplitController.allPaneIds.count
        #expect(manager.createSplit(direction: .right) == nil)
        #expect(workspace.bonsplitController.allPaneIds.count == paneCount)
        #expect(manager.createQuadSplit() == false)
        #expect(workspace.bonsplitController.allPaneIds.count == paneCount)

        let apply = GdockGridSplitAction.applyShape(.quad, to: workspace)
        #expect(apply == .success(overflowPanelIds: []) || apply == .alreadyShaped)
        #expect(GdockGridSplitAction.applyShape(.quad, to: workspace) != .vetoed(.allowSplitsDisabled))
        let zoomPanel = try #require(workspace.focusedPanelId)
        #expect(workspace.toggleSplitZoom(panelId: zoomPanel))
    }

    @Test @MainActor
    func autoGroupDoesNotInsertAHeaderWorkspaceWhenGridIsOn() throws {
        let previousGrid = GdockGridModeSettings.isEnabled()
        let previousGroup = GdockAutoWorkspaceGroupModeSettings.isEnabled()
        GdockGridModeSettings.setEnabled(true)
        GdockAutoWorkspaceGroupModeSettings.setEnabled(true)
        defer {
            GdockGridModeSettings.setEnabled(previousGrid)
            GdockAutoWorkspaceGroupModeSettings.setEnabled(previousGroup)
        }

        let manager = TabManager()
        let first = try #require(manager.selectedWorkspace)
        let second = manager.addWorkspace(select: false)
        let beforeIds = Set(manager.tabs.map(\.id))
        #expect(beforeIds.count == 2)

        let groupId = try #require(
            manager.createWorkspaceGroup(
                name: "stokd-cloud/gdock",
                childWorkspaceIds: [first.id, second.id],
                selectAnchor: false,
                collapseSidebarSelection: false,
                insertDedicatedAnchor: false
            )
        )

        #expect(Set(manager.tabs.map(\.id)) == beforeIds)
        let group = try #require(manager.workspaceGroups.first(where: { $0.id == groupId }))
        #expect(group.anchorWorkspaceId == first.id)
        #expect(first.groupId == groupId)
        #expect(second.groupId == groupId)
    }
}
