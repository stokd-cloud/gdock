import XCTest
import CmuxDockable
import Foundation

#if canImport(cmux_DEV)
@testable import cmux_DEV
#elseif canImport(cmux)
@testable import cmux
#endif

/// VAL-PERSIST-001/002/004: primary DockableSnapshot encode shape + live save/restore.
@MainActor
final class DockableSnapshotTests: XCTestCase {
    override func setUp() {
        super.setUp()
        DockableBootstrap.registerAllIfNeeded()
    }

    func testNewSessionWritePrimaryShapeIsDockableSnapshot() throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("cmux-dockable-snap-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }

        let mdURL = root.appendingPathComponent("note.md")
        try "# dockable\n".write(to: mdURL, atomically: true, encoding: .utf8)

        let workspace = Workspace()
        let paneId = try XCTUnwrap(workspace.bonsplitController.allPaneIds.first)
        _ = try XCTUnwrap(workspace.focusedPanelId)
        let browser = try XCTUnwrap(
            workspace.newBrowserSurface(
                inPane: paneId,
                url: URL(string: "https://example.com/persist"),
                focus: false
            )
        )
        let markdown = try XCTUnwrap(
            workspace.newMarkdownSurface(inPane: paneId, filePath: mdURL.path, focus: false)
        )
        workspace.setPanelCustomTitle(panelId: browser.id, title: "Example Browser")
        workspace.setPanelPinned(panelId: markdown.id, pinned: true)

        let snapshot = workspace.sessionSnapshot(includeScrollback: false)
        XCTAssertGreaterThanOrEqual(snapshot.panels.count, 3)

        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        let data = try encoder.encode(snapshot)
        let rootObject = try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
        let panels = try XCTUnwrap(rootObject["panels"] as? [[String: Any]])

        for panel in panels {
            // Primary content is nested DockableSnapshot — not the 9 optional fields.
            XCTAssertNotNil(panel["dockable"], "panel missing dockable: \(panel)")
            XCTAssertNil(panel["terminal"])
            XCTAssertNil(panel["browser"])
            XCTAssertNil(panel["markdown"])
            XCTAssertNil(panel["filePreview"])
            XCTAssertNil(panel["rightSidebarTool"])
            XCTAssertNil(panel["customSidebar"])
            XCTAssertNil(panel["agentSession"])
            XCTAssertNil(panel["project"])
            XCTAssertNil(panel["workspaceTodo"])

            let dockable = try XCTUnwrap(panel["dockable"] as? [String: Any])
            XCTAssertNotNil(dockable["id"])
            XCTAssertNotNil(dockable["kind"])
            XCTAssertNotNil(dockable["payload"])
        }

        // Metadata preserved on panel schema.
        let browserSnap = try XCTUnwrap(snapshot.panels.first { $0.id == browser.id })
        XCTAssertEqual(browserSnap.customTitle, "Example Browser")
        XCTAssertEqual(browserSnap.type, .browser)
        let mdSnap = try XCTUnwrap(snapshot.panels.first { $0.id == markdown.id })
        XCTAssertTrue(mdSnap.isPinned)
        XCTAssertEqual(mdSnap.markdown?.filePath, mdURL.path)
    }

