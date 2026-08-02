import AppKit
import Bonsplit
import CmuxControlSocket
import CmuxSettings
import Foundation
import Testing

#if canImport(cmux_DEV)
@testable import cmux_DEV
#elseif canImport(cmux)
@testable import cmux
#endif

/// VAL-QUAD-004 / D-34: DEBUG-only tagged-socket dogfood for late-failure
/// injection and preflight veto observation through the running-app surface.
///
/// Proves the same shared `QuadSplitAction` preflight/action path used by
/// production adapters, with truthful topology, veto classification, remote
/// command log, and late-failure events. No parallel test-only split algorithm.
@Suite("Quad split running-failure DEBUG dogfood", .serialized)
struct QuadSplitRunningFailureDebugTests {

    // MARK: - Method inventory / release boundary

    @Test("DEBUG method inventory includes fail_after, reset, perform, stage_fixture")
    @MainActor
    func debugMethodInventoryIncludesRunningFailureSurface() {
        let names = Set(TerminalController.quadSplitDebugMethodNames)
        for required in [
            "debug.quad.fail_after",
            "debug.quad.reset_hooks",
            "debug.quad.perform",
            "debug.quad.stage_fixture",
            "debug.quad.adapter_perform",
            "debug.quad.adapters",
        ] {
            #expect(names.contains(required), "missing \(required) in quadSplitDebugMethodNames")
        }
        let capability = Set(TerminalController.v2DebugMethodNames)
        for required in [
            "debug.quad.fail_after",
            "debug.quad.reset_hooks",
            "debug.quad.perform",
            "debug.quad.stage_fixture",
        ] {
            #expect(capability.contains(required), "missing \(required) in v2DebugMethodNames")
        }
    }

    // MARK: - Hook configure / atomic reset

