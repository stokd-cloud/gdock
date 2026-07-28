import Foundation
import Testing
@testable import CmuxDockable

#if canImport(AppKit)
import AppKit

@MainActor
private final class StubDockable: Dockable {
    let id: UUID
    let dockableKind: DockableKind
    let dockableTitle: String
    let token: String

    init(
        id: UUID = UUID(),
        kind: DockableKind,
        title: String = "Stub",
        token: String = ""
    ) {
        self.id = id
        self.dockableKind = kind
        self.dockableTitle = title
        self.token = token
    }

    func makeDockContentView(context: DockableMountContext) -> NSView {
        _ = context
        return NSView(frame: .zero)
    }

    func encodeDockPayload() throws -> Data {
        Data(token.utf8)
    }
}

@MainActor
struct DockableRegistryTests {
    @Test func registerThenMakeReturnsConformer() {
        let registry = DockableRegistry()
        registry.register(
            kind: .markdown,
            make: { StubDockable(kind: .markdown, title: "MD") },
            decode: { _ in StubDockable(kind: .markdown) }
        )

        let made = registry.make(kind: .markdown)
        #expect(made != nil)
        #expect(made?.dockableKind == .markdown)
        #expect(made?.dockableTitle == "MD")
    }

    @Test func unregisteredKindReturnsNil() {
        let registry = DockableRegistry()
        #expect(registry.make(kind: .project) == nil)
        #expect(registry.decode(kind: .project, payload: Data()) == nil)
    }

    @Test func doubleRegistrationLastWins() {
        let registry = DockableRegistry()
        registry.register(
            kind: .browser,
            make: { StubDockable(kind: .browser, title: "first") },
            decode: { _ in StubDockable(kind: .browser, title: "first") }
        )
        registry.register(
            kind: .browser,
            make: { StubDockable(kind: .browser, title: "second") },
            decode: { _ in StubDockable(kind: .browser, title: "second") }
        )

        #expect(registry.make(kind: .browser)?.dockableTitle == "second")
        #expect(registry.decode(kind: .browser, payload: Data())?.dockableTitle == "second")
    }

    @Test func decodeRoundTrip() throws {
        let registry = DockableRegistry()
        let originalID = UUID()
        registry.register(
            kind: .markdown,
            make: { StubDockable(kind: .markdown) },
            decode: { data in
                let token = String(data: data, encoding: .utf8) ?? ""
                return StubDockable(id: originalID, kind: .markdown, token: token)
            }
        )

        let original = StubDockable(id: originalID, kind: .markdown, token: "hello-payload")
        let payload = try original.encodeDockPayload()
        let rehydrated = registry.decode(kind: .markdown, payload: payload)

        #expect(rehydrated != nil)
        #expect(rehydrated?.id == originalID)
        #expect(rehydrated?.dockableKind == .markdown)
        let stub = rehydrated as? StubDockable
        #expect(stub?.token == "hello-payload")
    }

    @Test func payloadRoundTripForStubViaSnapshot() throws {
        let registry = DockableRegistry()
        registry.register(
            kind: .agentSession,
            make: { StubDockable(kind: .agentSession) },
            decode: { data in
                let token = String(data: data, encoding: .utf8) ?? ""
                return StubDockable(kind: .agentSession, token: token)
            }
        )

        let id = UUID()
        let original = StubDockable(id: id, kind: .agentSession, token: "session-state")
        let snapshot = DockableSnapshot(
            id: id,
            kind: original.dockableKind,
            payload: try original.encodeDockPayload()
        )

        let encoder = JSONEncoder()
        let decoder = JSONDecoder()
        let data = try encoder.encode(snapshot)
        let decodedSnapshot = try decoder.decode(DockableSnapshot.self, from: data)

        #expect(decodedSnapshot.id == id)
        #expect(decodedSnapshot.kind == .agentSession)

        let rehydrated = registry.decode(kind: decodedSnapshot.kind, payload: decodedSnapshot.payload)
        let stub = rehydrated as? StubDockable
        #expect(stub?.token == "session-state")
        #expect(stub?.dockableKind == .agentSession)
    }

    @Test func defaultEncodeDockPayloadIsEmpty() throws {
        let dockable = StubDockable(kind: .cloudVMLoading, token: "ignored-by-default")
        // Override is present on StubDockable; verify protocol default via a type
        // that does not override encode — use a nested type.
        final class EmptyPayloadDockable: Dockable {
            let id = UUID()
            let dockableKind: DockableKind = .extensionBrowser
            let dockableTitle = "Empty"
            func makeDockContentView(context: DockableMountContext) -> NSView {
                _ = context
                return NSView(frame: .zero)
            }
        }
        let empty = EmptyPayloadDockable()
        #expect(try empty.encodeDockPayload().isEmpty)
        _ = dockable
    }
}
#endif
