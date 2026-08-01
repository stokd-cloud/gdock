import AppKit
import Bonsplit
import CmuxCore
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

    // MARK: - VAL-QUAD-004: complete veto catalog (table-driven)

    @Test(
        "known veto catalog is atomic: full tree + remote log unchanged",
        arguments: QuadSplitActionTests.workspaceVetoCases
    )
    @MainActor
    func knownWorkspaceVetoCatalogIsAtomic(caseName: String, expected: QuadSplitAction.Veto) throws {
        QuadSplitAction.resetTestingHooks()
        defer { QuadSplitAction.resetTestingHooks() }

        let manager = TabManager()
        let workspace = try #require(manager.selectedWorkspace)
        let rootPane = try #require(workspace.bonsplitController.allPaneIds.first)
        let paneForAction = try Self.prepareWorkspaceVeto(
            named: caseName,
            workspace: workspace,
            rootPane: rootPane
        )

        let treeBefore = workspace.bonsplitController.treeSnapshot()
        let panesBefore = workspace.bonsplitController.allPaneIds.count
        let remoteLogBefore = QuadSplitAction.testingRemoteCommandLog

        let outcome = QuadSplitAction.performDetailed(inPane: paneForAction, workspace: workspace)

        #expect(outcome == .vetoed(expected), "case \(caseName)")
        #expect(workspace.bonsplitController.treeSnapshot() == treeBefore, "case \(caseName) tree mutated")
        #expect(workspace.bonsplitController.allPaneIds.count == panesBefore, "case \(caseName) pane count")
        #expect(
            QuadSplitAction.testingRemoteCommandLog == remoteLogBefore,
            "case \(caseName) remote command log mutated"
        )
        // Preflight must never append remote split commands.
        #expect(!QuadSplitAction.testingRemoteCommandLog.contains(where: { $0.contains("split-window") }))
    }

    @Test("Dock empty/invalid source vetoes leave Dock tree and main unchanged")
    @MainActor
    func dockEmptyAndInvalidSourceVetoesAreAtomic() async throws {
        try await AppContextSerialGate.withExclusiveAppContext {
            try Self.withDockHarness { harness in
                QuadSplitAction.resetTestingHooks()
                defer { QuadSplitAction.resetTestingHooks() }

                let mainBefore = harness.mainWorkspace.bonsplitController.treeSnapshot()
                let dockTreeEmpty = harness.dock.bonsplitController.treeSnapshot()
                let remoteLogBefore = QuadSplitAction.testingRemoteCommandLog

                // Empty Dock root (no tabs seeded).
                let emptyOutcome = QuadSplitAction.performDetailed(
                    inPane: harness.rootPane,
                    dock: harness.dock
                )
                #expect(emptyOutcome == .vetoed(.emptyDockSource))
                #expect(harness.dock.bonsplitController.treeSnapshot() == dockTreeEmpty)
                #expect(harness.mainWorkspace.bonsplitController.treeSnapshot() == mainBefore)
                #expect(QuadSplitAction.testingRemoteCommandLog == remoteLogBefore)

                // Invalid: pane not in Dock tree.
                let invalidPane = PaneID()
                let invalidOutcome = QuadSplitAction.performDetailed(
                    inPane: invalidPane,
                    dock: harness.dock
                )
                #expect(invalidOutcome == .vetoed(.invalidDockSource))
                #expect(harness.dock.bonsplitController.treeSnapshot() == dockTreeEmpty)
                #expect(harness.mainWorkspace.bonsplitController.treeSnapshot() == mainBefore)
                #expect(QuadSplitAction.testingRemoteCommandLog == remoteLogBefore)

                // Invalid: nil pane overload.
                let nilOutcome = QuadSplitAction.preflight(inPane: PaneID?.none, dock: harness.dock)
                #expect(nilOutcome == .invalidDockSource)
            }
        }
    }

    @Test("Dock allowSplits false is atomic via shared preflight")
    @MainActor
    func dockAllowSplitsFalseIsAtomic() async throws {
        try await AppContextSerialGate.withExclusiveAppContext {
            try Self.withDockHarness { harness in
                _ = try #require(
                    harness.dock.newSurface(kind: .terminal, inPane: harness.rootPane, focus: true)
                )
                var config = harness.dock.bonsplitController.configuration
                config.allowSplits = false
                harness.dock.bonsplitController.configuration = config
                let treeBefore = harness.dock.bonsplitController.treeSnapshot()
                let outcome = QuadSplitAction.performDetailed(
                    inPane: harness.rootPane,
                    dock: harness.dock
                )
                #expect(outcome == .vetoed(.allowSplitsDisabled))
                #expect(harness.dock.bonsplitController.treeSnapshot() == treeBefore)
            }
        }
    }

    // MARK: - VAL-QUAD-004: late-failure injection

    @Test("injected late failure after step 1 leaves partial state and logs failure")
    @MainActor
    func lateFailureAfterStep1IsExplicit() throws {
        QuadSplitAction.resetTestingHooks()
        defer { QuadSplitAction.resetTestingHooks() }

        let manager = TabManager()
        let workspace = try #require(manager.selectedWorkspace)
        let rootPane = try #require(workspace.bonsplitController.allPaneIds.first)
        #expect(workspace.bonsplitController.allPaneIds.count == 1)

        QuadSplitAction.testingFailAfterCompletedSplits = 1
        let outcome = QuadSplitAction.performDetailed(inPane: rootPane, workspace: workspace)

        #expect(outcome == .lateFailure(completedSplits: 1))
        // Partial grid: first horizontal split applied (+1 pane), no rollback corruption.
        #expect(workspace.bonsplitController.allPaneIds.count == 2)
        #expect(QuadSplitAction.testingLateFailureEvents.contains(where: {
            $0.contains("quad.lateFailure") && $0.contains("completedSplits=1")
        }))
        // No attempted rollback to zero panes (would destroy partial state).
        #expect(workspace.bonsplitController.allPaneIds.count != 1)
        // Recipe must not claim success and must not continue to four panes.
        #expect(workspace.bonsplitController.allPaneIds.count != 4)
    }

    @Test("injected late failure after step 2 leaves partial state and logs failure")
    @MainActor
    func lateFailureAfterStep2IsExplicit() throws {
        QuadSplitAction.resetTestingHooks()
        defer { QuadSplitAction.resetTestingHooks() }

        let manager = TabManager()
        let workspace = try #require(manager.selectedWorkspace)
        let rootPane = try #require(workspace.bonsplitController.allPaneIds.first)
        #expect(workspace.bonsplitController.allPaneIds.count == 1)

        QuadSplitAction.testingFailAfterCompletedSplits = 2
        let outcome = QuadSplitAction.performDetailed(inPane: rootPane, workspace: workspace)

        #expect(outcome == .lateFailure(completedSplits: 2))
        // Two successful splits: horizontal + left vertical → 3 panes.
        #expect(workspace.bonsplitController.allPaneIds.count == 3)
        #expect(QuadSplitAction.testingLateFailureEvents.contains(where: {
            $0.contains("quad.lateFailure") && $0.contains("completedSplits=2")
        }))
        #expect(workspace.bonsplitController.allPaneIds.count != 1)
        #expect(workspace.bonsplitController.allPaneIds.count != 4)
    }

    @Test("Dock late failure after step 1 is explicit and does not fall through")
    @MainActor
    func dockLateFailureAfterStep1IsExplicit() async throws {
        try await AppContextSerialGate.withExclusiveAppContext {
            try Self.withDockHarness { harness in
                QuadSplitAction.resetTestingHooks()
                defer { QuadSplitAction.resetTestingHooks() }

                _ = try #require(
                    harness.dock.newSurface(kind: .terminal, inPane: harness.rootPane, focus: true)
                )
                let mainBefore = harness.mainWorkspace.bonsplitController.allPaneIds.count
                QuadSplitAction.testingFailAfterCompletedSplits = 1

                let outcome = QuadSplitAction.performDetailed(
                    inPane: harness.rootPane,
                    dock: harness.dock
                )
                #expect(outcome == .lateFailure(completedSplits: 1))
                #expect(harness.dock.bonsplitController.allPaneIds.count == 2)
                #expect(harness.mainWorkspace.bonsplitController.allPaneIds.count == mainBefore)
                #expect(QuadSplitAction.testingLateFailureEvents.contains(where: {
                    $0.contains("quad.lateFailure") && $0.contains("surface=dock")
                }))

                // Tri-state route reports handled(false) — not notApplicable fallthrough.
                let route = harness.appDelegate.routeQuadToFocusedDock(preferredWindow: harness.window)
                if case .handled(let success) = route {
                    // Dock is still partially split / or veto path on re-entry; either way
                    // handled means callers must not fall through to main.
                    _ = success
                } else {
                    Issue.record("expected handled outcome, got \(route)")
                }
                #expect(harness.mainWorkspace.bonsplitController.allPaneIds.count == mainBefore)
            }
        }
    }
}

