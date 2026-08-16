import Foundation
import os

/// Canonical seed contents and self-healing for dock rails (VAL-RAIL-001/002, VAL-FLAG-003).
///
/// Reuses landed ``LeftWorkspaceSelectorPanel`` and ``RightSidebarToolPanel`` — never a
/// duplicate selector kind (mission D-2).
@MainActor
enum SidebarDockSeeding {
    private static let logger = Logger(subsystem: "ai.manaflow.cmux", category: "SidebarDockSeeding")

    /// Canonical right-rail tool order: Files, Find, Vault (`.sessions`).
    static let canonicalRightModes: [RightSidebarMode] = [.files, .find, .sessions]

    /// Build the three canonical right-rail tool panels for a workspace.
    static func makeCanonicalRightPanels(workspace: Workspace) -> [RightSidebarToolPanel] {
        canonicalRightModes.map { RightSidebarToolPanel(workspace: workspace, mode: $0) }
    }

    /// Seed a right rail when empty. Selects a placement-allowed preferred mode, else Files.
    @discardableResult
    static func seedRightIfEmpty(
        store: SidebarDockStore,
        workspace: Workspace,
        preferredMode: RightSidebarMode?
    ) -> Bool {
        guard store.edge == .right else { return false }
        guard store.panels.isEmpty else { return false }
        let panels = makeCanonicalRightPanels(workspace: workspace)
        store.seedRootPanels(panels)
        let mode = resolvedPreferredMode(preferredMode)
        _ = store.selectToolMode(mode, focus: false)
        return true
    }

    /// Seed a left rail when empty with the landed workspace selector.
    @discardableResult
    static func seedLeftIfEmpty(
        store: SidebarDockStore,
        workspace: Workspace
    ) -> Bool {
        guard store.edge == .left else { return false }
        guard store.panels.isEmpty else { return false }
        let panel = LeftWorkspaceSelectorPanel(workspace: workspace)
        store.seedRootPanels([panel])
        return true
    }

    /// Self-heal an emptied left rail (VAL-RAIL-001).
    @discardableResult
    static func ensureLeftNonEmpty(
        store: SidebarDockStore,
        workspace: Workspace
    ) -> Bool {
        guard store.edge == .left else { return false }
        guard store.panels.isEmpty else { return false }
        logger.error("sidebar-dock: empty left rail reseeding selector window=\(store.windowId.uuidString, privacy: .public)")
        return seedLeftIfEmpty(store: store, workspace: workspace)
    }

    /// Self-heal an emptied right rail (VAL-RAIL-002 / D-24).
    @discardableResult
    static func ensureRightNonEmpty(
        store: SidebarDockStore,
        workspace: Workspace,
        preferredMode: RightSidebarMode?
    ) -> Bool {
        guard store.edge == .right else { return false }
        guard store.panels.isEmpty else { return false }
        logger.error("sidebar-dock: empty right rail reseeding tools window=\(store.windowId.uuidString, privacy: .public)")
        return seedRightIfEmpty(store: store, workspace: workspace, preferredMode: preferredMode)
    }

    /// Seed both rails of a registry when empty (flag-on first mount).
    static func seedRegistryIfEmpty(
        registry: SidebarDockStoreRegistry,
        workspace: Workspace,
        preferredRightMode: RightSidebarMode?
    ) {
        _ = seedLeftIfEmpty(store: registry.left, workspace: workspace)
        _ = seedRightIfEmpty(
            store: registry.right,
            workspace: workspace,
            preferredMode: preferredRightMode
        )
    }

    /// Prefer a rail-allowed mode; fall back to Files.
    static func resolvedPreferredMode(_ preferred: RightSidebarMode?) -> RightSidebarMode {
        guard let preferred, SidebarDockPlacementMatrix.allows(mode: preferred) else {
            return .files
        }
        return preferred
    }

    /// Ordered modes present on a right rail (for tests / inventory).
    static func orderedRightModes(in store: SidebarDockStore) -> [RightSidebarMode] {
        guard store.edge == .right else { return [] }
        var modes: [RightSidebarMode] = []
        for pane in store.orderedSectionPaneIds() {
            for tab in store.bonsplitController.tabs(inPane: pane) {
                if let tool = store.panel(for: tab.id) as? RightSidebarToolPanel {
                    modes.append(tool.mode)
                }
            }
        }
        return modes
    }
}
