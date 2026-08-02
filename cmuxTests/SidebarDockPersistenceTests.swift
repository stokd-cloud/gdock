import AppKit
import Bonsplit
import Foundation
import Testing

#if canImport(cmux_DEV)
@testable import cmux_DEV
#elseif canImport(cmux)
@testable import cmux
#endif

/// VAL-PERSIST-001..005: session rail round-trip, fingerprint matrix, legacy
/// first-use, partial/all-invalid recovery, schema/workspace case guards.
@MainActor
@Suite("Sidebar dock session persistence", .serialized)
struct SidebarDockPersistenceTests {
    // MARK: - Schema guards (VAL-PERSIST-001)

    @Test func schemaVersionRemainsOneAndNoNewWorkspaceLayoutCase() throws {
        #expect(SessionSnapshotSchema.currentVersion == 1)
        // Case set is still pane/split only — encode a nested vertical chain.
        let layout: SessionWorkspaceLayoutSnapshot = .split(
            SessionSplitLayoutSnapshot(
                orientation: .vertical,
                dividerPosition: 0.4,
                first: .pane(SessionPaneLayoutSnapshot(panelIds: [UUID()], selectedPanelId: nil)),
                second: .pane(SessionPaneLayoutSnapshot(panelIds: [UUID()], selectedPanelId: nil))
            )
        )
        let data = try JSONEncoder().encode(layout)
        let decoded = try JSONDecoder().decode(SessionWorkspaceLayoutSnapshot.self, from: data)
        if case .split = decoded {
            // ok
        } else {
            Issue.record("Expected split case only")
        }
        // Unknown third case must fail decode (no new case).
        let bogus = Data(#"{"type":"railSection","pane":{"panelIds":[]}}"#.utf8)
        #expect(throws: DecodingError.self) {
            _ = try JSONDecoder().decode(SessionWorkspaceLayoutSnapshot.self, from: bogus)
        }
    }

    @Test func legacySessionWithoutRailFieldsDecodesCleanly() throws {
        let window = SessionWindowSnapshot(
            windowId: UUID(),
            frame: nil,
            display: nil,
            tabManager: SessionTabManagerSnapshot(selectedWorkspaceIndex: 0, workspaces: []),
            sidebar: SessionSidebarSnapshot(isVisible: true, selection: .tabs, width: 240),
            configFrames: nil,
            dock: nil
        )
        let snapshot = AppSessionSnapshot(
            version: SessionSnapshotSchema.currentVersion,
            createdAt: Date().timeIntervalSince1970,
            windows: [window]
        )
        let encoded = try JSONEncoder().encode(snapshot)
        var root = try #require(JSONSerialization.jsonObject(with: encoded) as? [String: Any])
        var windows = try #require(root["windows"] as? [[String: Any]])
        windows[0].removeValue(forKey: "leftSidebarDock")
        windows[0].removeValue(forKey: "rightSidebarDock")
        root["windows"] = windows
        let legacyData = try JSONSerialization.data(withJSONObject: root)
        let decoded = try JSONDecoder().decode(AppSessionSnapshot.self, from: legacyData)
        #expect(decoded.windows.first?.leftSidebarDock == nil)
        #expect(decoded.windows.first?.rightSidebarDock == nil)
        #expect(decoded.version == 1)
    }

    // MARK: - Round-trip N=3 / N=5 (VAL-PERSIST-001)

