import Bonsplit
import Foundation
import os

extension SidebarDockStore {
    /// Outcome of restoring a rail session snapshot (VAL-PERSIST-002).
    struct SessionRestoreResult: Equatable, Sendable {
        var didReseedCanonical: Bool
        var didLogRecovery: Bool
        var restoredSectionCount: Int
        var prunedPanelCount: Int
    }

    private static let restoreLogger = Logger(
        subsystem: "ai.manaflow.cmux",
        category: "SidebarDockRestore"
    )

    /// Restore a pruned/repaired rail arrangement for the given workspace.
    ///
    /// - Invalid/disallowed panels are dropped.
    /// - One-sided invalid trees collapse.
    /// - All-invalid edges reseed the canonical nonempty rail and log once.
    @discardableResult
    func restoreSessionSnapshot(
        _ snapshot: SessionSidebarDockSnapshot?,
        workspace: Workspace,
        preferredLegacyMode: RightSidebarMode? = nil,
        recoveryLogSink: ((String) -> Void)? = nil
    ) -> SessionRestoreResult {
        guard let snapshot else {
            // No snapshot: first-use seed when empty (VAL-PERSIST-004).
            let seeded: Bool
            switch edge {
            case .left:
                seeded = SidebarDockSeeding.seedLeftIfEmpty(store: self, workspace: workspace)
            case .right:
                seeded = SidebarDockSeeding.seedRightIfEmpty(
                    store: self,
                    workspace: workspace,
                    preferredMode: preferredLegacyMode
                )
            }
            return SessionRestoreResult(
                didReseedCanonical: seeded,
                didLogRecovery: false,
                restoredSectionCount: sectionCount,
                prunedPanelCount: 0
            )
        }

        let prepared = Self.prepareRailSections(
            from: snapshot,
            edge: edge
        )

        if prepared.sections.isEmpty {
            clearRailContents()
            let seeded: Bool
            switch edge {
            case .left:
                seeded = SidebarDockSeeding.seedLeftIfEmpty(store: self, workspace: workspace)
            case .right:
                seeded = SidebarDockSeeding.seedRightIfEmpty(
                    store: self,
                    workspace: workspace,
                    preferredMode: preferredLegacyMode
                )
            }
            let message =
                "sidebar-dock: all-invalid \(edge.rawValue) rail reseeded window=\(windowId.uuidString)"
            Self.restoreLogger.error("\(message, privacy: .public)")
            recoveryLogSink?(message)
            return SessionRestoreResult(
                didReseedCanonical: seeded,
                didLogRecovery: true,
                restoredSectionCount: sectionCount,
                prunedPanelCount: prepared.prunedPanelCount
            )
        }

        clearRailContents()

        // Materialize every section expanded first. Collapse pins are keyed by
        // parent split ids; attaching a later section restructures the vertical
        // chain and expands/prunes those pins (moveTabToNewSection + prune).
        // Applying collapse after the final topology is stable is the only way
        // middle-section collapse survives N≥3 round-trips (VAL-PERSIST-001).
        for (index, section) in prepared.sections.enumerated() {
            let livePanels: [any Panel] = section.panelSpecs.compactMap { spec in
                makeRestoredPanel(spec: spec, workspace: workspace)
            }
            guard !livePanels.isEmpty else { continue }
            let selectedId: UUID? = {
                if let token = section.selectedToken {
                    return livePanels.first(where: { panelToken($0) == token })?.id
                        ?? livePanels.first?.id
                }
                return livePanels.first?.id
            }()
            let position: SidebarDockSectionPosition = index == 0 ? .top : .bottom
            // First section seeds the empty root; later sections append at bottom.
            if index == 0 {
                seedRootPanels(livePanels)
                if let selectedId, let tab = surfaceId(forPanelId: selectedId) {
                    _ = selectTab(tab)
                }
                if let root = orderedSectionPaneIds().first {
                    bindSectionId(section.sectionId, to: root)
                }
            } else {
                _ = attachSectionPanels(
                    livePanels,
                    selectedPanelId: selectedId,
                    sectionId: section.sectionId,
                    isCollapsed: false,
                    rememberedExtent: nil,
                    position: position
                )
            }
        }

        // Reattach every restored tool to the target workspace (VAL-CROSS-001 / D-15).
        reattachAllPanels(to: workspace)

        reconcileSectionIdentities()
        // Rebind durable ids onto the final host order before collapse pins.
        var livePanes = orderedSectionPaneIds()
        for (index, section) in prepared.sections.enumerated() where index < livePanes.count {
            bindSectionId(section.sectionId, to: livePanes[index])
        }

        // Apply divider positions while sections are still expanded so the
        // snapshot fractions land on live splits; collapse impositions follow.
        if prepared.sections.count == orderedSectionPaneIds().count {
            let layoutCodec = SessionSplitContainerLayoutCodec(controller: bonsplitController)
            layoutCodec.applyDividerPositions(
                snapshotNode: snapshot.layout,
                liveNode: bonsplitController.treeSnapshot()
            )
        }

        // Collapse last: pins attach to the final parent splits. Dropped /
        // unknown collapse markers never appear in prepared.sections and are
        // ignored (VAL-PERSIST-002).
        livePanes = orderedSectionPaneIds()
        for (index, section) in prepared.sections.enumerated() where index < livePanes.count {
            guard section.isCollapsed else { continue }
            let pane = livePanes[index]
            _ = collapseSection(paneId: pane)
            if let extent = section.rememberedExtent {
                if let parent = parentSplitId(of: pane) {
                    rememberedExtentBySplitId[parent] = extent
                } else if sectionCount == 1 {
                    soleSectionRememberedExtent = extent
                }
            }
        }

        // Reassert durable ids after collapse host churn (same as reorder path).
        livePanes = orderedSectionPaneIds()
        for (index, section) in prepared.sections.enumerated() where index < livePanes.count {
            bindSectionId(section.sectionId, to: livePanes[index])
        }
        refreshTabBarVisibility()
        publishFocusedToolModeMirror()

        return SessionRestoreResult(
            didReseedCanonical: false,
            didLogRecovery: false,
            restoredSectionCount: sectionCount,
            prunedPanelCount: prepared.prunedPanelCount
        )
    }

