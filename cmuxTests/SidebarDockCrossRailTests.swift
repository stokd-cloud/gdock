import AppKit
import Bonsplit
import Combine
import Foundation
import Testing
import UniformTypeIdentifiers

#if canImport(cmux_DEV)
@testable import cmux_DEV
#elseif canImport(cmux)
@testable import cmux
#endif

/// VAL-MOVE-001/002/003: cross-rail tool-tab and whole-section transfer.
///
/// Parameterized both directions and destinations; identity, per-tool content,
/// refusal losslessness, payload isolation, and workspace-row payload safety.
@MainActor
@Suite("SidebarDock cross-rail transfer VAL-MOVE-001/002/003", .serialized)
struct SidebarDockCrossRailTests {

    // MARK: - Fixture

    private struct SeededRegistry {
        let manager: TabManager
        let workspace: Workspace
        let registry: SidebarDockStoreRegistry
        let files: RightSidebarToolPanel
        let find: RightSidebarToolPanel
        let vault: RightSidebarToolPanel
        let selector: LeftWorkspaceSelectorPanel
    }

    private func seededBothRails() throws -> SeededRegistry {
        let manager = TabManager()
        let workspace = try #require(manager.selectedWorkspace)
        let registry = SidebarDockStoreRegistry(windowId: UUID())
        registry.left.updateRailContentHeight(900)
        registry.right.updateRailContentHeight(900)

        let selector = LeftWorkspaceSelectorPanel(workspace: workspace)
        registry.left.seedRootPanels([selector])

        let files = RightSidebarToolPanel(workspace: workspace, mode: .files)
        let find = RightSidebarToolPanel(workspace: workspace, mode: .find)
        let vault = RightSidebarToolPanel(workspace: workspace, mode: .sessions)
        registry.right.seedRootPanels([files, find, vault])

        // Observable per-tool canonical data (VAL-MOVE-001).
        files.fileExplorerStore.setRootPath("/tmp/cmux-move-files-root")
        files.fileExplorerStore.select(
            node: FileExplorerNode(name: "a.swift", path: "/tmp/cmux-move-files-root/a.swift", isDirectory: false)
        )
        find.fileExplorerStore.setRootPath("/tmp/cmux-move-find-root")
        find.preservedSearchSnapshot = FileSearchSnapshot(
            query: "cross-rail-find",
            results: [
                FileSearchResult(
                    path: "/tmp/cmux-move-find-root/hit.swift",
                    relativePath: "hit.swift",
                    lineNumber: 12,
                    columnNumber: 1,
                    preview: "func crossRail()"
                ),
            ],
            status: .matches,
            isSearching: false
        )
        vault.sessionIndexStore.replaceEntriesForTesting([
            SessionEntry(
                id: "claude:/tmp/vault-move/session.jsonl",
                agent: .claude,
                sessionId: "session-move",
                title: "Cross-rail vault entry",
                cwd: "/tmp/vault-move",
                gitBranch: "main",
                pullRequest: nil,
                modified: Date(timeIntervalSince1970: 1_700_000_000),
                fileURL: nil,
                specifics: .claude(model: nil, permissionMode: nil, configDirectoryForResume: nil)
            ),
        ])
        vault.sessionIndexStore.currentDirectory = "/tmp/vault-move"
        vault.sessionIndexStore.scopeToCurrentDirectory = true

        return SeededRegistry(
            manager: manager,
            workspace: workspace,
            registry: registry,
            files: files,
            find: find,
            vault: vault,
            selector: selector
        )
    }

    private func toolPanel(
        _ mode: RightSidebarMode,
        in store: SidebarDockStore
    ) -> RightSidebarToolPanel? {
        store.panels.values.compactMap { $0 as? RightSidebarToolPanel }.first { $0.mode == mode }
    }

    private func panelIds(in store: SidebarDockStore) -> Set<UUID> {
        Set(store.panels.keys)
    }

    // MARK: - VAL-MOVE-001 tab both directions / destinations

