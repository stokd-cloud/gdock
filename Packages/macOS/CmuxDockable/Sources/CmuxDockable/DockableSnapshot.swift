public import Foundation

/// Opaque session snapshot for a single dockable pane or panel.
///
/// `payload` is kind-specific `Data` produced by ``Dockable/encodeDockPayload()``
/// and consumed by ``DockableRegistry/decode(kind:payload:)``. The package never
/// imports app session types, keeping the dependency edge one-way (app → package).
public struct DockableSnapshot: Codable, Sendable {
    /// Stable identity of the dockable instance.
    public var id: UUID

    /// Content kind used for registry decode and open-pane dispatch.
    public var kind: DockableKind

    /// Opaque per-kind state. Empty `Data` for content-less kinds.
    public var payload: Data

    /// Creates a snapshot.
    /// - Parameters:
    ///   - id: Stable identity of the dockable instance.
    ///   - kind: Content kind.
    ///   - payload: Opaque per-kind state.
    public init(id: UUID, kind: DockableKind, payload: Data) {
        self.id = id
        self.kind = kind
        self.payload = payload
    }
}
