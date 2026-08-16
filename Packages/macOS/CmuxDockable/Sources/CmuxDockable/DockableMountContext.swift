#if canImport(AppKit)
public import Foundation
public import AppKit

/// Inputs supplied when a ``Dockable`` builds its mountable content view.
///
/// Mirrors the container and focus callback historically passed into canvas
/// pane content mounts.
public struct DockableMountContext {
    /// Host view that will own the dockable's content.
    public let container: NSView

    /// Invoked when the dockable content requests focus for the given identity.
    public let onFocus: @MainActor (UUID) -> Void

    /// Creates a mount context.
    /// - Parameters:
    ///   - container: Host view that will own the dockable's content.
    ///   - onFocus: Focus callback for the dockable's identity.
    public init(container: NSView, onFocus: @escaping @MainActor (UUID) -> Void) {
        self.container = container
        self.onFocus = onFocus
    }
}
#endif
