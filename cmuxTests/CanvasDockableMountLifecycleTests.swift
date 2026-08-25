import XCTest
import AppKit
import CmuxDockable
import CmuxCanvasUI

#if canImport(cmux_DEV)
@testable import cmux_DEV
#elseif canImport(cmux)
@testable import cmux
#endif

/// VAL-CANVAS-001: `CanvasPaneContentMount` drives the pane content lifecycle
/// (mount / render / unmount) for terminal, browser, and markdown panels.
///
/// These tests were originally written against a `CanvasPaneContentMount(dockable:)`
/// initializer that stored `any Dockable`. The mount now takes an explicit
/// ``CanvasPaneContent`` (terminal surfaces are hosted directly; every other
/// panel goes through an `NSHostingView`) plus the pane's attention color, so
/// the calls below construct content the way `WorkspaceCanvasHostView` does.
/// The former `testMountStoresAnyDockableNotContentEnum` asserted the erased-
/// storage design that this change replaced; it is superseded by
/// `testTerminalMountUsesTerminalContent`, which pins the behavior that
/// actually holds — the terminal path hosts the panel's own view rather than a
/// SwiftUI wrapper.
@MainActor
final class CanvasDockableMountLifecycleTests: XCTestCase {
    private func makeHostedContent(
        panel: any Panel,
        container: NSView,
        onFocus: @escaping @MainActor (UUID) -> Void = { _ in }
    ) -> CanvasPaneContent {
        let presentation = CanvasHostedPanelPresentation(
            isFocused: false,
            allowsPointerInput: true,
            pointerInputOwner: container
        )
        let hosted = panel.makeDockContentView(
            context: DockableMountContext(container: container, onFocus: onFocus)
        )
        return .hosted(panel, hosted, presentation)
    }

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

        // No canvas host environment → makeDockContentView still sets mount flags.
        let mount = CanvasPaneContentMount(
            content: makeHostedContent(panel: panel, container: container),
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

        let mount = CanvasPaneContentMount(
            content: makeHostedContent(panel: panel, container: container),
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
        XCTAssertEqual(mount.panelId, panel.id)
        XCTAssertTrue(mount.terminalPanel === panel)
        mount.unmount()
        XCTAssertNil(panel.hostedView.superview)
    }

    func testTerminalMountUsesTerminalContent() {
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
        XCTAssertEqual(mount.panelId, panel.id)
        // The terminal path attaches the panel's own hosted view — not a
        // SwiftUI hosting wrapper — which is what lets the canvas crop it.
        XCTAssertTrue(container.subviews.contains { $0 === panel.hostedView })
        mount.unmount()
        XCTAssertNil(panel.hostedView.superview)
    }
}