    /// Reattach every live panel to `workspace` (workspace switch / layout apply).
    func reattachAllPanels(to workspace: Workspace) {
        for panel in panels.values {
            if let tool = panel as? RightSidebarToolPanel {
                tool.reattach(to: workspace)
            } else if let selector = panel as? LeftWorkspaceSelectorPanel {
                selector.reattach(to: workspace)
            }
        }
    }

    // MARK: - Clear / build helpers

    /// Remove all live panels/tabs while keeping a single empty root pane.
    func clearRailContents() {
        for tabId in bonsplitController.allTabIds {
            surfaceIdToPanelId.removeValue(forKey: tabId)
            _ = bonsplitController.closeTab(tabId)
        }
        panels.removeAll(keepingCapacity: true)
        surfaceIdToPanelId.removeAll(keepingCapacity: true)
        sectionIdByPaneHost.removeAll(keepingCapacity: true)
        collapsedSplitIds.removeAll(keepingCapacity: true)
        rememberedExtentBySplitId.removeAll(keepingCapacity: true)
        trailingCollapsedParentSplitId = nil
        isSoleSectionCollapsed = false
        soleSectionRememberedExtent = nil
        lastExpandedPaneId = nil
        pendingCollapsePaneIds.removeAll()
        // Closing the last tabs may leave one empty root; mint a durable id for it.
        if let root = bonsplitController.allPaneIds.first {
            _ = sectionId(forPane: root)
        }
        refreshTabBarVisibility()
    }

    // MARK: - Preparation

    fileprivate struct RestoredPanelSpec: Equatable {
        var oldPanelId: UUID
        var token: String
        var mode: RightSidebarMode?
    }

    fileprivate struct PreparedSection: Equatable {
        var sectionId: SidebarDockSectionID
        var panelSpecs: [RestoredPanelSpec]
        var selectedToken: String?
        var isCollapsed: Bool
        var rememberedExtent: CGFloat?
    }

