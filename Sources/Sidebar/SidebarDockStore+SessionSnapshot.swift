import Bonsplit
import Foundation

extension SidebarDockStore {
    /// Capture the live rail as a rail-specific session envelope.
    ///
    /// Identity oracle is app-owned ``SidebarDockSectionID`` (never Bonsplit pane ids).
    /// Panel payloads are mode/selector only; no terminal scrollback is written.
    func sessionSnapshot() -> SessionSidebarDockSnapshot {
        let layoutCodec = SessionSplitContainerLayoutCodec(controller: bonsplitController)
        let rawLayout = layoutCodec.snapshot(panelIdForTabId: { [self] in surfaceIdToPanelId[$0] })
        let sections = sectionSnapshots()
        let panelSnapshots = orderedSessionPanelIds().compactMap { panelSessionSnapshot(panelId: $0) }
        let persistedPanelIds = Set(panelSnapshots.map(\.id))
        let layout = layoutCodec.pruned(rawLayout, keeping: persistedPanelIds)
            ?? .pane(SessionPaneLayoutSnapshot(panelIds: [], selectedPanelId: nil))

        let sectionIds = sections.map(\.sectionId)
        let collapsed = sections.filter(\.isCollapsed).map(\.sectionId)
        var extents: [String: Double] = [:]
        for section in sections {
            if let remembered = section.rememberedExtent {
                extents[section.sectionId.uuidString] = Double(remembered)
            }
        }

        let focused: UUID? = {
            if let pane = bonsplitController.focusedPaneId,
               let tab = bonsplitController.selectedTab(inPane: pane)
                ?? bonsplitController.tabs(inPane: pane).first,
               let panelId = surfaceIdToPanelId[tab.id],
               persistedPanelIds.contains(panelId) {
                return panelId
            }
            return sections.compactMap(\.selectedPanelId).first
        }()

        return SessionSidebarDockSnapshot(
            focusedPanelId: focused,
            layout: layout,
            panels: panelSnapshots,
            sectionIds: sectionIds.isEmpty ? nil : sectionIds,
            collapsedSectionIds: collapsed.isEmpty ? nil : collapsed,
            rememberedExtentsBySectionId: extents.isEmpty ? nil : extents
        )
    }

    /// Fingerprint of every persisted rail dimension (VAL-PERSIST-003).
    func sessionAutosaveFingerprint() -> Int {
        var hasher = Hasher()
        hasher.combine(edge.rawValue)
        hasher.combine(windowId)
        let sections = sectionSnapshots()
        hasher.combine(sections.count)
        for section in sections {
            hasher.combine(section.sectionId)
            // Never hash Bonsplit pane host ids.
            hasher.combine(section.tabPanelIds.count)
            for panelId in section.tabPanelIds {
                hasher.combine(panelId)
                if let tool = panels[panelId] as? RightSidebarToolPanel {
                    hasher.combine("tool")
                    hasher.combine(tool.mode.rawValue)
                } else if panels[panelId] is LeftWorkspaceSelectorPanel {
                    hasher.combine("selector")
                } else {
                    hasher.combine("unknown")
                }
            }
            hasher.combine(section.selectedPanelId)
            hasher.combine(section.isCollapsed)
            if let extent = section.rememberedExtent {
                hasher.combine(Int((extent * 1000).rounded()))
            } else {
                hasher.combine(-1)
            }
        }
        // Divider positions along the vertical chain.
        hashDividerPositions(bonsplitController.treeSnapshot(), into: &hasher)
        return hasher.finalize()
    }

    private func orderedSessionPanelIds() -> [UUID] {
        var result: [UUID] = []
        var seen: Set<UUID> = []
        for pane in orderedSectionPaneIds() {
            for tab in bonsplitController.tabs(inPane: pane) {
                guard let panelId = surfaceIdToPanelId[tab.id], seen.insert(panelId).inserted else {
                    continue
                }
                result.append(panelId)
            }
        }
        return result
    }

    private func panelSessionSnapshot(panelId: UUID) -> SessionPanelSnapshot? {
        guard let panel = panels[panelId] else { return nil }
        switch panel.panelType {
        case .rightSidebarTool:
            guard let tool = panel as? RightSidebarToolPanel,
                  SidebarDockPlacementMatrix.allows(mode: tool.mode) else {
                return nil
            }
            return SessionPanelSnapshot(
                id: panelId,
                stableSurfaceId: panel.stableSurfaceId,
                type: .rightSidebarTool,
                title: tool.displayTitle,
                customTitle: nil,
                directory: nil,
                isPinned: false,
                isManuallyUnread: false,
                gitBranch: nil,
                listeningPorts: [],
                ttyName: nil,
                terminal: nil,
                browser: nil,
                markdown: nil,
                filePreview: nil,
                rightSidebarTool: SessionRightSidebarToolPanelSnapshot(mode: tool.mode),
                leftWorkspaceSelector: nil
            )
        case .leftWorkspaceSelector:
            return SessionPanelSnapshot(
                id: panelId,
                stableSurfaceId: panel.stableSurfaceId,
                type: .leftWorkspaceSelector,
                title: panel.displayTitle,
                customTitle: nil,
                directory: nil,
                isPinned: false,
                isManuallyUnread: false,
                gitBranch: nil,
                listeningPorts: [],
                ttyName: nil,
                terminal: nil,
                browser: nil,
                markdown: nil,
                filePreview: nil,
                rightSidebarTool: nil,
                leftWorkspaceSelector: SessionLeftWorkspaceSelectorPanelSnapshot()
            )
        default:
            return nil
        }
    }

    private func hashDividerPositions(_ node: ExternalTreeNode, into hasher: inout Hasher) {
        switch node {
        case .pane:
            break
        case .split(let split):
            hasher.combine(split.orientation.lowercased())
            hasher.combine(Int((split.dividerPosition * 10_000).rounded()))
            hashDividerPositions(split.first, into: &hasher)
            hashDividerPositions(split.second, into: &hasher)
        }
    }
}

extension SidebarDockStoreRegistry {
    /// Combined fingerprint for both rails of a window.
    func sessionAutosaveFingerprint() -> Int {
        var hasher = Hasher()
        hasher.combine(windowId)
        hasher.combine(left.sessionAutosaveFingerprint())
        hasher.combine(right.sessionAutosaveFingerprint())
        return hasher.finalize()
    }

    /// Capture both rails when the flag is on; otherwise both nil (VAL-FLAG-004).
    func sessionWindowRailSnapshots(
        flagEnabled: Bool = RightSidebarBetaFeatureSettings.isSidebarDockEnabled()
    ) -> (left: SessionSidebarDockSnapshot?, right: SessionSidebarDockSnapshot?) {
        guard flagEnabled else { return (nil, nil) }
        let leftSnap = left.panels.isEmpty ? nil : left.sessionSnapshot()
        let rightSnap = right.panels.isEmpty ? nil : right.sessionSnapshot()
        return (leftSnap, rightSnap)
    }
}
