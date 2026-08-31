import Darwin
import Foundation

/// Off-actor filesystem scan of one workspace's stokd runtime state.
///
/// Split out from the store so every `FileManager` call is provably off the
/// main actor: the sidebar reduce may only read an already-computed snapshot
/// (AX-GDOCK-PANEL-CARD-SESSION-SUMMARY).
enum StokdSessionOutcomesScanner {
    /// Cheap change detector for one session's append-only log.
    ///
    /// Size and mtime together, because appending to an existing file leaves
    /// the *directory* mtime untouched — a directory-only check would go stale
    /// the moment a session stops creating files and starts appending to them.
    struct Fingerprint: Equatable, Sendable {
        let modifiedAt: Date
        let size: Int64
    }

    struct WorkspaceScan: Sendable {
        let key: String
        let root: String
        let descriptors: [StokdSessionOutcomesLocator.SessionDescriptor]
        let summariesBySessionID: [String: StokdSessionOutcomeSummary]
        let fingerprintsBySessionID: [String: Fingerprint]
    }

    /// Ancestor levels searched for a stokd workspace root. A pane's cwd is
    /// usually the root itself but may be any directory inside it.
    static let maximumAncestorDepth = 24

    /// Walks up from `directory` to the nearest ancestor that stokd has runtime
    /// state for, or nil when none does.
    static func resolveWorkspaceRoot(
        forDirectory directory: String,
        home: URL,
        fileManager: FileManager = .default
    ) -> String? {
        let trimmed = directory.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }

        var candidate = URL(fileURLWithPath: trimmed).standardizedFileURL
        for _ in 0..<maximumAncestorDepth {
            let path = candidate.path
            guard !path.isEmpty, path != "/" else { break }
            let runtime = StokdWorkspaceStatePaths.runtimeDirectory(forRoot: path, home: home)
            var isDirectory: ObjCBool = false
            if fileManager.fileExists(atPath: runtime.path, isDirectory: &isDirectory), isDirectory.boolValue {
                return path
            }
            let parent = candidate.deletingLastPathComponent().standardizedFileURL
            guard parent.path != candidate.path else { break }
            candidate = parent
        }
        return nil
    }

    /// Reads every session in one workspace, reusing a prior summary whenever
    /// the session's log is byte-for-byte unchanged.
    ///
    /// Driven by the **union** of `runtime/sessions/*.runtime.json` and
    /// `runtime/*.outcomes.jsonl`, because the two do not track each other:
    ///
    /// - stokd prunes a session's runtime record when the session ends but
    ///   keeps its log, so a record-only scan hides every finished session —
    ///   exactly the completed work most worth showing on a card.
    /// - A freshly started session has a record and no log yet, so a log-only
    ///   scan would leave a live pane with no session to bind to at all.
    ///
    /// A session missing its record contributes no process identity (pid and
    /// pgid stay 0, which the locator treats as "never matches") and competes
    /// only in the recency tiers.
    static func scan(
        root: String,
        home: URL,
        previousSummaries: [String: StokdSessionOutcomeSummary],
        previousFingerprints: [String: Fingerprint],
        fileManager: FileManager = .default
    ) -> WorkspaceScan {
        let key = StokdWorkspaceStatePaths.workspaceKey(forRoot: root)
        let recordsBySessionID = sessionRecords(root: root, home: home, fileManager: fileManager)
        let logSessionIDs = outcomeLogSessionIDs(root: root, home: home, fileManager: fileManager)

        var descriptors: [StokdSessionOutcomesLocator.SessionDescriptor] = []
        var summaries: [String: StokdSessionOutcomeSummary] = [:]
        var fingerprints: [String: Fingerprint] = [:]

        // Sorted so a scan is deterministic regardless of directory order.
        for sessionID in Set(recordsBySessionID.keys).union(logSessionIDs).sorted() {
            let record = recordsBySessionID[sessionID]
            let outcomesFile = StokdWorkspaceStatePaths.outcomesFile(
                forRoot: root,
                sessionID: sessionID,
                home: home
            )
            let fingerprint = self.fingerprint(of: outcomesFile, fileManager: fileManager)
            let disposition = dispositionText(forRoot: root, sessionID: sessionID, home: home)
            // No record means the session is over: stokd removed it on exit.
            let isRunning = record?.status.lowercased() == "running"

            if let fingerprint {
                fingerprints[sessionID] = fingerprint
            }

            let summary: StokdSessionOutcomeSummary?
            if let fingerprint,
               previousFingerprints[sessionID] == fingerprint,
               let cached = previousSummaries[sessionID],
               cached.disposition == disposition,
               cached.isRunning == isRunning,
               cached.startedAt == record?.startedAt {
                // Unchanged log and unchanged session state: nothing to reparse.
                summary = cached
            } else if fingerprint != nil,
                      let text = try? String(contentsOf: outcomesFile, encoding: .utf8) {
                summary = StokdSessionOutcomeSummarizer.summary(
                    sessionID: sessionID,
                    records: StokdSessionOutcomeLog.records(fromJSONL: text),
                    disposition: disposition,
                    isRunning: isRunning,
                    startedAt: record?.startedAt
                )
            } else {
                summary = nil
            }

            if let summary {
                summaries[sessionID] = summary
            }
            let recordFile = StokdWorkspaceStatePaths.sessionRecordFile(
                forRoot: root,
                sessionID: sessionID,
                home: home
            )
            descriptors.append(
                StokdSessionOutcomesLocator.SessionDescriptor(
                    sessionID: sessionID,
                    pid: record?.pid ?? 0,
                    pgid: record?.pgid ?? 0,
                    isRunning: isRunning,
                    modifiedAt: fingerprint?.modifiedAt
                        ?? modificationDate(of: recordFile, fileManager: fileManager)
                        ?? .distantPast
                )
            )
        }

        return WorkspaceScan(
            key: key,
            root: root,
            descriptors: descriptors,
            summariesBySessionID: summaries,
            fingerprintsBySessionID: fingerprints
        )
    }

    // MARK: - Directory listings

    /// Runtime records keyed by the sanitized session id their filename uses,
    /// so they line up with the log filenames.
    private static func sessionRecords(
        root: String,
        home: URL,
        fileManager: FileManager
    ) -> [String: SessionRecord] {
        let directory = StokdWorkspaceStatePaths.sessionRecordsDirectory(forRoot: root, home: home)
        let files = (try? fileManager.contentsOfDirectory(
            at: directory,
            includingPropertiesForKeys: nil
        )) ?? []

        var result: [String: SessionRecord] = [:]
        for file in files {
            let name = file.lastPathComponent
            guard name.hasSuffix(".runtime.json") else { continue }
            guard let record = sessionRecord(at: file), !record.sessionID.isEmpty else { continue }
            result[StokdWorkspaceStatePaths.sanitizeSessionID(record.sessionID)] = record
        }
        return result
    }

    /// Session ids that have an outcome log, taken from the filenames — which
    /// are already the sanitized form the path builders round-trip to.
    private static func outcomeLogSessionIDs(
        root: String,
        home: URL,
        fileManager: FileManager
    ) -> Set<String> {
        let directory = StokdWorkspaceStatePaths.runtimeDirectory(forRoot: root, home: home)
        let files = (try? fileManager.contentsOfDirectory(
            at: directory,
            includingPropertiesForKeys: nil
        )) ?? []

        let suffix = ".outcomes.jsonl"
        var result: Set<String> = []
        for file in files {
            let name = file.lastPathComponent
            guard name.hasSuffix(suffix) else { continue }
            let sessionID = String(name.dropLast(suffix.count))
            guard !sessionID.isEmpty else { continue }
            result.insert(sessionID)
        }
        return result
    }

    // MARK: - Individual files

    private struct SessionRecord: Decodable {
        let sessionID: String
        let pid: Int32
        let pgid: Int32
        let status: String
        /// `started_at` is epoch milliseconds in stokd's runtime record.
        let startedAt: Date?

        private enum CodingKeys: String, CodingKey {
            case sessionID = "session_id"
            case pid
            case pgid
            case status
            case startedAt = "started_at"
        }

        init(from decoder: Decoder) throws {
            let container = try decoder.container(keyedBy: CodingKeys.self)
            sessionID = try container.decodeIfPresent(String.self, forKey: .sessionID) ?? ""
            pid = try container.decodeIfPresent(Int32.self, forKey: .pid) ?? 0
            pgid = try container.decodeIfPresent(Int32.self, forKey: .pgid) ?? 0
            status = try container.decodeIfPresent(String.self, forKey: .status) ?? ""
            if let milliseconds = try container.decodeIfPresent(Double.self, forKey: .startedAt),
               milliseconds > 0 {
                startedAt = Date(timeIntervalSince1970: milliseconds / 1000)
            } else {
                startedAt = nil
            }
        }
    }

    private static func sessionRecord(at url: URL) -> SessionRecord? {
        guard let data = try? Data(contentsOf: url) else { return nil }
        return try? JSONDecoder().decode(SessionRecord.self, from: data)
    }

    private static func dispositionText(
        forRoot root: String,
        sessionID: String,
        home: URL
    ) -> String? {
        let url = StokdWorkspaceStatePaths.dispositionFile(
            forRoot: root,
            sessionID: sessionID,
            home: home
        )
        guard let raw = try? String(contentsOf: url, encoding: .utf8) else { return nil }
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }

    private static func fingerprint(of url: URL, fileManager: FileManager) -> Fingerprint? {
        guard let attributes = try? fileManager.attributesOfItem(atPath: url.path),
              let modifiedAt = attributes[.modificationDate] as? Date else { return nil }
        let size = (attributes[.size] as? NSNumber)?.int64Value ?? 0
        return Fingerprint(modifiedAt: modifiedAt, size: size)
    }

    private static func modificationDate(of url: URL, fileManager: FileManager) -> Date? {
        (try? fileManager.attributesOfItem(atPath: url.path))?[.modificationDate] as? Date
    }
}