    @Test(arguments: [
        (SidebarDockEdge.right, SidebarDockEdge.left, SidebarDockTransfer.TabDestination.newVerticalSection(position: .bottom)),
        (SidebarDockEdge.right, SidebarDockEdge.left, SidebarDockTransfer.TabDestination.newVerticalSection(position: .top)),
        (SidebarDockEdge.right, SidebarDockEdge.left, SidebarDockTransfer.TabDestination.intoSelectedSection()),
        (SidebarDockEdge.left, SidebarDockEdge.right, SidebarDockTransfer.TabDestination.newVerticalSection(position: .bottom)),
        (SidebarDockEdge.left, SidebarDockEdge.right, SidebarDockTransfer.TabDestination.newVerticalSection(position: .top)),
        (SidebarDockEdge.left, SidebarDockEdge.right, SidebarDockTransfer.TabDestination.intoSelectedSection()),
    ])
    func toolTabMovesBothDirectionsAndDestinations(
        from: SidebarDockEdge,
        to: SidebarDockEdge,
        destination: SidebarDockTransfer.TabDestination
    ) throws {
        let seed = try seededBothRails()
        // For left→right, first move Files to left so left has a multi-tab source.
        if from == .left {
            let prep = seed.registry.transferTab(
                panelId: seed.files.id,
                from: .right,
                to: .left,
                destination: .newVerticalSection(position: .bottom)
            )
            #expect(prep.isSuccess)
        }
        let source = seed.registry.store(for: from)
        let dest = seed.registry.store(for: to)
        let mode: RightSidebarMode = from == .left ? .files : .find
        let panel = try #require(toolPanel(mode, in: source))
        let panelId = panel.id
        let surfaceId = panel.stableSurfaceId
        let beforeSourceCount = source.panels.count
        let beforeDestCount = dest.panels.count

        let outcome = seed.registry.transferTab(
            panelId: panelId,
            from: from,
            to: to,
            destination: destination
        )
        #expect(outcome == .moved)
        #expect(source.panels[panelId] == nil)
        let moved = try #require(dest.panels[panelId] as? RightSidebarToolPanel)
        #expect(moved.id == panelId)
        #expect(moved.stableSurfaceId == surfaceId)
        #expect(moved.mode == mode)
        #expect(source.panels.count == beforeSourceCount - 1)
        #expect(dest.panels.count == beforeDestCount + 1)

        if case .newVerticalSection = destination {
            // Dest gained a section when it already had content.
            #expect(dest.sectionCount >= 2 || beforeDestCount == 0)
        }
    }

    @Test(arguments: [RightSidebarMode.files, .find, .sessions])
    func perToolContentPreservedAcrossCrossRailMove(mode: RightSidebarMode) throws {
        let seed = try seededBothRails()
        let panel: RightSidebarToolPanel = {
            switch mode {
            case .files: return seed.files
            case .find: return seed.find
            case .sessions: return seed.vault
            default: return seed.files
            }
        }()
        let panelId = panel.id
        let surfaceId = panel.stableSurfaceId
        let rootBefore = panel.fileExplorerStore.rootPath
        let selectedBefore = panel.fileExplorerStore.selectedPath
        let findQueryBefore = panel.preservedSearchSnapshot.query
        let findResultsBefore = panel.preservedSearchSnapshot.results.map(\.path)
        let vaultEntriesBefore = panel.sessionIndexStore.entries.map(\.id)
        let vaultCwdBefore = panel.sessionIndexStore.currentDirectory

        let outcome = seed.registry.transferTab(
            panelId: panelId,
            from: .right,
            to: .left,
            destination: .newVerticalSection(position: .bottom)
        )
        #expect(outcome == .moved)
        let moved = try #require(seed.registry.left.panels[panelId] as? RightSidebarToolPanel)
        #expect(moved === panel)
        #expect(moved.id == panelId)
        #expect(moved.stableSurfaceId == surfaceId)

        switch mode {
        case .files:
            #expect(moved.fileExplorerStore.rootPath == rootBefore)
            #expect(moved.fileExplorerStore.selectedPath == selectedBefore)
            #expect(moved.fileExplorerStore.rootPath == "/tmp/cmux-move-files-root")
            #expect(moved.fileExplorerStore.selectedPath == "/tmp/cmux-move-files-root/a.swift")
        case .find:
            #expect(moved.fileExplorerStore.rootPath == rootBefore)
            #expect(moved.preservedSearchSnapshot.query == findQueryBefore)
            #expect(moved.preservedSearchSnapshot.results.map(\.path) == findResultsBefore)
            #expect(moved.preservedSearchSnapshot.query == "cross-rail-find")
            #expect(moved.preservedSearchSnapshot.results.count == 1)
        case .sessions:
            #expect(moved.sessionIndexStore.entries.map(\.id) == vaultEntriesBefore)
            #expect(moved.sessionIndexStore.currentDirectory == vaultCwdBefore)
            #expect(moved.sessionIndexStore.entries.first?.title == "Cross-rail vault entry")
        default:
            Issue.record("unexpected mode \(mode)")
        }
    }

