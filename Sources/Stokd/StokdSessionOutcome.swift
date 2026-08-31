import Foundation

/// One entry an agent session appended to its `.outcomes.jsonl`.
///
/// stokd writes these live — append-only, fsynced per entry — so a reader can
/// always encounter a half-written trailing line. Decoding is therefore
/// tolerant by contract, never fatal (AX-GDOCK-PANEL-CARD-SESSION-SUMMARY).
struct StokdSessionOutcomeRecord: Equatable, Sendable {
    /// The outcome kinds stokd emits today.
    ///
    /// The raw string is kept alongside this so an unrecognized future kind
    /// still displays, rather than dropping the entry: gdock ships on its own
    /// cadence and must not go blind when the CLI adds a kind.
    enum Kind: String, Equatable, Sendable, CaseIterable {
        case fixed
        case decided
        case shipped
        case blocked
        case needsYou = "needs-you"
    }

    let sessionID: String
    let timestamp: Date
    /// Kind exactly as written, so unknown kinds survive.
    let kindRaw: String
    let text: String
    let attribution: String?
    let branch: String?
    let isDirty: Bool
    let isUnpushed: Bool

    var kind: Kind? { Kind(rawValue: kindRaw) }

    init(
        sessionID: String,
        timestamp: Date,
        kindRaw: String,
        text: String,
        attribution: String? = nil,
        branch: String? = nil,
        isDirty: Bool = false,
        isUnpushed: Bool = false
    ) {
        self.sessionID = sessionID
        self.timestamp = timestamp
        self.kindRaw = kindRaw
        self.text = text
        self.attribution = attribution
        self.branch = branch
        self.isDirty = isDirty
        self.isUnpushed = isUnpushed
    }
}

// MARK: - Decoding

extension StokdSessionOutcomeRecord: Decodable {
    private enum CodingKeys: String, CodingKey {
        case sessionID = "session_id"
        case entryTimestamp = "entry_timestamp"
        case kind
        case text
        case footprint
        case attribution
    }

    private struct Footprint: Decodable {
        let branch: String?
        let dirty: Bool?
        let unpushed: Bool?
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        sessionID = try container.decodeIfPresent(String.self, forKey: .sessionID) ?? ""
        kindRaw = try container.decode(String.self, forKey: .kind)
        text = try container.decode(String.self, forKey: .text)
        attribution = try container.decodeIfPresent(String.self, forKey: .attribution)

        let rawTimestamp = try container.decode(String.self, forKey: .entryTimestamp)
        guard let parsed = StokdSessionOutcomeRecord.parseTimestamp(rawTimestamp) else {
            throw DecodingError.dataCorruptedError(
                forKey: .entryTimestamp,
                in: container,
                debugDescription: "unparseable RFC 3339 timestamp \(rawTimestamp)"
            )
        }
        timestamp = parsed

        let footprint = try container.decodeIfPresent(Footprint.self, forKey: .footprint)
        branch = footprint?.branch
        isDirty = footprint?.dirty ?? false
        isUnpushed = footprint?.unpushed ?? false
    }

    /// stokd writes microsecond precision (`...19.717738+00:00`), but the
    /// fractional part is not guaranteed, so both shapes are accepted.
    static func parseTimestamp(_ raw: String) -> Date? {
        for formatter in [fractionalFormatter, plainFormatter] {
            if let date = formatter.date(from: raw) { return date }
        }
        return nil
    }

    private static let fractionalFormatter: ISO8601DateFormatter = {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return formatter
    }()

    private static let plainFormatter: ISO8601DateFormatter = {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime]
        return formatter
    }()
}

/// Tolerant reader for the append-only JSONL the stokd CLI writes.
enum StokdSessionOutcomeLog {
    /// Decodes every line that is a valid record and silently skips the rest.
    ///
    /// Blank lines, malformed JSON, and a truncated trailing line are all
    /// expected — the file is being appended to while it is read — so a bad
    /// line must never discard the good ones around it.
    static func records(fromJSONL text: String) -> [StokdSessionOutcomeRecord] {
        let decoder = JSONDecoder()
        var records: [StokdSessionOutcomeRecord] = []
        for line in text.split(separator: "\n", omittingEmptySubsequences: false) {
            let trimmed = line.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmed.isEmpty, let data = trimmed.data(using: .utf8) else { continue }
            guard let record = try? decoder.decode(StokdSessionOutcomeRecord.self, from: data) else { continue }
            records.append(record)
        }
        return records
    }
}