    func testSaveRestoreRoundTripTerminalBrowserMarkdownWithGeometry() throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("cmux-dockable-rt-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }

        let mdURL = root.appendingPathComponent("readme.md")
        try "# restore me\n".write(to: mdURL, atomically: true, encoding: .utf8)

        let workspace = Workspace()
        let paneId = try XCTUnwrap(workspace.bonsplitController.allPaneIds.first)
        let terminalId = try XCTUnwrap(workspace.focusedPanelId)
        workspace.setPanelCustomTitle(panelId: terminalId, title: "Main Term")
        workspace.setPanelPinned(panelId: terminalId, pinned: true)

        let browser = try XCTUnwrap(
            workspace.newBrowserSurface(
                inPane: paneId,
                url: URL(string: "https://example.com/roundtrip"),
                focus: false
            )
        )
        let markdown = try XCTUnwrap(
            workspace.newMarkdownSurface(inPane: paneId, filePath: mdURL.path, focus: true)
        )

        // Canvas geometry for VAL-PERSIST-004.
        // Tests often lack live split frames, so seed canvas panes explicitly
        // (same restorePanes path production restore uses) then assert round-trip.
        workspace.setLayoutMode(.canvas)
        workspace.canvasModel.restorePanes([
            .init(
                paneId: terminalId,
                frame: CGRect(x: 40, y: 60, width: 480, height: 320),
                panelIds: [terminalId, browser.id, markdown.id],
                selectedPanelId: markdown.id
            )
        ])

        let snapshot = workspace.sessionSnapshot(includeScrollback: false)
        XCTAssertEqual(snapshot.layoutMode, WorkspaceLayoutMode.canvas.rawValue)
        XCTAssertNotNil(snapshot.canvasPanes)
        XCTAssertFalse(snapshot.canvasPanes?.isEmpty ?? true)
        XCTAssertEqual(snapshot.canvasPanes?.first?.x, 40)
        XCTAssertEqual(snapshot.canvasPanes?.first?.y, 60)

        // Round-trip through JSON to force DockableSnapshot encode/decode path.
        let encoded = try JSONEncoder().encode(snapshot)
        let decoded = try JSONDecoder().decode(SessionWorkspaceSnapshot.self, from: encoded)

        // Every panel carries DockableSnapshot-reconstructable typed state.
        for panel in decoded.panels {
            XCTAssertTrue(panel.hasRestorableTypedPayload || panel.type == .workspaceTodo)
            let dockable = try panel.makeDockableSnapshot()
            XCTAssertEqual(dockable.id, panel.id)
            XCTAssertEqual(dockable.kind.rawValue, panel.type.rawValue)
        }

        let restored = Workspace()
        let idMap = restored.restoreSessionSnapshot(decoded)

        XCTAssertEqual(restored.layoutMode, .canvas)
        XCTAssertEqual(restored.panels.count, snapshot.panels.count)

        // Kinds + representative state.
        let restoredTerminal = try XCTUnwrap(
            restored.panels.values.first { $0.panelType == .terminal } as? TerminalPanel
        )
        XCTAssertEqual(restored.panelCustomTitles[restoredTerminal.id], "Main Term")
        XCTAssertTrue(restored.pinnedPanelIds.contains(restoredTerminal.id))

        let restoredBrowser = try XCTUnwrap(
            restored.panels.values.first { $0.panelType == .browser } as? BrowserPanel
        )
        XCTAssertNotNil(restoredBrowser)

        let restoredMarkdown = try XCTUnwrap(
            restored.panels.values.first { $0.panelType == .markdown } as? MarkdownPanel
        )
        XCTAssertEqual(restoredMarkdown.filePath, mdURL.path)

        // Geometry preserved (within remapped pane ids).
        let frames = restored.canvasModel.persistablePanes.map(\.frame)
        XCTAssertFalse(frames.isEmpty)
        XCTAssertTrue(
            frames.contains(where: { abs($0.origin.x - 40) < 0.5 && abs($0.origin.y - 60) < 0.5 }),
            "expected restored canvas frame near (40,60); got \(frames)"
        )

        // Id map covers original panels (remap is valid).
        XCTAssertEqual(idMap.count, snapshot.panels.count)
        XCTAssertNotNil(idMap[terminalId])
        XCTAssertNotNil(idMap[browser.id])
        XCTAssertNotNil(idMap[markdown.id])
    }

    func testStatefulPayloadRoundTripViaRegistry() throws {
        let workspace = Workspace()
        let cases: [(DockableKind, Data, (any Dockable) -> Bool)] = try makeStatefulPayloadCases(workspace: workspace)

        for (kind, payload, validate) in cases {
            let restored = DockableBootstrap.decode(
                kind: kind,
                payload: payload,
                context: DockableCreateContext(workspaceId: workspace.id),
                workspace: workspace
            )
            XCTAssertNotNil(restored, "registry decode failed for \(kind.rawValue)")
            if let restored {
                XCTAssertEqual(restored.dockableKind, kind)
                XCTAssertTrue(validate(restored), "field fidelity failed for \(kind.rawValue)")
            }
        }

        // Content-less: empty payload
        for kind: DockableKind in [.extensionBrowser, .cloudVMLoading] {
            let restored = DockableBootstrap.decode(
                kind: kind,
                payload: Data(),
                context: DockableCreateContext(workspaceId: workspace.id),
                workspace: workspace
            )
            XCTAssertNotNil(restored, "content-less decode failed for \(kind.rawValue)")
            XCTAssertEqual(try restored?.encodeDockPayload().count, 0)
        }
    }