    @Test("fail_after configure sets hook and reset_hooks clears it")
    @MainActor
    func failAfterConfigureAndReset() async throws {
        try await AppContextSerialGate.withExclusiveAppContext {
            try Self.withHarness(dockFocused: false) { harness in
                let controller = TerminalController.shared
                QuadSplitAction.resetTestingHooks()
                defer { QuadSplitAction.resetTestingHooks() }

                let configure = try #require(
                    controller.v2DebugQuadSplit(
                        method: "debug.quad.fail_after",
                        params: ["completed_splits": 1]
                    )
                )
                guard case .ok(let configured) = configure else {
                    Issue.record("expected ok configure, got \(configure)")
                    return
                }
                #expect(configured["fail_after"] as? Int == 1)
                #expect(QuadSplitAction.testingFailAfterCompletedSplits == 1)

                let reset = try #require(
                    controller.v2DebugQuadSplit(method: "debug.quad.reset_hooks", params: [:])
                )
                guard case .ok(let resetPayload) = reset else {
                    Issue.record("expected ok reset, got \(reset)")
                    return
                }
                #expect(resetPayload["reset"] as? Bool == true)
                #expect(QuadSplitAction.testingFailAfterCompletedSplits == nil)
                _ = harness
            }
        }
    }

    // MARK: - Late failure through DEBUG perform (shared action path)

    @Test("DEBUG perform fail_after=1 leaves partial topology, lateFailure outcome, and log")
    @MainActor
    func debugPerformFailAfterStep1() async throws {
        try await AppContextSerialGate.withExclusiveAppContext {
            try Self.withHarness(dockFocused: false) { harness in
                let controller = TerminalController.shared
                QuadSplitAction.resetTestingHooks()
                defer { QuadSplitAction.resetTestingHooks() }

                let surface = try #require(harness.mainWorkspace.focusedPanelId)
                let result = try #require(
                    controller.v2DebugQuadSplit(
                        method: "debug.quad.perform",
                        params: [
                            "surface_id": surface.uuidString,
                            "window_id": harness.windowId.uuidString,
                            "fail_after": 1,
                        ]
                    )
                )
                guard case .ok(let payload) = result else {
                    Issue.record("expected ok perform, got \(result)")
                    return
                }

                #expect(payload["outcome"] as? String == "late_failure")
                #expect(payload["completed_splits"] as? Int == 1)
                #expect(payload["owner_kind"] as? String == "main")
                #expect(payload["preflight_veto"] as? String == nil
                    || (payload["preflight_veto"] as? NSNull) != nil
                    || payload["preflight_veto"] == nil)

                let after = try #require(payload["topology_after"] as? [String: Any])
                #expect(after["main_pane_count"] as? Int == 2)

                let events = try #require(payload["late_failure_events"] as? [String])
                #expect(events.contains(where: {
                    $0.contains("quad.lateFailure") && $0.contains("completedSplits=1")
                }))

                // Hook must be reset after dogfood call.
                #expect(payload["fail_after_after_reset"] as? Int == nil
                    || payload["fail_after_after_reset"] is NSNull
                    || payload["fail_after_after_reset"] == nil)
                #expect(QuadSplitAction.testingFailAfterCompletedSplits == nil)

                // No silent success / no four-pane completion.
                #expect(harness.mainWorkspace.bonsplitController.allPaneIds.count == 2)
                #expect(harness.mainWorkspace.bonsplitController.allPaneIds.count != 4)
            }
        }
    }

    @Test("DEBUG perform fail_after=2 leaves three-pane partial state and log")
    @MainActor
    func debugPerformFailAfterStep2() async throws {
        try await AppContextSerialGate.withExclusiveAppContext {
            try Self.withHarness(dockFocused: false) { harness in
                let controller = TerminalController.shared
                QuadSplitAction.resetTestingHooks()
                defer { QuadSplitAction.resetTestingHooks() }

                let surface = try #require(harness.mainWorkspace.focusedPanelId)
                let result = try #require(
                    controller.v2DebugQuadSplit(
                        method: "debug.quad.perform",
                        params: [
                            "surface_id": surface.uuidString,
                            "window_id": harness.windowId.uuidString,
                            "fail_after": 2,
                        ]
                    )
                )
                guard case .ok(let payload) = result else {
                    Issue.record("expected ok perform, got \(result)")
                    return
                }

                #expect(payload["outcome"] as? String == "late_failure")
                #expect(payload["completed_splits"] as? Int == 2)
                let after = try #require(payload["topology_after"] as? [String: Any])
                #expect(after["main_pane_count"] as? Int == 3)
                let events = try #require(payload["late_failure_events"] as? [String])
                #expect(events.contains(where: {
                    $0.contains("quad.lateFailure") && $0.contains("completedSplits=2")
                }))
                #expect(QuadSplitAction.testingFailAfterCompletedSplits == nil)
                #expect(harness.mainWorkspace.bonsplitController.allPaneIds.count == 3)
            }
        }
    }

    @Test("DEBUG Dock perform fail_after=1 does not mutate main and resets hook")
    @MainActor
    func debugDockPerformFailAfterStep1() async throws {
        try await AppContextSerialGate.withExclusiveAppContext {
            try Self.withHarness(dockFocused: true) { harness in
                let controller = TerminalController.shared
                QuadSplitAction.resetTestingHooks()
                defer { QuadSplitAction.resetTestingHooks() }

                let dockSurface = try #require(
                    harness.dock.newSurface(kind: .terminal, inPane: harness.rootPane, focus: true)
                )
                let mainBefore = harness.mainWorkspace.bonsplitController.allPaneIds.count

                let result = try #require(
                    controller.v2DebugQuadSplit(
                        method: "debug.quad.perform",
                        params: [
                            "surface_id": dockSurface.uuidString,
                            "window_id": harness.windowId.uuidString,
                            "fail_after": 1,
                        ]
                    )
                )
                guard case .ok(let payload) = result else {
                    Issue.record("expected ok dock perform, got \(result)")
                    return
                }
                #expect(payload["outcome"] as? String == "late_failure")
                #expect(payload["owner_kind"] as? String == "dock")
                #expect(payload["completed_splits"] as? Int == 1)
                #expect(harness.mainWorkspace.bonsplitController.allPaneIds.count == mainBefore)
                #expect(harness.dock.bonsplitController.allPaneIds.count == 2)
                #expect(QuadSplitAction.testingFailAfterCompletedSplits == nil)
            }
        }
    }

    // MARK: - Veto fixtures via same preflight/action path (no remote delegate)

    @Test(
        "DEBUG perform representative veto fixtures are atomic with unchanged remote log",
        arguments: [
            "local_success",
            "canvas",
            "empty_dock",
            "remote_connecting",
            "remote_disconnected",
            "remote_unresolved",
            "missing_target",
        ]
    )
    @MainActor
    func debugPerformVetoFixturesAreAtomic(fixture: String) async throws {
        try await AppContextSerialGate.withExclusiveAppContext {
            try Self.withHarness(dockFocused: fixture == "empty_dock") { harness in
                let controller = TerminalController.shared
                QuadSplitAction.resetTestingHooks()
                defer { QuadSplitAction.resetTestingHooks() }

                // Stage via DEBUG fixture surface so live dogfood uses the same path.
                let stage = try #require(
                    controller.v2DebugQuadSplit(
                        method: "debug.quad.stage_fixture",
                        params: [
                            "fixture": fixture,
                            "window_id": harness.windowId.uuidString,
                        ]
                    )
                )
                guard case .ok(let staged) = stage else {
                    Issue.record("stage_fixture \(fixture) failed: \(stage)")
                    return
                }

                let remoteLogBefore = QuadSplitAction.testingRemoteCommandLog
                var params: [String: Any] = [
                    "window_id": harness.windowId.uuidString,
                ]
                if let surface = staged["surface_id"] as? String {
                    params["surface_id"] = surface
                }
                if let owner = staged["owner_kind"] as? String {
                    params["owner"] = owner
                }
                // missing_target: deliberately use a bogus surface when staged.
                if fixture == "missing_target" {
                    params["surface_id"] = UUID().uuidString
                    params["owner"] = "main"
                }

                let mainTreeBefore = harness.mainWorkspace.bonsplitController.treeSnapshot()
                let dockTreeBefore = harness.dock.bonsplitController.treeSnapshot()

                let result = try #require(
                    controller.v2DebugQuadSplit(method: "debug.quad.perform", params: params)
                )
                guard case .ok(let payload) = result else {
                    Issue.record("perform \(fixture) failed: \(result)")
                    return
                }

                let log = try #require(payload["remote_command_log"] as? [String])
                #expect(log == remoteLogBefore || log.isEmpty || log == QuadSplitAction.testingRemoteCommandLog)
                #expect(!log.contains(where: { $0.contains("split-window") }))

                if fixture == "local_success" {
                    #expect(payload["outcome"] as? String == "success")
                    #expect(harness.mainWorkspace.bonsplitController.allPaneIds.count == 4)
                    return
                }

                #expect(payload["outcome"] as? String == "vetoed", "fixture \(fixture)")
                let veto = payload["veto"] as? String ?? payload["preflight_veto"] as? String
                #expect(veto != nil && !(veto ?? "").isEmpty, "fixture \(fixture) missing veto")

                // Known vetoes must not mutate trees.
                #expect(
                    harness.mainWorkspace.bonsplitController.treeSnapshot() == mainTreeBefore
                        || fixture == "empty_dock",
                    "main mutated for \(fixture)"
                )
                if fixture == "empty_dock" {
                    #expect(harness.dock.bonsplitController.treeSnapshot() == dockTreeBefore)
                    #expect(harness.mainWorkspace.bonsplitController.treeSnapshot() == mainTreeBefore)
                    #expect(veto == "emptyDockSource")
                }
                if fixture == "canvas" {
                    #expect(veto == "canvasMode")
                }
                if fixture == "remote_connecting" {
                    #expect(veto == "remoteConnecting")
                }
                if fixture == "remote_disconnected" {
                    #expect(veto == "remoteDisconnected")
                }
                if fixture == "remote_unresolved" {
                    #expect(veto == "remoteUnresolved")
                }
                if fixture == "missing_target" {
                    // Explicit bogus surface → surface not found / missing target style error.
                    let outcome = payload["outcome"] as? String
                    #expect(outcome == "vetoed" || outcome == "error")
                }

                // No side-effecting remote delegate: log probe unchanged.
                #expect(QuadSplitAction.testingRemoteCommandLog == remoteLogBefore)
            }
        }
    }

    @Test("DEBUG perform returns full known veto catalog classification fields")
    @MainActor
    func debugPerformReturnsVetoCatalogFields() async throws {
        try await AppContextSerialGate.withExclusiveAppContext {
            try Self.withHarness(dockFocused: false) { harness in
                let controller = TerminalController.shared
                harness.mainWorkspace.layoutMode = .canvas
                let surface = try #require(harness.mainWorkspace.focusedPanelId)
                let result = try #require(
                    controller.v2DebugQuadSplit(
                        method: "debug.quad.perform",
                        params: [
                            "surface_id": surface.uuidString,
                            "window_id": harness.windowId.uuidString,
                        ]
                    )
                )
                guard case .ok(let payload) = result else {
                    Issue.record("expected ok, got \(result)")
                    return
                }
                #expect(payload["outcome"] as? String == "vetoed")
                #expect(payload["preflight_veto"] as? String == "canvasMode")
                let catalog = try #require(payload["known_vetoes"] as? [String])
                #expect(catalog.contains("canvasMode"))
                #expect(catalog.contains("remoteConnecting"))
                #expect(catalog.contains("emptyDockSource"))
                #expect(catalog.count == QuadSplitAction.Veto.allCases.count)
                #expect(payload["topology_before"] != nil)
                #expect(payload["topology_after"] != nil)
                #expect(payload["remote_command_log"] != nil)
                #expect(payload["late_failure_events"] != nil)
            }
        }
    }

    @Test("release boundary: injection is only via DEBUG hooks and reset is safe")
    @MainActor
    func releaseBoundaryInjectionIsDebugOnlyAndResetSafe() {
        // Source-level release inertness: shouldInject is private; prove the
        // public testing seam resets cleanly and defaults to nil (Release has
        // no socket method to set it; DEBUG dogfood always resets after perform).
        QuadSplitAction.resetTestingHooks()
        #expect(QuadSplitAction.testingFailAfterCompletedSplits == nil)
        QuadSplitAction.testingFailAfterCompletedSplits = 1
        #expect(QuadSplitAction.testingFailAfterCompletedSplits == 1)
        QuadSplitAction.resetTestingHooks()
        #expect(QuadSplitAction.testingFailAfterCompletedSplits == nil)
        // Capability list is DEBUG-compiled; presence of names is the
        // compile-time release boundary (methods live under #if DEBUG).
        #expect(TerminalController.v2DebugMethodNames.contains("debug.quad.perform"))
        #expect(TerminalController.v2DebugMethodNames.contains("debug.quad.fail_after"))
    }
}