    fileprivate struct PreparedRail {
        var sections: [PreparedSection]
        var prunedPanelCount: Int
        var oldToNewPanelIds: [UUID: UUID]
    }

    fileprivate static func prepareRailSections(
        from snapshot: SessionSidebarDockSnapshot,
        edge: SidebarDockEdge
    ) -> PreparedRail {
        let panelById = Dictionary(uniqueKeysWithValues: snapshot.panels.map { ($0.id, $0) })
        let leaves = flattenPaneLeaves(snapshot.layout)
        let sectionIds = snapshot.sectionIds ?? []
        let collapsed = Set(snapshot.collapsedSectionIds ?? [])
        let extents = snapshot.rememberedExtentsBySectionId ?? [:]

        var sections: [PreparedSection] = []
        var pruned = 0
        // oldToNew is filled at materialization time; preparation keeps identity map empty.
        var oldToNew: [UUID: UUID] = [:]

        for (index, leaf) in leaves.enumerated() {
            var specs: [RestoredPanelSpec] = []
            for panelId in leaf.panelIds {
                guard let panelSnap = panelById[panelId] else {
                    pruned += 1
                    continue
                }
                guard let spec = acceptedPanelSpec(panelSnap, edge: edge) else {
                    pruned += 1
                    continue
                }
                specs.append(spec)
            }
            guard !specs.isEmpty else {
                pruned += leaf.panelIds.count
                continue
            }

            let stableId: SidebarDockSectionID = {
                if index < sectionIds.count {
                    return SidebarDockSectionID(sectionIds[index])
                }
                return SidebarDockSectionID()
            }()

            let selectedToken: String? = {
                if let selected = leaf.selectedPanelId,
                   let panelSnap = panelById[selected],
                   let spec = acceptedPanelSpec(panelSnap, edge: edge) {
                    return spec.token
                }
                return specs.first?.token
            }()

            let remembered: CGFloat? = {
                if let raw = extents[stableId.uuidString] {
                    return CGFloat(raw)
                }
                return nil
            }()

            sections.append(
                PreparedSection(
                    sectionId: stableId,
                    panelSpecs: specs,
                    selectedToken: selectedToken,
                    isCollapsed: collapsed.contains(stableId.rawValue),
                    rememberedExtent: remembered
                )
            )
            for spec in specs {
                // Placeholder identity — real id assigned when panels are created.
                oldToNew[spec.oldPanelId] = spec.oldPanelId
            }
        }

        // If layout had no leaves but panels exist, treat as one section.
        if sections.isEmpty, !snapshot.panels.isEmpty {
            var specs: [RestoredPanelSpec] = []
            for panelSnap in snapshot.panels {
                guard let spec = acceptedPanelSpec(panelSnap, edge: edge) else {
                    pruned += 1
                    continue
                }
                specs.append(spec)
            }
            if !specs.isEmpty {
                let stableId = sectionIds.first.map(SidebarDockSectionID.init) ?? SidebarDockSectionID()
                sections.append(
                    PreparedSection(
                        sectionId: stableId,
                        panelSpecs: specs,
                        selectedToken: specs.first?.token,
                        isCollapsed: collapsed.contains(stableId.rawValue),
                        rememberedExtent: extents[stableId.uuidString].map { CGFloat($0) }
                    )
                )
            }
        }

        return PreparedRail(sections: sections, prunedPanelCount: pruned, oldToNewPanelIds: oldToNew)
    }

    fileprivate static func acceptedPanelSpec(
        _ snapshot: SessionPanelSnapshot,
        edge: SidebarDockEdge
    ) -> RestoredPanelSpec? {
        switch snapshot.type {
        case .rightSidebarTool:
            guard let mode = snapshot.rightSidebarTool?.mode,
                  SidebarDockPlacementMatrix.allows(mode: mode) else {
                return nil
            }
            // Left rail may host tools after cross-rail move.
            return RestoredPanelSpec(
                oldPanelId: snapshot.id,
                token: mode.rawValue,
                mode: mode
            )
        case .leftWorkspaceSelector:
            return RestoredPanelSpec(
                oldPanelId: snapshot.id,
                token: CmuxSidebarDockDefinition.workspaceSelectorToken,
                mode: nil
            )
        default:
            return nil
        }
    }

