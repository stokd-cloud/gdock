import Foundation
import Testing

#if canImport(cmux_DEV)
@testable import cmux_DEV
#elseif canImport(cmux)
@testable import cmux
#endif

/// Pane-to-session precedence: process identity first, recency last (AC5).
///
/// A workspace usually holds several sessions, most of them finished, so
/// "newest file wins" on its own would attribute one pane's work to another
/// pane's card.
@Suite struct StokdSessionOutcomesLocatorTests {
    private typealias Locator = StokdSessionOutcomesLocator
    private typealias Descriptor = StokdSessionOutcomesLocator.SessionDescriptor

    private func descriptor(
        _ id: String,
        pid: Int32,
        pgid: Int32 = 0,
        running: Bool = false,
        minutesAgo: Double
    ) -> Descriptor {
        Descriptor(
            sessionID: id,
            pid: pid,
            pgid: pgid,
            isRunning: running,
            modifiedAt: Date(timeIntervalSince1970: 1_788_000_000 - minutesAgo * 60)
        )
    }

    @Test func anEmptyListYieldsNoSession() {
        #expect(Locator.session(agentPIDs: [42], in: []) == nil)
    }

    /// An exact pid match beats a newer session in every other tier.
    @Test func anExactPidMatchWinsOverEverythingNewer() {
        let descriptors = [
            descriptor("mine", pid: 300, minutesAgo: 90),
            descriptor("newest-running", pid: 999, pgid: 999, running: true, minutesAgo: 1)
        ]

        let match = Locator.session(
            agentPIDs: [300],
            agentProcessGroupIDs: [999],
            in: descriptors
        )

        #expect(match?.sessionID == "mine")
    }

    /// stokd may wrap the provider CLI, so the pane's pid can be a sibling of
    /// the recorded leader rather than equal to it. The process group is what
    /// still binds them.
    @Test func aProcessGroupMatchWinsOverTheMostRecentRunningSession() {
        let descriptors = [
            descriptor("same-group", pid: 500, pgid: 500, minutesAgo: 120),
            descriptor("newest-running", pid: 900, pgid: 900, running: true, minutesAgo: 1)
        ]

        let match = Locator.session(
            agentPIDs: [501],
            agentProcessGroupIDs: [500],
            in: descriptors
        )

        #expect(match?.sessionID == "same-group")
    }

    @Test func anExactPidMatchWinsOverAProcessGroupMatch() {
        let descriptors = [
            descriptor("by-group", pid: 500, pgid: 500, minutesAgo: 1),
            descriptor("by-pid", pid: 700, pgid: 700, minutesAgo: 120)
        ]

        let match = Locator.session(
            agentPIDs: [700],
            agentProcessGroupIDs: [500, 700],
            in: descriptors
        )

        #expect(match?.sessionID == "by-pid")
    }

    /// With no process match at all, a live session beats a more recently
    /// touched dead one — the pane is running something now.
    @Test func aRunningSessionWinsOverANewerFinishedOne() {
        let descriptors = [
            descriptor("running", pid: 100, pgid: 100, running: true, minutesAgo: 60),
            descriptor("finished", pid: 200, pgid: 200, running: false, minutesAgo: 1)
        ]

        let match = Locator.session(agentPIDs: [], agentProcessGroupIDs: [], in: descriptors)

        #expect(match?.sessionID == "running")
    }

    @Test func theMostRecentRunningSessionWinsAmongRunningOnes() {
        let descriptors = [
            descriptor("older-running", pid: 100, running: true, minutesAgo: 60),
            descriptor("newer-running", pid: 200, running: true, minutesAgo: 5)
        ]

        let match = Locator.session(agentPIDs: [], in: descriptors)

        #expect(match?.sessionID == "newer-running")
    }

    @Test func withNothingRunningTheMostRecentSessionWins() {
        let descriptors = [
            descriptor("old", pid: 100, minutesAgo: 600),
            descriptor("recent", pid: 200, minutesAgo: 3)
        ]

        let match = Locator.session(agentPIDs: [], in: descriptors)

        #expect(match?.sessionID == "recent")
    }

    /// A recorded pgid of 0 means "stokd did not record one" and must not
    /// match a pane whose own group also failed to resolve.
    @Test func anUnrecordedProcessGroupNeverMatches() {
        let descriptors = [
            descriptor("no-group", pid: 100, pgid: 0, minutesAgo: 600),
            descriptor("recent", pid: 200, pgid: 200, minutesAgo: 3)
        ]

        let match = Locator.session(
            agentPIDs: [],
            agentProcessGroupIDs: [0],
            in: descriptors
        )

        #expect(match?.sessionID == "recent")
    }

    /// Equal timestamps must not reorder between reads, or the card would
    /// flicker between two sessions.
    @Test func equalTimestampsResolveDeterministically() {
        let descriptors = [
            descriptor("bbb", pid: 100, minutesAgo: 10),
            descriptor("aaa", pid: 200, minutesAgo: 10)
        ]

        let first = Locator.session(agentPIDs: [], in: descriptors)
        let second = Locator.session(agentPIDs: [], in: descriptors.reversed())

        #expect(first?.sessionID == second?.sessionID)
        #expect(first?.sessionID == "bbb")
    }

    /// A pane with several agent pids (a resumed session alongside a live one)
    /// still resolves, picking the most recently active of its own sessions.
    @Test func severalAgentPidsResolveToTheMostRecentOfThem() {
        let descriptors = [
            descriptor("older-mine", pid: 100, minutesAgo: 90),
            descriptor("newer-mine", pid: 200, minutesAgo: 4),
            descriptor("not-mine", pid: 300, running: true, minutesAgo: 1)
        ]

        let match = Locator.session(agentPIDs: [100, 200], in: descriptors)

        #expect(match?.sessionID == "newer-mine")
    }
}
