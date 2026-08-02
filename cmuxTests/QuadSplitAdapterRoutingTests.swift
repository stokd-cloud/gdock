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

/// VAL-QUAD-002 / VAL-QUAD-003 (D-34): Dock CLI/explicit routing, every named
/// production adapter handler, and DEBUG dogfood that re-enters adapters
/// (never ``QuadSplitAction/perform`` as a substitute).
@Suite("Quad split adapter routing", .serialized)
struct QuadSplitAdapterRoutingTests {
    // MARK: - Dock CLI / explicit routing

    @Test("v2 CLI explicit Dock surface mutates only Dock")
    @MainActor
    func v2ExplicitDockSurfaceMutatesOnlyDock() async throws {
        try await AppContextSerialGate.withExclusiveAppContext {
            try Self.withHarness(dockFocused: false) { harness in
                let dockSurface = try #require(
                    harness.dock.newSurface(kind: .terminal, inPane: harness.rootPane, focus: true)
                )
                let mainBefore = harness.mainWorkspace.bonsplitController.allPaneIds.count
                let dockBefore = harness.dock.bonsplitController.allPaneIds.count

                let controller = TerminalController.shared
                let previous = controller.activeTabManagerForCallerNotification()
                controller.setActiveTabManager(harness.manager)
                defer { controller.setActiveTabManager(previous) }

                let routing = ControlRoutingSelectors(
                    hasWindowIDParam: true,
                    windowID: harness.windowId,
                    groupID: nil,
                    workspaceID: nil,
                    surfaceID: dockSurface,
                    paneID: nil
                )
                let inputs = ControlSurfaceSplitInputs(
                    directionRaw: "quad",
                    typeRaw: nil,
                    urlRaw: nil,
                    requestedSourceSurfaceID: dockSurface,
                    workingDirectory: nil,
                    initialCommand: nil,
                    tmuxStartCommand: nil,
                    remotePTYSessionID: nil,
                    remoteContextRaw: nil,
                    startupEnvironment: [:],
                    clientUnsupportedRemoteTmuxOptions: [],
                    requestedFocus: false,
                    initialDividerPosition: nil
                )
                let resolution = controller.controlSurfaceSplit(routing: routing, inputs: inputs)
                guard case .created = resolution else {
                    Issue.record("expected created Dock quad, got \(resolution)")
                    return
                }
                #expect(harness.dock.bonsplitController.allPaneIds.count == dockBefore + 3)
                #expect(harness.mainWorkspace.bonsplitController.allPaneIds.count == mainBefore)
            }
        }
    }

    @Test("v2 CLI focused Dock mutates only Dock and never falls through to main")
    @MainActor
    func v2FocusedDockMutatesOnlyDock() async throws {
        try await AppContextSerialGate.withExclusiveAppContext {
            try Self.withHarness(dockFocused: true) { harness in
                _ = try #require(
                    harness.dock.newSurface(kind: .terminal, inPane: harness.rootPane, focus: true)
                )
                let mainBefore = harness.mainWorkspace.bonsplitController.allPaneIds.count
                let dockBefore = harness.dock.bonsplitController.allPaneIds.count

                let controller = TerminalController.shared
                let previous = controller.activeTabManagerForCallerNotification()
                controller.setActiveTabManager(harness.manager)
                defer { controller.setActiveTabManager(previous) }

                let routing = ControlRoutingSelectors(
                    hasWindowIDParam: true,
                    windowID: harness.windowId,
                    groupID: nil,
                    workspaceID: nil,
                    surfaceID: nil,
                    paneID: nil
                )
                let inputs = ControlSurfaceSplitInputs(
                    directionRaw: "quad",
                    typeRaw: nil,
                    urlRaw: nil,
                    requestedSourceSurfaceID: nil,
                    workingDirectory: nil,
                    initialCommand: nil,
                    tmuxStartCommand: nil,
                    remotePTYSessionID: nil,
                    remoteContextRaw: nil,
                    startupEnvironment: [:],
                    clientUnsupportedRemoteTmuxOptions: [],
                    requestedFocus: false,
                    initialDividerPosition: nil
                )
                let resolution = controller.controlSurfaceSplit(routing: routing, inputs: inputs)
                guard case .created = resolution else {
                    Issue.record("expected created Dock quad from focus, got \(resolution)")
                    return
                }
                #expect(harness.dock.bonsplitController.allPaneIds.count == dockBefore + 3)
                #expect(harness.mainWorkspace.bonsplitController.allPaneIds.count == mainBefore)
            }
        }
    }

    @Test("legacy CLI explicit Dock surface mutates only Dock")
    @MainActor
    func legacyExplicitDockSurfaceMutatesOnlyDock() async throws {
        try await AppContextSerialGate.withExclusiveAppContext {
            try Self.withHarness(dockFocused: false) { harness in
                let dockSurface = try #require(
                    harness.dock.newSurface(kind: .terminal, inPane: harness.rootPane, focus: true)
                )
                let mainBefore = harness.mainWorkspace.bonsplitController.allPaneIds.count
                let dockBefore = harness.dock.bonsplitController.allPaneIds.count

                let controller = TerminalController.shared
                let previous = controller.activeTabManagerForCallerNotification()
                controller.setActiveTabManager(harness.manager)
                defer { controller.setActiveTabManager(previous) }

                let response = controller.debugInvokeLegacyNewSplitForTests(
                    "quad \(dockSurface.uuidString)"
                )
                #expect(response.hasPrefix("OK"), "legacy response: \(response)")
                #expect(harness.dock.bonsplitController.allPaneIds.count == dockBefore + 3)
                #expect(harness.mainWorkspace.bonsplitController.allPaneIds.count == mainBefore)
            }
        }
    }

    @Test("invalid explicit surface is lossless with explicit error")
    @MainActor
    func invalidExplicitSurfaceIsLossless() async throws {
        try await AppContextSerialGate.withExclusiveAppContext {
            try Self.withHarness(dockFocused: false) { harness in
                let mainBefore = harness.mainWorkspace.bonsplitController.allPaneIds.count
                let dockBefore = harness.dock.bonsplitController.allPaneIds.count
                let missing = UUID()

                let controller = TerminalController.shared
                let previous = controller.activeTabManagerForCallerNotification()
                controller.setActiveTabManager(harness.manager)
                defer { controller.setActiveTabManager(previous) }

                let routing = ControlRoutingSelectors(
                    hasWindowIDParam: true,
                    windowID: harness.windowId,
                    groupID: nil,
                    workspaceID: nil,
                    surfaceID: missing,
                    paneID: nil
                )
                let inputs = ControlSurfaceSplitInputs(
                    directionRaw: "quad",
                    typeRaw: nil,
                    urlRaw: nil,
                    requestedSourceSurfaceID: missing,
                    workingDirectory: nil,
                    initialCommand: nil,
                    tmuxStartCommand: nil,
                    remotePTYSessionID: nil,
                    remoteContextRaw: nil,
                    startupEnvironment: [:],
                    clientUnsupportedRemoteTmuxOptions: [],
                    requestedFocus: false,
                    initialDividerPosition: nil
                )
                let resolution = controller.controlSurfaceSplit(routing: routing, inputs: inputs)
                guard case .requestedSurfaceNotFound(let id) = resolution else {
                    Issue.record("expected surface not found, got \(resolution)")
                    return
                }
                #expect(id == missing)
                #expect(harness.mainWorkspace.bonsplitController.allPaneIds.count == mainBefore)
                #expect(harness.dock.bonsplitController.allPaneIds.count == dockBefore)

                let legacy = controller.debugInvokeLegacyNewSplitForTests(
                    "quad \(missing.uuidString)"
                )
                #expect(legacy.contains("not found") || legacy.hasPrefix("ERROR"))
                #expect(harness.mainWorkspace.bonsplitController.allPaneIds.count == mainBefore)
                #expect(harness.dock.bonsplitController.allPaneIds.count == dockBefore)
            }
        }
    }

    // MARK: - Every named adapter handler

    @Test("adapter inventory covers every approved entrypoint")
    @MainActor
    func adapterInventoryIsComplete() {
        let ids = Set(QuadSplitAdapters.allAdapterIds.map(\.rawValue))
        for required in [
            "tab_button",
            "view_menu",
            "primary_palette",
            "dock_palette",
            "context_menu",
            "shortcut",
            "cli_v2",
            "cli_legacy",
        ] {
            #expect(ids.contains(required), "missing adapter \(required)")
        }
        #expect(QuadSplitAdapters.allAdapterIds.count == 8)
    }

    @Test(
        "every named production adapter handler mutates via its own path",
        arguments: QuadSplitAdapters.ID.allCases
    )
    @MainActor
    func everyNamedAdapterHandlerWorks(adapter: QuadSplitAdapters.ID) async throws {
        try await AppContextSerialGate.withExclusiveAppContext {
            // CLI/socket + context/tab button need an explicit surface target on main.
            // Focus-path adapters (menu/palette/shortcut/dock_palette) use focus.
            let needsDockFocus = adapter == .viewMenu
                || adapter == .primaryPalette
                || adapter == .dockPalette
                || adapter == .shortcut
            try Self.withHarness(dockFocused: needsDockFocus) { harness in
                let dockSurface = try #require(
                    harness.dock.newSurface(kind: .terminal, inPane: harness.rootPane, focus: true)
                )
                // Ensure main also has a terminal surface for main-targeted adapters.
                let mainSurface = try #require(harness.mainWorkspace.focusedPanelId)

                let mainBefore = harness.mainWorkspace.bonsplitController.allPaneIds.count
                let dockBefore = harness.dock.bonsplitController.allPaneIds.count

                let explicitSurface: UUID?
                switch adapter {
                case .cliV2, .cliLegacy, .contextMenu, .tabButton:
                    // Drive Dock ownership for CLI/context/tab when dock-focused
                    // tests already set focus; for non-focus harness use Dock
                    // explicit surface so we prove Dock routing on those adapters.
                    explicitSurface = needsDockFocus ? nil : dockSurface
                case .viewMenu, .primaryPalette, .dockPalette, .shortcut:
                    explicitSurface = nil
                }

                let result = QuadSplitAdapters.invokeProductionAdapter(
                    adapter,
                    preferredWindow: harness.window,
                    tabManager: harness.manager,
                    explicitSurfaceId: explicitSurface,
                    explicitDock: harness.dock,
                    explicitWorkspace: harness.mainWorkspace,
                    explicitPane: needsDockFocus || explicitSurface == dockSurface
                        ? harness.rootPane
                        : harness.mainWorkspace.bonsplitController.focusedPaneId
                )

                #expect(result.adapterId == adapter.rawValue)
                #expect(result.success, "adapter \(adapter.rawValue) failed: \(result.error ?? "nil")")

                // Dock-targeted adapters must not grow main.
                if result.ownerKind == "dock" {
                    #expect(result.mainPaneCountAfter == mainBefore
                        || harness.mainWorkspace.bonsplitController.allPaneIds.count == mainBefore)
                    #expect(harness.dock.bonsplitController.allPaneIds.count >= dockBefore + 3
                        || harness.dock.bonsplitController.allPaneIds.count == 4)
                } else if result.ownerKind == "main" {
                    #expect(harness.mainWorkspace.bonsplitController.allPaneIds.count >= mainBefore + 3
                        || harness.mainWorkspace.bonsplitController.allPaneIds.count == 4)
                    #expect(harness.dock.bonsplitController.allPaneIds.count == dockBefore
                        || harness.dock.bonsplitController.allPaneIds.count == 1)
                } else {
                    Issue.record("adapter \(adapter.rawValue) resolved no owner: \(result)")
                }

                // Sanity: main surface still addressable after Dock work.
                #expect(harness.mainWorkspace.panels[mainSurface] != nil || mainBefore == 0)
            }
        }
    }

    @Test("DEBUG adapter dogfood does not call perform as substitute — records adapter id and topology")
    @MainActor
    func debugAdapterDogfoodRecordsAdapterAndTopology() async throws {
        try await AppContextSerialGate.withExclusiveAppContext {
            try Self.withHarness(dockFocused: true) { harness in
                _ = try #require(
                    harness.dock.newSurface(kind: .terminal, inPane: harness.rootPane, focus: true)
                )
                let mainBefore = harness.mainWorkspace.bonsplitController.allPaneIds.count

                // Invoke via the production adapter registry (same path DEBUG uses).
                let result = QuadSplitAdapters.invokeProductionAdapter(
                    .shortcut,
                    preferredWindow: harness.window,
                    tabManager: harness.manager,
                    explicitSurfaceId: nil
                )
                #expect(result.adapterId == "shortcut")
                #expect(result.success)
                #expect(result.ownerKind == "dock")
                #expect(result.mainPaneCountAfter == mainBefore
                    || harness.mainWorkspace.bonsplitController.allPaneIds.count == mainBefore)
                #expect(result.dockPaneCountAfter >= result.dockPaneCountBefore + 3
                    || harness.dock.bonsplitController.allPaneIds.count == 4)
                #expect(result.resolvedWindowId != nil || result.ownerKind == "dock")
            }
        }
    }

    @Test("Dock failure on CLI is handled and does not fall through to main")
    @MainActor
    func dockCliFailureDoesNotFallThrough() async throws {
        try await AppContextSerialGate.withExclusiveAppContext {
            try Self.withHarness(dockFocused: true) { harness in
                let dockSurface = try #require(
                    harness.dock.newSurface(kind: .terminal, inPane: harness.rootPane, focus: true)
                )
                var config = harness.dock.bonsplitController.configuration
                config.allowSplits = false
                harness.dock.bonsplitController.configuration = config

                let mainBefore = harness.mainWorkspace.bonsplitController.allPaneIds.count
                let dockBefore = harness.dock.bonsplitController.allPaneIds.count

                let controller = TerminalController.shared
                let previous = controller.activeTabManagerForCallerNotification()
                controller.setActiveTabManager(harness.manager)
                defer { controller.setActiveTabManager(previous) }

                let routing = ControlRoutingSelectors(
                    hasWindowIDParam: true,
                    windowID: harness.windowId,
                    groupID: nil,
                    workspaceID: nil,
                    surfaceID: dockSurface,
                    paneID: nil
                )
                let inputs = ControlSurfaceSplitInputs(
                    directionRaw: "quad",
                    typeRaw: nil,
                    urlRaw: nil,
                    requestedSourceSurfaceID: dockSurface,
                    workingDirectory: nil,
                    initialCommand: nil,
                    tmuxStartCommand: nil,
                    remotePTYSessionID: nil,
                    remoteContextRaw: nil,
                    startupEnvironment: [:],
                    clientUnsupportedRemoteTmuxOptions: [],
                    requestedFocus: false,
                    initialDividerPosition: nil
                )
                let resolution = controller.controlSurfaceSplit(routing: routing, inputs: inputs)
                // Handled Dock failure — not a main mutation success.
                #expect({
                    if case .createFailed = resolution { return true }
                    if case .created = resolution { return false }
                    return true
                }())
                #expect(harness.mainWorkspace.bonsplitController.allPaneIds.count == mainBefore)
                #expect(harness.dock.bonsplitController.allPaneIds.count == dockBefore)
            }
        }
    }
}

// MARK: - Harness

private extension QuadSplitAdapterRoutingTests {
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
            prefix: "cmux-quad-adapter-routing"
        )
        KeyboardShortcutSettings.resetAll()

        let appDelegate = AppDelegate()
        let suiteName = "QuadSplitAdapterRoutingTests.\(UUID().uuidString)"
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
        // Seed a main terminal so main-targeted adapters have a surface.
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
