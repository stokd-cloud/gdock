import XCTest
import AppKit
import CmuxDockable
import CmuxCanvasUI

#if canImport(cmux_DEV)
@testable import cmux_DEV
#elseif canImport(cmux)
@testable import cmux
#endif

/// VAL-CANVAS-001: generic CanvasPaneContentMount drives any Dockable for
/// terminal, browser, and markdown (mount / render / unmount).
@MainActor
final class CanvasDockableMountLifecycleTests: XCTestCase {
    func testTerminalMountRenderUnmountViaContent() {
        let panel = TerminalPanel(workspaceId: UUID())
        let container = NSView(frame: NSRect(x: 0, y: 0, width: 640, height: 480))
        var focused: UUID?

        let mount = CanvasPaneContentMount(
            content: .terminal(panel, .disabled),
            panelId: panel.id,
            container: container,
            workspaceAttentionColor: WorkspaceAttentionColor(configuredHex: nil),
            onFocusPanel: { focused = $0 },
            makeTerminalVisible: { _ in }
        )
        XCTAssertTrue(mount is CanvasPaneContentMounting)
        XCTAssertEqual(panel.hostedView.superview, container)

        mount.setRendering(false)
        mount.setRendering(true)

        let tokenBefore = panel.viewReattachToken
        mount.unmount()
        XCTAssertNil(panel.hostedView.superview)
        XCTAssertEqual(panel.viewReattachToken, tokenBefore &+ 1)
        _ = focused
    }

    func testBrowserMountRenderUnmountViaContent() {
        let panel = BrowserPanel(workspaceId: UUID(), renderInitialNavigation: false)
        let container = NSView(frame: NSRect(x: 0, y: 0, width: 640, height: 480))
        let presentation = CanvasHostedPanelPresentation(
            isFocused: false,
            allowsPointerInput: true,
            pointerInputOwner: container
        )

        let mount = CanvasPaneContentMount(
            content: .hosted(panel, NSView(frame: container.bounds), presentation),
            panelId: panel.id,
            container: container,
            workspaceAttentionColor: WorkspaceAttentionColor(configuredHex: nil),
            onFocusPanel: { _ in }
        )
        XCTAssertTrue(panel.canvasInlineHostingActive)
        XCTAssertEqual(panel.webViewLastVisibilityChangeReason, "canvas.mount")

        mount.setRendering(false)
        XCTAssertTrue(panel.canvasInlineHostingActive)
        XCTAssertEqual(panel.webViewLastVisibilityChangeReason, "canvas.occlude")

        mount.setRendering(true)
        XCTAssertEqual(panel.webViewLastVisibilityChangeReason, "canvas.render")

        mount.unmount()
        XCTAssertFalse(panel.canvasInlineHostingActive)
        XCTAssertEqual(panel.webViewLastVisibilityChangeReason, "canvas.unmount")
        panel.close()
    }

    func testMarkdownMountRenderUnmountViaContent() throws {
        let fileURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("canvas-mount-\(UUID().uuidString).md")
        try "# mount\n".write(to: fileURL, atomically: true, encoding: .utf8)
        defer { try? FileManager.default.removeItem(at: fileURL) }

        let panel = MarkdownPanel(workspaceId: UUID(), filePath: fileURL.path)
        let container = NSView(frame: NSRect(x: 0, y: 0, width: 640, height: 480))
        let presentation = CanvasHostedPanelPresentation(
            isFocused: false,
            allowsPointerInput: true,
            pointerInputOwner: container
        )

        let mount = CanvasPaneContentMount(
            content: .hosted(panel, NSView(frame: container.bounds), presentation),
            panelId: panel.id,
            container: container,
            workspaceAttentionColor: WorkspaceAttentionColor(configuredHex: nil),
            onFocusPanel: { _ in }
        )
        XCTAssertTrue(mount is CanvasPaneContentMounting)
        // Hosted path pins a content subview.
        XCTAssertFalse(container.subviews.isEmpty)

        mount.setRendering(false)
        mount.setRendering(true)
        mount.unmount()
        XCTAssertTrue(container.subviews.isEmpty)
    }

    func testMountExposesTerminalPanel() {
        let panel = TerminalPanel(workspaceId: UUID())
        let container = NSView(frame: NSRect(x: 0, y: 0, width: 100, height: 100))
        let mount = CanvasPaneContentMount(
            content: .terminal(panel, .disabled),
            panelId: panel.id,
            container: container,
            workspaceAttentionColor: WorkspaceAttentionColor(configuredHex: nil),
            onFocusPanel: { _ in },
            makeTerminalVisible: { _ in }
        )
        XCTAssertTrue(mount.terminalPanel === panel)
        mount.unmount()
    }
}
