import AppKit
import Foundation
import UniformTypeIdentifiers

/// Exported drag payload for cross-rail tool-tab and whole-section transfers.
///
/// Distinct from `com.cmux.sidebar-tab-reorder` (workspace-row reorder) so a tool
/// tab cannot decode as a workspace id and land on a terminal/browser drop target
/// (VAL-MOVE-003 / PRD 3.1).
struct SidebarDockTransferPayload: Codable, Equatable, Sendable {
    static let typeIdentifier = "com.cmux.sidebar-panel-tab.transfer"
    static let dropContentType = UTType(exportedAs: typeIdentifier)
    static let dropContentTypes: [UTType] = [dropContentType]

    enum Kind: String, Codable, Sendable {
        case tab
        case section
    }

    var kind: Kind
    var windowId: UUID
    var sourceEdge: String
    /// Ordered panel ids (one for tab; full section order for section moves).
    var panelIds: [UUID]
    /// App-owned durable section id (section transfers only).
    var sectionId: UUID?
    var selectedPanelId: UUID?
    var isCollapsed: Bool?
    var rememberedExtent: Double?

    // MARK: - Encode / decode

    func encode() throws -> Data {
        try JSONEncoder().encode(self)
    }

    static func decode(_ data: Data) throws -> SidebarDockTransferPayload {
        try JSONDecoder().decode(SidebarDockTransferPayload.self, from: data)
    }

    /// Pasteboard recovery for live drag sessions.
    static func decode(from pasteboard: NSPasteboard) -> SidebarDockTransferPayload? {
        guard let data = pasteboard.data(forType: .init(typeIdentifier)) else {
            return nil
        }
        return try? decode(data)
    }

    /// True when the pasteboard carries the workspace-row reorder type only
    /// (must never decode as a rail transfer).
    static func isWorkspaceRowReorder(_ pasteboard: NSPasteboard) -> Bool {
        pasteboard.data(forType: .init(SidebarTabDragPayload.typeIdentifier)) != nil
            && pasteboard.data(forType: .init(typeIdentifier)) == nil
    }

    /// True when pasteboard has the rail transfer type (not workspace reorder).
    static func isRailTransfer(_ pasteboard: NSPasteboard) -> Bool {
        pasteboard.data(forType: .init(typeIdentifier)) != nil
    }

    func write(to pasteboard: NSPasteboard) {
        pasteboard.clearContents()
        if let data = try? encode() {
            pasteboard.setData(data, forType: .init(Self.typeIdentifier))
        }
    }

    func provider() -> NSItemProvider {
        let provider = NSItemProvider()
        let data = (try? encode()) ?? Data()
        provider.registerDataRepresentation(
            forTypeIdentifier: Self.typeIdentifier,
            visibility: .ownProcess
        ) { completion in
            completion(data, nil)
            return nil
        }
        return provider
    }
}