/// What one pane's card shows about its agent session.
///
/// A value, not a view model: it crosses the sidebar's lazy-list boundary, where
/// holding an observable reference is what reintroduces the 100%-CPU spin loop
/// (CLAUDE.md; issue 2586).
struct StokdSessionOutcomeSummary: Equatable, Sendable {
    let sessionID: String
    /// Kind of the most recent entry, exactly as written.
    let latestKindRaw: String
    /// One derived line — never the raw entry text, which runs to paragraphs.
    let headline: String
    /// Entry count per raw kind, for the accessibility label and tooltip.
    let countsByKind: [String: Int]
    let entryCount: Int
    let updatedAt: Date
    /// Terminal disposition once the session declared one (`dev_complete`,
    /// `blocked`, …), otherwise nil.
    let disposition: String?
    let isRunning: Bool

    var latestKind: StokdSessionOutcomeRecord.Kind? {
        StokdSessionOutcomeRecord.Kind(rawValue: latestKindRaw)
    }
}

/// Reduces a session's raw entries into the single value a card renders.
///
/// Pure, so the headline derivation and the "latest entry wins" rule are
/// unit-tested without a filesystem.
enum StokdSessionOutcomeSummarizer {
    /// Headlines are capped so a card stays one line at any sidebar width.
    static let headlineLimit = 90

    /// First sentence of `text`, whitespace-collapsed, without a trailing
    /// period, capped at ``headlineLimit`` characters with a trailing ellipsis.
    static func headline(from text: String) -> String {
        let collapsed = text
            .split(whereSeparator: { $0.isWhitespace || $0.isNewline })
            .joined(separator: " ")
        guard !collapsed.isEmpty else { return "" }

        let sentence = firstSentence(of: collapsed)
        let trimmed = sentence.trimmingCharacters(in: .whitespaces)
        guard trimmed.count > headlineLimit else { return trimmed }
        let clipped = String(trimmed.prefix(headlineLimit - 1))
            .trimmingCharacters(in: .whitespaces)
        return clipped + "…"
    }

    /// Splits on the first sentence-ending period followed by a space, so
    /// decimals and abbreviations mid-sentence do not cut the headline short.
    /// A single sentence keeps its whole text minus the final period.
    private static func firstSentence(of collapsed: String) -> String {
        var index = collapsed.startIndex
        while let period = collapsed[index...].firstIndex(of: ".") {
            let next = collapsed.index(after: period)
            if next == collapsed.endIndex {
                // Trailing period: the sentence is everything before it.
                return String(collapsed[collapsed.startIndex..<period])
            }
            if collapsed[next] == " " {
                return String(collapsed[collapsed.startIndex..<period])
            }
            index = next
        }
        return collapsed
    }

    /// Builds the summary, or nil when the session has no entries at all —
    /// a card with nothing to say renders exactly as it does today.
    static func summary(
        sessionID: String,
        records: [StokdSessionOutcomeRecord],
        disposition: String? = nil,
        isRunning: Bool = false
    ) -> StokdSessionOutcomeSummary? {
        guard let latest = records.max(by: { $0.timestamp < $1.timestamp }) else { return nil }

        var counts: [String: Int] = [:]
        for record in records {
            counts[record.kindRaw, default: 0] += 1
        }

        return StokdSessionOutcomeSummary(
            sessionID: sessionID,
            latestKindRaw: latest.kindRaw,
            headline: headline(from: latest.text),
            countsByKind: counts,
            entryCount: records.count,
            updatedAt: latest.timestamp,
            disposition: disposition?.trimmingCharacters(in: .whitespacesAndNewlines).nilIfEmpty,
            isRunning: isRunning
        )
    }
}

private extension String {
    var nilIfEmpty: String? { isEmpty ? nil : self }
}