/// Caches stokd session summaries for the sidebar.
///
/// Shaped after ``StokdEnvironmentStore`` so both stokd-backed sidebar surfaces
/// refresh the same way: an idempotent `refreshIfNeeded` kicked off from the
/// render path, and a synchronous read that only ever touches memory.
@MainActor
final class StokdSessionOutcomesStore: ObservableObject {
    static let shared = StokdSessionOutcomesStore()

    /// Bumped only when a scan actually changed what a card would draw.
    ///
    /// The sidebar container observes this so new outcomes appear without
    /// waiting for an unrelated invalidation. Publishing on every scan instead
    /// would rebuild the whole sidebar on a timer, which is exactly the kind of
    /// churn the list-boundary rules exist to prevent.
    @Published private(set) var snapshotVersion: Int = 0

    /// Floor between scans of one directory. The sidebar reduce runs far more
    /// often than agents append outcomes, so without this the render path would
    /// queue a scan per build.
    let minimumRefreshInterval: TimeInterval

    private let home: URL
    private var summariesByKey: [String: [String: StokdSessionOutcomeSummary]] = [:]
    private var descriptorsByKey: [String: [StokdSessionOutcomesLocator.SessionDescriptor]] = [:]
    private var fingerprintsByKey: [String: [String: StokdSessionOutcomesScanner.Fingerprint]] = [:]
    /// Pane directory to the workspace root that owns its stokd state.
    private var rootByDirectory: [String: String] = [:]
    private var lastAttemptByDirectory: [String: Date] = [:]
    private var inFlightDirectories: Set<String> = []

    init(
        home: URL = StokdWorkspaceStatePaths.homeDirectory(),
        minimumRefreshInterval: TimeInterval = 2
    ) {
        self.home = home
        self.minimumRefreshInterval = minimumRefreshInterval
    }

