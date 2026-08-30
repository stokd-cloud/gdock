import AppKit
import Bonsplit
import CmuxSettings
import Foundation
import Testing

#if canImport(cmux_DEV)
@testable import cmux_DEV
#elseif canImport(cmux)
@testable import cmux
#endif

/// VAL-QUAD-002 / VAL-QUAD-003 / VAL-QUAD-005: button defaults, shared adapters,
/// Dock routing tri-state, unbound configurable shortcut, remote filtering.
@Suite("Quad split button and entrypoints", .serialized)
struct QuadSplitButtonTests {
    @Test("defaults end with quad and map to custom action")
    @MainActor
    func defaultsEndWithQuadAndMapToCustomAction() {
        let defaults = CmuxSurfaceTabBarButton.defaults
        #expect(defaults.count == 5)
        #expect(defaults.map(\.id).contains(CmuxSurfaceTabBarBuiltInAction.splitQuad.configID))
        #expect(defaults.last?.id == CmuxSurfaceTabBarBuiltInAction.splitQuad.configID)
        #expect(CmuxSurfaceTabBarBuiltInAction.splitQuad.bonsplitAction == .custom("cmux.splitQuad"))
        #expect(CmuxSurfaceTabBarBuiltInAction.splitQuad.defaultIcon == "square.split.2x2")
        #expect(CmuxSurfaceTabBarBuiltInAction(configID: "cmux.splitQuad") == .splitQuad)
        #expect(CmuxSurfaceTabBarBuiltInAction(configID: "splitQuad") == .splitQuad)
    }

    @Test("every dispatch site handles the case")
    @MainActor
    func everyQuadDispatchSiteHandlesTheCase() throws {
        let resolved = CmuxResolvedConfigAction.builtIn(.splitQuad)
        #expect(!resolved.title.isEmpty)
        #expect(resolved.keywords.contains("quad") || resolved.keywords.contains("split"))
        #expect(resolved.action == .builtIn(.splitQuad))

        let manager = TabManager()
        let workspace = try #require(manager.selectedWorkspace)
        let pane = try #require(workspace.bonsplitController.allPaneIds.first)
        #expect(workspace.bonsplitController.allPaneIds.count == 1)

        // Tab-bar custom action path (shared mutation).
        workspace.splitTabBar(
            workspace.bonsplitController,
            didRequestCustomAction: QuadSplitAction.customActionIdentifier,
            inPane: pane
        )
        #expect(workspace.bonsplitController.allPaneIds.count == 4)
    }

