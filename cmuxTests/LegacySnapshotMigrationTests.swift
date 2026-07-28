import XCTest
import CmuxDockable
import Foundation

#if canImport(cmux_DEV)
@testable import cmux_DEV
#elseif canImport(cmux)
@testable import cmux
#endif

/// VAL-PERSIST-003: legacy SessionPanelSnapshot decode + mixed legacy/new restore.
@MainActor
final class LegacySnapshotMigrationTests: XCTestCase {
    override func setUp() {
        super.setUp()
        DockableBootstrap.registerAllIfNeeded()
    }

    func testDecodesLegacyTerminalAndMarkdownFixture() throws {
        let url = try XCTUnwrap(fixtureURL())
        let data = try Data(contentsOf: url)
        let root = try JSONSerialization.jsonObject(with: data) as? [String: Any]
        let panelsJSON = try XCTUnwrap(root?["panels"] as? [[String: Any]])
        XCTAssertEqual(panelsJSON.count, 2)

        let panelsData = try JSONSerialization.data(withJSONObject: panelsJSON)
        let panels = try JSONDecoder().decode([SessionPanelSnapshot].self, from: panelsData)

        XCTAssertEqual(panels.map(\.type), [.terminal, .markdown])
        XCTAssertEqual(panels[0].terminal?.workingDirectory, "/tmp/legacy-term")
        XCTAssertEqual(panels[0].customTitle, "Work shell")
        XCTAssertEqual(panels[0].listeningPorts, [8080])
        XCTAssertEqual(panels[1].markdown?.filePath, "/tmp/legacy-note.md")

        // Maps to DockableSnapshot + registry decode.
        let termDock = try panels[0].makeDockableSnapshot()
        XCTAssertEqual(termDock.kind, .terminal)
        XCTAssertFalse(termDock.payload.isEmpty)
        let mdDock = try panels[1].makeDockableSnapshot()
        XCTAssertEqual(mdDock.kind, .markdown)

        let workspace = Workspace()
        let termPanel = panels[0].decodeDockable(workspace: workspace)
        let mdPanel = panels[1].decodeDockable(
            workspace: workspace,
            context: DockableCreateContext(workspaceId: workspace.id)
        )
        XCTAssertEqual(termPanel?.dockableKind, .terminal)
        XCTAssertEqual((mdPanel as? MarkdownPanel)?.filePath, "/tmp/legacy-note.md")
    }

