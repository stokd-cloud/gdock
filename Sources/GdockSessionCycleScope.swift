import Foundation

/// Which sessions the cycler is cycling.
///
/// An ordered ring, not a boolean: right-arrow advances, left-arrow retreats,
/// both wrap, and adding a third scope (current window, current machine, cloud)
/// is a new case and nothing else (AX-GDOCK-SESSION-CYCLER).
///
/// Case order is the ring order the operator walks, so `currentRepo` comes
/// first: the sessions in the repository you are already in are the ones you
/// reach for most.
enum GdockSessionCycleScope: String, CaseIterable, Equatable, Sendable {
    /// Sessions belonging to the selected workspace's repository group.
    case currentRepo
    /// Every agent session open in the app.
    case allSessions

    func next() -> GdockSessionCycleScope {
        GdockCycleRing.next(after: self)
    }

    func previous() -> GdockSessionCycleScope {
        GdockCycleRing.previous(before: self)
    }
}