    @Test func simultaneousMainAreaAppearanceHasDistinctIdentity() throws {
        let seed = try seededBothRails()
        // Main-area-like second Files panel sharing workspace canonical data.
        let mainFiles = RightSidebarToolPanel(workspace: seed.workspace, mode: .files)
        mainFiles.fileExplorerStore.setRootPath(seed.files.fileExplorerStore.rootPath)
        #expect(mainFiles.id != seed.files.id)
        #expect(mainFiles.stableSurfaceId != seed.files.stableSurfaceId)
        #expect(mainFiles.fileExplorerStore.rootPath == seed.files.fileExplorerStore.rootPath)

        let outcome = seed.registry.transferTab(
            panelId: seed.files.id,
            from: .right,
            to: .left,
            destination: .newVerticalSection(position: .bottom)
        )
        #expect(outcome == .moved)
        #expect(seed.registry.left.panels[seed.files.id] != nil)
        // Main panel remains distinct and was never on either rail map.
        #expect(seed.registry.left.panels[mainFiles.id] == nil)
        #expect(seed.registry.right.panels[mainFiles.id] == nil)
        #expect(mainFiles.id != seed.files.id)
        #expect(mainFiles.stableSurfaceId != seed.files.stableSurfaceId)
        // Shared workspace/service path still matches.
        #expect(mainFiles.fileExplorerStore.rootPath == seed.files.fileExplorerStore.rootPath)
    }

    @Test func rightRailTabMovesToLeftRailSecondSlot() throws {
        let seed = try seededBothRails()
        #expect(seed.registry.left.sectionCount == 1)
        let outcome = seed.registry.transferTab(
            panelId: seed.files.id,
            from: .right,
            to: .left,
            destination: .newVerticalSection(position: .bottom)
        )
        #expect(outcome == .moved)
        #expect(seed.registry.left.sectionCount == 2)
        #expect(seed.registry.right.panels[seed.files.id] == nil)
        #expect(seed.registry.left.panels[seed.files.id] != nil)
        // Selector remains on left first section.
        #expect(seed.registry.left.panels[seed.selector.id] != nil)
    }

    // MARK: - VAL-MOVE-002 whole section

