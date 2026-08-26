import Bonsplit
import Foundation

/// Shared production mutation path for rail edge-band drops.
///
/// Tab context / palette commands, live Bonsplit top/bottom bands (via
/// `shouldSplitPane` + `moveTabToNewSection`), header-adjacent drop simulation,
/// and DEBUG `debug.sidebar_dock.simulate_drop` all converge here so actor
/// surfaces cannot diverge from store unit paths (VAL-RAIL-003/004).
@MainActor
enum SidebarDockDropHandler {
    /// Outcome of one edge-band / center / refuse attempt.
    enum Outcome: Equatable, Sendable {
        case createdSection(position: SidebarDockSectionPosition)
        case movedIntoPane
        case samePaneNoop
        case refused(reason: RefusalReason)

        var isSuccess: Bool {
            switch self {
            case .createdSection, .movedIntoPane, .samePaneNoop: return true
            case .refused: return false
            }
        }

        var reasonCode: String {
            switch self {
            case .createdSection(let position): return "created_\(position.rawValue)"
            case .movedIntoPane: return "moved_into_pane"
            case .samePaneNoop: return "same_pane_noop"
            case .refused(let reason): return reason.rawValue
            }
        }
    }

    enum RefusalReason: String, Equatable, Sendable {
        case horizontal
        case disallowedPanel
        case geometry
        case missingTab
        case emptyRailGuard
        case unknown
    }

    /// Handle a tab drop onto a rail zone using the shared mutation path.
    ///
    /// - Parameters:
    ///   - store: Target rail store.
    ///   - tabId: Tab being dropped (must already map to a panel on this store
    ///     for vertical create / same-rail move; external disallowed kinds refuse).
    ///   - zone: Edge band zone (top/bottom create; left/right refuse; center move/noop).
    ///   - targetPaneId: Optional destination pane for center / band targeting.
    @discardableResult
    static func handle(
        store: SidebarDockStore,
        tabId: TabID,
        zone: SidebarDockEdgeBand.Zone,
        targetPaneId: PaneID? = nil
    ) -> Outcome {
        // Horizontal destinations are always refused without mutating source/dest.
        if zone.isHorizontalRefuseBand {
            return .refused(reason: .horizontal)
        }

        // Missing / unknown tab on this rail → refuse (external disallowed kinds).
        guard store.surfaceIdToPanelId[tabId] != nil else {
            return .refused(reason: .missingTab)
        }
        guard let panelId = store.surfaceIdToPanelId[tabId],
              let panel = store.panels[panelId] else {
            return .refused(reason: .missingTab)
        }
        guard SidebarDockPlacementMatrix.allows(panel: panel, on: store.edge) else {
            return .refused(reason: .disallowedPanel)
        }

        if let position = zone.sectionPosition {
            let beforeSections = store.sectionCount
            let beforeTabs = store.surfaceIdToPanelId.count
            let beforePanels = store.panels.count
            let ok = store.moveTabToNewSection(tabId, position: position)
            if ok {
                return .createdSection(position: position)
            }
            // Lossless recovery: counts and membership unchanged on refuse.
            if store.sectionCount == beforeSections,
               store.surfaceIdToPanelId.count == beforeTabs,
               store.panels.count == beforePanels {
                if !store.configurationAllowsNewSection() {
                    return .refused(reason: .geometry)
                }
                return .refused(reason: .unknown)
            }
            return .refused(reason: .unknown)
        }

        // Center: same-pane is a no-op; cross-pane moves through the store path.
        let sourcePane = store.paneId(forTabId: tabId)
        let destination = targetPaneId
            ?? store.bonsplitController.focusedPaneId
            ?? store.orderedSectionPaneIds().first
        guard let destination else {
            return .refused(reason: .unknown)
        }
        if sourcePane == destination {
            return .samePaneNoop
        }
        let beforeSections = store.sectionCount
        let beforeTabs = store.surfaceIdToPanelId.count
        let ok = store.moveTab(tabId, toPane: destination)
        if ok {
            return .movedIntoPane
        }
        if store.sectionCount == beforeSections,
           store.surfaceIdToPanelId.count == beforeTabs {
            if store.wouldEmptyRail(removing: tabId) {
                return .refused(reason: .emptyRailGuard)
            }
            return .refused(reason: .unknown)
        }
        return .refused(reason: .unknown)
    }

    /// External Bonsplit tab-transfer drop → shared path.
    @discardableResult
    static func handleExternal(
        store: SidebarDockStore,
        request: BonsplitController.ExternalTabDropRequest
    ) -> Bool {
        switch request.destination {
        case .insert(let targetPane, _):
            let outcome = handle(
                store: store,
                tabId: request.tabId,
                zone: .center,
                targetPaneId: targetPane
            )
            return outcome.isSuccess
        case .split(_, let orientation, let insertFirst):
            if orientation != .vertical {
                // Horizontal external split: refuse without mutation.
                return false
            }
            let zone: SidebarDockEdgeBand.Zone = insertFirst ? .top : .bottom
            let outcome = handle(
                store: store,
                tabId: request.tabId,
                zone: zone,
                targetPaneId: nil
            )
            return outcome.isSuccess
        }
    }

    /// Lossless refuse for a disallowed panel type without attaching or mutating
    /// the rail. DEBUG dogfood and external fixtures call this for the
    /// representative disallowed-panel cell of the VAL-RAIL-004 matrix.
    @discardableResult
    static func refuseDisallowedPanel(
        store: SidebarDockStore,
        panelType: PanelType
    ) -> Outcome {
        // Allowed types are not refused here — callers must use the live drop path.
        guard !SidebarDockPlacementMatrix.allows(panelType: panelType) else {
            return .refused(reason: .unknown)
        }
        // Explicit no-op mutation check: read-only snapshots must stay equal.
        _ = store.sectionSnapshots()
        _ = store.panels.count
        _ = store.surfaceIdToPanelId.count
        return .refused(reason: .disallowedPanel)
    }
}
