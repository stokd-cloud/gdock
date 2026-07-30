import Foundation
import Testing
@testable import CmuxDockable

#if canImport(AppKit)
import AppKit

@MainActor
private final class MinimalDockable: Dockable {
    let id: UUID
    let dockableKind: DockableKind
    let dockableTitle: String
    private let contentView: NSView

    init(
        id: UUID = UUID(),
        kind: DockableKind = .markdown,
        title: String = "Minimal",
        contentView: NSView = NSView(frame: .zero)
    ) {
        self.id = id
        self.dockableKind = kind
        self.dockableTitle = title
        self.contentView = contentView
    }

    func makeDockContentView(context: DockableMountContext) -> NSView {
        _ = context
        return contentView
    }
}

@MainActor
private final class PortalDockable: PortalHostable {
    let id: UUID
    let dockableKind: DockableKind
    let dockableTitle: String
    private let contentView: NSView
    private(set) var detachCount = 0
    private(set) var reattachCount = 0

    init(
        id: UUID = UUID(),
        kind: DockableKind = .terminal,
        title: String = "Portal",
        contentView: NSView = NSView(frame: .zero)
    ) {
        self.id = id
        self.dockableKind = kind
        self.dockableTitle = title
        self.contentView = contentView
    }

    func makeDockContentView(context: DockableMountContext) -> NSView {
        _ = context
        return contentView
    }

    func detachContentFromPortal() -> NSView {
        detachCount += 1
        return contentView
    }

    func reattachContentToPortal(_ view: NSView) {
        _ = view
        reattachCount += 1
    }
}

@MainActor
struct DockableProtocolTests {
    @Test func minimalConformerCompilesAndDefaults() throws {
        let view = NSView(frame: NSRect(x: 0, y: 0, width: 10, height: 10))
        let dockable = MinimalDockable(contentView: view)
        let container = NSView(frame: .zero)
        let context = DockableMountContext(container: container) { _ in }

        // Defaulted members are callable without override.
        dockable.setDockRendering(true)
        dockable.tearDownDockMount()
        let payload = try dockable.encodeDockPayload()
        #expect(payload.isEmpty)

        let made = dockable.makeDockContentView(context: context)
        #expect(made === view)
        #expect(dockable.dockableKind == .markdown)
        #expect(dockable.dockableTitle == "Minimal")
    }

    @Test func portalHostableRefinesDockable() {
        let portal = PortalDockable()
        let asDockable: any Dockable = portal
        #expect(asDockable.dockableKind == .terminal)

        let detached = portal.detachContentFromPortal()
        portal.reattachContentToPortal(detached)
        #expect(portal.detachCount == 1)
        #expect(portal.reattachCount == 1)
    }
}
#endif