    private func makeStatefulPayloadCases(
        workspace: Workspace
    ) throws -> [(DockableKind, Data, (any Dockable) -> Bool)] {
        let fileURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("dock-payload-\(UUID().uuidString).md")
        try "# body\n".write(to: fileURL, atomically: true, encoding: .utf8)
        addTeardownBlock { try? FileManager.default.removeItem(at: fileURL) }

        let terminal = TerminalPanel(workspaceId: workspace.id, workingDirectory: "/tmp/term-wd", runtimeSpawnPolicy: .immediate)
        let browser = BrowserPanel(
            workspaceId: workspace.id,
            initialURL: URL(string: "https://example.com/payload"),
            renderInitialNavigation: false,
            omnibarVisible: false,
            transparentBackground: true
        )
        let markdown = MarkdownPanel(workspaceId: workspace.id, filePath: fileURL.path)
        let filePreview = FilePreviewPanel(workspaceId: workspace.id, filePath: fileURL.path)
        let tool = RightSidebarToolPanel(workspace: workspace, mode: .files)
        let leftSelector = LeftWorkspaceSelectorPanel(workspace: workspace)
        let sidebarURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("dock-\(UUID().uuidString).cmuxsidebar")
        try "".write(to: sidebarURL, atomically: true, encoding: .utf8)
        addTeardownBlock { try? FileManager.default.removeItem(at: sidebarURL) }
        let custom = CustomSidebarPanel(workspace: workspace, name: "DemoSidebar", fileURL: sidebarURL)
        let agent = AgentSessionPanel(
            workspaceId: workspace.id,
            rendererKind: .solid,
            initialProviderID: .claude,
            workingDirectory: "/tmp/agent-wd"
        )
        let project = ProjectPanel(projectURL: URL(fileURLWithPath: "/tmp/Demo.xcodeproj"))
        project.selectedSchemeName = "DemoScheme"
        project.selectedConfigurationName = "Debug"
        let todo = WorkspaceTodoPanel(workspace: workspace)

        return [
            (.terminal, try terminal.encodeDockPayload(), { ($0 as? TerminalPanel) != nil }),
            (.browser, try browser.encodeDockPayload(), { dock in
                (dock as? BrowserPanel)?.profileID == browser.profileID
            }),
            (.markdown, try markdown.encodeDockPayload(), { ($0 as? MarkdownPanel)?.filePath == fileURL.path }),
            (.filePreview, try filePreview.encodeDockPayload(), { ($0 as? FilePreviewPanel)?.filePath == fileURL.path }),
            (.rightSidebarTool, try tool.encodeDockPayload(), { ($0 as? RightSidebarToolPanel)?.mode == .files }),
            (.leftWorkspaceSelector, try leftSelector.encodeDockPayload(), { ($0 as? LeftWorkspaceSelectorPanel) != nil }),
            (.customSidebar, try custom.encodeDockPayload(), { ($0 as? CustomSidebarPanel)?.name == "DemoSidebar" }),
            (.agentSession, try agent.encodeDockPayload(), { dock in
                let panel = dock as? AgentSessionPanel
                return panel?.rendererKind == .solid
                    && panel?.currentProviderID == .claude
                    && panel?.workingDirectory == "/tmp/agent-wd"
            }),
            (.project, try project.encodeDockPayload(), { dock in
                let panel = dock as? ProjectPanel
                return panel?.projectURL.path == "/tmp/Demo.xcodeproj"
                    && panel?.selectedSchemeName == "DemoScheme"
            }),
            (.workspaceTodo, try todo.encodeDockPayload(), { ($0 as? WorkspaceTodoPanel) != nil }),
        ]
    }
}