    @Test func roundTripThreeSectionRightRailPreservesStableIdsAndState() throws {
        let manager = TabManager()
        let workspace = try #require(manager.selectedWorkspace)
        let store = SidebarDockStore(edge: .right, windowId: UUID())
        #expect(SidebarDockSeeding.seedRightIfEmpty(
            store: store,
            workspace: workspace,
            preferredMode: .find
        ))
        // Peel Files and Vault into their own sections → 3 sections.
        let modes = SidebarDockSeeding.orderedRightModes(in: store)
        #expect(modes.count == 3)
        let filesPanel = try #require(store.panels.values.compactMap { $0 as? RightSidebarToolPanel }.first { $0.mode == .files })
        let vaultPanel = try #require(store.panels.values.compactMap { $0 as? RightSidebarToolPanel }.first { $0.mode == .sessions })
        let filesTab = try #require(store.surfaceId(forPanelId: filesPanel.id))
        #expect(store.moveTabToNewSection(filesTab, position: .bottom))
        let vaultTab = try #require(store.surfaceId(forPanelId: vaultPanel.id))
        #expect(store.moveTabToNewSection(vaultTab, position: .bottom))
        #expect(store.sectionCount == 3)

        let before = store.sectionSnapshots()
        let beforeIds = before.map(\.sectionId)
        #expect(beforeIds.count == 3)
        // Collapse middle section.
        let middlePane = store.orderedSectionPaneIds()[1]
        #expect(store.collapseSection(paneId: middlePane))

        let snap = store.sessionSnapshot()
        #expect(snap.sectionIds?.count == 3)
        #expect(snap.sectionIds == beforeIds)
        // Pane host ids must not appear as section identity.
        let paneHosts = Set(before.map(\.paneId))
        for sid in snap.sectionIds ?? [] {
            #expect(!paneHosts.contains(sid))
        }

        let restoreStore = SidebarDockStore(edge: .right, windowId: UUID())
        let result = restoreStore.restoreSessionSnapshot(snap, workspace: workspace)
        #expect(!result.didReseedCanonical)
        #expect(restoreStore.sectionCount == 3)
        let after = restoreStore.sectionSnapshots()
        #expect(after.map(\.sectionId) == beforeIds)
        #expect(after.map(\.tabPanelIds.count) == before.map(\.tabPanelIds.count))
        #expect(after.filter { $0.isCollapsed }.count == 1)
        #expect(SidebarDockSeeding.orderedRightModes(in: restoreStore).count == 3)
    }

    @Test func roundTripFiveSectionRailIsNotCapped() throws {
        let manager = TabManager()
        let workspace = try #require(manager.selectedWorkspace)
        let store = SidebarDockStore(edge: .right, windowId: UUID())
        // Seed three tools then peel each into its own section and add two more via new sections.
        #expect(SidebarDockSeeding.seedRightIfEmpty(
            store: store,
            workspace: workspace,
            preferredMode: .files
        ))
        let tools = store.panels.values.compactMap { $0 as? RightSidebarToolPanel }
        for tool in tools.dropFirst() {
            if let tab = store.surfaceId(forPanelId: tool.id) {
                _ = store.moveTabToNewSection(tab, position: .bottom)
            }
        }
        // Add two more tool sections (Files clones allowed as distinct panels).
        for _ in 0..<2 {
            let panel = RightSidebarToolPanel(workspace: workspace, mode: .find)
            #expect(store.attachPanelAsNewVerticalSection(panel, position: .bottom) != nil)
        }
        #expect(store.sectionCount == 5)

        let snap = store.sessionSnapshot()
        #expect(snap.sectionIds?.count == 5)
        let restoreStore = SidebarDockStore(edge: .right, windowId: UUID())
        _ = restoreStore.restoreSessionSnapshot(snap, workspace: workspace)
        #expect(restoreStore.sectionCount == 5)
        #expect(restoreStore.sectionSnapshots().map(\.sectionId) == snap.sectionIds)
    }

    // MARK: - Fingerprint matrix (VAL-PERSIST-003)

    @Test func fingerprintMatrixMutatesPerDimensionAndNoOpDoesNot() throws {
        let manager = TabManager()
        let workspace = try #require(manager.selectedWorkspace)
        let rightWindowId = UUID()
        let store = SidebarDockStore(edge: .right, windowId: rightWindowId)
        #expect(SidebarDockSeeding.seedRightIfEmpty(
            store: store,
            workspace: workspace,
            preferredMode: .files
        ))
        let base = store.sessionAutosaveFingerprint()
        #expect(store.sessionAutosaveFingerprint() == base) // no-op

        // Edge dimension: left vs right must not collide.
        let left = SidebarDockStore(edge: .left, windowId: rightWindowId)
        #expect(SidebarDockSeeding.seedLeftIfEmpty(store: left, workspace: workspace))
        #expect(left.sessionAutosaveFingerprint() != base)

        // Selection
        #expect(store.selectToolMode(.find, focus: false))
        let afterSelection = store.sessionAutosaveFingerprint()
        #expect(afterSelection != base)

        // Tab order within the multi-tab root section
        let filesPanel = try #require(
            store.panels.values.compactMap { $0 as? RightSidebarToolPanel }.first { $0.mode == .files }
        )
        let filesTab = try #require(store.surfaceId(forPanelId: filesPanel.id))
        #expect(store.reorderTab(filesTab, toIndex: 2) || store.reorderTab(filesTab, toIndex: 1))
        let afterTabOrder = store.sessionAutosaveFingerprint()
        #expect(afterTabOrder != afterSelection)

        // Section creation / order
        let findPanel = try #require(
            store.panels.values.compactMap { $0 as? RightSidebarToolPanel }.first { $0.mode == .find }
        )
        let findTab = try #require(store.surfaceId(forPanelId: findPanel.id))
        #expect(store.moveTabToNewSection(findTab, position: .bottom))
        let afterCreate = store.sessionAutosaveFingerprint()
        #expect(afterCreate != afterTabOrder)

        // Section reorder (swap two sections)
        if store.sectionCount >= 2 {
            #expect(store.reorderSection(from: 0, to: 1))
            let afterSectionOrder = store.sessionAutosaveFingerprint()
            #expect(afterSectionOrder != afterCreate)
        }

        // Divider weight/extent: set first vertical split when present
        let tree = store.bonsplitController.treeSnapshot()
        if case .split(let split) = tree, let splitId = UUID(uuidString: split.id) {
            let beforeDivider = store.sessionAutosaveFingerprint()
            #expect(store.bonsplitController.setDividerPosition(0.35, forSplit: splitId, fromExternal: true))
            let afterDivider = store.sessionAutosaveFingerprint()
            #expect(afterDivider != beforeDivider)
        }

        // Collapse
        let beforeCollapse = store.sessionAutosaveFingerprint()
        let pane = try #require(store.orderedSectionPaneIds().last)
        #expect(store.collapseSection(paneId: pane))
        let afterCollapse = store.sessionAutosaveFingerprint()
        #expect(afterCollapse != beforeCollapse)

        // Expand (remembered extent dimension still distinct from pre-collapse)
        #expect(store.expandSection(paneId: pane))
        let afterExpand = store.sessionAutosaveFingerprint()
        #expect(afterExpand != afterCollapse)

        // Named-layout apply mutates fingerprint on a registry
        let registry = SidebarDockStoreRegistry(windowId: UUID())
        SidebarDockSeeding.seedRegistryIfEmpty(
            registry: registry,
            workspace: workspace,
            preferredRightMode: .files
        )
        let beforeLayout = registry.sessionAutosaveFingerprint()
        let definition = CmuxSidebarDockDefinition(
            left: .init(sections: [
                .init(panels: ["workspaceSelector"], selected: "workspaceSelector"),
            ]),
            right: .init(sections: [
                .init(panels: ["find"], selected: "find"),
                .init(panels: ["sessions"], selected: "sessions", collapsed: true),
            ])
        )
        let appliedNamedLayout = registry.applyNamedLayoutDefinition(definition, workspace: workspace)
        #expect(appliedNamedLayout)
        #expect(registry.sessionAutosaveFingerprint() != beforeLayout)

        // Section removal: peel vault then close its sole tab via detach
        if let vault = store.panels.values.compactMap({ $0 as? RightSidebarToolPanel }).first(where: { $0.mode == .sessions }),
           let vaultTab = store.surfaceId(forPanelId: vault.id) {
            // Ensure vault is alone in a section so detach reduces section count.
            if store.sectionCount == 1 || (store.paneId(forTabId: vaultTab).map { store.bonsplitController.tabs(inPane: $0).count } ?? 0) > 1 {
                _ = store.moveTabToNewSection(vaultTab, position: .bottom)
            }
            let beforeRemove = store.sessionAutosaveFingerprint()
            _ = store.detachPanelKeepingInstance(panelId: vault.id)
            #expect(store.sessionAutosaveFingerprint() != beforeRemove)
        }

        // No-op again
        let stable = store.sessionAutosaveFingerprint()
        #expect(store.sessionAutosaveFingerprint() == stable)
    }

    // MARK: - First use + legacy (VAL-PERSIST-004)

    @Test(arguments: [
        RightSidebarMode.files,
        RightSidebarMode.find,
        RightSidebarMode.sessions,
        RightSidebarMode.feed,
        RightSidebarMode.dock,
    ])
    func firstFlagOnUseHonorsValidLegacySelection(_ mode: RightSidebarMode) throws {
        let suiteName = "cmux.sidebar.dock.persist.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defer { defaults.removePersistentDomain(forName: suiteName) }
        defaults.set(mode.rawValue, forKey: "rightSidebar.mode")
        let before = defaults.dictionaryRepresentation().filter { $0.key.hasPrefix("rightSidebar") || $0.key.hasPrefix("fileExplorer") }

        let manager = TabManager()
        let workspace = try #require(manager.selectedWorkspace)
        let store = SidebarDockStore(edge: .right, windowId: UUID())
        // No snapshot path: seed with legacy preference.
        #expect(SidebarDockSeeding.seedRightIfEmpty(
            store: store,
            workspace: workspace,
            preferredMode: mode
        ))
        let expected = SidebarDockPlacementMatrix.allows(mode: mode) ? mode : .files
        #expect(store.focusedToolMode() == expected)
        #expect(SidebarDockSeeding.orderedRightModes(in: store) == [.files, .find, .sessions])

        let after = defaults.dictionaryRepresentation().filter { $0.key.hasPrefix("rightSidebar") || $0.key.hasPrefix("fileExplorer") }
        #expect(after["rightSidebar.mode"] as? String == before["rightSidebar.mode"] as? String)
    }

    // MARK: - Invalid recovery (VAL-PERSIST-002)

    @Test func railEnvelopeKeepsSharedDockSnapshotClean() throws {
        // Shared Dock envelope must not grow rail-only fields.
        let dock = SessionSplitContainerSnapshot(
            focusedPanelId: nil,
            layout: .pane(SessionPaneLayoutSnapshot(panelIds: [], selectedPanelId: nil)),
            panels: []
        )
        let data = try JSONEncoder().encode(dock)
        let object = try #require(JSONSerialization.jsonObject(with: data) as? [String: Any])
        #expect(object["sectionIds"] == nil)
        #expect(object["collapsedSectionIds"] == nil)
        #expect(object["rememberedExtentsBySectionId"] == nil)

        let rail = SessionSidebarDockSnapshot(
            focusedPanelId: nil,
            layout: .pane(SessionPaneLayoutSnapshot(panelIds: [UUID()], selectedPanelId: nil)),
            panels: [],
            sectionIds: [UUID()],
            collapsedSectionIds: [UUID()],
            rememberedExtentsBySectionId: [UUID().uuidString: 120]
        )
        let railData = try JSONEncoder().encode(rail)
        let railObject = try #require(JSONSerialization.jsonObject(with: railData) as? [String: Any])
        #expect(railObject["sectionIds"] != nil)
        #expect(railObject["collapsedSectionIds"] != nil)
        #expect(railObject["rememberedExtentsBySectionId"] != nil)
    }

    @Test func partialInvalidPrunesAndKeepsSurvivors() throws {
        let manager = TabManager()
        let workspace = try #require(manager.selectedWorkspace)
        let goodId = UUID()
        let badId = UUID()
        let sectionId = UUID()
        let snap = SessionSidebarDockSnapshot(
            focusedPanelId: goodId,
            layout: .pane(SessionPaneLayoutSnapshot(
                panelIds: [goodId, badId],
                selectedPanelId: badId
            )),
            panels: [
                SessionPanelSnapshot(
                    id: goodId,
                    type: .rightSidebarTool,
                    title: "Find",
                    customTitle: nil,
                    directory: nil,
                    isPinned: false,
                    isManuallyUnread: false,
                    gitBranch: nil,
                    listeningPorts: [],
                    ttyName: nil,
                    terminal: nil,
                    browser: nil,
                    markdown: nil,
                    filePreview: nil,
                    rightSidebarTool: SessionRightSidebarToolPanelSnapshot(mode: .find)
                ),
                SessionPanelSnapshot(
                    id: badId,
                    type: .terminal,
                    title: "Term",
                    customTitle: nil,
                    directory: nil,
                    isPinned: false,
                    isManuallyUnread: false,
                    gitBranch: nil,
                    listeningPorts: [],
                    ttyName: nil,
                    terminal: nil,
                    browser: nil,
                    markdown: nil,
                    filePreview: nil,
                    rightSidebarTool: nil
                ),
            ],
            sectionIds: [sectionId]
        )
        let store = SidebarDockStore(edge: .right, windowId: UUID())
        let result = store.restoreSessionSnapshot(snap, workspace: workspace)
        #expect(!result.didReseedCanonical)
        #expect(result.prunedPanelCount >= 1)
        #expect(store.sectionCount >= 1)
        #expect(store.focusedToolMode() == .find)
        #expect(store.sectionSnapshots().first?.sectionId == sectionId)
    }

    @Test func allInvalidReseedsCanonicalAndLogsOnce() throws {
        let manager = TabManager()
        let workspace = try #require(manager.selectedWorkspace)
        let badId = UUID()
        let snap = SessionSidebarDockSnapshot(
            focusedPanelId: badId,
            layout: .pane(SessionPaneLayoutSnapshot(panelIds: [badId], selectedPanelId: badId)),
            panels: [
                SessionPanelSnapshot(
                    id: badId,
                    type: .browser,
                    title: "Web",
                    customTitle: nil,
                    directory: nil,
                    isPinned: false,
                    isManuallyUnread: false,
                    gitBranch: nil,
                    listeningPorts: [],
                    ttyName: nil,
                    terminal: nil,
                    browser: nil,
                    markdown: nil,
                    filePreview: nil,
                    rightSidebarTool: nil
                ),
            ],
            sectionIds: [UUID()]
        )
        var logs: [String] = []
        let store = SidebarDockStore(edge: .right, windowId: UUID())
        let result = store.restoreSessionSnapshot(
            snap,
            workspace: workspace,
            preferredLegacyMode: .sessions,
            recoveryLogSink: { logs.append($0) }
        )
        #expect(result.didReseedCanonical)
        #expect(result.didLogRecovery)
        #expect(logs.count == 1)
        #expect(SidebarDockSeeding.orderedRightModes(in: store) == [.files, .find, .sessions])
        #expect(store.focusedToolMode() == .sessions)
    }

    @Test func leftAllInvalidReseedsSelector() throws {
        let manager = TabManager()
        let workspace = try #require(manager.selectedWorkspace)
        let badId = UUID()
        let snap = SessionSidebarDockSnapshot(
            focusedPanelId: nil,
            layout: .pane(SessionPaneLayoutSnapshot(panelIds: [badId], selectedPanelId: nil)),
            panels: [
                SessionPanelSnapshot(
                    id: badId,
                    type: .terminal,
                    title: "t",
                    customTitle: nil,
                    directory: nil,
                    isPinned: false,
                    isManuallyUnread: false,
                    gitBranch: nil,
                    listeningPorts: [],
                    ttyName: nil,
                    terminal: nil,
                    browser: nil,
                    markdown: nil,
                    filePreview: nil,
                    rightSidebarTool: nil
                ),
            ]
        )
        var logs = 0
        let store = SidebarDockStore(edge: .left, windowId: UUID())
        let result = store.restoreSessionSnapshot(
            snap,
            workspace: workspace,
            recoveryLogSink: { _ in logs += 1 }
        )
        #expect(result.didReseedCanonical)
        #expect(logs == 1)
        #expect(store.panels.values.first is LeftWorkspaceSelectorPanel)
    }
}
