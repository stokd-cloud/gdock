import XCTest
import CmuxDockable

#if canImport(cmux_DEV)
@testable import cmux_DEV
#elseif canImport(cmux)
@testable import cmux
#endif

/// Bidirectional PanelType ↔ DockableKind raw-value parity for all 12 kinds.
final class DockableKindParityTests: XCTestCase {
    private let expectedRaws: Set<String> = [
        "terminal",
        "browser",
        "markdown",
        "filepreview",
        "rightSidebarTool",
        "leftWorkspaceSelector",
        "customSidebar",
        "agentSession",
        "project",
        "extensionBrowser",
        "workspaceTodo",
        "cloudVMLoading",
    ]

    func testDockableKindRawValueSetMatchesExpected() {
        let raws = Set(DockableKind.allCases.map(\.rawValue))
        XCTAssertEqual(DockableKind.allCases.count, 12)
        XCTAssertEqual(raws, expectedRaws)
    }

    func testBidirectionalPanelTypeDockableKindRoundTrip() {
        for raw in expectedRaws {
            XCTAssertNotNil(PanelType(rawValue: raw), "PanelType missing raw \(raw)")
            XCTAssertNotNil(DockableKind(rawValue: raw), "DockableKind missing raw \(raw)")
            XCTAssertEqual(PanelType(rawValue: raw)?.rawValue, DockableKind(rawValue: raw)?.rawValue)
        }
    }

    @MainActor
    func testAllTwelvePanelKindsMapDockableKindFromPanelType() {
        let workspace = Workspace()
        let fileURL = URL(fileURLWithPath: "/tmp/cmux-dockable-parity.md")
        try? "parity".write(to: fileURL, atomically: true, encoding: .utf8)
        defer { try? FileManager.default.removeItem(at: fileURL) }

        let panels: [any Panel] = [
            TerminalPanel(workspaceId: workspace.id),
            BrowserPanel(workspaceId: workspace.id),
            MarkdownPanel(workspaceId: workspace.id, filePath: fileURL.path),
            FilePreviewPanel(workspaceId: workspace.id, filePath: fileURL.path),
            RightSidebarToolPanel(workspace: workspace, mode: .files),
            LeftWorkspaceSelectorPanel(workspace: workspace),
            CustomSidebarPanel(workspace: workspace, name: "demo", fileURL: fileURL),
            AgentSessionPanel(workspaceId: workspace.id, rendererKind: .react),
            ProjectPanel(projectURL: URL(fileURLWithPath: "/tmp/Demo.xcodeproj")),
            CMUXSidebarExtensionBrowserPanel(title: "Extensions"),
            WorkspaceTodoPanel(workspace: workspace),
            CloudVMLoadingPanel(workspaceId: workspace.id),
        ]

        XCTAssertEqual(panels.count, 12)
        var kinds = Set<DockableKind>()
        for panel in panels {
            let kind = panel.dockableKind
            XCTAssertEqual(kind.rawValue, panel.panelType.rawValue)
            XCTAssertEqual(panel.dockableTitle, panel.displayTitle)
            kinds.insert(kind)
            // Smoke: default hosted path returns a view.
            let container = NSView(frame: NSRect(x: 0, y: 0, width: 100, height: 100))
            let view = panel.makeDockContentView(
                context: DockableMountContext(container: container, onFocus: { _ in })
            )
            XCTAssertNotNil(view)
        }
        XCTAssertEqual(kinds, Set(DockableKind.allCases))
    }
}
