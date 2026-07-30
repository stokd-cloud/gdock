public import Foundation

/// Kind-keyed factory and decode catalog for ``Dockable`` instances.
///
/// The registry holds no app panel types. Callers inject `make` / `decode`
/// factories at startup (or via a context-aware app-owned wrapper later).
/// Unregistered kinds return `nil`. Re-registering a kind overwrites the prior
/// entry (last wins).
@MainActor
public final class DockableRegistry {
    /// Shared process-wide registry. Tests may construct isolated instances via
    /// ``init()``.
    public static let shared = DockableRegistry()

    private struct Entry {
        /// May return `nil` when required create context is missing (fail-closed).
        let make: @MainActor () -> (any Dockable)?
        let decode: @MainActor (Data) -> (any Dockable)?
    }

    private var entries: [DockableKind: Entry] = [:]

    /// Creates an empty registry.
    public init() {}

    /// Registers factories for `kind`. A second registration for the same kind
    /// replaces the previous factories.
    ///
    /// - Parameters:
    ///   - kind: Dockable kind to associate with the factories.
    ///   - make: Creates a fresh dockable of that kind, or `nil` when required
    ///     context is missing (fail-closed; no dummy placeholders).
    ///   - decode: Rehydrates a dockable from an opaque payload, or returns
    ///     `nil` when the payload is invalid.
    public func register(
        kind: DockableKind,
        make: @escaping @MainActor () -> (any Dockable)?,
        decode: @escaping @MainActor (Data) -> (any Dockable)?
    ) {
        entries[kind] = Entry(make: make, decode: decode)
    }

    /// Creates a dockable for `kind`, or `nil` when unregistered or when the
    /// registered factory fails closed (missing context / unsupported).
    public func make(kind: DockableKind) -> (any Dockable)? {
        entries[kind]?.make()
    }

    /// Decodes a dockable of `kind` from `payload`, or `nil` when unregistered
    /// or when the registered decode returns `nil`.
    public func decode(kind: DockableKind, payload: Data) -> (any Dockable)? {
        entries[kind]?.decode(payload)
    }
}
