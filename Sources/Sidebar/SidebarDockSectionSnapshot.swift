import Foundation

/// Snapshot of one rail section for reorder / tests.
struct SidebarDockSectionSnapshot: Equatable, Sendable {
    /// App-owned durable section identity (not the Bonsplit pane host).
    var sectionId: UUID
    /// Current Bonsplit pane host id (may change when topology is rebuilt).
    var paneId: UUID
    var tabPanelIds: [UUID]
    var selectedPanelId: UUID?
    var isCollapsed: Bool
    var rememberedExtent: CGFloat?
}
