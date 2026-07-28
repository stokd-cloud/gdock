import XCTest
import CmuxDockable
import Foundation

#if canImport(cmux_DEV)
@testable import cmux_DEV
#elseif canImport(cmux)
@testable import cmux
#endif

/// VAL-CROSS-PERSIST-001: ClosedItemHistory reopen after DockableSnapshot primary write.
@MainActor
final class ClosedItemHistoryDockableTests: XCTestCase {
    override func setUp() {
        super.setUp()
        DockableBootstrap.registerAllIfNeeded()
        ClosedItemHistoryStore.shared.removeAll()
    }

    override func tearDown() {
        ClosedItemHistoryStore.shared.removeAll()
        super.tearDown()
    }

    func testReopenClosedTerminalFromHistoryAfterDockableEncode() throws {
        let workspace = Workspace()
        let paneId = try XCTUnwrap(workspace.bonsplitController.allPaneIds.first)
        let firstId = try XCTUnwrap(workspace.focusedPanelId)

        let second = try XCTUnwrap(
            workspace.newTerminalSurface(inPane: paneId, focus: true)
        )
        workspace.setPanelCustomTitle(panelId: second.id, title: "Closeable Term")
        workspace.markCloseHistoryEligible(panelId: second.id)

        // Capture history snapshot the same way production close does, then
        // force DockableSnapshot primary encode through Codable.
        let historySnapshot = SessionPanelSnapshot(
            id: second.id,
            type: .terminal,
            title: "Terminal",
            customTitle: "Closeable Term",
            directory: nil,
            isPinned: false,
            isManuallyUnread: false,
            listeningPorts: [],
            ttyName: nil,
            terminal: SessionTerminalPanelSnapshot(workingDirectory: NSHomeDirectory()),
            browser: nil,
            markdown: nil,
            filePreview: nil,
            rightSidebarTool: nil
        )
        let encoded = try JSONEncoder().encode(historySnapshot)
        let object = try XCTUnwrap(JSONSerialization.jsonObject(with: encoded) as? [String: Any])
        XCTAssertNotNil(object["dockable"], "history snapshot must primary-encode DockableSnapshot")
        XCTAssertNil(object["terminal"])
        let decoded = try JSONDecoder().decode(SessionPanelSnapshot.self, from: encoded)
        XCTAssertEqual(decoded.type, .terminal)
        XCTAssertEqual(decoded.customTitle, "Closeable Term")
        XCTAssertNotNil(decoded.terminal)

        ClosedItemHistoryStore.shared.push(.panel(ClosedPanelHistoryEntry(
            workspaceId: workspace.id,
            paneId: paneId.id,
            tabIndex: 1,
            snapshot: decoded
        )))

        XCTAssertTrue(workspace.closePanel(second.id, force: true))

        let beforeCount = workspace.panels.count
        XCTAssertTrue(ClosedItemHistoryStore.shared.canReopen)
        let reopened = ClosedItemHistoryStore.shared.restoreFirstRestorable { entry in
            guard case .panel(let panelEntry) = entry else { return false }
            return workspace.restoreClosedPanel(panelEntry) != nil
        }
        XCTAssertTrue(reopened)
        XCTAssertGreaterThan(workspace.panels.count, beforeCount)
        XCTAssertNotNil(workspace.panels[firstId])

        let restored = workspace.panels.values.first {
            workspace.panelCustomTitles[$0.id] == "Closeable Term"
        }
        XCTAssertNotNil(restored)
        XCTAssertEqual(restored?.panelType, .terminal)
    }

    func testReopenClosedMarkdownFromHistoryAndCoexistWithLegacyEntry() throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("cmux-history-md-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let mdURL = root.appendingPathComponent("hist.md")
        try "# history\n".write(to: mdURL, atomically: true, encoding: .utf8)

        let workspace = Workspace()
        let paneId = try XCTUnwrap(workspace.bonsplitController.allPaneIds.first)

        // New-shape markdown history entry (DockableSnapshot primary encode).
        let markdownSnapshot = SessionPanelSnapshot(
            id: UUID(),
            type: .markdown,
            title: "Markdown",
            customTitle: "Hist MD",
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
        let mdEncoded = try JSONEncoder().encode(markdownSnapshot)
        let mdObject = try XCTUnwrap(JSONSerialization.jsonObject(with: mdEncoded) as? [String: Any])
        XCTAssertNotNil(mdObject["dockable"])
        let mdDecoded = try JSONDecoder().decode(SessionPanelSnapshot.self, from: mdEncoded)

        ClosedItemHistoryStore.shared.push(.panel(ClosedPanelHistoryEntry(
            workspaceId: workspace.id,
            paneId: paneId.id,
            tabIndex: 0,
            snapshot: mdDecoded
        )))

        // Pre-refactor-style history entry (legacy optional fields on disk).
        let legacyObject: [String: Any] = [
            "id": UUID().uuidString,
            "type": "terminal",
            "title": "Legacy Hist Term",
            "customTitle": "Legacy Hist",
            "directory": "/tmp/legacy-hist",
            "isPinned": false,
            "isManuallyUnread": false,
            "listeningPorts": [],
            "terminal": [
                "workingDirectory": "/tmp/legacy-hist"
            ]
        ]
        let legacyData = try JSONSerialization.data(withJSONObject: legacyObject)
        let legacyDecoded = try JSONDecoder().decode(SessionPanelSnapshot.self, from: legacyData)
        ClosedItemHistoryStore.shared.push(.panel(ClosedPanelHistoryEntry(
            workspaceId: workspace.id,
            paneId: paneId.id,
            tabIndex: 0,
            snapshot: legacyDecoded
        )))

        XCTAssertTrue(ClosedItemHistoryStore.shared.canReopen)
        let menu = ClosedItemHistoryStore.shared.menuSnapshot()
        XCTAssertGreaterThanOrEqual(menu.totalItemCount, 2)

        // Reopen newest first (legacy terminal pushed last → first restorable).
        let reopenedLegacy = ClosedItemHistoryStore.shared.restoreFirstRestorable { entry in
            guard case .panel(let panelEntry) = entry else { return false }
            return workspace.restoreClosedPanel(panelEntry) != nil
        }
        XCTAssertTrue(reopenedLegacy)
        XCTAssertTrue(workspace.panels.values.contains { $0.panelType == .terminal })

        // Then reopen markdown history entry (pre/post-refactor coexist).
        let reopenedMarkdown = ClosedItemHistoryStore.shared.restoreFirstRestorable { entry in
            guard case .panel(let panelEntry) = entry else { return false }
            return workspace.restoreClosedPanel(panelEntry) != nil
        }
        XCTAssertTrue(reopenedMarkdown)
        let restoredMarkdown = workspace.panels.values.compactMap { $0 as? MarkdownPanel }.first
        XCTAssertEqual(restoredMarkdown?.filePath, mdURL.path)
        XCTAssertEqual(
            workspace.panelCustomTitles[restoredMarkdown?.id ?? UUID()],
            "Hist MD"
        )
    }
}
