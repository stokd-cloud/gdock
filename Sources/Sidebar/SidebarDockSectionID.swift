import Foundation

/// App-owned durable identity for one live rail section.
///
/// Distinct from Bonsplit `PaneID`, which is a replaceable rendering host.
/// Complete snapshots, within-rail reorder, cross-rail move, and persistence
/// use this id as the section oracle (VAL-RAIL-008 / VAL-MOVE-002 / VAL-PERSIST-001).
struct SidebarDockSectionID: Hashable, Sendable, Codable, Equatable, CustomStringConvertible {
    let rawValue: UUID

    init(_ rawValue: UUID = UUID()) {
        self.rawValue = rawValue
    }

    init?(uuidString: String) {
        guard let uuid = UUID(uuidString: uuidString) else { return nil }
        self.rawValue = uuid
    }

    var uuidString: String { rawValue.uuidString }
    var description: String { uuidString }
}
