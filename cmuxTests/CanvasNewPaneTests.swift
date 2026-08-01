import XCTest
import AppKit
import CmuxDockable

#if canImport(cmux_DEV)
@testable import cmux_DEV
#elseif canImport(cmux)
@testable import cmux
#endif

/// VAL-CANVAS-003 / VAL-ACTIONS-001: openNewCanvasPane(kind:) and entrypoint fail-closed paths.
@MainActor
final class CanvasNewPaneTests: XCTestCase {
    override func setUp() {
        super.setUp()
        DockableBootstrap.registerAllIfNeeded()
    }

    func testOpensMarkdownPane() throws {
        let workspace = Workspace()
        workspace.setLayoutMode(.canvas)
        // Ensure a focused bonsplit pane exists (default workspace creates one terminal).
        XCTAssertNotNil(workspace.bonsplitController.focusedPaneId)

        let panelId = try XCTUnwrap(
            workspace.openNewCanvasPane(kind: .markdown, focus: true),
            "markdown open should succeed via registry-backed surface path"
        )
        let panel = try XCTUnwrap(workspace.panels[panelId])
        XCTAssertEqual(panel.dockableKind, .markdown)
        XCTAssertEqual(workspace.focusedPanelId, panelId)
        XCTAssertTrue(workspace.orderedPanelIds.contains(panelId))
    }

    func testOpensTerminalAndBrowserPanes() throws {
        let workspace = Workspace()
        workspace.setLayoutMode(.canvas)

        let terminalId = try XCTUnwrap(workspace.openNewCanvasPane(kind: .terminal, focus: true))
        XCTAssertEqual(workspace.panels[terminalId]?.dockableKind, .terminal)

        let browserId = try XCTUnwrap(workspace.openNewCanvasPane(kind: .browser, focus: true))
        XCTAssertEqual(workspace.panels[browserId]?.dockableKind, .browser)
    }

    func testNonCanvasModeFailsClosed() {
        let workspace = Workspace()
        // Default is splits, not canvas.
        XCTAssertNotEqual(workspace.layoutMode, .canvas)
        XCTAssertNil(workspace.openNewCanvasPane(kind: .terminal, focus: true))
        XCTAssertNil(workspace.openNewCanvasPane(kind: .browser, focus: true))
        XCTAssertNil(workspace.openNewCanvasPane(kind: .markdown, focus: true))
    }

    func testInvalidKindStringFailsClosedAtControlEntrypoint() {
        // DockableKind(rawValue:) is the shared control path gate.
        XCTAssertNil(DockableKind(rawValue: "widget"))
        XCTAssertNil(DockableKind(rawValue: "not-a-kind"))
        XCTAssertNotNil(DockableKind(rawValue: "markdown"))
        XCTAssertNotNil(DockableKind(rawValue: "terminal"))
        XCTAssertNotNil(DockableKind(rawValue: "browser"))
    }

    func testControlCanvasNewPaneKindStrings() {
        // Mirrors TerminalController.controlCanvasNewPane shared kind dispatch.
        for raw in ["terminal", "browser", "markdown"] {
            XCTAssertNotNil(DockableKind(rawValue: raw), raw)
        }
        XCTAssertNil(DockableKind(rawValue: "widget"))
    }
}
