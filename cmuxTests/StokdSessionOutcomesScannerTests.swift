import Foundation
import Testing

#if canImport(cmux_DEV)
@testable import cmux_DEV
#elseif canImport(cmux)
@testable import cmux
#endif

/// End-to-end read of a stokd workspace's runtime state against a real
/// temporary directory laid out the way the CLI lays out `~/.stokd` (AC3).
///
/// The important asymmetry this pins down: stokd prunes
/// `runtime/sessions/<id>.runtime.json` when a session ends, but the session's
/// `<id>.outcomes.jsonl` stays. A scan driven only by runtime records would
/// therefore hide every *finished* session — which is exactly the work most
/// worth showing on a card.
@Suite struct StokdSessionOutcomesScannerTests {
    private typealias Scanner = StokdSessionOutcomesScanner

    /// One temporary `~/.stokd` plus a workspace root inside it.
    private struct Fixture {
        let home: URL
        let root: String

        init() throws {
            let base = URL(fileURLWithPath: NSTemporaryDirectory(), isDirectory: true)
                .appendingPathComponent("gdock-scanner-\(UUID().uuidString)", isDirectory: true)
            home = base.appendingPathComponent(".stokd", isDirectory: true)
            let workspace = base.appendingPathComponent("repo", isDirectory: true)
            try FileManager.default.createDirectory(at: workspace, withIntermediateDirectories: true)
            root = workspace.path
            try FileManager.default.createDirectory(
                at: StokdWorkspaceStatePaths.sessionRecordsDirectory(forRoot: root, home: home),
                withIntermediateDirectories: true
            )
        }

        func writeRuntimeRecord(sessionID: String, pid: Int32, pgid: Int32, status: String) throws {
            let json = """
            {"session_id":"\(sessionID)","pid":\(pid),"pgid":\(pgid),"kind":"interactive",\
            "status":"\(status)","workspace_root":"\(root)","origin":"spawned"}
            """
            try json.write(
                to: StokdWorkspaceStatePaths.sessionRecordFile(forRoot: root, sessionID: sessionID, home: home),
                atomically: true,
                encoding: .utf8
            )
        }

        func writeOutcomes(sessionID: String, entries: [(String, String, String)]) throws {
            let lines = entries.map { kind, timestamp, text in
                """
                {"session_id":"\(sessionID)","entry_timestamp":"\(timestamp)","kind":"\(kind)",\
                "text":"\(text)","footprint":{"packages":{},"branch":"HEAD","dirty":false,"unpushed":false},\
                "attribution":"agent"}
                """
            }
            try lines.joined(separator: "\n").write(
                to: StokdWorkspaceStatePaths.outcomesFile(forRoot: root, sessionID: sessionID, home: home),
                atomically: true,
                encoding: .utf8
            )
        }

        func writeDisposition(sessionID: String, value: String) throws {
            try value.write(
                to: StokdWorkspaceStatePaths.dispositionFile(forRoot: root, sessionID: sessionID, home: home),
                atomically: true,
                encoding: .utf8
            )
        }

        func cleanUp() {
            try? FileManager.default.removeItem(
                at: home.deletingLastPathComponent()
            )
        }
    }

    private func scan(_ fixture: Fixture) -> Scanner.WorkspaceScan {
        Scanner.scan(
            root: fixture.root,
            home: fixture.home,
            previousSummaries: [:],
            previousFingerprints: [:]
        )
    }

    /// A finished session keeps its log after its runtime record is pruned, and
    /// must still produce a summary.
    @Test func aSessionWithOutcomesButNoRuntimeRecordIsStillSummarized() throws {
        let fixture = try Fixture()
        defer { fixture.cleanUp() }
        try fixture.writeOutcomes(sessionID: "captured-claude-99-1", entries: [
            ("fixed", "2026-08-30T20:00:00.000000+00:00", "Resolved the conflicts. Staged only.")
        ])
        try fixture.writeDisposition(sessionID: "captured-claude-99-1", value: "dev_complete\n")

        let result = scan(fixture)

        #expect(result.descriptors.map(\.sessionID) == ["captured-claude-99-1"])
        let summary = result.summariesBySessionID["captured-claude-99-1"]
        #expect(summary?.latestKindRaw == "fixed")
        #expect(summary?.headline == "Resolved the conflicts")
        #expect(summary?.disposition == "dev_complete")
        #expect(summary?.isRunning == false)
        // No runtime record means no process identity, and the locator must not
        // treat an absent pgid as a match.
        #expect(result.descriptors[0].pid == 0)
        #expect(result.descriptors[0].pgid == 0)
    }

    /// A live session's record supplies the process identity the locator binds
    /// a pane with.
    @Test func aRunningSessionCarriesItsPidAndProcessGroup() throws {
        let fixture = try Fixture()
        defer { fixture.cleanUp() }
        try fixture.writeRuntimeRecord(sessionID: "interactive-claude-3235-1", pid: 3235, pgid: 3200, status: "running")
        try fixture.writeOutcomes(sessionID: "interactive-claude-3235-1", entries: [
            ("blocked", "2026-08-30T21:00:00.000000+00:00", "Waiting on the judge.")
        ])

        let result = scan(fixture)

        #expect(result.descriptors.count == 1)
        #expect(result.descriptors[0].pid == 3235)
        #expect(result.descriptors[0].pgid == 3200)
        #expect(result.descriptors[0].isRunning)
        #expect(result.summariesBySessionID["interactive-claude-3235-1"]?.isRunning == true)
    }