    /// Schedules a scan for any of `directories` not scanned recently.
    ///
    /// Safe to call on every sidebar build: it does no filesystem work itself,
    /// and the interval plus in-flight guard collapse repeat calls.
    func refreshIfNeeded(directories: [String], now: Date = Date()) {
        for directory in Set(directories) {
            let trimmed = directory.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmed.isEmpty, !inFlightDirectories.contains(trimmed) else { continue }
            if let last = lastAttemptByDirectory[trimmed],
               now.timeIntervalSince(last) < minimumRefreshInterval {
                continue
            }
            lastAttemptByDirectory[trimmed] = now
            inFlightDirectories.insert(trimmed)
            scheduleScan(directory: trimmed)
        }
    }

    /// The summary for the session this pane is running, or nil.
    ///
    /// A pure read of the last published snapshot plus one `getpgid` per agent
    /// pid — no allocation-heavy work, no IO, no subprocess — so it is legal on
    /// the render path.
    func summary(forDirectory directory: String, agentPIDs: [Int32]) -> StokdSessionOutcomeSummary? {
        let trimmed = directory.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty,
              let root = rootByDirectory[trimmed] else { return nil }
        let key = StokdWorkspaceStatePaths.workspaceKey(forRoot: root)
        guard let descriptors = descriptorsByKey[key], !descriptors.isEmpty else { return nil }

        let pids = Set(agentPIDs.filter { $0 > 0 })
        let groups = Set(pids.compactMap { pid -> Int32? in
            let group = getpgid(pid)
            return group > 0 ? group : nil
        })
        guard let match = StokdSessionOutcomesLocator.session(
            agentPIDs: pids,
            agentProcessGroupIDs: groups,
            in: descriptors
        ) else { return nil }
        return summariesByKey[key]?[match.sessionID]
    }

    /// Drops every cached snapshot so the next refresh re-reads from disk.
    func invalidate() {
        summariesByKey.removeAll()
        descriptorsByKey.removeAll()
        fingerprintsByKey.removeAll()
        rootByDirectory.removeAll()
        lastAttemptByDirectory.removeAll()
    }

    private func scheduleScan(directory: String) {
        let home = home
        let knownRoot = rootByDirectory[directory]
        let previousKey = knownRoot.map { StokdWorkspaceStatePaths.workspaceKey(forRoot: $0) }
        let previousSummaries = previousKey.flatMap { summariesByKey[$0] } ?? [:]
        let previousFingerprints = previousKey.flatMap { fingerprintsByKey[$0] } ?? [:]

        Task.detached(priority: .utility) { [weak self] in
            let root = knownRoot ?? StokdSessionOutcomesScanner.resolveWorkspaceRoot(
                forDirectory: directory,
                home: home
            )
            let scan = root.map {
                StokdSessionOutcomesScanner.scan(
                    root: $0,
                    home: home,
                    previousSummaries: previousSummaries,
                    previousFingerprints: previousFingerprints
                )
            }
            await MainActor.run {
                self?.apply(scan: scan, directory: directory)
            }
        }
    }

    /// Publishes a completed scan. Internal so tests can drive the store
    /// without a filesystem.
    func apply(scan: StokdSessionOutcomesScanner.WorkspaceScan?, directory: String) {
        inFlightDirectories.remove(directory)
        guard let scan else {
            // Not a stokd workspace — remember nothing, so the next refresh
            // re-checks cheaply once the interval elapses.
            let hadRoot = rootByDirectory.removeValue(forKey: directory) != nil
            if hadRoot { snapshotVersion += 1 }
            return
        }

        let changed = rootByDirectory[directory] != scan.root
            || descriptorsByKey[scan.key] != scan.descriptors
            || summariesByKey[scan.key] != scan.summariesBySessionID

        rootByDirectory[directory] = scan.root
        descriptorsByKey[scan.key] = scan.descriptors
        summariesByKey[scan.key] = scan.summariesBySessionID
        fingerprintsByKey[scan.key] = scan.fingerprintsBySessionID

        if changed { snapshotVersion += 1 }
    }
}
