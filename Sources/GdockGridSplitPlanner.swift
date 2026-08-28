import Foundation

/// Pure planning for gdock Grid Mode's enforced split shape.
///
/// Grid Mode's contract is the opposite of Quad Split's surplus rule: nothing
/// may hide behind another surface, so every cell holds exactly one surface
/// (or an unactivated placeholder) and surfaces beyond `rows × cols` are
/// reported as overflow for the caller to relocate into another workspace —
/// never stacked as background tabs.
///
/// Reuses ``QuadSplitPlanner/PaneSnapshot`` as the input shape so the same
/// snapshot capture (`QuadSplitAction.orderedPaneSnapshots`) feeds both
/// planners.
enum GdockGridSplitPlanner {
    /// The assignment of existing surfaces to grid cells.
    struct Plan: Equatable, Sendable {
        /// One entry per cell in build order; `nil` means the cell gets an
        /// unactivated placeholder terminal.
        let cellPanelIds: [UUID?]
        /// Surfaces that do not fit the grid, in stable order. The caller
        /// moves these to another workspace; they are never hidden as tabs.
        let overflowPanelIds: [UUID]
    }

    /// Assigns every existing surface to a cell of the target shape.
    ///
    /// The focused pane's displayed surface leads cell 0 so whatever the user
    /// was looking at stays put; remaining surfaces follow in tree order with
    /// each pane's displayed surface before its background tabs.
    ///
    /// - Parameters:
    ///   - panes: Workspace panes in tree order.
    ///   - focusedPaneId: The currently focused pane, when known.
    ///   - shape: The enforced grid shape.
    static func plan(
        panes: [QuadSplitPlanner.PaneSnapshot],
        focusedPaneId: UUID?,
        shape: GdockGridShape
    ) -> Plan {
        var orderedPanes = panes
        if let focusedPaneId,
           let focusedIndex = orderedPanes.firstIndex(where: { $0.paneId == focusedPaneId }) {
            let focused = orderedPanes.remove(at: focusedIndex)
            orderedPanes.insert(focused, at: 0)
        }

        let orderedPanelIds = orderedPanes.flatMap(\.displayOrderedPanelIds)
        let leading = orderedPanelIds.prefix(shape.cellCount)
        var cells: [UUID?] = leading.map { $0 }
        while cells.count < shape.cellCount {
            cells.append(nil)
        }
        return Plan(
            cellPanelIds: cells,
            overflowPanelIds: Array(orderedPanelIds.dropFirst(shape.cellCount))
        )
    }

    // MARK: - Shape signature

    /// Structural mirror of a Bonsplit tree, decoupled from live types so the
    /// grid signature check is unit-testable without a workspace.
    indirect enum TreeShape: Equatable, Sendable {
        case pane
        /// `isVertical` follows Bonsplit: vertical = stacked rows,
        /// horizontal = side-by-side columns.
        case split(isVertical: Bool, first: TreeShape, second: TreeShape)
    }

    /// Whether `tree` already is a perfect `shape` grid, in either canonical
    /// nesting (rows-of-columns or columns-of-rows). Structure only; per-pane
    /// tab counts are the caller's concern.
    static func matchesGrid(_ tree: TreeShape, shape: GdockGridShape) -> Bool {
        if let rows = fan(tree, isVertical: true),
           rows.count == shape.rows,
           rows.allSatisfy({ isPureFan($0, isVertical: false, count: shape.cols) }) {
            return true
        }
        if let cols = fan(tree, isVertical: false),
           cols.count == shape.cols,
           cols.allSatisfy({ isPureFan($0, isVertical: true, count: shape.rows) }) {
            return true
        }
        return false
    }

    /// Flattens consecutive same-orientation splits into an ordered fan.
    /// A `.pane` is a fan of one; the opposite orientation ends the fan.
    private static func fan(_ tree: TreeShape, isVertical: Bool) -> [TreeShape]? {
        switch tree {
        case .pane:
            return [tree]
        case .split(let vertical, let first, let second):
            guard vertical == isVertical else { return [tree] }
            guard let firstFan = fan(first, isVertical: isVertical),
                  let secondFan = fan(second, isVertical: isVertical) else {
                return nil
            }
            return firstFan + secondFan
        }
    }

    /// Whether `tree` is a fan of exactly `count` leaf panes along the given
    /// orientation with no cross-orientation nesting inside.
    private static func isPureFan(_ tree: TreeShape, isVertical: Bool, count: Int) -> Bool {
        guard let members = fan(tree, isVertical: isVertical) else { return false }
        return members.count == count && members.allSatisfy { $0 == .pane }
    }
}