    /// The scan covers the union of both directories: live sessions that have
    /// not written any outcome yet, and finished sessions whose record is gone.
    @Test func theScanCoversTheUnionOfRecordsAndLogs() throws {
        let fixture = try Fixture()
        defer { fixture.cleanUp() }
        // Live, no outcomes written yet — this is what a freshly started
        // session looks like on disk.
        try fixture.writeRuntimeRecord(sessionID: "live-no-outcomes", pid: 11, pgid: 11, status: "running")
        // Finished, record pruned, log retained.
        try fixture.writeOutcomes(sessionID: "done-no-record", entries: [
            ("shipped", "2026-08-30T22:00:00.000000+00:00", "Landed it.")
        ])
        // Live with outcomes.
        try fixture.writeRuntimeRecord(sessionID: "live-with-outcomes", pid: 22, pgid: 22, status: "running")
        try fixture.writeOutcomes(sessionID: "live-with-outcomes", entries: [
            ("decided", "2026-08-30T23:00:00.000000+00:00", "Chose the simpler path.")
        ])

        let result = scan(fixture)

        #expect(Set(result.descriptors.map(\.sessionID)) == [
            "live-no-outcomes", "done-no-record", "live-with-outcomes"
        ])
        // A session with no log has no summary, but still exists as a
        // descriptor so a pane can bind to it by pid.
        #expect(result.summariesBySessionID["live-no-outcomes"] == nil)
        #expect(result.summariesBySessionID["done-no-record"]?.latestKindRaw == "shipped")
        #expect(result.summariesBySessionID["live-with-outcomes"]?.latestKindRaw == "decided")
    }

    @Test func aWorkspaceWithNoRuntimeStateScansToNothing() throws {
        let fixture = try Fixture()
        defer { fixture.cleanUp() }

        let result = scan(fixture)

        #expect(result.descriptors.isEmpty)
        #expect(result.summariesBySessionID.isEmpty)
        #expect(result.key == StokdWorkspaceStatePaths.workspaceKey(forRoot: fixture.root))
    }

    /// An unchanged log is not reparsed. The cached summary is returned as-is,
    /// which is what keeps repeated scans cheap.
    @Test func anUnchangedLogReusesTheCachedSummary() throws {
        let fixture = try Fixture()
        defer { fixture.cleanUp() }
        try fixture.writeOutcomes(sessionID: "stable", entries: [
            ("fixed", "2026-08-30T20:00:00.000000+00:00", "Real text.")
        ])

        let first = scan(fixture)
        guard let fingerprint = first.fingerprintsBySessionID["stable"] else {
            // Guarded rather than force-unwrapped: a nil here would crash the
            // whole test host and take every unrelated suite down with it.
            Issue.record("no fingerprint recorded for a session with a log")
            return
        }

        // A sentinel the parser could never produce proves the cache was used
        // rather than the file re-read.
        let sentinel = StokdSessionOutcomeSummary(
            sessionID: "stable",
            latestKindRaw: "fixed",
            headline: "CACHED SENTINEL",
            countsByKind: ["fixed": 1],
            entryCount: 1,
            updatedAt: Date(timeIntervalSince1970: 0),
            disposition: nil,
            isRunning: false
        )
        let second = StokdSessionOutcomesScanner.scan(
            root: fixture.root,
            home: fixture.home,
            previousSummaries: ["stable": sentinel],
            previousFingerprints: ["stable": fingerprint]
        )

        #expect(second.summariesBySessionID["stable"]?.headline == "CACHED SENTINEL")
    }

    /// Walking up from a directory inside the workspace finds the root, so a
    /// pane cwd'd into a subdirectory still resolves.
    @Test func theWorkspaceRootResolvesFromASubdirectory() throws {
        let fixture = try Fixture()
        defer { fixture.cleanUp() }
        try FileManager.default.createDirectory(
            at: StokdWorkspaceStatePaths.runtimeDirectory(forRoot: fixture.root, home: fixture.home),
            withIntermediateDirectories: true
        )
        let nested = URL(fileURLWithPath: fixture.root).appendingPathComponent("Sources/Stokd")
        try FileManager.default.createDirectory(at: nested, withIntermediateDirectories: true)

        let resolved = Scanner.resolveWorkspaceRoot(
            forDirectory: nested.path,
            home: fixture.home
        )

        #expect(resolved == URL(fileURLWithPath: fixture.root).resolvingSymlinksInPath().path)
    }

    @Test func aDirectoryOutsideAnyStokdWorkspaceResolvesToNil() throws {
        let fixture = try Fixture()
        defer { fixture.cleanUp() }

        let resolved = Scanner.resolveWorkspaceRoot(
            forDirectory: NSTemporaryDirectory(),
            home: fixture.home
        )

        #expect(resolved == nil)
    }
}
