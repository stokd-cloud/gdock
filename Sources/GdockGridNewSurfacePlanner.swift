import Foundation

/// Pure routing for Grid Mode's New Surface (Cmd+T) path.
///
/// Empty cells activate first. When the selected grid is full, the
/// least-recently-touched real panel is rolled over instead of creating a
/// workspace of unstarted placeholders.
enum GdockGridNewSurfacePlanner {
    enum Route: Equatable, Sendable {
        case activatePlaceholder(UUID)
        case rollOver(UUID)
    }

    /// Chooses the next New Surface action for one workspace's ordered cells.
    ///
    /// Untouched real panels are older than any touched panel. Equal touch
    /// ranks break toward earlier spatial order.
    static func route(
        orderedPanelIds: [UUID],
        placeholderPanelIds: [UUID],
        touchOrder: [UUID: Int]
    ) -> Route {
        let placeholders = Set(placeholderPanelIds)
        if let placeholder = orderedPanelIds.first(where: { placeholders.contains($0) }) {
            return .activatePlaceholder(placeholder)
        }

        let realPanelIds = orderedPanelIds.filter { !placeholders.contains($0) }
        let spatialIndex = Dictionary(
            uniqueKeysWithValues: orderedPanelIds.enumerated().map { ($0.element, $0.offset) }
        )
        let oldest = realPanelIds.min { lhs, rhs in
            let leftTouch = touchOrder[lhs] ?? .min
            let rightTouch = touchOrder[rhs] ?? .min
            if leftTouch != rightTouch {
                return leftTouch < rightTouch
            }
            return (spatialIndex[lhs] ?? 0) < (spatialIndex[rhs] ?? 0)
        }
        return .rollOver(oldest ?? orderedPanelIds[0])
    }
}
