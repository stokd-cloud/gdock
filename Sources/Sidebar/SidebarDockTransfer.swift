import Bonsplit
import Foundation
import os

/// One shared production transfer path for cross-rail tool-tab and whole-section moves.
///
/// Header drag, tab drag, localized palette/context commands, external Bonsplit
/// drop, and DEBUG dogfood all converge here so actor surfaces cannot diverge
/// (VAL-MOVE-001/002/003).
@MainActor
enum SidebarDockTransfer {
    private static let logger = Logger(subsystem: "ai.manaflow.cmux", category: "SidebarDockTransfer")

    // MARK: - Destination / outcome

    /// Where a transferred tab lands on the destination rail.
    enum TabDestination: Equatable, Sendable {
        /// Insert into an existing section (selected / focused when nil).
        case intoSelectedSection(paneId: UUID? = nil, atIndex: Int? = nil)
        /// Create a new vertical section at the top or bottom of the dest rail.
        case newVerticalSection(position: SidebarDockSectionPosition)
        /// Horizontal split destination — always refused losslessly.
        case horizontalSplit
    }

    /// Where a whole section lands on the destination rail.
    enum SectionDestination: Equatable, Sendable {
        case top
        case bottom
        case horizontalSplit
    }

    enum Outcome: Equatable, Sendable {
        case moved
        case refused(Reason)

        var isSuccess: Bool {
            if case .moved = self { return true }
            return false
        }

        var reasonCode: String {
            switch self {
            case .moved: return "moved"
            case .refused(let reason): return reason.rawValue
            }
        }
    }

    enum Reason: String, Equatable, Sendable {
        case emptyRailGuard
        case placement
        case horizontal
        case missingSource
        case payloadMismatch
        case sameEdgeNoop
        case unknown
    }

    // MARK: - Tab transfer

    /// Move a live tool panel between rails without recreating it.
    ///
    /// Preserves `panel.id` and `stableSurfaceIdentity`. Bonsplit tab ids may
    /// change (new host controller); app-owned panel identity does not.
    @discardableResult
    static func moveTab(
        registry: SidebarDockStoreRegistry,
        panelId: UUID,
        from sourceEdge: SidebarDockEdge,
        to destEdge: SidebarDockEdge,
        destination: TabDestination
    ) -> Outcome {
        if case .horizontalSplit = destination {
            return .refused(.horizontal)
        }
        guard sourceEdge != destEdge else {
            return .refused(.sameEdgeNoop)
        }

        // RED STUB: intentional refuse so CrossRail suite fails before green impl.
        return .refused(.unknown)

        let source = registry.store(for: sourceEdge)
        let dest = registry.store(for: destEdge)

        let sourceBefore = completeRailFingerprint(source)
        let destBefore = completeRailFingerprint(dest)

        guard let panel = source.panels[panelId],
              let sourceTabId = source.surfaceId(forPanelId: panelId) else {
            return .refused(.missingSource)
        }
        guard SidebarDockPlacementMatrix.allows(panel: panel) else {
            return losslessRefuse(source: source, dest: dest, before: (sourceBefore, destBefore), reason: .placement)
        }
        if source.wouldEmptyRail(removing: sourceTabId) {
            return losslessRefuse(source: source, dest: dest, before: (sourceBefore, destBefore), reason: .emptyRailGuard)
        }

        // Snapshot identities before topology mutates.
        let preservedPanelId = panel.id
        let preservedSurfaceId = panel.stableSurfaceId

        guard let detached = source.detachPanelKeepingInstance(panelId: panelId) else {
            return losslessRefuse(source: source, dest: dest, before: (sourceBefore, destBefore), reason: .unknown)
        }
        // Detach must not empty source (guarded above); verify.
        if source.panels.isEmpty {
            // Roll back if detach left an empty rail unexpectedly.
            _ = source.attachPanel(detached, select: false)
            return losslessRefuse(source: source, dest: dest, before: (sourceBefore, destBefore), reason: .emptyRailGuard)
        }

        let attached: TabID?
        switch destination {
        case .horizontalSplit:
            _ = source.attachPanel(detached, select: false)
            return losslessRefuse(source: source, dest: dest, before: (sourceBefore, destBefore), reason: .horizontal)
        case .intoSelectedSection(let paneUUID, let atIndex):
            let targetPane: PaneID? = {
                if let paneUUID {
                    return dest.orderedSectionPaneIds().first(where: { $0.id == paneUUID })
                }
                return dest.bonsplitController.focusedPaneId
                    ?? dest.orderedSectionPaneIds().first
            }()
            attached = dest.attachPanel(detached, inPane: targetPane, select: true)
            if let attached, let atIndex {
                _ = dest.reorderTab(attached, toIndex: atIndex)
            }
        case .newVerticalSection(let position):
            attached = dest.attachPanelAsNewVerticalSection(detached, position: position)
        }

        guard attached != nil,
              dest.panels[preservedPanelId] != nil,
              dest.panels[preservedPanelId]?.stableSurfaceId == preservedSurfaceId,
              source.panels[preservedPanelId] == nil else {
            // Attach failed — restore source.
            if dest.panels[preservedPanelId] != nil {
                _ = dest.detachPanelKeepingInstance(panelId: preservedPanelId)
            }
            _ = source.attachPanel(detached, select: false)
            return losslessRefuse(source: source, dest: dest, before: (sourceBefore, destBefore), reason: .unknown)
        }

        source.reconcileAfterCrossRailMutation()
        dest.reconcileAfterCrossRailMutation()
        return .moved
    }

