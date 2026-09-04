import CoreGraphics
import Foundation

/// Vertical stacking model for right-sidebar tool sections.
///
/// The sidebar shows one tool at a time. Dragging a tool chip down out of the
/// mode bar detaches it into its own section so several tools share the sidebar
/// vertically — the VS Code Explorer model (MAIN / OUTLINE / TIMELINE …), with a
/// draggable separator between neighbours and a collapsible header each.
///
/// This type owns only geometry and ordering; it never touches views, so the
/// resize and collapse math is testable without a running app. Heights are
/// stored as relative weights rather than points so the stack reflows when the
/// sidebar is resized instead of pinning stale pixel values.
struct RightSidebarSectionLayout: Equatable, Sendable {
    /// Height of a section's header row (also its total height when collapsed).
    static let headerHeight: CGFloat = 24
    /// Smallest content area an expanded section may be squeezed to.
    static let minContentHeight: CGFloat = 60

    struct Section: Equatable, Sendable, Identifiable {
        let mode: RightSidebarMode
        /// Relative share of the flexible space. Only meaningful when expanded.
        var weight: CGFloat
        var isCollapsed: Bool

        var id: RightSidebarMode { mode }

        init(mode: RightSidebarMode, weight: CGFloat = 1, isCollapsed: Bool = false) {
            self.mode = mode
            self.weight = max(weight, 0.0001)
            self.isCollapsed = isCollapsed
        }
    }

    private(set) var sections: [Section]

    init(sections: [Section] = []) {
        self.sections = sections
    }

    var isEmpty: Bool { sections.isEmpty }
    var modes: [RightSidebarMode] { sections.map(\.mode) }

    func contains(_ mode: RightSidebarMode) -> Bool {
        sections.contains { $0.mode == mode }
    }

    // MARK: - Mutation

    /// Inserts `mode` as a section, or moves it when already stacked.
    ///
    /// New sections inherit the average weight of their neighbours so a drop
    /// does not visually collapse the existing sections.
    mutating func insert(_ mode: RightSidebarMode, at index: Int) {
        let clampedIndex = max(0, min(index, sections.count))
        if let existing = sections.firstIndex(where: { $0.mode == mode }) {
            let section = sections.remove(at: existing)
            let adjusted = existing < clampedIndex ? clampedIndex - 1 : clampedIndex
            sections.insert(section, at: max(0, min(adjusted, sections.count)))
            return
        }
        let expanded = sections.filter { !$0.isCollapsed }
        let weight = expanded.isEmpty ? 1 : expanded.map(\.weight).reduce(0, +) / CGFloat(expanded.count)
        sections.insert(Section(mode: mode, weight: weight), at: clampedIndex)
    }

    @discardableResult
    mutating func remove(_ mode: RightSidebarMode) -> Bool {
        guard let index = sections.firstIndex(where: { $0.mode == mode }) else { return false }
        sections.remove(at: index)
        return true
    }

    mutating func toggleCollapse(_ mode: RightSidebarMode) {
        guard let index = sections.firstIndex(where: { $0.mode == mode }) else { return }
        sections[index].isCollapsed.toggle()
    }

    mutating func setCollapsed(_ collapsed: Bool, for mode: RightSidebarMode) {
        guard let index = sections.firstIndex(where: { $0.mode == mode }) else { return }
        sections[index].isCollapsed = collapsed
    }

    // MARK: - Geometry

