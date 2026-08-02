import Foundation

/// UUID-free named-layout definition for both sidebar rails.
///
/// Flat weighted sections (not a nested binary tree). Applied to a target
/// window's selected workspace; panel identity is mode/selector strings only
/// (VAL-LAYOUT-001 / VAL-LAYOUT-002 / D-15).
struct CmuxSidebarDockDefinition: Codable, Sendable, Hashable {
    struct Section: Codable, Sendable, Hashable {
        /// `RightSidebarMode` raw values, or `workspaceSelector`.
        var panels: [String]
        /// Must be a member of `panels` when present.
        var selected: String?
        /// Absent == expanded.
        var collapsed: Bool?
        /// Relative share of the rail; nil == equal share.
        var weight: Double?

        init(
            panels: [String],
            selected: String? = nil,
            collapsed: Bool? = nil,
            weight: Double? = nil
        ) {
            self.panels = panels
            self.selected = selected
            self.collapsed = collapsed
            self.weight = weight
        }
    }

    struct Rail: Codable, Sendable, Hashable {
        /// 1..N sections, no upper bound.
        var sections: [Section]

        init(sections: [Section]) {
            self.sections = sections
        }
    }

    var left: Rail?
    var right: Rail?

    init(left: Rail? = nil, right: Rail? = nil) {
        self.left = left
        self.right = right
    }

    /// Panel token for the workspace selector.
    static let workspaceSelectorToken = "workspaceSelector"

    // MARK: - Weight normalization (VAL-LAYOUT-002)

    /// Normalize section weights into positive finite shares that sum to 1.
    ///
    /// - Nil weights take an equal share of the residual after explicit weights.
    /// - Negative, zero-total, NaN, and infinite inputs fall back to equal shares.
    static func normalizedWeights(for sections: [Section]) -> [Double] {
        let count = sections.count
        guard count > 0 else { return [] }
        let equal = Array(repeating: 1.0 / Double(count), count: count)

        var explicit: [Double?] = sections.map { section in
            guard let raw = section.weight else { return nil }
            guard raw.isFinite, raw > 0 else { return nil }
            return raw
        }

        let known = explicit.compactMap { $0 }
        let knownSum = known.reduce(0, +)
        if known.isEmpty || !knownSum.isFinite || knownSum <= 0 {
            return equal
        }

        let nilCount = explicit.filter { $0 == nil }.count
        if nilCount == 0 {
            return explicit.map { ($0 ?? 0) / knownSum }
        }

        // Explicit weights keep their relative mass; residual is split equally
        // among nil entries. If residual is non-positive, fall back to equal.
        let residual = max(0, 1.0 - (knownSum / (knownSum + Double(nilCount))))
        // Simpler deterministic path: treat nil as mean of known positives, then renorm.
        let meanKnown = knownSum / Double(known.count)
        var filled: [Double] = explicit.map { $0 ?? meanKnown }
        let filledSum = filled.reduce(0, +)
        guard filledSum.isFinite, filledSum > 0 else { return equal }
        return filled.map { $0 / filledSum }
    }

    /// Convert normalized weights (top → bottom) into successive first-child
    /// divider positions for a left-associated vertical chain.
    static func dividerPositions(fromNormalizedWeights weights: [Double]) -> [Double] {
        guard weights.count >= 2 else { return [] }
        var remaining = 1.0
        var positions: [Double] = []
        for index in 0..<(weights.count - 1) {
            let share = weights[index]
            let pos = remaining > 0 ? min(0.9, max(0.1, share / remaining)) : 0.5
            positions.append(pos)
            remaining = max(0.000_1, remaining * (1.0 - pos))
        }
        return positions
    }
}