    // MARK: - Section transfer

    /// Move a whole section between rails, preserving tab order, selection,
    /// collapse, remembered extent, and app-owned section id.
    @discardableResult
    static func moveSection(
        registry: SidebarDockStoreRegistry,
        sectionId: SidebarDockSectionID,
        from sourceEdge: SidebarDockEdge,
        to destEdge: SidebarDockEdge,
        destination: SectionDestination
    ) -> Outcome {
        if case .horizontalSplit = destination {
            return .refused(.horizontal)
        }
        guard sourceEdge != destEdge else {
            return .refused(.sameEdgeNoop)
        }

        // RED STUB: intentional refuse so CrossRail suite fails before green impl.
        return .refused(.unknown)

        let source = registry.store(for: sourceEdge)
        let dest = registry.store(for: destEdge)
        let sourceBefore = completeRailFingerprint(source)
        let destBefore = completeRailFingerprint(dest)

        if source.wouldEmptyRail(removingSection: sectionId) {
            return losslessRefuse(source: source, dest: dest, before: (sourceBefore, destBefore), reason: .emptyRailGuard)
        }

        guard let capture = source.captureSectionForCrossRailTransfer(sectionId: sectionId) else {
            return .refused(.missingSource)
        }
        // Placement: every panel must be allowed on a rail.
        for panel in capture.panels {
            guard SidebarDockPlacementMatrix.allows(panel: panel) else {
                return losslessRefuse(source: source, dest: dest, before: (sourceBefore, destBefore), reason: .placement)
            }
        }

        // Detach every panel in reverse order so empty-pane teardown is stable.
        var detachedPanels: [any Panel] = []
        for panel in capture.panels.reversed() {
            guard let live = source.detachPanelKeepingInstance(panelId: panel.id) else {
                // Roll back already-detached panels.
                for panel in detachedPanels.reversed() {
                    _ = source.attachPanel(panel, select: false)
                }
                return losslessRefuse(source: source, dest: dest, before: (sourceBefore, destBefore), reason: .unknown)
            }
            detachedPanels.insert(live, at: 0)
        }

        if source.panels.isEmpty {
            for panel in detachedPanels.reversed() {
                _ = source.attachPanel(panel, select: false)
            }
            return losslessRefuse(source: source, dest: dest, before: (sourceBefore, destBefore), reason: .emptyRailGuard)
        }

        let position: SidebarDockSectionPosition = {
            switch destination {
            case .top: return .top
            case .bottom: return .bottom
            case .horizontalSplit: return .bottom
            }
        }()

        guard dest.attachSectionPanels(
            detachedPanels,
            selectedPanelId: capture.selectedPanelId,
            sectionId: capture.sectionId,
            isCollapsed: capture.isCollapsed,
            rememberedExtent: capture.rememberedExtent,
            position: position
        ) else {
            for panel in detachedPanels.reversed() {
                _ = source.attachPanel(panel, select: false)
            }
            return losslessRefuse(source: source, dest: dest, before: (sourceBefore, destBefore), reason: .unknown)
        }

        source.reconcileAfterCrossRailMutation()
        dest.reconcileAfterCrossRailMutation()
        return .moved
    }

    // MARK: - Payload-driven transfer (drag decode)

    /// Decode a pasteboard / provider payload and run the shared transfer path.
    @discardableResult
    static func moveFromPayload(
        registry: SidebarDockStoreRegistry,
        payload: SidebarDockTransferPayload,
        to destEdge: SidebarDockEdge,
        tabDestination: TabDestination = .newVerticalSection(position: .bottom),
        sectionDestination: SectionDestination = .bottom
    ) -> Outcome {
        // Payload isolation: wrong window is a refuse without mutation.
        guard payload.windowId == registry.windowId else {
            return .refused(.payloadMismatch)
        }
        guard let sourceEdge = SidebarDockEdge(rawValue: payload.sourceEdge) else {
            return .refused(.payloadMismatch)
        }
        switch payload.kind {
        case .tab:
            guard let panelId = payload.panelIds.first else {
                return .refused(.missingSource)
            }
            return moveTab(
                registry: registry,
                panelId: panelId,
                from: sourceEdge,
                to: destEdge,
                destination: tabDestination
            )
        case .section:
            guard let sectionUUID = payload.sectionId else {
                return .refused(.payloadMismatch)
            }
            return moveSection(
                registry: registry,
                sectionId: SidebarDockSectionID(sectionUUID),
                from: sourceEdge,
                to: destEdge,
                destination: sectionDestination
            )
        }
    }

