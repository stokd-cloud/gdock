import AppKit
import CmuxCanvasUI
import CmuxDockable

/// Owns the mounted content of one canvas pane and its teardown. This is the
/// app-side witness of the `CmuxCanvasUI` content seam: the package drives
/// lifecycle through ``CanvasPaneContentMounting`` without seeing panel types.
///
/// Content is always an ``any Dockable``. Portal-hosted kinds (terminals) opt
/// into ``PortalHostable`` detach/reattach; rendering/occlusion and unmount
/// teardown flow through ``Dockable/setDockRendering(_:)`` and
/// ``Dockable/tearDownDockMount()``.
@MainActor
final class CanvasPaneContentMount: CanvasPaneContentMounting {
    let panelId: UUID
    /// The dockable content hosted in this pane.
    let dockable: any Dockable
    private weak var container: NSView?
    private var mountedView: NSView?
    private var onFocusPanel: ((UUID) -> Void)?
    private let isPortalHosted: Bool

    /// Mounts dockable content into the pane's content container.
    ///
    /// - Parameters:
    ///   - dockable: Content to mount (any ``Dockable``).
    ///   - panelId: The panel this content belongs to.
    ///   - container: The pane view's content container.
    ///   - onFocusPanel: Invoked when the content reports keyboard focus
    ///     (terminal surfaces report via their `onFocus` hook).
    ///   - makeTerminalVisible: Applies terminal visibility after attaching
    ///     a portal-detached terminal view to its container.
    init(
        dockable: any Dockable,
        panelId: UUID,
        container: NSView,
        onFocusPanel: @escaping (UUID) -> Void,
        makeTerminalVisible: @MainActor (NSView) -> Void = { view in
            (view as? GhosttySurfaceScrollView)?.setVisibleInUI(true)
        }
    ) {
        self.dockable = dockable
        self.panelId = panelId
        self.container = container
        self.onFocusPanel = onFocusPanel

        let mountContext = DockableMountContext(container: container) { focusedId in
            onFocusPanel(focusedId)
        }

        let isPortal = dockable is (any PortalHostable)
        self.isPortalHosted = isPortal

        if let portal = dockable as? any PortalHostable {
            // Detach from the window portal before parenting into the pane so
            // the clip view crops instead of reflowing at the viewport edge.
            _ = portal.detachContentFromPortal()
        }

        let view = dockable.makeDockContentView(context: mountContext)
        self.mountedView = view

        if isPortal {
            Self.attachTerminalView(
                view,
                to: container,
                makeVisible: makeTerminalVisible
            )
        } else {
            // Hosting views self-size to SwiftUI's ideal size under
            // autoresizing; pin with constraints so the pane dictates size.
            view.translatesAutoresizingMaskIntoConstraints = false
            container.addSubview(view)
            NSLayoutConstraint.activate([
                view.topAnchor.constraint(equalTo: container.topAnchor),
                view.bottomAnchor.constraint(equalTo: container.bottomAnchor),
                view.leadingAnchor.constraint(equalTo: container.leadingAnchor),
                view.trailingAnchor.constraint(equalTo: container.trailingAnchor),
            ])
        }
    }

    /// Attaches a terminal (portal) view before applying its visible lifecycle state.
    static func attachTerminalView<View: NSView>(
        _ view: View,
        to container: NSView,
        makeVisible: @MainActor (View) -> Void
    ) {
        // Ghostty's scroll view manages its own constraints-free layout.
        view.translatesAutoresizingMaskIntoConstraints = true
        view.autoresizingMask = [.width, .height]
        view.frame = container.bounds
        container.addSubview(view)
        makeVisible(view)
    }

    /// Applies host presentation state that changes while direct-hosted
    /// terminal content stays mounted. Narrow-casts ``TerminalPanel`` only
    /// for session content width / active / inactive overlay (not a content-kind
    /// lifecycle switch).
    func updatePresentation(
        isFocused: Bool,
        showsInactiveOverlay: Bool,
        inactiveOverlayColor: NSColor,
        inactiveOverlayOpacity: Double,
        sessionContentWidthPresentation: SessionContentWidthPresentation
    ) {
        guard let terminalPanel = dockable as? TerminalPanel else { return }
        let hostedView = terminalPanel.hostedView
        hostedView.setSessionContentWidthPresentation(sessionContentWidthPresentation)
        hostedView.setActive(isFocused)
        hostedView.setInactiveOverlay(
            color: inactiveOverlayColor,
            opacity: CGFloat(inactiveOverlayOpacity),
            visible: showsInactiveOverlay
        )
    }

    /// Applies the explicit canvas lifecycle state to the mounted content.
    /// Offscreen terminals stop rendering (Ghostty occlusion) but keep their
    /// size, so re-entering the viewport never reflows.
    func setRendering(_ rendering: Bool) {
        dockable.setDockRendering(rendering)
    }

    /// Unmounts the content. Portal-hosted kinds reattach to the window portal
    /// system; other kinds tear down dock mount flags and remove their view.
    func unmount() {
        if let portal = dockable as? any PortalHostable {
            let view = mountedView ?? (dockable as? TerminalPanel)?.hostedView
            if let view {
                portal.reattachContentToPortal(view)
            } else {
                dockable.tearDownDockMount()
            }
        } else {
            dockable.tearDownDockMount()
            mountedView?.removeFromSuperview()
        }
        mountedView = nil
        onFocusPanel = nil
    }
}