    fileprivate static func flattenPaneLeaves(
        _ node: SessionWorkspaceLayoutSnapshot
    ) -> [SessionPaneLayoutSnapshot] {
        switch node {
        case .pane(let pane):
            return [pane]
        case .split(let split):
            // Rails are vertical chains; walk pre-order first-then-second.
            return flattenPaneLeaves(split.first) + flattenPaneLeaves(split.second)
        }
    }

    private func makeRestoredPanel(spec: RestoredPanelSpec, workspace: Workspace) -> (any Panel)? {
        if let mode = spec.mode {
            return RightSidebarToolPanel(workspace: workspace, mode: mode)
        }
        if spec.token == CmuxSidebarDockDefinition.workspaceSelectorToken {
            return LeftWorkspaceSelectorPanel(workspace: workspace)
        }
        return nil
    }

    private func panelToken(_ panel: any Panel) -> String {
        if let tool = panel as? RightSidebarToolPanel {
            return tool.mode.rawValue
        }
        if panel is LeftWorkspaceSelectorPanel {
            return CmuxSidebarDockDefinition.workspaceSelectorToken
        }
        return panel.id.uuidString
    }

    private func remapLayoutPanelIds(
        _ node: SessionWorkspaceLayoutSnapshot,
        oldToNew: [UUID: UUID]
    ) -> SessionWorkspaceLayoutSnapshot {
        switch node {
        case .pane(let pane):
            let mapped = pane.panelIds.compactMap { oldToNew[$0] ?? $0 }
            let selected = pane.selectedPanelId.flatMap { oldToNew[$0] ?? $0 }
            return .pane(SessionPaneLayoutSnapshot(
                panelIds: mapped,
                selectedPanelId: selected.flatMap { mapped.contains($0) ? $0 : mapped.first },
                isFullWidthTabMode: pane.isFullWidthTabMode
            ))
        case .split(let split):
            return .split(SessionSplitLayoutSnapshot(
                orientation: split.orientation,
                dividerPosition: split.dividerPosition,
                first: remapLayoutPanelIds(split.first, oldToNew: oldToNew),
                second: remapLayoutPanelIds(split.second, oldToNew: oldToNew)
            ))
        }
    }
}

extension SidebarDockStoreRegistry {
    /// Restore both rails from a window session snapshot.
    /// Returns true when either rail performed an all-invalid reseed (autosave repair).
    @discardableResult
    func restoreSessionRails(
        leftSnapshot: SessionSidebarDockSnapshot?,
        rightSnapshot: SessionSidebarDockSnapshot?,
        workspace: Workspace,
        preferredLegacyMode: RightSidebarMode?,
        recoveryLogSink: ((String) -> Void)? = nil
    ) -> (left: SidebarDockStore.SessionRestoreResult, right: SidebarDockStore.SessionRestoreResult) {
        let leftResult = left.restoreSessionSnapshot(
            leftSnapshot,
            workspace: workspace,
            preferredLegacyMode: nil,
            recoveryLogSink: recoveryLogSink
        )
        let rightResult = right.restoreSessionSnapshot(
            rightSnapshot,
            workspace: workspace,
            preferredLegacyMode: preferredLegacyMode,
            recoveryLogSink: recoveryLogSink
        )
        return (leftResult, rightResult)
    }

    /// Apply a UUID-free named-layout rail definition to this window's rails.
    @discardableResult
    func applyNamedLayoutDefinition(
        _ definition: CmuxSidebarDockDefinition,
        workspace: Workspace,
        preferredLegacyMode: RightSidebarMode? = nil
    ) -> Bool {
        var ok = true
        if let leftRail = definition.left {
            ok = applyRailDefinition(leftRail, to: left, workspace: workspace, preferredLegacyMode: nil) && ok
        }
        if let rightRail = definition.right {
            ok = applyRailDefinition(
                rightRail,
                to: right,
                workspace: workspace,
                preferredLegacyMode: preferredLegacyMode
            ) && ok
        }
        return ok
    }

