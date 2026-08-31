import Foundation
import Testing

#if canImport(cmux_DEV)
@testable import cmux_DEV
#elseif canImport(cmux)
@testable import cmux
#endif

/// Tolerant reading of the append-only log (AC3) and derivation of the one line
/// a card shows (AC4).
@Suite struct StokdSessionOutcomeSummarizerTests {
    private typealias Log = StokdSessionOutcomeLog
    private typealias Summarizer = StokdSessionOutcomeSummarizer

    private static let sessionID = "captured-claude-92991-1788120376830420000"

    private static func line(
        kind: String,
        timestamp: String,
        text: String
    ) -> String {
        let escaped = text.replacingOccurrences(of: "\"", with: "\\\"")
        return """
        {"session_id":"\(sessionID)","entry_timestamp":"\(timestamp)","kind":"\(kind)",\
        "text":"\(escaped)","footprint":{"packages":{},"branch":"HEAD","dirty":false,"unpushed":false},\
        "attribution":"agent"}
        """
    }

    // MARK: - AC3, tolerant decoding

    /// The writer appends and fsyncs per entry, so a reader routinely sees a
    /// half-written last line. One bad line must never discard the good ones.
    @Test func malformedBlankAndTruncatedLinesAreSkippedWithoutLosingValidOnes() {
        let jsonl = [
            Self.line(kind: "fixed", timestamp: "2026-08-30T20:20:19.717738+00:00", text: "First entry."),
            "",
            "{ this is not json at all",
            Self.line(kind: "decided", timestamp: "2026-08-30T20:20:19.869565+00:00", text: "Second entry."),
            #"{"session_id":"x","entry_timestamp":"2026-08-30T20:2"#
        ].joined(separator: "\n")

        let records = Log.records(fromJSONL: jsonl)

        #expect(records.count == 2)
        #expect(records.map(\.kindRaw) == ["fixed", "decided"])
        #expect(records[0].text == "First entry.")
        #expect(records[1].text == "Second entry.")
    }

    @Test func recordsCarryTheFootprintAndAttribution() {
        let records = Log.records(fromJSONL: Self.line(
            kind: "shipped",
            timestamp: "2026-08-30T20:20:19.717738+00:00",
            text: "Shipped it."
        ))

        #expect(records.count == 1)
        #expect(records[0].sessionID == Self.sessionID)
        #expect(records[0].branch == "HEAD")
        #expect(records[0].isDirty == false)
        #expect(records[0].isUnpushed == false)
        #expect(records[0].attribution == "agent")
        #expect(records[0].kind == .shipped)
    }

    /// gdock ships on its own cadence, so a kind the CLI adds later must still
    /// display rather than vanish.
    @Test func anUnknownKindIsPreservedRatherThanDropped() {
        let records = Log.records(fromJSONL: Self.line(
            kind: "escalated",
            timestamp: "2026-08-30T20:20:19.717738+00:00",
            text: "Something new."
        ))

        #expect(records.count == 1)
        #expect(records[0].kindRaw == "escalated")
        #expect(records[0].kind == nil)
    }

    @Test func timestampsWithoutFractionalSecondsStillParse() {
        let records = Log.records(fromJSONL: Self.line(
            kind: "fixed",
            timestamp: "2026-08-30T20:20:19Z",
            text: "No fraction."
        ))

        #expect(records.count == 1)
    }

    @Test func needsYouDecodesToItsHyphenatedKind() {
        let records = Log.records(fromJSONL: Self.line(
            kind: "needs-you",
            timestamp: "2026-08-30T20:20:19.717738+00:00",
            text: "Waiting on a decision."
        ))

        #expect(records[0].kind == .needsYou)
    }

    // MARK: - AC4, summarization

