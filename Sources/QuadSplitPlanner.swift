import Foundation

/// Pure quadrant assignment for Quad Split.
///
/// Quad Split's contract is that the workspace ends as a flat 2x2 — never a
/// 2x2 nested inside whichever leaf happened to be focused. Deciding *which*
/// surface lands in each quadrant is separable from mutating the split tree, so
/// it lives here and is unit-tested without a live `Workspace`.
///
/// Empty quadrants are filled from surfaces the workspace already owns but is
/// not displaying (background tabs) before any new terminal is spawned, so
/// hitting Quad Split spreads existing work out instead of burying it behind
/// four fresh shells. Surplus surfaces beyond four ride along as tabs of the
/// quadrant their pane became — they are never closed and never relocated to
/// another workspace.
enum QuadSplitPlanner {
    /// One pane of the workspace as it exists before the quad is applied.
    struct PaneSnapshot: Equatable, Sendable {
        /// Bonsplit pane identity.
        let paneId: UUID
        /// Every panel in the pane, in tab order.
        let panelIds: [UUID]
        /// The panel currently displayed in the pane, when the pane has one.
        let selectedPanelId: UUID?

        init(paneId: UUID, panelIds: [UUID], selectedPanelId: UUID?) {
            self.paneId = paneId
            self.panelIds = panelIds
            self.selectedPanelId = selectedPanelId
        }

        /// Panels ordered so the displayed surface leads: a pane that becomes a
        /// quadrant keeps showing what it was already showing.
        var displayOrderedPanelIds: [UUID] {
            guard let selectedPanelId, panelIds.contains(selectedPanelId) else {
                return panelIds
            }
            return [selectedPanelId] + panelIds.filter { $0 != selectedPanelId }
        }
    }

    /// The contents of one quadrant of the resulting 2x2.
    struct Quadrant: Equatable, Sendable {
        /// Existing panel that leads (is displayed in) this quadrant, or `nil`
        /// when the workspace had too few surfaces and a new terminal is needed.
        let leadPanelId: UUID?
        /// Existing panels that ride along as background tabs of this quadrant.
        let trailingPanelIds: [UUID]

        init(leadPanelId: UUID?, trailingPanelIds: [UUID] = []) {
            self.leadPanelId = leadPanelId
            self.trailingPanelIds = trailingPanelIds
        }

        /// True when applying this quadrant must spawn a terminal.
        var needsNewTerminal: Bool { leadPanelId == nil }

        var allPanelIds: [UUID] {
            guard let leadPanelId else { return trailingPanelIds }
            return [leadPanelId] + trailingPanelIds
        }
    }

    /// Number of quadrants in the target layout.
    static let quadrantCount = 4

    /// Assigns every existing surface to one of exactly four quadrants.
    ///
    /// Returned order is `[topLeft, topRight, bottomLeft, bottomRight]`.
    /// `topLeft` is always the invoking pane, so the surface the user acted from
    /// stays put and stays displayed.
    ///
    /// - Parameters:
    ///   - panes: Workspace panes in tree order.
    ///   - targetPaneId: The pane Quad Split was invoked on.
    /// - Returns: Exactly `quadrantCount` quadrants, or `nil` when `targetPaneId`
    ///   is absent from `panes` or names a pane with no surfaces.
    static func plan(panes: [PaneSnapshot], targetPaneId: UUID) -> [Quadrant]? {
        guard let targetIndex = panes.firstIndex(where: { $0.paneId == targetPaneId }),
              !panes[targetIndex].panelIds.isEmpty else {
            return nil
        }

        // Target pane leads; remaining panes follow in tree order.
        let orderedPanes = [panes[targetIndex]] + panes.enumerated()
            .filter { $0.offset != targetIndex }
            .map(\.element)

        var groups: [[UUID]] = orderedPanes
            .map(\.displayOrderedPanelIds)
            .filter { !$0.isEmpty }

        mergeSurplusPanes(into: &groups)
        promoteBackgroundTabs(into: &groups)

        var quadrants = groups.map { group in
            Quadrant(leadPanelId: group.first, trailingPanelIds: Array(group.dropFirst()))
        }
        while quadrants.count < quadrantCount {
            quadrants.append(Quadrant(leadPanelId: nil))
        }
        return quadrants
    }

    /// Folds panes past the fourth into the four quadrants, round-robin.
    ///
    /// Their surfaces survive as background tabs — "more than enough panes"
    /// means the extras stay tabs rather than being discarded.
    private static func mergeSurplusPanes(into groups: inout [[UUID]]) {
        guard groups.count > quadrantCount else { return }
        let surplus = groups[quadrantCount...]
        groups = Array(groups.prefix(quadrantCount))
        for (offset, group) in surplus.enumerated() {
            groups[offset % quadrantCount].append(contentsOf: group)
        }
    }

    /// Fills quadrants from background tabs before falling back to new terminals.
    ///
    /// Pulls from the most crowded group each round so surfaces spread evenly,
    /// and takes that group's last tab so earlier tabs stay with their lead.
    private static func promoteBackgroundTabs(into groups: inout [[UUID]]) {
        while groups.count < quadrantCount {
            guard let donorIndex = groups.indices
                .filter({ groups[$0].count > 1 })
                .max(by: { groups[$0].count < groups[$1].count })
            else {
                return
            }
            groups.append([groups[donorIndex].removeLast()])
        }
    }
}
