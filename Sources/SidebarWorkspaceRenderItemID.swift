import Foundation

/// Stable, allocation-free identity for a `SidebarWorkspaceRenderItem`.
///
/// `ForEach` gathers row identifiers on every list diff, so the id must be
/// cheap to create and hash. Keep the discriminator as a byte so SwiftUI's
/// per-scroll list diff avoids enum-payload hash/equality witnesses.
struct SidebarWorkspaceRenderItemID: Hashable {
    private let kind: UInt8
    private let uuid: UUID

    static func group(_ uuid: UUID) -> Self {
        Self(kind: 1, uuid: uuid)
    }

    static func workspace(_ uuid: UUID) -> Self {
        Self(kind: 2, uuid: uuid)
    }

    /// The agent-session card stack that stands in for the focused workspace's
    /// own row. Keyed by that workspace, so it never collides with a group row
    /// and stays stable as cards come and go inside it.
    static func panelCardStack(_ workspaceId: UUID) -> Self {
        Self(kind: 3, uuid: workspaceId)
    }

    static func == (lhs: Self, rhs: Self) -> Bool {
        lhs.kind == rhs.kind && lhs.uuid == rhs.uuid
    }

    func hash(into hasher: inout Hasher) {
        hasher.combine(kind)
        hasher.combine(uuid)
    }
}
