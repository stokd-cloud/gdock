import Foundation

/// Modular stepping over an ordered set of cases.
///
/// gdock's cyclers advance and retreat through a ring rather than flipping a
/// boolean (AX-GDOCK-SESSION-CYCLER). A flip cannot grow: the day a third scope
/// arrives, every call site that assumed two states is a bug. Stepping
/// modularly over `allCases` means a new case is a new case and nothing else.
enum GdockCycleRing {
    /// The case one step after `value`, wrapping past the last.
    ///
    /// Returns `value` unchanged when its type has no cases or it is somehow
    /// absent from `allCases`, so a caller can never be handed a value outside
    /// the ring.
    static func next<Ring: CaseIterable & Equatable>(after value: Ring) -> Ring {
        step(from: value, by: 1)
    }

    /// The case one step before `value`, wrapping past the first.
    static func previous<Ring: CaseIterable & Equatable>(before value: Ring) -> Ring {
        step(from: value, by: -1)
    }

    /// Advances `offset` places from `value`, wrapping in both directions.
    ///
    /// The double modulo is what makes negative offsets wrap rather than crash:
    /// Swift's `%` keeps the sign of the dividend, so `-1 % 3` is `-1`.
    static func step<Ring: CaseIterable & Equatable>(from value: Ring, by offset: Int) -> Ring {
        let cases = Array(Ring.allCases)
        guard !cases.isEmpty, let index = cases.firstIndex(of: value) else { return value }
        let count = cases.count
        // The double modulo is what makes a negative offset wrap rather than
        // trap: Swift's `%` keeps the sign of the dividend, so `-1 % 3` is `-1`.
        let destination = ((index + offset) % count + count) % count
        return cases[destination]
    }
}
