public import Foundation
#if canImport(AppKit)
public import AppKit
#endif

/// A visible object that can be docked into a canvas pane, panel host, or
/// similar surface without the host branching on concrete content type.
///
/// All lifecycle methods are main-actor isolated. Mount helpers that touch
/// AppKit views are available only when AppKit is present.
@MainActor
public protocol Dockable: AnyObject, Identifiable where ID == UUID {
    /// Kind used for factory registration, open-pane dispatch, and persistence.
    var dockableKind: DockableKind { get }

    /// User-visible title for chrome, tabs, and accessibility.
    var dockableTitle: String { get }

    /// Enables or disables rendering while the dockable remains mounted.
    ///
    /// Default implementation is a no-op. Browsers and terminals may override
    /// to control webview visibility or occlusion.
    func setDockRendering(_ rendering: Bool)

    /// Tears down host-side mount state after the content view is removed.
    ///
    /// Default implementation is a no-op.
    func tearDownDockMount()

    /// Encodes opaque per-kind state for session persistence.
    ///
    /// Default implementation returns empty `Data`. Stateful panels override
    /// with a JSON (or other) payload understood by their registry decode path.
    func encodeDockPayload() throws -> Data

    #if canImport(AppKit)
    /// Builds the AppKit content view for the given mount context.
    ///
    /// Required for AppKit hosts. There is no default implementation.
    func makeDockContentView(context: DockableMountContext) -> NSView
    #endif
}

extension Dockable {
    /// Default no-op rendering toggle.
    public func setDockRendering(_ rendering: Bool) {}

    /// Default no-op mount teardown.
    public func tearDownDockMount() {}

    /// Default empty payload for content-less or not-yet-persisted kinds.
    public func encodeDockPayload() throws -> Data {
        Data()
    }
}
