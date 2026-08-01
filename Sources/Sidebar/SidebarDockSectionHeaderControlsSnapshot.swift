import Foundation

/// Immutable chrome snapshot for focused-section header controls.
///
/// Built above list/Bonsplit row boundaries so rows receive only value snapshots
/// plus closure action bundles (no store references).
struct SidebarDockSectionHeaderControlsSnapshot: Equatable, Sendable {
    let paneId: UUID
    let sectionCount: Int
    let isCollapsed: Bool
    let canCollapse: Bool
    let canExpand: Bool
    let canReorderUp: Bool
    let canReorderDown: Bool
    /// True when multi-section chrome should expose a header drag affordance.
    let showsHeaderDragAffordance: Bool
}