    func testLegacyFieldTableCoversAllNineStatefulPayloads() throws {
        let id = UUID()
        let table: [(PanelType, SessionPanelSnapshot, DockableKind, (SessionPanelSnapshot) -> Bool)] = [
            (
                .terminal,
                SessionPanelSnapshot(
                    id: id, type: .terminal, title: "t", customTitle: nil, directory: "/d",
                    isPinned: false, isManuallyUnread: false, listeningPorts: [], ttyName: nil,
                    terminal: SessionTerminalPanelSnapshot(workingDirectory: "/d", fontSize: 15),
                    browser: nil, markdown: nil, filePreview: nil, rightSidebarTool: nil
                ),
                .terminal,
                { $0.terminal?.fontSize == 15 && $0.terminal?.workingDirectory == "/d" }
            ),
            (
                .browser,
                SessionPanelSnapshot(
                    id: id, type: .browser, title: "b", customTitle: nil, directory: nil,
                    isPinned: false, isManuallyUnread: false, listeningPorts: [], ttyName: nil,
                    terminal: nil,
                    browser: SessionBrowserPanelSnapshot(
                        urlString: "https://example.com/legacy",
                        profileID: nil,
                        shouldRenderWebView: true,
                        pageZoom: 1.25,
                        developerToolsVisible: true,
                        backHistoryURLStrings: ["https://example.com/back"],
                        forwardHistoryURLStrings: nil,
                        transparentBackground: true
                    ),
                    markdown: nil, filePreview: nil, rightSidebarTool: nil
                ),
                .browser,
                { $0.browser?.pageZoom == 1.25 && $0.browser?.urlString == "https://example.com/legacy" }
            ),
            (
                .markdown,
                SessionPanelSnapshot(
                    id: id, type: .markdown, title: "m", customTitle: nil, directory: nil,
                    isPinned: false, isManuallyUnread: false, listeningPorts: [], ttyName: nil,
                    terminal: nil, browser: nil,
                    markdown: SessionMarkdownPanelSnapshot(filePath: "/tmp/a.md"),
                    filePreview: nil, rightSidebarTool: nil
                ),
                .markdown,
                { $0.markdown?.filePath == "/tmp/a.md" }
            ),
            (
                .filePreview,
                SessionPanelSnapshot(
                    id: id, type: .filePreview, title: "f", customTitle: nil, directory: nil,
                    isPinned: false, isManuallyUnread: false, listeningPorts: [], ttyName: nil,
                    terminal: nil, browser: nil, markdown: nil,
                    filePreview: SessionFilePreviewPanelSnapshot(filePath: "/tmp/a.swift"),
                    rightSidebarTool: nil
                ),
                .filePreview,
                { $0.filePreview?.filePath == "/tmp/a.swift" }
            ),
            (
                .rightSidebarTool,
                SessionPanelSnapshot(
                    id: id, type: .rightSidebarTool, title: "r", customTitle: nil, directory: nil,
                    isPinned: false, isManuallyUnread: false, listeningPorts: [], ttyName: nil,
                    terminal: nil, browser: nil, markdown: nil, filePreview: nil,
                    rightSidebarTool: SessionRightSidebarToolPanelSnapshot(mode: .files)
                ),
                .rightSidebarTool,
                { $0.rightSidebarTool?.mode == .files }
            ),
            (
                .customSidebar,
                SessionPanelSnapshot(
                    id: id, type: .customSidebar, title: "c", customTitle: nil, directory: nil,
                    isPinned: false, isManuallyUnread: false, listeningPorts: [], ttyName: nil,
                    terminal: nil, browser: nil, markdown: nil, filePreview: nil, rightSidebarTool: nil,
                    customSidebar: SessionCustomSidebarPanelSnapshot(name: "MySidebar")
                ),
                .customSidebar,
                { $0.customSidebar?.name == "MySidebar" }
            ),
            (
                .agentSession,
                SessionPanelSnapshot(
                    id: id, type: .agentSession, title: "a", customTitle: nil, directory: "/agent",
                    isPinned: false, isManuallyUnread: false, listeningPorts: [], ttyName: nil,
                    terminal: nil, browser: nil, markdown: nil, filePreview: nil, rightSidebarTool: nil,
                    agentSession: SessionAgentSessionPanelSnapshot(
                        rendererKind: .solid,
                        providerID: .claude,
                        workingDirectory: "/agent"
                    )
                ),
                .agentSession,
                { $0.agentSession?.providerID == .claude && $0.agentSession?.workingDirectory == "/agent" }
            ),
            (
                .project,
                SessionPanelSnapshot(
                    id: id, type: .project, title: "p", customTitle: nil, directory: nil,
                    isPinned: false, isManuallyUnread: false, listeningPorts: [], ttyName: nil,
                    terminal: nil, browser: nil, markdown: nil, filePreview: nil, rightSidebarTool: nil,
                    project: SessionProjectPanelSnapshot(
                        projectPath: "/tmp/P.xcodeproj",
                        selectedNodePath: "/tmp/P/Sources/A.swift",
                        activeTab: "files",
                        selectedSchemeName: "App",
                        selectedConfigurationName: "Release"
                    )
                ),
                .project,
                {
                    $0.project?.projectPath == "/tmp/P.xcodeproj"
                        && $0.project?.selectedSchemeName == "App"
                        && $0.project?.selectedConfigurationName == "Release"
                }
            ),
            (
                .workspaceTodo,
                SessionPanelSnapshot(
                    id: id, type: .workspaceTodo, title: "todo", customTitle: nil, directory: nil,
                    isPinned: false, isManuallyUnread: false, listeningPorts: [], ttyName: nil,
                    terminal: nil, browser: nil, markdown: nil, filePreview: nil, rightSidebarTool: nil,
                    workspaceTodo: SessionWorkspaceTodoPanelSnapshot()
                ),
                .workspaceTodo,
                { $0.workspaceTodo != nil || $0.type == .workspaceTodo }
            ),
        ]

        XCTAssertEqual(table.count, 9, "must cover all 9 legacy stateful fields")

        for (type, legacy, kind, validate) in table {
            // Encode legacy shape JSON (multi-optional fields present).
            let legacyJSON = try encodeLegacyShape(legacy)
            let decoded = try JSONDecoder().decode(SessionPanelSnapshot.self, from: legacyJSON)
            XCTAssertEqual(decoded.type, type)
            XCTAssertTrue(validate(decoded), "legacy field fidelity failed for \(type.rawValue)")

            let dockable = try decoded.makeDockableSnapshot()
            XCTAssertEqual(dockable.kind, kind)
            XCTAssertEqual(dockable.id, id)

            // New encode must not re-emit legacy optional keys.
            let newData = try JSONEncoder().encode(decoded)
            let newObject = try XCTUnwrap(JSONSerialization.jsonObject(with: newData) as? [String: Any])
            XCTAssertNotNil(newObject["dockable"])
            XCTAssertNil(newObject["terminal"])
            XCTAssertNil(newObject["browser"])
            XCTAssertNil(newObject["markdown"])
            XCTAssertNil(newObject["filePreview"])
            XCTAssertNil(newObject["rightSidebarTool"])
            XCTAssertNil(newObject["customSidebar"])
            XCTAssertNil(newObject["agentSession"])
            XCTAssertNil(newObject["project"])
            XCTAssertNil(newObject["workspaceTodo"])
        }
    }

