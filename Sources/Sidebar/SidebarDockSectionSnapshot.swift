import Foundation

/// Snapshot of one rail section for reorder / tests.
struct SidebarDockSectionSnapshot: Equatable, Sendable {
    var paneId: UUID
    var tabPanelIds: [UUID]
    var selectedPanelId: UUID?
    var isCollapsed: Bool
    var rememberedExtent: CGFloat?
}
