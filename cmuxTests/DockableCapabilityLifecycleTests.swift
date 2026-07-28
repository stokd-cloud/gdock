import XCTest
import CmuxDockable
import AppKit

#if canImport(cmux_DEV)
@testable import cmux_DEV
#elseif canImport(cmux)
@testable import cmux
#endif

/// Capability lifecycle for TerminalPanel (PortalHostable) and BrowserPanel visibility.
@MainActor
final class DockableCapabilityLifecycleTests: XCTestCase {
    func testTerminalPanelConformsToPortalHostableAndLifecycle() {
        let panel = TerminalPanel(workspaceId: UUID())
        XCTAssertTrue(panel is (any PortalHostable))
        XCTAssertEqual(panel.dockableKind, .terminal)

        let container = NSView(frame: NSRect(x: 0, y: 0, width: 320, height: 240))
        var focusedID: UUID?
        let context = DockableMountContext(container: container) { id in
            focusedID = id
        }

        let portal = panel as any PortalHostable

        // detach without requiring a prior portal bind (no-op detach is fine).
        let detached = portal.detachContentFromPortal()
        XCTAssertTrue(detached === panel.hostedView)

        let contentView = panel.makeDockContentView(context: context)
        XCTAssertTrue(contentView === panel.hostedView)

        // Hosted path: parent into a plain container the same way canvas does.
        CanvasPaneContentMount.attachTerminalView(panel.hostedView, to: container) { view in
            // Avoid Ghostty display-link churn in unit tests: do not force visibleInUI.
            _ = view
        }
        XCTAssertEqual(panel.hostedView.superview, container)

        // setDockRendering drives occlusion (visible flag).
        panel.setDockRendering(true)
        panel.setDockRendering(false)
        panel.setDockRendering(true)

        let tokenBefore = panel.viewReattachToken
        portal.reattachContentToPortal(panel.hostedView)
        XCTAssertNil(panel.hostedView.superview)
        XCTAssertEqual(panel.viewReattachToken, tokenBefore &+ 1)

        // Re-install focus handler after reattach clears it.
        _ = panel.makeDockContentView(context: context)
        _ = focusedID

        // Do not call panel.close() here: TerminalPanel.close detaches portal state
        // and can tear down the Ghostty runtime in a way that races unit-test teardown.
    }

    func testBrowserPanelSetDockRenderingAndMountUnmountVisibility() {
        let panel = BrowserPanel(workspaceId: UUID(), renderInitialNavigation: false)
        XCTAssertEqual(panel.dockableKind, .browser)
        XCTAssertFalse(panel.canvasInlineHostingActive)

        // Mount parity: canvas sets inline hosting + visibility.
        panel.canvasInlineHostingActive = true
        panel.noteWebViewVisibility(true, reason: "canvas.mount")
        XCTAssertTrue(panel.canvasInlineHostingActive)
        XCTAssertEqual(panel.webViewLastVisibilityChangeReason, "canvas.mount")
        XCTAssertEqual(panel.webViewLifecycleTopPayload()["visible_in_ui"] as? Bool, true)

        // Render/occlude must NOT clear canvasInlineHostingActive.
        panel.setDockRendering(false)
        XCTAssertTrue(panel.canvasInlineHostingActive)
        XCTAssertEqual(panel.webViewLastVisibilityChangeReason, "canvas.occlude")
        XCTAssertEqual(panel.webViewLifecycleTopPayload()["visible_in_ui"] as? Bool, false)

        panel.setDockRendering(true)
        XCTAssertTrue(panel.canvasInlineHostingActive)
        XCTAssertEqual(panel.webViewLastVisibilityChangeReason, "canvas.render")
        XCTAssertEqual(panel.webViewLifecycleTopPayload()["visible_in_ui"] as? Bool, true)

        // Unmount parity via tearDownDockMount.
        panel.tearDownDockMount()
        XCTAssertFalse(panel.canvasInlineHostingActive)
        XCTAssertEqual(panel.webViewLastVisibilityChangeReason, "canvas.unmount")
        XCTAssertEqual(panel.webViewLifecycleTopPayload()["visible_in_ui"] as? Bool, false)

        panel.close()
    }
}