    /// Resolved pixel heights, top to bottom, for a stack `totalHeight` tall.
    ///
    /// Collapsed sections occupy exactly a header. Expanded sections split what
    /// is left by weight, each keeping `minContentHeight` where the space allows;
    /// when it does not, the remainder is shared proportionally so the stack
    /// still fits rather than overflowing.
    func resolvedHeights(totalHeight: CGFloat) -> [CGFloat] {
        guard !sections.isEmpty else { return [] }

        let headerTotal = Self.headerHeight * CGFloat(sections.count)
        let expandedIndices = sections.indices.filter { !sections[$0].isCollapsed }
        guard !expandedIndices.isEmpty else {
            return sections.map { _ in Self.headerHeight }
        }

        let flexible = totalHeight - headerTotal
        var heights = sections.map { _ in Self.headerHeight }
        guard flexible > 0 else { return heights }

        let comfortable = Self.minContentHeight * CGFloat(expandedIndices.count)
        let weightTotal = expandedIndices.map { sections[$0].weight }.reduce(0, +)
        guard weightTotal > 0 else { return heights }

        if flexible >= comfortable {
            // Enough room to honour minimums: give each its minimum, then split
            // the surplus by weight.
            let surplus = flexible - comfortable
            for index in expandedIndices {
                let share = surplus * (sections[index].weight / weightTotal)
                heights[index] = Self.headerHeight + Self.minContentHeight + share
            }
        } else {
            for index in expandedIndices {
                let share = flexible * (sections[index].weight / weightTotal)
                heights[index] = Self.headerHeight + share
            }
        }
        return heights
    }

    /// Inserts any missing stackable modes and drops modes that are no longer
    /// stackable, preserving order, collapse, and weights of sections that stay.
    mutating func reconcileStackableModes(_ modes: [RightSidebarMode]) {
        let allowed = Set(modes)
        sections.removeAll { !allowed.contains($0.mode) }
        for mode in modes where !contains(mode) {
            insert(mode, at: sections.count)
        }
    }

    /// Moves the section at `index`, or the collapsed run it starts, to `destination`.
    mutating func moveBlock(startingAt index: Int, to destination: Int) {
        guard sections.indices.contains(index) else { return }
        var end = index
        if sections[index].isCollapsed {
            while end + 1 < sections.count, sections[end + 1].isCollapsed {
                end += 1
            }
        }
        let block = Array(sections[index...end])
        sections.removeSubrange(index...end)
        var dest = destination
        if dest > index {
            dest -= block.count
        }
        dest = max(0, min(dest, sections.count))
        sections.insert(contentsOf: block, at: dest)
    }

    /// Drags the top of `sections[index]`.
    ///
    /// Valid only when the immediately preceding section is expanded. A
    /// collapsed run moves as one block against the next expanded section.
    /// Dragging an internal collapsed boundary is a no-op.
    mutating func resize(dividerAbove index: Int, by delta: CGFloat, totalHeight: CGFloat) {
        guard index > 0, index < sections.count else { return }
        guard !sections[index - 1].isCollapsed else { return }
        guard let below = sections[index...].firstIndex(where: { !$0.isCollapsed }) else {
            return
        }
        let above = index - 1

        let heights = resolvedHeights(totalHeight: totalHeight)
        let aboveContent = heights[above] - Self.headerHeight
        let belowContent = heights[below] - Self.headerHeight

        // Clamp so neither neighbour is driven under its minimum.
        let lowerBound = -(aboveContent - Self.minContentHeight)
        let upperBound = belowContent - Self.minContentHeight
        let applied = max(lowerBound, min(delta, upperBound))
        guard applied != 0 else { return }

        let newAbove = aboveContent + applied
        let newBelow = belowContent - applied
        guard newAbove > 0, newBelow > 0 else { return }

        // Re-express as weights, preserving the pair's combined weight.
        let pairWeight = sections[above].weight + sections[below].weight
        let contentTotal = newAbove + newBelow
        guard contentTotal > 0 else { return }
        sections[above].weight = max(pairWeight * (newAbove / contentTotal), 0.0001)
        sections[below].weight = max(pairWeight * (newBelow / contentTotal), 0.0001)
    }

    /// Insertion index for a drop landing at `y` within a stack `totalHeight`
    /// tall — the boundary nearest the drop point.
    func insertionIndex(forDropAt y: CGFloat, totalHeight: CGFloat) -> Int {
        guard !sections.isEmpty else { return 0 }
        let heights = resolvedHeights(totalHeight: totalHeight)
        var cursor: CGFloat = 0
        for (index, height) in heights.enumerated() {
            if y < cursor + height / 2 { return index }
            cursor += height
        }
        return sections.count
    }
}