// MARK: - Veto catalog fixtures

private extension QuadSplitActionTests {
    /// Table rows: (case name, expected veto). Arguments drive one test per row.
    static var workspaceVetoCases: [(String, QuadSplitAction.Veto)] {
        [
            ("missingTarget", .missingTarget),
            ("invalidTarget", .invalidTarget),
            ("allowSplitsDisabled", .allowSplitsDisabled),
            ("noninteractive", .noninteractive),
            ("transientFocusSuppressed", .transientFocusSuppressed),
            ("canvasMode", .canvasMode),
            ("remoteMirror", .remoteMirror),
            ("remoteConnecting", .remoteConnecting),
            ("remoteDisconnected", .remoteDisconnected),
            ("remoteUnresolved", .remoteUnresolved),
            ("remoteUnsupportedDirection", .remoteUnsupportedDirection),
            ("delegateRestriction", .delegateRestriction),
        ]
    }

    @MainActor
    static func prepareWorkspaceVeto(
        named caseName: String,
        workspace: Workspace,
        rootPane: PaneID
    ) throws -> PaneID {
        switch caseName {
        case "missingTarget":
            return PaneID()
        case "invalidTarget":
            let tab = try #require(
                workspace.bonsplitController.selectedTab(inPane: rootPane)
                    ?? workspace.bonsplitController.tabs(inPane: rootPane).first
            )
            workspace.removeSurfaceMapping(forSurfaceId: tab.id)
            return rootPane
        case "allowSplitsDisabled":
            var configuration = workspace.bonsplitController.configuration
            configuration.allowSplits = false
            workspace.bonsplitController.configuration = configuration
            return rootPane
        case "noninteractive":
            workspace.bonsplitController.isInteractive = false
            return rootPane
        case "transientFocusSuppressed":
            QuadSplitAction.testingForceTransientFocusSuppressed = true
            return rootPane
        case "canvasMode":
            workspace.layoutMode = .canvas
            return rootPane
        case "remoteMirror":
            workspace.isRemoteTmuxMirror = true
            return rootPane
        case "remoteConnecting":
            workspace.remoteConfiguration = Self.sampleRemoteConfiguration()
            workspace.remoteConnectionState = .connecting
            return rootPane
        case "remoteDisconnected":
            workspace.remoteConfiguration = Self.sampleRemoteConfiguration()
            workspace.remoteConnectionState = .disconnected
            return rootPane
        case "remoteUnresolved":
            let panelId = try #require(workspace.focusedPanelId)
            workspace.remoteConnectionState = .connected
            workspace.remoteConfiguration = Self.sampleRemoteConfiguration()
            workspace.trackRemoteTerminalSurface(panelId)
            return rootPane
        case "remoteUnsupportedDirection":
            workspace.remoteConfiguration = Self.sampleRemoteConfiguration()
            workspace.remoteConnectionState = .connected
            // No remote terminal surface → direction/options unsupported for quad.
            return rootPane
        case "delegateRestriction":
            // Pure live path: active remote-tmux mutation transaction.
            // Also force so the table row stays deterministic if coordinator
            // nesting differs under concurrent suites.
            QuadSplitAction.testingForceDelegateRestriction = true
            return rootPane
        default:
            Issue.record("unknown veto case \(caseName)")
            return rootPane
        }
    }

    static func sampleRemoteConfiguration() -> WorkspaceRemoteConfiguration {
        WorkspaceRemoteConfiguration(
            destination: "cmux-quad-veto-test",
            port: nil,
            identityFile: nil,
            sshOptions: [],
            localProxyPort: nil,
            relayPort: nil,
            relayID: nil,
            relayToken: nil,
            localSocketPath: nil,
            terminalStartupCommand: nil
        )
    }

    @MainActor
    struct DockHarness {
        let appDelegate: AppDelegate
        let dock: DockSplitStore
        let mainWorkspace: Workspace
        let rootPane: PaneID
        let window: NSWindow
    }

    @MainActor
    static func withDockHarness(_ body: (DockHarness) throws -> Void) throws {
        let previousAppDelegate = AppDelegate.shared
        let previousManager = TerminalController.shared.activeTabManagerForCallerNotification()
        let originalSettingsFileStore = KeyboardShortcutSettings.installIsolatedTestFileStore(
            prefix: "cmux-quad-action-dock"
        )
        KeyboardShortcutSettings.resetAll()

        let appDelegate = AppDelegate()
        let suiteName = "QuadSplitActionTests.Dock.\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suiteName))
        let settings = UserDefaultsSettingsClient(defaults: defaults)
        let manager = TabManager(autoWelcomeIfNeeded: false, settings: settings)
        let fileExplorerState = FileExplorerState()
        let windowId = UUID()
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 640, height: 480),
            styleMask: [.titled, .closable],
            backing: .buffered,
            defer: false
        )
        window.isReleasedWhenClosed = false
        window.identifier = NSUserInterfaceItemIdentifier("cmux.main.\(windowId.uuidString)")

        AppDelegate.shared = appDelegate
        appDelegate.tabManager = manager
        TerminalController.shared.setActiveTabManager(manager)
        appDelegate.registerMainWindow(
            window,
            windowId: windowId,
            tabManager: manager,
            sidebarState: SidebarState(),
            sidebarSelectionState: SidebarSelectionState(),
            fileExplorerState: fileExplorerState
        )
        window.makeKeyAndOrderFront(nil)

        let mainWorkspace = try #require(manager.tabs.first)
        let dock = appDelegate.windowDock(forWindowId: windowId)
        let rootPane = try #require(dock.bonsplitController.allPaneIds.first)
        dock.setVisibleInUI(true)
        fileExplorerState.setVisible(true)
        fileExplorerState.mode = .dock
        appDelegate.noteRightSidebarKeyboardFocusIntent(mode: .dock, in: window)

        defer {
            defaults.removePersistentDomain(forName: suiteName)
            KeyboardShortcutSettings.resetAll()
            KeyboardShortcutSettings.settingsFileStore = originalSettingsFileStore
            TerminalController.shared.setActiveTabManager(previousManager)
            appDelegate.unregisterMainWindowContextForTesting(windowId: windowId)
            manager.tabs.forEach { $0.teardownAllPanels() }
            window.orderOut(nil)
            window.close()
            AppDelegate.shared = previousAppDelegate
        }

        try body(DockHarness(
            appDelegate: appDelegate,
            dock: dock,
            mainWorkspace: mainWorkspace,
            rootPane: rootPane,
            window: window
        ))
    }
}
