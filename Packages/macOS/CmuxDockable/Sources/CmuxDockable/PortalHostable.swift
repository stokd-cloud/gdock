#if canImport(AppKit)
public import AppKit
// PortalHostable uses NSView from AppKit only.

/// Opt-in capability for dockables whose content lives in a window portal and
/// must detach into a pane container (and reattach on unmount).
///
/// Terminals use this instead of a host-level `.terminal` content branch.
@MainActor
public protocol PortalHostable: Dockable {
    /// Detaches portal-hosted content and returns the view to mount in a pane.
    func detachContentFromPortal() -> NSView

    /// Returns a previously detached content view to the window portal system.
    func reattachContentToPortal(_ view: NSView)
}
#endif
