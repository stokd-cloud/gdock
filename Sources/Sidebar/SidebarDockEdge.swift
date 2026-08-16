import Foundation

/// Which edge-anchored sidebar rail a ``SidebarDockStore`` owns.
///
/// One type addresses both rails; left and right share the same store,
/// placement matrix, and section model.
enum SidebarDockEdge: String, Codable, Sendable, CaseIterable, Hashable {
    case left
    case right
}
