import Foundation

/// Decides which stokd session a terminal pane is actually running.
///
/// Process identity first, recency only as a fallback
/// (AX-GDOCK-PANEL-CARD-SESSION-SUMMARY). A workspace commonly holds several
/// sessions — some finished, some live — so "newest file wins" alone would
/// attribute one pane's work to another pane's card.
///
/// Pure over injected descriptors: the `getpgid` syscall and the directory
/// listing both happen in the caller, which is what lets the precedence order
/// be tested exhaustively without a filesystem or live processes.
enum StokdSessionOutcomesLocator {
    /// One session as it exists in a workspace's `runtime/sessions` directory.
    struct SessionDescriptor: Equatable, Sendable {
        let sessionID: String
        /// Session leader pid from `<session>.runtime.json`.
        let pid: Int32
        /// Process group from the same record; 0 when stokd did not record one.
        let pgid: Int32
        let isRunning: Bool
        /// Modification time of the session's `.outcomes.jsonl`, or of its
        /// runtime record when it has written no outcomes yet.
        let modifiedAt: Date

        init(
            sessionID: String,
            pid: Int32,
            pgid: Int32 = 0,
            isRunning: Bool,
            modifiedAt: Date
        ) {
            self.sessionID = sessionID
            self.pid = pid
            self.pgid = pgid
            self.isRunning = isRunning
            self.modifiedAt = modifiedAt
        }
    }

    /// Resolves the session bound to a pane.
    ///
    /// Precedence, highest first:
    /// 1. a session whose pid is one of the pane's own agent pids;
    /// 2. a session whose process group is one of the pane's agent process
    ///    groups — stokd may wrap the provider CLI, so the pane's pid can be a
    ///    sibling of the recorded leader rather than equal to it;
    /// 3. the most recently active *running* session in this workspace;
    /// 4. the most recently active session at all.
    ///
    /// Within a tier the most recently modified session wins, so the result is
    /// deterministic. Returns nil for an empty list: no session is invented,
    /// and the card then renders exactly as it does without stokd.
    static func session(
        agentPIDs: Set<Int32>,
        agentProcessGroupIDs: Set<Int32> = [],
        in descriptors: [SessionDescriptor]
    ) -> SessionDescriptor? {
        guard !descriptors.isEmpty else { return nil }

        if let exact = mostRecent(descriptors.filter { agentPIDs.contains($0.pid) }) {
            return exact
        }
        // A recorded pgid of 0 means "not recorded" and must not match a pane
        // that also failed to resolve a group.
        if let grouped = mostRecent(descriptors.filter {
            $0.pgid != 0 && agentProcessGroupIDs.contains($0.pgid)
        }) {
            return grouped
        }
        if let running = mostRecent(descriptors.filter(\.isRunning)) {
            return running
        }
        return mostRecent(descriptors)
    }

    private static func mostRecent(_ descriptors: [SessionDescriptor]) -> SessionDescriptor? {
        descriptors.max { lhs, rhs in
            if lhs.modifiedAt != rhs.modifiedAt { return lhs.modifiedAt < rhs.modifiedAt }
            // Stable tie-break so equal timestamps do not reorder between reads.
            return lhs.sessionID < rhs.sessionID
        }
    }
}
