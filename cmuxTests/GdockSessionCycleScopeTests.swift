import Foundation
import Testing

#if canImport(cmux_DEV)
@testable import cmux_DEV
#elseif canImport(cmux)
@testable import cmux
#endif

/// The scope ring is modular over N members, never a two-way boolean toggle
/// (AX-GDOCK-SESSION-CYCLER).
///
/// The fixture ring has three members on purpose: a two-member ring cannot tell
/// "advance one, wrapping" apart from "flip", and flipping is exactly the
/// implementation this axiom exists to forbid.
@Suite struct GdockSessionCycleScopeTests {
    /// Stand-in for a future third scope (current window, current machine, …).
    private enum FixtureRing: CaseIterable, Equatable {
        case first
        case second
        case third
    }

    // MARK: - The generic ring

    @Test func nextAdvancesOneMemberAndWrapsAtTheEnd() {
        #expect(GdockCycleRing.next(after: FixtureRing.first) == .second)
        #expect(GdockCycleRing.next(after: FixtureRing.second) == .third)
        #expect(GdockCycleRing.next(after: FixtureRing.third) == .first)
    }

    @Test func previousRetreatsOneMemberAndWrapsAtTheStart() {
        #expect(GdockCycleRing.previous(before: FixtureRing.third) == .second)
        #expect(GdockCycleRing.previous(before: FixtureRing.second) == .first)
        #expect(GdockCycleRing.previous(before: FixtureRing.first) == .third)
    }

    @Test func nextAndPreviousAreInversesForEveryMember() {
        for member in FixtureRing.allCases {
            #expect(GdockCycleRing.previous(before: GdockCycleRing.next(after: member)) == member)
            #expect(GdockCycleRing.next(after: GdockCycleRing.previous(before: member)) == member)
        }
    }

    /// A full lap returns to the start, which is what makes adding a fourth
    /// scope a no-op at every call site.
    @Test func oneFullLapReturnsToTheStartingMember() {
        var member = FixtureRing.first
        for _ in FixtureRing.allCases {
            member = GdockCycleRing.next(after: member)
        }
        #expect(member == .first)
    }

    // MARK: - The session-cycler ring

    @Test func sessionScopeRingCyclesCurrentRepoToAllSessionsAndBack() {
        #expect(GdockSessionCycleScope.currentRepo.next() == .allSessions)
        #expect(GdockSessionCycleScope.allSessions.next() == .currentRepo)
        #expect(GdockSessionCycleScope.allSessions.previous() == .currentRepo)
        #expect(GdockSessionCycleScope.currentRepo.previous() == .allSessions)
    }

    @Test func sessionScopeRingStartsAtCurrentRepo() {
        #expect(GdockSessionCycleScope.allCases.first == .currentRepo)
    }
}
