import XCTest
import AppKit
import CmuxDockable
import CmuxCanvasUI

#if canImport(cmux_DEV)
@testable import cmux_DEV
#elseif canImport(cmux)
@testable import cmux
#endif

/// Builds a ``CanvasPaneContentMount`` the way ``WorkspaceCanvasHostView`` does,
/// with the smallest content the mount's own contract needs: terminals mount
/// their real hosted view, and every other panel kind mounts through a plain
/// hosted `NSView`, because the mount drives panel-level lifecycle rather than
/// anything about the hosted view's identity.
@MainActor
func makeCanvasPaneContentMountForTesting(
    panel: any Panel,
    container: NSView,
    onFocusPanel: @escaping (UUID) -> Void = { _ in },
    makeTerminalVisible: @escaping @MainActor (GhosttySurfaceScrollView) -> Void = { $0.setVisibleInUI(true) }
) -> CanvasPaneContentMount {
    let workspaceAttentionColor = WorkspaceAttentionColor(configuredHex: nil)
    let content: CanvasPaneContent
    if let terminalPanel = panel as? TerminalPanel {
        content = .terminal(terminalPanel, .disabled)
    } else {
        content = .hosted(
            panel,
            NSView(frame: container.bounds),
            CanvasHostedPanelPresentation(
                isFocused: false,
                allowsPointerInput: true,
                pointerInputOwner: container,
                workspaceAttentionColor: workspaceAttentionColor
            )
        )
    }
    return CanvasPaneContentMount(
        content: content,
        panelId: panel.id,
        container: container,
        workspaceAttentionColor: workspaceAttentionColor,
        onFocusPanel: onFocusPanel,
        makeTerminalVisible: makeTerminalVisible
    )
}

/// VAL-CANVAS-001: CanvasPaneContentMount drives any panel for terminal,
/// browser, and markdown (mount / render / unmount).
@MainActor
final class CanvasDockableMountLifecycleTests: XCTestCase {
    func testTerminalMountRenderUnmountViaDockable() {
        let panel = TerminalPanel(workspaceId: UUID())
        let container = NSView(frame: NSRect(x: 0, y: 0, width: 640, height: 480))
        var focused: UUID?

        let mount = makeCanvasPaneContentMountForTesting(
            panel: panel,
            container: container,
            onFocusPanel: { focused = $0 },
            makeTerminalVisible: { _ in }
        )
        XCTAssertEqual(panel.hostedView.superview, container)

        mount.setRendering(false)
        mount.setRendering(true)

        let tokenBefore = panel.viewReattachToken
        mount.unmount()
        XCTAssertNil(panel.hostedView.superview)
        XCTAssertEqual(panel.viewReattachToken, tokenBefore &+ 1)
        _ = focused
    }

    func testBrowserMountRenderUnmountViaDockable() {
        let panel = BrowserPanel(workspaceId: UUID(), renderInitialNavigation: false)
        let container = NSView(frame: NSRect(x: 0, y: 0, width: 640, height: 480))

        // No canvas host environment → mounting still sets panel mount flags.
        let mount = makeCanvasPaneContentMountForTesting(
            panel: panel,
            container: container
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

    func testMarkdownMountRenderUnmountViaDockable() throws {
        let fileURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("canvas-mount-\(UUID().uuidString).md")
        try "# mount\n".write(to: fileURL, atomically: true, encoding: .utf8)
        defer { try? FileManager.default.removeItem(at: fileURL) }

        let panel = MarkdownPanel(workspaceId: UUID(), filePath: fileURL.path)
        let container = NSView(frame: NSRect(x: 0, y: 0, width: 640, height: 480))

        let mount = makeCanvasPaneContentMountForTesting(
            panel: panel,
            container: container
        )
        // Hosted path pins a content subview.
        XCTAssertFalse(container.subviews.isEmpty)

        mount.setRendering(false)
        mount.setRendering(true)
        mount.unmount()
        XCTAssertTrue(container.subviews.isEmpty)
    }

    /// The canvas drives content only through the package-owned
    /// ``CanvasPaneContentMounting`` seam, so a panel's dockable identity stays
    /// on the panel and never leaks into `CmuxCanvasUI`.
    func testMountDrivesPanelThroughGenericMountingSeam() {
        let panel = TerminalPanel(workspaceId: UUID())
        let container = NSView(frame: NSRect(x: 0, y: 0, width: 100, height: 100))
        let mount = makeCanvasPaneContentMountForTesting(
            panel: panel,
            container: container,
            makeTerminalVisible: { _ in }
        )
        // The canvas package only ever sees the protocol, never the panel type.
        let mounting: any CanvasPaneContentMounting = mount
        XCTAssertEqual(mount.panelId, panel.id)
        XCTAssertEqual(panel.dockableKind, .terminal)
        XCTAssertEqual(panel.hostedView.superview, container)
        mounting.unmount()
        XCTAssertNil(panel.hostedView.superview)
    }
}