    /// Capture UUID-free rail definitions from this window.
    func captureNamedLayoutDefinition() -> CmuxSidebarDockDefinition {
        CmuxSidebarDockDefinition(
            left: captureRailDefinition(left),
            right: captureRailDefinition(right)
        )
    }

    private func captureRailDefinition(_ store: SidebarDockStore) -> CmuxSidebarDockDefinition.Rail? {
        let sections = store.sectionSnapshots()
        guard !sections.isEmpty else { return nil }
        // Equal weights when capturing from live divider geometry is fine;
        // encode proportional shares from successive divider positions.
        let weights = proportionalWeights(from: store)
        var defs: [CmuxSidebarDockDefinition.Section] = []
        for (index, section) in sections.enumerated() {
            let tokens: [String] = section.tabPanelIds.compactMap { panelId in
                guard let panel = store.panels[panelId] else { return nil }
                if let tool = panel as? RightSidebarToolPanel {
                    return tool.mode.rawValue
                }
                if panel is LeftWorkspaceSelectorPanel {
                    return CmuxSidebarDockDefinition.workspaceSelectorToken
                }
                return nil
            }
            guard !tokens.isEmpty else { continue }
            let selectedToken: String? = {
                guard let selected = section.selectedPanelId,
                      let panel = store.panels[selected] else {
                    return tokens.first
                }
                if let tool = panel as? RightSidebarToolPanel {
                    return tool.mode.rawValue
                }
                if panel is LeftWorkspaceSelectorPanel {
                    return CmuxSidebarDockDefinition.workspaceSelectorToken
                }
                return tokens.first
            }()
            defs.append(
                CmuxSidebarDockDefinition.Section(
                    panels: tokens,
                    selected: selectedToken,
                    collapsed: section.isCollapsed ? true : nil,
                    weight: index < weights.count ? weights[index] : nil
                )
            )
        }
        guard !defs.isEmpty else { return nil }
        return CmuxSidebarDockDefinition.Rail(sections: defs)
    }

    private func proportionalWeights(from store: SidebarDockStore) -> [Double] {
        let count = store.sectionCount
        guard count > 0 else { return [] }
        // Walk divider chain for first-child fractions.
        var shares: [Double] = []
        func walk(_ node: ExternalTreeNode, remaining: Double) {
            switch node {
            case .pane:
                shares.append(remaining)
            case .split(let split):
                let pos = max(0.0, min(1.0, split.dividerPosition))
                walk(split.first, remaining: remaining * pos)
                walk(split.second, remaining: remaining * (1.0 - pos))
            }
        }
        walk(store.bonsplitController.treeSnapshot(), remaining: 1.0)
        if shares.count != count {
            return Array(repeating: 1.0 / Double(count), count: count)
        }
        let sum = shares.reduce(0, +)
        guard sum > 0 else {
            return Array(repeating: 1.0 / Double(count), count: count)
        }
        return shares.map { $0 / sum }
    }