    func testMixedLegacyAndNewSessionRestoresAllValidPanes() throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("cmux-mixed-legacy-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let mdURL = root.appendingPathComponent("mixed.md")
        try "# mixed\n".write(to: mdURL, atomically: true, encoding: .utf8)

        let legacyTerminal = SessionPanelSnapshot(
            id: UUID(),
            type: .terminal,
            title: "Legacy T",
            customTitle: "Legacy Title",
            directory: "/tmp/mixed-term",
            isPinned: true,
            isManuallyUnread: false,
            listeningPorts: [],
            ttyName: nil,
            terminal: SessionTerminalPanelSnapshot(workingDirectory: "/tmp/mixed-term", fontSize: 13),
            browser: nil,
            markdown: nil,
            filePreview: nil,
            rightSidebarTool: nil
        )

        // New shape: encode via DockableSnapshot primary path.
        let newMarkdown = SessionPanelSnapshot(
            id: UUID(),
            type: .markdown,
            title: "New MD",
            customTitle: nil,
            directory: nil,
            isPinned: false,
            isManuallyUnread: false,
            listeningPorts: [],
            ttyName: nil,
            terminal: nil,
            browser: nil,
            markdown: SessionMarkdownPanelSnapshot(filePath: mdURL.path),
            filePreview: nil,
            rightSidebarTool: nil
        )
        let newEncoded = try JSONEncoder().encode(newMarkdown)
        let newDecoded = try JSONDecoder().decode(SessionPanelSnapshot.self, from: newEncoded)
        XCTAssertNotNil(try? JSONSerialization.jsonObject(with: newEncoded) as? [String: Any])
        let newObject = try XCTUnwrap(JSONSerialization.jsonObject(with: newEncoded) as? [String: Any])
        XCTAssertNotNil(newObject["dockable"])

        // Invalid multi-field legacy row should not abort whole restore.
        var invalid = SessionPanelSnapshot(
            id: UUID(),
            type: .terminal,
            title: "Bad",
            customTitle: nil,
            directory: nil,
            isPinned: false,
            isManuallyUnread: false,
            listeningPorts: [],
            ttyName: nil,
            terminal: SessionTerminalPanelSnapshot(workingDirectory: "/tmp/bad"),
            browser: SessionBrowserPanelSnapshot(
                urlString: "https://example.com",
                profileID: nil,
                shouldRenderWebView: true,
                pageZoom: 1,
                developerToolsVisible: false,
                backHistoryURLStrings: nil,
                forwardHistoryURLStrings: nil
            ),
            markdown: SessionMarkdownPanelSnapshot(filePath: "/tmp/x.md"),
            filePreview: nil,
            rightSidebarTool: nil
        )
        // Force multi-field through legacy JSON round-trip.
        let invalidLegacyData = try encodeLegacyShape(invalid)
        invalid = try JSONDecoder().decode(SessionPanelSnapshot.self, from: invalidLegacyData)
        // After decode, multi-field is collapsed to type-matching field only.
        XCTAssertNotNil(invalid.terminal)
        XCTAssertNil(invalid.browser)
        XCTAssertNil(invalid.markdown)

        let legacyData = try encodeLegacyShape(legacyTerminal)
        let legacyDecoded = try JSONDecoder().decode(SessionPanelSnapshot.self, from: legacyData)

        let workspaceSnapshot = SessionWorkspaceSnapshot(
            processTitle: "mixed",
            customTitle: "Mixed WS",
            customDescription: nil,
            customColor: nil,
            isPinned: false,
            terminalScrollBarHidden: nil,
            currentDirectory: root.path,
            focusedPanelId: legacyDecoded.id,
            layout: .pane(SessionPaneLayoutSnapshot(
                panelIds: [legacyDecoded.id, newDecoded.id, invalid.id],
                selectedPanelId: legacyDecoded.id
            )),
            layoutMode: WorkspaceLayoutMode.splits.rawValue,
            panels: [legacyDecoded, newDecoded, invalid],
            statusEntries: [],
            logEntries: [],
            progress: nil,
            gitBranch: nil,
            remote: nil
        )

        let restored = Workspace()
        let map = restored.restoreSessionSnapshot(workspaceSnapshot)
        XCTAssertGreaterThanOrEqual(map.count, 2, "mixed restore should keep valid panes")
        XCTAssertEqual(restored.customTitle, "Mixed WS")

        let hasTerminal = restored.panels.values.contains { $0.panelType == .terminal }
        let hasMarkdown = restored.panels.values.contains { $0.panelType == .markdown }
        XCTAssertTrue(hasTerminal)
        XCTAssertTrue(hasMarkdown)

        if let md = restored.panels.values.compactMap({ $0 as? MarkdownPanel }).first {
            XCTAssertEqual(md.filePath, mdURL.path)
        } else {
            XCTFail("expected restored markdown panel")
        }
    }