    /// Attempt to decode workspace-row reorder as a rail transfer — must fail.
    static func decodeRailTransfer(fromWorkspaceRow raw: String?) -> SidebarDockTransferPayload? {
        // Workspace rows use `cmux.sidebar-tab.<uuid>` and never the rail JSON type.
        guard let raw, raw.hasPrefix(SidebarTabDragPayload.prefix) else { return nil }
        // Explicit isolation: never construct a rail transfer from a workspace id.
        return nil
    }

    // MARK: - External Bonsplit drop (cross-rail + same-rail)

    /// Shared external-drop entry used by each rail store's `onExternalTabDrop`.
    @discardableResult
    static func handleExternalDrop(
        registry: SidebarDockStoreRegistry,
        targetEdge: SidebarDockEdge,
        request: BonsplitController.ExternalTabDropRequest
    ) -> Bool {
        let dest = registry.store(for: targetEdge)
        let sourceEdge: SidebarDockEdge?
        let panelId: UUID?

        // Locate which rail owns this Bonsplit tab id.
        if dest.surfaceIdToPanelId[request.tabId] != nil {
            // Same-rail external path (unusual but valid): reuse drop handler.
            return SidebarDockDropHandler.handleExternal(store: dest, request: request)
        }
        let other: SidebarDockEdge = targetEdge == .left ? .right : .left
        let source = registry.store(for: other)
        if let pid = source.surfaceIdToPanelId[request.tabId] {
            sourceEdge = other
            panelId = pid
        } else {
            // Unknown tab — placement refuse, no mutation.
            return false
        }

        guard let sourceEdge, let panelId else { return false }

        let destination: TabDestination
        switch request.destination {
        case .insert(let targetPane, let index):
            destination = .intoSelectedSection(paneId: targetPane.id, atIndex: index)
        case .split(_, let orientation, let insertFirst):
            if orientation != .vertical {
                // Must route horizontal through veto path without mutation.
                // Calling shouldSplitPane documents the veto for dogfood.
                if let pane = dest.orderedSectionPaneIds().first {
                    _ = dest.splitTabBar(
                        dest.bonsplitController,
                        shouldSplitPane: pane,
                        orientation: .horizontal
                    )
                }
                return false
            }
            destination = .newVerticalSection(position: insertFirst ? .top : .bottom)
        }

        let outcome = moveTab(
            registry: registry,
            panelId: panelId,
            from: sourceEdge,
            to: targetEdge,
            destination: destination
        )
        return outcome.isSuccess
    }

    // MARK: - Payload builders

    static func makeTabPayload(
        registry: SidebarDockStoreRegistry,
        edge: SidebarDockEdge,
        panelId: UUID
    ) -> SidebarDockTransferPayload? {
        let store = registry.store(for: edge)
        guard store.panels[panelId] != nil else { return nil }
        return SidebarDockTransferPayload(
            kind: .tab,
            windowId: registry.windowId,
            sourceEdge: edge.rawValue,
            panelIds: [panelId],
            sectionId: nil,
            selectedPanelId: panelId,
            isCollapsed: nil,
            rememberedExtent: nil
        )
    }

    static func makeSectionPayload(
        registry: SidebarDockStoreRegistry,
        edge: SidebarDockEdge,
        sectionId: SidebarDockSectionID
    ) -> SidebarDockTransferPayload? {
        let store = registry.store(for: edge)
        guard let capture = store.captureSectionForCrossRailTransfer(sectionId: sectionId) else {
            return nil
        }
        return SidebarDockTransferPayload(
            kind: .section,
            windowId: registry.windowId,
            sourceEdge: edge.rawValue,
            panelIds: capture.panels.map { $0.id },
            sectionId: capture.sectionId.rawValue,
            selectedPanelId: capture.selectedPanelId,
            isCollapsed: capture.isCollapsed,
            rememberedExtent: capture.rememberedExtent.map { Double($0) }
        )
    }

    // MARK: - Fingerprints (lossless refuse)

    struct RailFingerprint: Equatable {
        var panelIds: Set<UUID>
        var sectionIds: [UUID]
        var tabPanelOrders: [[UUID]]
        var panelCount: Int
        var tabCount: Int
    }

    static func completeRailFingerprint(_ store: SidebarDockStore) -> RailFingerprint {
        let snaps = store.sectionSnapshots()
        return RailFingerprint(
            panelIds: Set(store.panels.keys),
            sectionIds: snaps.map(\.sectionId),
            tabPanelOrders: snaps.map(\.tabPanelIds),
            panelCount: store.panels.count,
            tabCount: store.surfaceIdToPanelId.count
        )
    }

    private static func losslessRefuse(
        source: SidebarDockStore,
        dest: SidebarDockStore,
        before: (RailFingerprint, RailFingerprint),
        reason: Reason
    ) -> Outcome {
        let afterSource = completeRailFingerprint(source)
        let afterDest = completeRailFingerprint(dest)
        if afterSource != before.0 || afterDest != before.1 {
            logger.error(
                "sidebar-dock: transfer refuse was not lossless reason=\(reason.rawValue, privacy: .public)"
            )
        }
        return .refused(reason)
    }
}
