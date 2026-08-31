import Foundation

/// Read-only mirror of stokd's on-disk state layout.
///
/// gdock never writes, truncates, locks, or migrates anything under
/// `~/.stokd` — it is strictly a consumer (AX-GDOCK-PANEL-CARD-SESSION-SUMMARY).
/// This type exists so the layout is derived in exactly one place rather than
/// string-guessed at each call site: the directory name stokd uses is a hash of
/// the canonical workspace root, so it cannot be reconstructed by convention.
///
/// The derivation is a port of `apps/cli/src/state_paths.rs` in stokd-cloud/mono
/// (`workspace_key`, `sanitize_segment`, `fnv1a64_hex`, `sanitize_session_id`).
/// Two worktrees of the same repository share a basename, so the digest is what
/// keeps their state apart.
enum StokdWorkspaceStatePaths {
    /// Maximum characters kept from the sanitized basename, matching the Rust
    /// `take(48)`.
    static let segmentLimit = 48

    /// Hex characters of the digest that appear in the key, matching the Rust
    /// `&digest[..12]`.
    static let digestPrefixLength = 12

    // MARK: - Key derivation

    /// Lowercases ASCII alphanumerics and collapses every run of other
    /// characters into a single dash, then trims dashes and caps the length.
    ///
    /// Leading non-alphanumerics are dropped rather than turned into a dash,
    /// because the Rust only emits a separator once output is non-empty.
    static func sanitizeSegment(_ input: String) -> String {
        var output = ""
        var lastWasDash = false
        for character in input {
            if character.isASCII, character.isLetter || character.isNumber {
                output.append(Character(character.lowercased()))
                lastWasDash = false
            } else if !lastWasDash, !output.isEmpty {
                output.append("-")
                lastWasDash = true
            }
        }
        // Trim before truncating: the Rust trims the whole string and only then
        // takes 48 characters, so a long input keeps its leading content.
        let trimmed = output.trimmingCharacters(in: CharacterSet(charactersIn: "-"))
        return String(trimmed.prefix(segmentLimit))
    }

    /// FNV-1a, 64-bit, zero-padded lowercase hex.
    ///
    /// Hashes UTF-8 bytes so multi-byte paths agree with the Rust, which walks
    /// `as_bytes()`.
    static func fnv1a64Hex(_ input: String) -> String {
        let offsetBasis: UInt64 = 0xcbf2_9ce4_8422_2325
        let prime: UInt64 = 0x0000_0100_0000_01b3
        var hash = offsetBasis
        for byte in input.utf8 {
            hash ^= UInt64(byte)
            hash = hash &* prime
        }
        return String(format: "%016lx", hash)
    }

    /// The directory name stokd stores this workspace's state under.
    static func workspaceKey(forRoot root: String) -> String {
        let canonical = canonicalRoot(root)
        let label = sanitizeSegment(URL(fileURLWithPath: canonical).lastPathComponent)
        let digest = fnv1a64Hex(canonical)
        let name = label.isEmpty ? "workspace" : label
        return "\(name)-\(String(digest.prefix(digestPrefixLength)))"
    }

    /// Resolves symlinks the way the Rust `canonicalize` does, and — like the
    /// Rust's `unwrap_or_else` — falls back to the path as given when it does
    /// not exist, so a key can still be derived for a stale or remote root.
    static func canonicalRoot(_ root: String) -> String {
        let url = URL(fileURLWithPath: root)
        guard FileManager.default.fileExists(atPath: url.path) else { return root }
        return url.resolvingSymlinksInPath().path
    }

    /// Sanitizes a session id into the single filesystem segment stokd names its
    /// per-session files with: alphanumerics, dash and underscore survive,
    /// everything else becomes `_`.
    static func sanitizeSessionID(_ sessionID: String) -> String {
        String(sessionID.map { character in
            if character.isASCII, character.isLetter || character.isNumber { return character }
            if character == "-" || character == "_" { return character }
            return "_"
        })
    }

    // MARK: - Paths

    /// `$STOKD_HOME`, or `~/.stokd`. The override exists so tests can point the
    /// whole layout at a temporary directory.
    static func homeDirectory(environment: [String: String] = ProcessInfo.processInfo.environment) -> URL {
        if let explicit = environment["STOKD_HOME"]?.trimmingCharacters(in: .whitespacesAndNewlines),
           !explicit.isEmpty {
            return URL(fileURLWithPath: explicit, isDirectory: true)
        }
        return FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent(".stokd", isDirectory: true)
    }

    static func workspaceStateDirectory(forRoot root: String, home: URL? = nil) -> URL {
        (home ?? homeDirectory())
            .appendingPathComponent("workspaces", isDirectory: true)
            .appendingPathComponent(workspaceKey(forRoot: root), isDirectory: true)
    }

    /// Holds the append-only `.outcomes.jsonl` and `.disposition` files.
    static func runtimeDirectory(forRoot root: String, home: URL? = nil) -> URL {
        workspaceStateDirectory(forRoot: root, home: home)
            .appendingPathComponent("runtime", isDirectory: true)
    }

    /// Holds one `<session>.runtime.json` per session, carrying pid/pgid/status.
    static func sessionRecordsDirectory(forRoot root: String, home: URL? = nil) -> URL {
        runtimeDirectory(forRoot: root, home: home)
            .appendingPathComponent("sessions", isDirectory: true)
    }

    static func outcomesFile(forRoot root: String, sessionID: String, home: URL? = nil) -> URL {
        runtimeDirectory(forRoot: root, home: home)
            .appendingPathComponent("\(sanitizeSessionID(sessionID)).outcomes.jsonl", isDirectory: false)
    }

    static func dispositionFile(forRoot root: String, sessionID: String, home: URL? = nil) -> URL {
        runtimeDirectory(forRoot: root, home: home)
            .appendingPathComponent("\(sanitizeSessionID(sessionID)).disposition", isDirectory: false)
    }

    static func sessionRecordFile(forRoot root: String, sessionID: String, home: URL? = nil) -> URL {
        sessionRecordsDirectory(forRoot: root, home: home)
            .appendingPathComponent("\(sanitizeSessionID(sessionID)).runtime.json", isDirectory: false)
    }
}