    private func applyRailDefinition(
        _ rail: CmuxSidebarDockDefinition.Rail,
        to store: SidebarDockStore,
        workspace: Workspace,
        preferredLegacyMode: RightSidebarMode?
    ) -> Bool {
        let repaired = Self.repairRailDefinition(rail, edge: store.edge)
        if repaired.sections.isEmpty {
            store.clearRailContents()
            switch store.edge {
            case .left:
                return SidebarDockSeeding.seedLeftIfEmpty(store: store, workspace: workspace)
            case .right:
                return SidebarDockSeeding.seedRightIfEmpty(
                    store: store,
                    workspace: workspace,
                    preferredMode: preferredLegacyMode
                )
            }
        }

        store.clearRailContents()
        let weights = CmuxSidebarDockDefinition.normalizedWeights(for: repaired.sections)

        for (index, section) in repaired.sections.enumerated() {
            let panels: [any Panel] = section.panels.compactMap { token in
                makePanel(token: token, workspace: workspace)
            }
            guard !panels.isEmpty else { continue }
            let selectedId: UUID? = {
                if let selected = section.selected,
                   let match = panels.first(where: { panelToken($0) == selected }) {
                    return match.id
                }
                return panels.first?.id
            }()
            let sectionId = SidebarDockSectionID()
            if index == 0 {
                store.seedRootPanels(panels)
                if let selectedId, let tab = store.surfaceId(forPanelId: selectedId) {
                    _ = store.selectTab(tab)
                }
                if let root = store.orderedSectionPaneIds().first {
                    store.bindSectionId(sectionId, to: root)
                }
                if section.collapsed == true, let pane = store.orderedSectionPaneIds().first {
                    _ = store.collapseSection(paneId: pane)
                }
            } else {
                _ = store.attachSectionPanels(
                    panels,
                    selectedPanelId: selectedId,
                    sectionId: sectionId,
                    isCollapsed: section.collapsed == true,
                    rememberedExtent: nil,
                    position: .bottom
                )
            }
        }

        store.reattachAllPanels(to: workspace)

        // Apply normalized weights as successive divider positions.
        let positions = CmuxSidebarDockDefinition.dividerPositions(fromNormalizedWeights: weights)
        applyDividerChain(positions, on: store)

        store.reconcileSectionIdentities()
        store.refreshTabBarVisibility()
        store.publishFocusedToolModeMirror()
        return store.sectionCount > 0
    }

    /// Prune unknown tokens; empty rail → empty sections (caller reseeds).
    static func repairRailDefinition(
        _ rail: CmuxSidebarDockDefinition.Rail,
        edge: SidebarDockEdge
    ) -> CmuxSidebarDockDefinition.Rail {
        var sections: [CmuxSidebarDockDefinition.Section] = []
        for section in rail.sections {
            let panels = section.panels.filter { token in
                if token == CmuxSidebarDockDefinition.workspaceSelectorToken {
                    return true
                }
                guard let mode = RightSidebarMode(rawValue: token) else { return false }
                return SidebarDockPlacementMatrix.allows(mode: mode)
            }
            guard !panels.isEmpty else { continue }
            let selected: String? = {
                if let selected = section.selected, panels.contains(selected) {
                    return selected
                }
                return panels.first
            }()
            sections.append(
                CmuxSidebarDockDefinition.Section(
                    panels: panels,
                    selected: selected,
                    collapsed: section.collapsed,
                    weight: section.weight
                )
            )
        }
        return CmuxSidebarDockDefinition.Rail(sections: sections)
    }

    private func makePanel(token: String, workspace: Workspace) -> (any Panel)? {
        if token == CmuxSidebarDockDefinition.workspaceSelectorToken {
            return LeftWorkspaceSelectorPanel(workspace: workspace)
        }
        guard let mode = RightSidebarMode(rawValue: token),
              SidebarDockPlacementMatrix.allows(mode: mode) else {
            return nil
        }
        return RightSidebarToolPanel(workspace: workspace, mode: mode)
    }

    private func panelToken(_ panel: any Panel) -> String {
        if let tool = panel as? RightSidebarToolPanel {
            return tool.mode.rawValue
        }
        if panel is LeftWorkspaceSelectorPanel {
            return CmuxSidebarDockDefinition.workspaceSelectorToken
        }
        return panel.id.uuidString
    }

    private func applyDividerChain(_ positions: [Double], on store: SidebarDockStore) {
        // Walk the live vertical chain and set divider positions in pre-order.
        var remaining = positions
        func apply(_ node: ExternalTreeNode) {
            switch node {
            case .pane:
                break
            case .split(let split):
                if let id = UUID(uuidString: split.id), !remaining.isEmpty {
                    let pos = remaining.removeFirst()
                    _ = store.bonsplitController.setDividerPosition(
                        CGFloat(pos),
                        forSplit: id,
                        fromExternal: true
                    )
                }
                apply(split.first)
                apply(split.second)
            }
        }
        apply(store.bonsplitController.treeSnapshot())
    }
}