    // MARK: - Helpers

    private func fixtureURL() -> URL? {
        let candidates = [
            URL(fileURLWithPath: #filePath)
                .deletingLastPathComponent()
                .appendingPathComponent("fixtures/legacy-session-panel.json"),
            URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
                .appendingPathComponent("cmuxTests/fixtures/legacy-session-panel.json"),
        ]
        return candidates.first { FileManager.default.fileExists(atPath: $0.path) }
    }

    /// Encodes the pre-refactor multi-optional-field shape without going through
    /// the new DockableSnapshot primary encoder.
    private func encodeLegacyShape(_ snapshot: SessionPanelSnapshot) throws -> Data {
        var object: [String: Any] = [
            "id": snapshot.id.uuidString,
            "type": snapshot.type.rawValue,
            "isPinned": snapshot.isPinned,
            "isManuallyUnread": snapshot.isManuallyUnread,
            "listeningPorts": snapshot.listeningPorts,
        ]
        if let title = snapshot.title { object["title"] = title }
        if let customTitle = snapshot.customTitle { object["customTitle"] = customTitle }
        if let directory = snapshot.directory { object["directory"] = directory }
        if let ttyName = snapshot.ttyName { object["ttyName"] = ttyName }

        let encoder = JSONEncoder()
        if let terminal = snapshot.terminal {
            object["terminal"] = try jsonObject(encoder.encode(terminal))
        }
        if let browser = snapshot.browser {
            object["browser"] = try jsonObject(encoder.encode(browser))
        }
        if let markdown = snapshot.markdown {
            object["markdown"] = try jsonObject(encoder.encode(markdown))
        }
        if let filePreview = snapshot.filePreview {
            object["filePreview"] = try jsonObject(encoder.encode(filePreview))
        }
        if let rightSidebarTool = snapshot.rightSidebarTool {
            object["rightSidebarTool"] = try jsonObject(encoder.encode(rightSidebarTool))
        }
        if let customSidebar = snapshot.customSidebar {
            object["customSidebar"] = try jsonObject(encoder.encode(customSidebar))
        }
        if let agentSession = snapshot.agentSession {
            object["agentSession"] = try jsonObject(encoder.encode(agentSession))
        }
        if let project = snapshot.project {
            object["project"] = try jsonObject(encoder.encode(project))
        }
        if let workspaceTodo = snapshot.workspaceTodo {
            object["workspaceTodo"] = try jsonObject(encoder.encode(workspaceTodo))
        }
        return try JSONSerialization.data(withJSONObject: object)
    }

    private func jsonObject(_ data: Data) throws -> Any {
        try JSONSerialization.jsonObject(with: data)
    }
}