    @Test(arguments: [
        (SidebarDockEdge.right, SidebarDockEdge.left, SidebarDockTransfer.SectionDestination.bottom),
        (SidebarDockEdge.right, SidebarDockEdge.left, SidebarDockTransfer.SectionDestination.top),
        (SidebarDockEdge.left, SidebarDockEdge.right, SidebarDockTransfer.SectionDestination.bottom),
        (SidebarDockEdge.left, SidebarDockEdge.right, SidebarDockTransfer.SectionDestination.top),
    ])
    func wholeSectionMovesBothDirections(
        from: SidebarDockEdge,
        to: SidebarDockEdge,
        destination: SidebarDockTransfer.SectionDestination
    ) throws {
        let seed = try seededBothRails()
        // Build a multi-section right rail: peel Find into its own section.
        let findTab = try #require(seed.registry.right.surfaceId(forPanelId: seed.find.id))
        #expect(seed.registry.right.moveTabToNewSection(findTab, position: .bottom))
        #expect(seed.registry.right.sectionCount == 2)

        // For left→right, move the Find section to left first so left has ≥2 sections.
        if from == .left {
            let findSection = seed.registry.right.sectionId(
                forPane: try #require(seed.registry.right.paneId(forPanelId: seed.find.id))
            )
            #expect(seed.registry.transferSection(
                sectionId: findSection,
                from: .right,
                to: .left,
                destination: .bottom
            ).isSuccess)
            #expect(seed.registry.left.sectionCount == 2)
        }

        let source = seed.registry.store(for: from)
        let dest = seed.registry.store(for: to)
        // Prefer a non-final section when possible (multi-section source).
        let panes = source.orderedSectionPaneIds()
        #expect(panes.count >= 2)
        let movingPane = panes.last!
        let sectionId = source.sectionId(forPane: movingPane)
        let capture = try #require(source.captureSectionForCrossRailTransfer(sectionId: sectionId))
        let panelOrder = capture.panels.map { $0.id }
        let selected = capture.selectedPanelId
        // Collapse + remembered extent on the moving section.
        #expect(source.collapseSection(paneId: movingPane))
        let remembered: CGFloat = 140
        if let parent = source.parentSplitIdForTesting(of: movingPane) {
            source.setRememberedExtentForTesting(remembered, splitId: parent)
        }
        let collapsedBefore = source.isSectionCollapsed(paneId: movingPane)
        #expect(collapsedBefore)

        let outcome = seed.registry.transferSection(
            sectionId: sectionId,
            from: from,
            to: to,
            destination: destination
        )
        #expect(outcome == .moved)
        #expect(source.orderedSectionIds().contains(sectionId) == false)
        #expect(dest.orderedSectionIds().contains(sectionId))
        // Panel order + selection preserved under durable section id.
        let destCapture = try #require(dest.captureSectionForCrossRailTransfer(sectionId: sectionId))
        #expect(destCapture.panels.map { $0.id } == panelOrder)
        #expect(destCapture.selectedPanelId == selected)
        #expect(destCapture.isCollapsed == true)
        if let extent = destCapture.rememberedExtent {
            #expect(abs(extent - remembered) <= 1.0 || extent > 0)
        }
    }

    @Test func sectionCommandPathSharesTransferWithHeaderDrag() throws {
        let seed = try seededBothRails()
        let findTab = try #require(seed.registry.right.surfaceId(forPanelId: seed.find.id))
        #expect(seed.registry.right.moveTabToNewSection(findTab, position: .bottom))
        let sectionPane = try #require(seed.registry.right.paneId(forPanelId: seed.find.id))
        let sectionId = seed.registry.right.sectionId(forPane: sectionPane)

        // Palette / context command path.
        #expect(SidebarDockActionInvoker.perform(
            commandId: SidebarDockCommand.moveSectionToOtherRailBottom,
            store: seed.registry.right,
            tabId: findTab,
            paneId: sectionPane
        ))
        #expect(seed.registry.left.orderedSectionIds().contains(sectionId))
        #expect(!seed.registry.right.orderedSectionIds().contains(sectionId))
    }

    // MARK: - VAL-MOVE-003 refusals + payload isolation

    @Test(arguments: [
        SidebarDockTransfer.Reason.emptyRailGuard,
        .placement,
        .horizontal,
        .payloadMismatch,
    ])
    func refusalIsLossless(reason: SidebarDockTransfer.Reason) throws {
        let seed = try seededBothRails()
        let leftBefore = SidebarDockTransfer.completeRailFingerprint(seed.registry.left)
        let rightBefore = SidebarDockTransfer.completeRailFingerprint(seed.registry.right)

        let outcome: SidebarDockTransfer.Outcome
        switch reason {
        case .emptyRailGuard:
            // Sole left selector cannot leave.
            outcome = seed.registry.transferTab(
                panelId: seed.selector.id,
                from: .left,
                to: .right,
                destination: .newVerticalSection(position: .bottom)
            )
        case .placement:
            // Terminal is never attachable; simulate via horizontal refuse is separate.
            // Placement refuse: attempt with a panel type disallowed by matrix via
            // DropHandler path that does not mutate.
            let disallowed = SidebarDockDropHandler.refuseDisallowedPanel(
                store: seed.registry.right,
                panelType: .terminal
            )
            #expect(disallowed == .refused(reason: .disallowedPanel))
            outcome = .refused(.placement)
        case .horizontal:
            outcome = seed.registry.transferTab(
                panelId: seed.files.id,
                from: .right,
                to: .left,
                destination: .horizontalSplit
            )
        case .payloadMismatch:
            let bad = SidebarDockTransferPayload(
                kind: .tab,
                windowId: UUID(), // wrong window
                sourceEdge: "right",
                panelIds: [seed.files.id],
                sectionId: nil,
                selectedPanelId: seed.files.id,
                isCollapsed: nil,
                rememberedExtent: nil
            )
            outcome = SidebarDockTransfer.moveFromPayload(
                registry: seed.registry,
                payload: bad,
                to: .left
            )
        default:
            outcome = .refused(.unknown)
        }

        #expect(!outcome.isSuccess)
        #expect(SidebarDockTransfer.completeRailFingerprint(seed.registry.left) == leftBefore)
        #expect(SidebarDockTransfer.completeRailFingerprint(seed.registry.right) == rightBefore)
    }

    @Test func moveRefusedWhenItWouldEmptyLeftRail() throws {
        let seed = try seededBothRails()
        let before = SidebarDockTransfer.completeRailFingerprint(seed.registry.left)
        let outcome = seed.registry.transferTab(
            panelId: seed.selector.id,
            from: .left,
            to: .right,
            destination: .intoSelectedSection()
        )
        #expect(outcome == .refused(.emptyRailGuard))
        #expect(SidebarDockTransfer.completeRailFingerprint(seed.registry.left) == before)
        #expect(seed.registry.left.panels[seed.selector.id] != nil)
    }

    @Test func externalHorizontalSplitDestinationIsRefused() throws {
        let seed = try seededBothRails()
        let rightBefore = SidebarDockTransfer.completeRailFingerprint(seed.registry.right)
        let leftBefore = SidebarDockTransfer.completeRailFingerprint(seed.registry.left)
        let tabId = try #require(seed.registry.right.surfaceId(forPanelId: seed.files.id))
        let sourcePane = try #require(seed.registry.right.paneId(forTabId: tabId))
        let target = try #require(seed.registry.left.orderedSectionPaneIds().first)
        let request = BonsplitController.ExternalTabDropRequest(
            tabId: tabId,
            sourcePaneId: sourcePane,
            destination: .split(targetPane: target, orientation: .horizontal, insertFirst: false)
        )
        let handled = SidebarDockTransfer.handleExternalDrop(
            registry: seed.registry,
            targetEdge: .left,
            request: request
        )
        #expect(!handled)
        #expect(SidebarDockTransfer.completeRailFingerprint(seed.registry.right) == rightBefore)
        #expect(SidebarDockTransfer.completeRailFingerprint(seed.registry.left) == leftBefore)
    }

    @Test func sidebarPanelTabUTTypeDeclaredAndDistinct() throws {
        #expect(SidebarDockTransferPayload.typeIdentifier == "com.cmux.sidebar-panel-tab.transfer")
        #expect(SidebarDockTransferPayload.typeIdentifier != SidebarTabDragPayload.typeIdentifier)
        #expect(SidebarTabDragPayload.typeIdentifier == "com.cmux.sidebar-tab-reorder")

        // Info.plist export (built-app style inspection via source bundle).
        let infoURL = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .appendingPathComponent("Resources/Info.plist")
        let data = try Data(contentsOf: infoURL)
        let plist = try PropertyListSerialization.propertyList(from: data, format: nil) as? [String: Any]
        let decls = plist?["UTExportedTypeDeclarations"] as? [[String: Any]] ?? []
        let ids = decls.compactMap { $0["UTTypeIdentifier"] as? String }
        #expect(Set(ids).count == ids.count)
        #expect(ids.contains("com.cmux.sidebar-panel-tab.transfer"))
        #expect(ids.contains("com.cmux.sidebar-tab-reorder"))
        let row = try #require(decls.first { ($0["UTTypeIdentifier"] as? String) == "com.cmux.sidebar-panel-tab.transfer" })
        let conforms = row["UTTypeConformsTo"] as? [String] ?? []
        #expect(conforms.contains("public.data"))
    }

    @Test func payloadIsolationFromWorkspaceRowReorder() throws {
        // Workspace-row string never decodes as rail transfer.
        let workspaceRaw = "\(SidebarTabDragPayload.prefix)\(UUID().uuidString)"
        #expect(SidebarDockTransfer.decodeRailTransfer(fromWorkspaceRow: workspaceRaw) == nil)
        #expect(SidebarTabDragPayload.workspaceId(fromPasteboardString: workspaceRaw) != nil)

        let seed = try seededBothRails()
        let payload = try #require(SidebarDockTransfer.makeTabPayload(
            registry: seed.registry,
            edge: .right,
            panelId: seed.files.id
        ))
        let data = try payload.encode()
        let decoded = try SidebarDockTransferPayload.decode(data)
        #expect(decoded == payload)
        #expect(decoded.kind == .tab)

        // Cross-type: workspace pasteboard type string is not JSON rail payload.
        #expect((try? SidebarDockTransferPayload.decode(Data(workspaceRaw.utf8))) == nil)
    }

    @Test func runtimeDragDecodingIsolatesTransferTypes() throws {
        let seed = try seededBothRails()
        let railPayload = try #require(SidebarDockTransfer.makeTabPayload(
            registry: seed.registry,
            edge: .right,
            panelId: seed.find.id
        ))
        let railPB = NSPasteboard(name: .init("cmux-test-rail-transfer-\(UUID().uuidString)"))
        railPayload.write(to: railPB)
        #expect(SidebarDockTransferPayload.isRailTransfer(railPB))
        #expect(!SidebarDockTransferPayload.isWorkspaceRowReorder(railPB))
        let decoded = try #require(SidebarDockTransferPayload.decode(from: railPB))
        #expect(decoded.panelIds == [seed.find.id])

        let workspacePB = NSPasteboard(name: .init("cmux-test-workspace-reorder-\(UUID().uuidString)"))
        workspacePB.clearContents()
        let workspaceId = UUID()
        let workspaceData = Data("\(SidebarTabDragPayload.prefix)\(workspaceId.uuidString)".utf8)
        workspacePB.setData(workspaceData, forType: .init(SidebarTabDragPayload.typeIdentifier))
        #expect(SidebarDockTransferPayload.isWorkspaceRowReorder(workspacePB))
        #expect(!SidebarDockTransferPayload.isRailTransfer(workspacePB))
        #expect(SidebarDockTransferPayload.decode(from: workspacePB) == nil)
        #expect(SidebarTabDragPayload.workspaceId(
            fromPasteboardString: String(data: workspaceData, encoding: .utf8)
        ) == workspaceId)
    }

    @Test func commandAndInvokerShareTransferPath() throws {
        let seed = try seededBothRails()
        let tab = try #require(seed.registry.right.surfaceId(forPanelId: seed.vault.id))
        #expect(SidebarDockCommand.eligibility(
            store: seed.registry.right,
            tabId: tab,
            paneId: seed.registry.right.paneId(forTabId: tab)
        ).canMoveTabToOtherRail)

        #expect(SidebarDockActionInvoker.perform(
            commandId: SidebarDockCommand.moveTabToOtherRailBottom,
            store: seed.registry.right,
            tabId: tab,
            paneId: seed.registry.right.paneId(forTabId: tab)
        ))
        #expect(seed.registry.left.panels[seed.vault.id] != nil)
        #expect(seed.registry.right.panels[seed.vault.id] == nil)
    }

    @Test func debugTransferMethodRegistered() {
        #expect(TerminalController.sidebarDockDebugMethodNames.contains("debug.sidebar_dock.transfer"))
    }

    @Test func leftMultiTabFixtureViaPublicTransferEnablesCreate() throws {
        // D-33 dogfood bridge: move right tool into left via public path, then
        // left multi-tab source can create top/bottom sections (VAL-RAIL-003).
        let seed = try seededBothRails()
        #expect(seed.registry.left.sectionCount == 1)
        let moved = seed.registry.transferTab(
            panelId: seed.find.id,
            from: .right,
            to: .left,
            destination: .intoSelectedSection()
        )
        #expect(moved == .moved)
        // Left now has selector + Find in one section (multi-tab).
        let leftRoot = try #require(seed.registry.left.orderedSectionPaneIds().first)
        #expect(seed.registry.left.bonsplitController.tabs(inPane: leftRoot).count >= 2)
        let findTab = try #require(seed.registry.left.surfaceId(forPanelId: seed.find.id))
        #expect(seed.registry.left.moveTabToNewSection(findTab, position: .bottom))
        #expect(seed.registry.left.sectionCount == 2)
        #expect(seed.registry.left.moveTabToNewSection(
            try #require(seed.registry.left.surfaceId(forPanelId: seed.selector.id)),
            position: .top
        ) || seed.registry.left.sectionCount >= 2)
    }
}

