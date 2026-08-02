import Foundation

/// Rail-specific session persistence envelope (VAL-PERSIST-001 / VAL-UPSTREAM-PERSIST-001).
///
/// Holds the same layout/panels shape the shared Dock container uses **plus**
/// rail-only identity and collapse metadata. Rail-only fields must never enter
/// ``SessionSplitContainerSnapshot`` (the shared Dock envelope).
struct SessionSidebarDockSnapshot: Codable, Sendable {
    var focusedPanelId: UUID?
    var layout: SessionWorkspaceLayoutSnapshot
    var panels: [SessionPanelSnapshot]
    /// App-owned durable section ids ordered top → bottom.
    /// Never Bonsplit pane host ids. Optional for partial/legacy payloads.
    var sectionIds: [UUID]? = nil
    /// Stable section ids that are collapsed.
    var collapsedSectionIds: [UUID]? = nil
    /// Remembered expanded extents keyed by stable section id string.
    var rememberedExtentsBySectionId: [String: Double]? = nil

    init(
        focusedPanelId: UUID? = nil,
        layout: SessionWorkspaceLayoutSnapshot,
        panels: [SessionPanelSnapshot],
        sectionIds: [UUID]? = nil,
        collapsedSectionIds: [UUID]? = nil,
        rememberedExtentsBySectionId: [String: Double]? = nil
    ) {
        self.focusedPanelId = focusedPanelId
        self.layout = layout
        self.panels = panels
        self.sectionIds = sectionIds
        self.collapsedSectionIds = collapsedSectionIds
        self.rememberedExtentsBySectionId = rememberedExtentsBySectionId
    }

    /// Project the layout/panels slice into the shared container type for codecs
    /// that operate on ``SessionSplitContainerSnapshot`` (layout prune/apply).
    var asContainerSnapshot: SessionSplitContainerSnapshot {
        SessionSplitContainerSnapshot(
            focusedPanelId: focusedPanelId,
            layout: layout,
            panels: panels,
            sourceWorkspaceIdsByPanelId: nil
        )
    }

    /// Build a rail envelope from a shared container snapshot plus rail metadata.
    static func from(
        container: SessionSplitContainerSnapshot,
        sectionIds: [UUID]?,
        collapsedSectionIds: [UUID]?,
        rememberedExtentsBySectionId: [String: Double]?
    ) -> SessionSidebarDockSnapshot {
        SessionSidebarDockSnapshot(
            focusedPanelId: container.focusedPanelId,
            layout: container.layout,
            panels: container.panels,
            sectionIds: sectionIds,
            collapsedSectionIds: collapsedSectionIds,
            rememberedExtentsBySectionId: rememberedExtentsBySectionId
        )
    }
}