    @Test func theLatestEntryDrivesTheKindAndHeadline() {
        let jsonl = [
            Self.line(kind: "fixed", timestamp: "2026-08-30T20:20:19.717738+00:00", text: "Older work."),
            Self.line(kind: "blocked", timestamp: "2026-08-30T22:00:00.000000+00:00", text: "Newest work."),
            Self.line(kind: "decided", timestamp: "2026-08-30T21:00:00.000000+00:00", text: "Middle work.")
        ].joined(separator: "\n")

        let summary = Summarizer.summary(
            sessionID: Self.sessionID,
            records: Log.records(fromJSONL: jsonl)
        )

        #expect(summary?.latestKindRaw == "blocked")
        #expect(summary?.latestKind == .blocked)
        #expect(summary?.headline == "Newest work")
    }

    @Test func everyKindIsCounted() {
        let jsonl = [
            Self.line(kind: "fixed", timestamp: "2026-08-30T20:00:00.000000+00:00", text: "a"),
            Self.line(kind: "fixed", timestamp: "2026-08-30T20:01:00.000000+00:00", text: "b"),
            Self.line(kind: "decided", timestamp: "2026-08-30T20:02:00.000000+00:00", text: "c")
        ].joined(separator: "\n")

        let summary = Summarizer.summary(
            sessionID: Self.sessionID,
            records: Log.records(fromJSONL: jsonl)
        )

        #expect(summary?.countsByKind == ["fixed": 2, "decided": 1])
        #expect(summary?.entryCount == 3)
    }

    @Test func aSessionWithNoEntriesHasNoSummary() {
        #expect(Summarizer.summary(sessionID: Self.sessionID, records: []) == nil)
    }

    @Test func dispositionAndRunningStateAreCarriedThrough() {
        let records = Log.records(fromJSONL: Self.line(
            kind: "shipped",
            timestamp: "2026-08-30T20:20:19.717738+00:00",
            text: "Done."
        ))

        let running = Summarizer.summary(sessionID: Self.sessionID, records: records, isRunning: true)
        let finished = Summarizer.summary(
            sessionID: Self.sessionID,
            records: records,
            disposition: "dev_complete\n",
            isRunning: false
        )

        #expect(running?.isRunning == true)
        #expect(running?.disposition == nil)
        #expect(finished?.isRunning == false)
        #expect(finished?.disposition == "dev_complete")
    }

    // MARK: - AC4, headline derivation

    @Test func theHeadlineIsTheFirstSentenceWithoutItsPeriod() {
        let text = "Resolved all 6 conflicted paths. The replayed commit was a subset. Staged, not committed."

        #expect(Summarizer.headline(from: text) == "Resolved all 6 conflicted paths")
    }

    @Test func theHeadlineCollapsesWhitespaceAndNewlines() {
        let text = "Retired  the\n review\tsurface"

        #expect(Summarizer.headline(from: text) == "Retired the review surface")
    }

    @Test func aSingleSentenceKeepsItsWholeTextMinusTheTrailingPeriod() {
        #expect(Summarizer.headline(from: "Just one thing.") == "Just one thing")
        #expect(Summarizer.headline(from: "No period at all") == "No period at all")
    }

    /// A period inside a token (a version, a filename, a decimal) is not a
    /// sentence break, or headlines would truncate to nonsense.
    @Test func aPeriodNotFollowedByASpaceDoesNotEndTheSentence() {
        let text = "Bumped grok-4.6 in the judge chain and re-ran it."

        #expect(Summarizer.headline(from: text) == "Bumped grok-4.6 in the judge chain and re-ran it")
    }

    @Test func aLongSentenceIsClippedToTheLimitWithAnEllipsis() {
        let text = String(repeating: "long ", count: 60) + "tail"

        let headline = Summarizer.headline(from: text)

        #expect(headline.count == Summarizer.headlineLimit)
        #expect(headline.hasSuffix("…"))
    }

    @Test func aHeadlineAtTheLimitIsNeverLongerThanTheLimit() {
        for count in [80, 89, 90, 91, 200] {
            let headline = Summarizer.headline(from: String(repeating: "x", count: count))
            #expect(headline.count <= Summarizer.headlineLimit)
        }
    }

    @Test func emptyTextProducesAnEmptyHeadline() {
        #expect(Summarizer.headline(from: "   \n  ") == "")
    }
}