    @Test("dock appearance includes the five-button list ending in quad")
    @MainActor
    func dockAppearanceIncludesQuadButton() {
        let appearance = DockSplitStore.makeAppearance(from: GhosttyConfig.load())
        #expect(appearance.splitButtons.count == 5)
        #expect(appearance.splitButtons.contains(where: {
            if case .custom(let id) = $0.action {
                return id == "cmux.splitQuad" || id == "splitQuad"
            }
            return false
        }))
        #expect(appearance.splitButtons.last?.id == "cmux.splitQuad"
            || appearance.splitButtons.last?.action == .custom("cmux.splitQuad"))
    }

    @Test("remote-tmux embedded lane filters custom quad button")
    @MainActor
    func remoteTmuxEmbeddedFiltersQuad() {
        var configuration = BonsplitConfiguration()
        configuration.appearance.splitButtons = QuadSplitAction.defaultSplitActionButtons
        #expect(configuration.appearance.splitButtons.count == 5)
        let embedded = configuration.remoteTmuxEmbedded
        #expect(embedded.appearance.splitButtons.count == 2)
        #expect(embedded.appearance.splitButtons.allSatisfy {
            $0.action == .splitRight || $0.action == .splitDown
        })
        #expect(!embedded.appearance.splitButtons.contains(where: {
            if case .custom = $0.action { return true }
            return false
        }))
    }

    @Test("shortcut is unbound by default and Settings-editable")
    @MainActor
    func shortcutIsUnboundByDefault() {
        let originalStore = KeyboardShortcutSettings.installIsolatedTestFileStore(
            prefix: "cmux-quad-shortcut"
        )
        defer {
            KeyboardShortcutSettings.resetAll()
            KeyboardShortcutSettings.settingsFileStore = originalStore
        }
        KeyboardShortcutSettings.resetAll()
        let shortcut = KeyboardShortcutSettings.shortcut(for: .splitQuad)
        #expect(shortcut.isUnbound)
        #expect(KeyboardShortcutSettings.Action.splitQuad.defaultShortcut.isUnbound)
        #expect(KeyboardShortcutSettings.publicShortcutActions.contains(.splitQuad))
        #expect(KeyboardShortcutSettings.settingsVisibleActions.contains(.splitQuad))

        let custom = StoredShortcut(key: "q", command: true, shift: true, option: true, control: true)
        KeyboardShortcutSettings.setShortcut(custom, for: .splitQuad)
        #expect(KeyboardShortcutSettings.shortcut(for: .splitQuad) == custom)
    }

    @Test("package ShortcutAction catalogs splitQuad unbound")
    func packageShortcutActionCatalogsSplitQuad() {
        #expect(ShortcutAction.splitQuad.rawValue == "splitQuad")
        #expect(ShortcutAction.splitQuad.group == .panes)
        #expect(ShortcutAction.splitQuad.defaultStroke == nil)
    }

    @Test("gdock quad pane shortcut actions default to Cmd-Y and Cmd-Shift-Y")
    @MainActor
    func gdockQuadPaneShortcutActionsAreDefaultedAndEditable() {
        let originalStore = KeyboardShortcutSettings.installIsolatedTestFileStore(
            prefix: "cmux-gdock-quad-shortcuts"
        )
        defer {
            KeyboardShortcutSettings.resetAll()
            KeyboardShortcutSettings.settingsFileStore = originalStore
        }
        KeyboardShortcutSettings.resetAll()

        #expect(KeyboardShortcutSettings.Action.gdockNextQuadPane.rawValue == "gdock.nextQuadPane")
        #expect(KeyboardShortcutSettings.Action.gdockQuadPaneWorkspaces.rawValue == "gdock.quadPaneWorkspaces")
        #expect(KeyboardShortcutSettings.shortcut(for: .gdockNextQuadPane) == StoredShortcut(key: "y", command: true, shift: false, option: false, control: false))
        #expect(KeyboardShortcutSettings.shortcut(for: .gdockQuadPaneWorkspaces) == StoredShortcut(key: "y", command: true, shift: true, option: false, control: false))
        #expect(KeyboardShortcutSettings.publicShortcutActions.contains(.gdockNextQuadPane))
        #expect(KeyboardShortcutSettings.publicShortcutActions.contains(.gdockQuadPaneWorkspaces))
        #expect(KeyboardShortcutSettings.settingsVisibleActions.contains(.gdockNextQuadPane))
        #expect(KeyboardShortcutSettings.settingsVisibleActions.contains(.gdockQuadPaneWorkspaces))

        let custom = StoredShortcut(key: "y", command: true, shift: true, option: true, control: false)
        KeyboardShortcutSettings.setShortcut(custom, for: .gdockNextQuadPane)
        #expect(KeyboardShortcutSettings.shortcut(for: .gdockNextQuadPane) == custom)
    }

    @Test("package ShortcutAction catalogs gdock quad pane defaults")
    func packageShortcutActionCatalogsGdockQuadPaneDefaults() {
        #expect(ShortcutAction.gdockNextQuadPane.rawValue == "gdock.nextQuadPane")
        #expect(ShortcutAction.gdockQuadPaneWorkspaces.rawValue == "gdock.quadPaneWorkspaces")
        #expect(ShortcutAction.gdockNextQuadPane.group == .panes)
        #expect(ShortcutAction.gdockQuadPaneWorkspaces.group == .panes)
        #expect(ShortcutAction.gdockNextQuadPane.defaultStroke == ShortcutStroke(key: "y", command: true, shift: false, option: false, control: false))
        #expect(ShortcutAction.gdockQuadPaneWorkspaces.defaultStroke == ShortcutStroke(key: "y", command: true, shift: true, option: false, control: false))
    }

    @Test("Dock tri-state routing: notApplicable when Dock unfocused")
    @MainActor
    func dockRouteNotApplicableWhenUnfocused() async throws {
        try await AppContextSerialGate.withExclusiveAppContext {
            try Self.withHarness(dockFocused: false) { harness in
                let outcome = harness.appDelegate.routeQuadToFocusedDock(
                    preferredWindow: harness.window
                )
                #expect(outcome == .notApplicable)
            }
        }
    }

    @Test("Dock quad mutates only Dock and leaves main unchanged")
    @MainActor
    func dockFocusedQuadSplitsDockOnly() async throws {
        try await AppContextSerialGate.withExclusiveAppContext {
            try Self.withHarness(dockFocused: true) { harness in
                let mainBefore = harness.mainWorkspace.bonsplitController.allPaneIds.count
                _ = try #require(
                    harness.dock.newSurface(kind: .terminal, inPane: harness.rootPane, focus: true)
                )
                #expect(QuadSplitAction.perform(inPane: harness.rootPane, dock: harness.dock))
                #expect(harness.dock.bonsplitController.allPaneIds.count == 4)
                #expect(harness.mainWorkspace.bonsplitController.allPaneIds.count == mainBefore)
            }
        }
    }

    @Test("Dock failure does not fall through to main (tri-state)")
    @MainActor
    func dockFailureDoesNotFallThrough() async throws {
        try await AppContextSerialGate.withExclusiveAppContext {
            try Self.withHarness(dockFocused: true) { harness in
                let mainBefore = harness.mainWorkspace.bonsplitController.allPaneIds.count
                _ = try #require(
                    harness.dock.newSurface(kind: .terminal, inPane: harness.rootPane, focus: true)
                )
                var config = harness.dock.bonsplitController.configuration
                config.allowSplits = false
                harness.dock.bonsplitController.configuration = config

                let outcome = QuadSplitAction.performDetailed(
                    inPane: harness.rootPane,
                    dock: harness.dock
                )
                #expect(outcome == .vetoed(.allowSplitsDisabled))
                #expect(harness.dock.bonsplitController.allPaneIds.count == 1)
                #expect(harness.mainWorkspace.bonsplitController.allPaneIds.count == mainBefore)

                // routeQuad reports handled(false) — callers must not fall through.
                let route = harness.appDelegate.routeQuadToFocusedDock(
                    preferredWindow: harness.window
                )
                if case .handled(let success) = route {
                    #expect(success == false)
                } else {
                    Issue.record("expected handled failure, got \(route)")
                }
                #expect(harness.mainWorkspace.bonsplitController.allPaneIds.count == mainBefore)
            }
        }
    }

    @Test("CLI accepts quad and rejects unknown directions")
    func cliAcceptsQuadAndRejectsUnknown() {
        #expect(QuadSplitAction.isQuadDirectionToken("quad"))
        #expect(QuadSplitAction.isQuadDirectionToken("Q"))
        #expect(!QuadSplitAction.isQuadDirectionToken("diagonal"))
        #expect(!QuadSplitAction.isQuadDirectionToken("left"))
    }

    @Test("bonsplit submodule worktree is clean")
    func bonsplitSubmoduleUnchanged() throws {
        let repoRoot = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        let dirty = Process()
        dirty.executableURL = URL(fileURLWithPath: "/usr/bin/git")
        dirty.arguments = ["-C", "vendor/bonsplit", "status", "--porcelain"]
        dirty.currentDirectoryURL = repoRoot
        let dirtyPipe = Pipe()
        dirty.standardOutput = dirtyPipe
        dirty.standardError = Pipe()
        try dirty.run()
        dirty.waitUntilExit()
        let dirtyOut = String(data: dirtyPipe.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? ""
        #expect(dirtyOut.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
    }
}

// MARK: - Harness

private extension QuadSplitButtonTests {
    @MainActor
    struct Harness {
        let appDelegate: AppDelegate
        let dock: DockSplitStore
        let mainWorkspace: Workspace
        let rootPane: PaneID
        let window: NSWindow
    }

    @MainActor
    static func withHarness(dockFocused: Bool, _ body: (Harness) throws -> Void) throws {
        let previousAppDelegate = AppDelegate.shared
        let previousManager = TerminalController.shared.activeTabManagerForCallerNotification()
        let originalSettingsFileStore = KeyboardShortcutSettings.installIsolatedTestFileStore(
            prefix: "cmux-quad-button"
        )
        KeyboardShortcutSettings.resetAll()

        let appDelegate = AppDelegate()
        let suiteName = "QuadSplitButtonTests.\(UUID().uuidString)"
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
            dock: dock,
            mainWorkspace: mainWorkspace,
            rootPane: rootPane,
            window: window
        ))
    }
}