// MARK: - Harness

private extension QuadSplitRunningFailureDebugTests {
    @MainActor
    struct Harness {
        let appDelegate: AppDelegate
        let manager: TabManager
        let dock: DockSplitStore
        let mainWorkspace: Workspace
        let rootPane: PaneID
        let window: NSWindow
        let windowId: UUID
    }

    @MainActor
    static func withHarness(dockFocused: Bool, _ body: (Harness) throws -> Void) throws {
        let previousAppDelegate = AppDelegate.shared
        let previousManager = TerminalController.shared.activeTabManagerForCallerNotification()
        let originalSettingsFileStore = KeyboardShortcutSettings.installIsolatedTestFileStore(
            prefix: "cmux-quad-running-failure"
        )
        KeyboardShortcutSettings.resetAll()

        let appDelegate = AppDelegate()
        let suiteName = "QuadSplitRunningFailureDebugTests.\(UUID().uuidString)"
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
        if mainWorkspace.focusedPanelId == nil,
           let mainPane = mainWorkspace.bonsplitController.allPaneIds.first {
            _ = mainWorkspace.newTerminalSurface(
                inPane: mainPane,
                inheritWorkingDirectoryFallback: true
            )
        }
        let dock = appDelegate.windowDock(forWindowId: windowId)
        let rootPane = try #require(dock.bonsplitController.allPaneIds.first)
        dock.setVisibleInUI(true)
        fileExplorerState.setVisible(true)
        if dockFocused {
            fileExplorerState.mode = .dock
            appDelegate.noteRightSidebarKeyboardFocusIntent(mode: .dock, in: window)
        }

        defer {
            QuadSplitAction.resetTestingHooks()
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

        try body(Harness(
            appDelegate: appDelegate,
            manager: manager,
            dock: dock,
            mainWorkspace: mainWorkspace,
            rootPane: rootPane,
            window: window,
            windowId: windowId
        ))
    }
}
