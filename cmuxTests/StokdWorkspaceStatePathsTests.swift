import Foundation
import Testing

#if canImport(cmux_DEV)
@testable import cmux_DEV
#elseif canImport(cmux)
@testable import cmux
#endif

/// gdock derives stokd's state directory rather than guessing it (AC2).
///
/// The expected keys are the real directories on the machine that wrote these
/// tests, and the algorithm is a port of `apps/cli/src/state_paths.rs` in
/// stokd-cloud/mono. If stokd ever changes its derivation, these vectors are
/// what catches it — the failure mode otherwise is a silently empty sidebar.
@Suite struct StokdWorkspaceStatePathsTests {
    private typealias Paths = StokdWorkspaceStatePaths

    @Test func workspaceKeyMatchesTheStokdCLIForKnownRoots() {
        #expect(Paths.workspaceKey(forRoot: "/opt/worktrees/stokd-cloud/mono/main") == "main-6fc0ab4a0966")
        #expect(Paths.workspaceKey(forRoot: "/opt/worktrees/stokd-cloud/gdock/main") == "main-c68129256fc3")
    }

    /// Two worktrees of one repository share a basename; only the digest keeps
    /// their state apart, which is the whole reason the key is hashed.
    @Test func sameBasenameDifferentPathsProduceDifferentKeys() {
        let mono = Paths.workspaceKey(forRoot: "/opt/worktrees/stokd-cloud/mono/main")
        let gdock = Paths.workspaceKey(forRoot: "/opt/worktrees/stokd-cloud/gdock/main")

        #expect(mono != gdock)
        #expect(mono.hasPrefix("main-"))
        #expect(gdock.hasPrefix("main-"))
    }

    @Test func fnv1a64MatchesTheReferenceVector() {
        // FNV-1a 64-bit of the empty string is the offset basis itself.
        #expect(Paths.fnv1a64Hex("") == "cbf29ce484222325")
        #expect(Paths.fnv1a64Hex("a") == "af63dc4c8601ec8c")
    }

    @Test func sanitizeSegmentLowercasesAndCollapsesRuns() {
        #expect(Paths.sanitizeSegment("Feature/Gdock Grid_Mode") == "feature-gdock-grid-mode")
        #expect(Paths.sanitizeSegment("a...b") == "a-b")
        #expect(Paths.sanitizeSegment("MAIN") == "main")
    }

    @Test func sanitizeSegmentTrimsLeadingAndTrailingSeparators() {
        #expect(Paths.sanitizeSegment("///main///") == "main")
        #expect(Paths.sanitizeSegment("...") == "")
        #expect(Paths.sanitizeSegment("") == "")
    }

    @Test func sanitizeSegmentCapsAtFortyEightCharacters() {
        let long = String(repeating: "x", count: 80)

        let sanitized = Paths.sanitizeSegment(long)

        #expect(sanitized.count == Paths.segmentLimit)
        #expect(sanitized == String(repeating: "x", count: 48))
    }

    /// The cap is applied after trimming, so trailing separators cannot eat
    /// characters the key is supposed to keep.
    @Test func sanitizeSegmentTrimsBeforeTruncating() {
        let input = "----" + String(repeating: "y", count: 50)

        #expect(Paths.sanitizeSegment(input) == String(repeating: "y", count: 48))
    }

    @Test func sessionIDsAreSanitizedIntoOneFilesystemSegment() {
        #expect(Paths.sanitizeSessionID("interactive-claude-30820-178815") == "interactive-claude-30820-178815")
        #expect(Paths.sanitizeSessionID("a/b:c d") == "a_b_c_d")
        #expect(Paths.sanitizeSessionID("keep_dash-and_underscore") == "keep_dash-and_underscore")
    }

    @Test func pathsHangOffTheWorkspaceKeyUnderTheGivenHome() {
        let home = URL(fileURLWithPath: "/tmp/fake-stokd-home", isDirectory: true)
        let root = "/opt/worktrees/stokd-cloud/gdock/main"
        let key = Paths.workspaceKey(forRoot: root)

        let runtime = Paths.runtimeDirectory(forRoot: root, home: home)
        let sessions = Paths.sessionRecordsDirectory(forRoot: root, home: home)
        let outcomes = Paths.outcomesFile(forRoot: root, sessionID: "interactive-claude-1-2", home: home)
        let disposition = Paths.dispositionFile(forRoot: root, sessionID: "interactive-claude-1-2", home: home)
        let record = Paths.sessionRecordFile(forRoot: root, sessionID: "interactive-claude-1-2", home: home)

        #expect(runtime.path == "/tmp/fake-stokd-home/workspaces/\(key)/runtime")
        #expect(sessions.path == "/tmp/fake-stokd-home/workspaces/\(key)/runtime/sessions")
        #expect(outcomes.lastPathComponent == "interactive-claude-1-2.outcomes.jsonl")
        #expect(disposition.lastPathComponent == "interactive-claude-1-2.disposition")
        #expect(record.path == "/tmp/fake-stokd-home/workspaces/\(key)/runtime/sessions/interactive-claude-1-2.runtime.json")
    }

    @Test func stokdHomeOverrideWins() {
        let home = Paths.homeDirectory(environment: ["STOKD_HOME": "/tmp/override-home"])

        #expect(home.path == "/tmp/override-home")
    }

    @Test func blankStokdHomeFallsBackToTheUserHome() {
        let home = Paths.homeDirectory(environment: ["STOKD_HOME": "   "])

        #expect(home.lastPathComponent == ".stokd")
    }
}