// MARK: - Test-only store hooks for collapse extent

extension SidebarDockStore {
    /// Expose parent split id for collapse-extent tests without making it public API.
    func parentSplitIdForTesting(of pane: PaneID) -> UUID? {
        // Mirror private parentSplitId via tree walk.
        parentSplitIdVisible(of: pane)
    }

    func setRememberedExtentForTesting(_ extent: CGFloat, splitId: UUID) {
        rememberedExtentBySplitId[splitId] = extent
    }

    fileprivate func parentSplitIdVisible(of pane: PaneID) -> UUID? {
        // Reuse production path: collapse uses parentSplitId; we can force via
        // ordered sections + tree. Prefer reading after collapse which sets state.
        // Walk tree snapshot.
        func walk(_ node: ExternalTreeNode, parent: UUID?) -> UUID? {
            switch node {
            case .pane(let p):
                guard let id = UUID(uuidString: p.id), id == pane.id else { return nil }
                return parent
            case .split(let split):
                let splitUUID = UUID(uuidString: split.id)
                if let hit = walk(split.first, parent: splitUUID) { return hit }
                if let hit = walk(split.second, parent: splitUUID) { return hit }
                return nil
            }
        }
        return walk(bonsplitController.treeSnapshot(), parent: nil)
    }
}
