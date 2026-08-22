import Bonsplit
import Foundation

/// Stable, additive session representation of one rail tab.
///
/// `kind` stays raw so snapshots written by future builds remain decodable.
/// `payload` is the panel's existing dockable payload.
struct SessionSidebarRailTabSnapshot: Codable, Equatable, Sendable {
    var id: UUID
    var kind: String
    var payload: Data
}

/// Stable, additive session representation of one vertical rail section.
struct SessionSidebarRailSectionSnapshot: Codable, Equatable, Sendable {
    var id: UUID
    var tabs: [SessionSidebarRailTabSnapshot]
    var selectedTabId: UUID?
    var isCollapsed: Bool = false
    var rememberedExtent: Double? = nil
}

/// Window-level rail layout. Kept independent of Bonsplit pane identities.
struct SessionSidebarRailSnapshot: Codable, Equatable, Sendable {
    var sections: [SessionSidebarRailSectionSnapshot]
    var focusedSectionId: UUID? = nil
}

@MainActor
enum SidebarDockSessionPersistence {
    static func capture(store: SidebarDockStore) -> SessionSidebarRailSnapshot? {
        let liveSections = store.sectionSnapshots()
        var sections: [SessionSidebarRailSectionSnapshot] = []

        for liveSection in liveSections {
            let tabs = liveSection.tabPanelIds.compactMap { panelId -> SessionSidebarRailTabSnapshot? in
                guard let panel = store.panels[panelId],
                      let payload = try? panel.encodeDockPayload() else {
                    return nil
                }
                return SessionSidebarRailTabSnapshot(
                    id: panelId,
                    kind: panel.panelType.rawValue,
                    payload: payload
                )
            }
            guard !tabs.isEmpty else { continue }
            let capturedIds = Set(tabs.map(\.id))
            sections.append(
                SessionSidebarRailSectionSnapshot(
                    id: liveSection.sectionId,
                    tabs: tabs,
                    selectedTabId: liveSection.selectedPanelId.flatMap {
                        capturedIds.contains($0) ? $0 : nil
                    },
                    isCollapsed: liveSection.isCollapsed,
                    rememberedExtent: liveSection.rememberedExtent.map(Double.init)
                )
            )
        }

        guard !sections.isEmpty else { return nil }
        let focusedSectionId = store.bonsplitController.focusedPaneId.flatMap { focusedPane in
            liveSections.first(where: { $0.paneId == focusedPane.id })?.sectionId
        }
        return SessionSidebarRailSnapshot(
            sections: sections,
            focusedSectionId: focusedSectionId
        )
    }

    /// Rehydrates known, placement-valid panels into an empty rail.
    /// Unknown or unavailable kinds are skipped independently.
    @discardableResult
    static func restore(
        snapshot: SessionSidebarRailSnapshot,
        into store: SidebarDockStore,
        workspace: Workspace,
        includeStokdWork: Bool
    ) -> Bool {
        guard store.panels.isEmpty else { return false }

        var panels: [any Panel] = []
        var restoredPanelIdBySnapshotId: [UUID: UUID] = [:]
        var restoredRightModes = Set<RightSidebarMode>()
        var restoredLeftKinds = Set<PanelType>()

        for section in snapshot.sections {
            for tab in section.tabs {
                guard let panel = makePanel(
                    from: tab,
                    edge: store.edge,
                    workspace: workspace,
                    includeStokdWork: includeStokdWork
                ) else {
                    continue
                }
                if let tool = panel as? RightSidebarToolPanel {
                    guard restoredRightModes.insert(tool.mode).inserted else { continue }
                } else {
                    guard restoredLeftKinds.insert(panel.panelType).inserted else { continue }
                }
                panels.append(panel)
                restoredPanelIdBySnapshotId[tab.id] = panel.id
            }
        }

        guard !panels.isEmpty else { return false }
        store.seedRootPanels(panels)

        let rootPaneId = store.bonsplitController.allPaneIds.first?.id ?? UUID()
        let liveSections = snapshot.sections.compactMap { section -> SidebarDockSectionSnapshot? in
            let panelIds = section.tabs.compactMap { restoredPanelIdBySnapshotId[$0.id] }
            guard !panelIds.isEmpty else { return nil }
            return SidebarDockSectionSnapshot(
                sectionId: section.id,
                paneId: rootPaneId,
                tabPanelIds: panelIds,
                selectedPanelId: section.selectedTabId.flatMap { restoredPanelIdBySnapshotId[$0] },
                isCollapsed: section.isCollapsed,
                rememberedExtent: section.rememberedExtent.map { CGFloat($0) }
            )
        }
        guard !liveSections.isEmpty, store.rebuildSections(from: liveSections) else {
            return false
        }

        if let focusedSectionId = snapshot.focusedSectionId,
           let focused = store.sectionSnapshots().first(where: { $0.sectionId == focusedSectionId }) {
            store.bonsplitController.focusPane(PaneID(id: focused.paneId))
        }
        return true
    }

    private static func makePanel(
        from tab: SessionSidebarRailTabSnapshot,
        edge: SidebarDockEdge,
        workspace: Workspace,
        includeStokdWork: Bool
    ) -> (any Panel)? {
        switch (edge, PanelType(rawValue: tab.kind)) {
        case (.right, .rightSidebarTool):
            guard let persisted = try? JSONDecoder().decode(
                SessionRightSidebarToolPanelSnapshot.self,
                from: tab.payload
            ),
                  let mode = persisted.mode,
                  mode != .stokdWork || includeStokdWork,
                  SidebarDockPlacementMatrix.allows(mode: mode) else {
                return nil
            }
            return RightSidebarToolPanel(workspace: workspace, mode: mode)
        case (.left, .leftWorkspaceSelector):
            if !tab.payload.isEmpty,
               (try? JSONDecoder().decode(
                   SessionLeftWorkspaceSelectorPanelSnapshot.self,
                   from: tab.payload
               )) == nil {
                return nil
            }
            return LeftWorkspaceSelectorPanel(workspace: workspace)
        default:
            return nil
        }
    }
}

extension AppDelegate.MainWindowContext {
    func restorePendingSidebarDockSnapshots(
        into registry: SidebarDockStoreRegistry,
        workspace: Workspace,
        includeStokdWork: Bool
    ) {
        let leftSnapshot = pendingLeftRailSnapshot
        let rightSnapshot = pendingRightRailSnapshot
        pendingLeftRailSnapshot = nil
        pendingRightRailSnapshot = nil

        if let leftSnapshot {
            _ = SidebarDockSessionPersistence.restore(
                snapshot: leftSnapshot,
                into: registry.left,
                workspace: workspace,
                includeStokdWork: includeStokdWork
            )
        }
        if let rightSnapshot {
            _ = SidebarDockSessionPersistence.restore(
                snapshot: rightSnapshot,
                into: registry.right,
                workspace: workspace,
                includeStokdWork: includeStokdWork
            )
        }
    }
}
