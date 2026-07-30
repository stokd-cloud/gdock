import XCTest
import CmuxDockable

#if canImport(cmux_DEV)
@testable import cmux_DEV
#elseif canImport(cmux)
@testable import cmux
#endif

@MainActor
final class DockableRegistrationTests: XCTestCase {
    override func setUp() {
        super.setUp()
        DockableBootstrap.registerAllIfNeeded()
    }

    func testAllKindsRegisteredWithRealFactories() {
        let workspace = Workspace()
        let fileURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("dockable-reg-\(UUID().uuidString).md")
        try? "# hello\n".write(to: fileURL, atomically: true, encoding: .utf8)
        defer { try? FileManager.default.removeItem(at: fileURL) }
        let sidebarURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("demo.cmuxsidebar")
        try? "".write(to: sidebarURL, atomically: true, encoding: .utf8)
        defer { try? FileManager.default.removeItem(at: sidebarURL) }

        for kind in DockableKind.allCases {
            let context = Self.context(
                for: kind,
                workspace: workspace,
                fileURL: fileURL,
                sidebarURL: sidebarURL
            )
            let dockable = DockableBootstrap.make(
                kind: kind,
                context: context,
                workspace: workspace
            )
            XCTAssertNotNil(dockable, "make failed for \(kind.rawValue)")
            XCTAssertEqual(dockable?.dockableKind, kind)
            // Real panels, not empty placeholders: title/kind identity must be non-empty.
            XCTAssertFalse(dockable?.dockableTitle.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == true)
        }
    }

    func testStatefulDecodeRehydratesFromEncodedPayload() throws {
        let workspace = Workspace()
        let fileURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("dockable-roundtrip-\(UUID().uuidString).md")
        try "# body\n".write(to: fileURL, atomically: true, encoding: .utf8)
        defer { try? FileManager.default.removeItem(at: fileURL) }

        // Markdown fidelity
        let markdown = MarkdownPanel(workspaceId: workspace.id, filePath: fileURL.path)
        let mdPayload = try markdown.encodeDockPayload()
        let mdRestored = DockableBootstrap.decode(
            kind: .markdown,
            payload: mdPayload,
            context: DockableCreateContext(workspaceId: workspace.id),
            workspace: workspace
        ) as? MarkdownPanel
        XCTAssertEqual(mdRestored?.filePath, fileURL.path)

        // Browser fidelity (url + profile)
        let browser = BrowserPanel(
            workspaceId: workspace.id,
            initialURL: URL(string: "https://example.com/dockable"),
            renderInitialNavigation: false
        )
        let browserPayload = try browser.encodeDockPayload()
        let browserRestored = DockableBootstrap.decode(
            kind: .browser,
            payload: browserPayload,
            context: DockableCreateContext(workspaceId: workspace.id)
        ) as? BrowserPanel
        XCTAssertNotNil(browserRestored)
        XCTAssertEqual(browserRestored?.profileID, browser.profileID)

        // Project fidelity
        let projectPath = "/tmp/DockableDemo.xcodeproj"
        let project = ProjectPanel(projectURL: URL(fileURLWithPath: projectPath))
        project.selectedSchemeName = "DemoScheme"
        let projectPayload = try project.encodeDockPayload()
        let projectRestored = DockableBootstrap.decode(
            kind: .project,
            payload: projectPayload
        ) as? ProjectPanel
        XCTAssertEqual(projectRestored?.projectURL.path, projectPath)
        XCTAssertEqual(projectRestored?.selectedSchemeName, "DemoScheme")

        // Agent session fidelity
        let agent = AgentSessionPanel(
            workspaceId: workspace.id,
            rendererKind: .solid,
            initialProviderID: .claude,
            workingDirectory: "/tmp/agent-wd"
        )
        let agentPayload = try agent.encodeDockPayload()
        let agentRestored = DockableBootstrap.decode(
            kind: .agentSession,
            payload: agentPayload,
            context: DockableCreateContext(workspaceId: workspace.id)
        ) as? AgentSessionPanel
        XCTAssertEqual(agentRestored?.rendererKind, .solid)
        XCTAssertEqual(agentRestored?.currentProviderID, .claude)
        XCTAssertEqual(agentRestored?.workingDirectory, "/tmp/agent-wd")

        // Right sidebar tool
        let tool = RightSidebarToolPanel(workspace: workspace, mode: .files)
        let toolPayload = try tool.encodeDockPayload()
        let toolRestored = DockableBootstrap.decode(
            kind: .rightSidebarTool,
            payload: toolPayload,
            workspace: workspace
        ) as? RightSidebarToolPanel
        XCTAssertEqual(toolRestored?.mode, .files)

        // Content-less empty payload
        let ext = DockableBootstrap.decode(
            kind: .extensionBrowser,
            payload: Data(),
            context: DockableCreateContext(extensionBrowserTitle: "Ext")
        ) as? CMUXSidebarExtensionBrowserPanel
        XCTAssertEqual(ext?.displayTitle, "Ext")

        let cloud = DockableBootstrap.decode(
            kind: .cloudVMLoading,
            payload: Data(),
            context: DockableCreateContext(workspaceId: workspace.id)
        ) as? CloudVMLoadingPanel
        XCTAssertEqual(cloud?.workspaceId, workspace.id)
    }

    func testInvalidPayloadFailsClosed() {
        let garbage = Data("not-json".utf8)
        XCTAssertNil(DockableBootstrap.decode(kind: .markdown, payload: garbage))
        XCTAssertNil(DockableBootstrap.decode(kind: .browser, payload: garbage))
        XCTAssertNil(DockableBootstrap.decode(kind: .project, payload: garbage))
        XCTAssertNil(DockableBootstrap.decode(kind: .terminal, payload: garbage))
    }

    private static func context(
        for kind: DockableKind,
        workspace: Workspace,
        fileURL: URL,
        sidebarURL: URL
    ) -> DockableCreateContext {
        var ctx = DockableCreateContext(workspaceId: workspace.id)
        switch kind {
        case .markdown, .filePreview:
            ctx.filePath = fileURL.path
        case .project:
            ctx.projectPath = "/tmp/DockableReg.xcodeproj"
        case .rightSidebarTool:
            ctx.rightSidebarMode = .files
        case .customSidebar:
            ctx.customSidebarName = "demo"
            ctx.customSidebarFileURL = sidebarURL
        case .browser:
            ctx.url = URL(string: "https://example.com")
        case .terminal, .agentSession, .extensionBrowser, .workspaceTodo, .cloudVMLoading, .leftWorkspaceSelector:
            break
        }
        return ctx
    }
}
