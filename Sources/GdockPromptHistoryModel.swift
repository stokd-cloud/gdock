import Foundation

/// One rendered row of the prompt-history overlay.
///
/// Carries text the view can draw directly — including the already-formatted
/// relative age — so nothing below the overlay's stack has to reach back into a
/// store or a formatter (`CLAUDE.md`; cmux issue 2586).
struct GdockPromptHistoryRow: Equatable, Identifiable {
    let id: UUID
    let text: String
    /// Pre-formatted age, e.g. "2 min. ago".
    let relativeTime: String
    /// The newest prompt, drawn last and emphasized.
    let isNewest: Bool
}

/// Mutable state behind the prompt-history overlay.
@MainActor
@Observable
final class GdockPromptHistoryViewModel {
    /// Oldest first: the overlay renders top-to-bottom, so the newest prompt is
    /// the last row and sits at the bottom edge.
    private(set) var rows: [GdockPromptHistoryRow] = []
    /// Pane the rows belong to, shown beside the title.
    private(set) var sessionTitle: String = ""
    /// Prompts that exist but did not fit. The overlay never scrolls, so it says
    /// so instead of silently hiding history.
    private(set) var hiddenCount: Int = 0
    /// False until the first collection pass, so the empty state cannot flash
    /// before any data has been read.
    private(set) var hasLoaded: Bool = false

    func apply(
        visible: [GdockPromptHistoryEntry],
        totalCount: Int,
        sessionTitle: String,
        now: Date = Date()
    ) {
        rows = Self.rows(from: visible, now: now)
        hiddenCount = max(0, totalCount - visible.count)
        self.sessionTitle = sessionTitle
        hasLoaded = true
    }

    func reset() {
        rows = []
        hiddenCount = 0
        sessionTitle = ""
        hasLoaded = false
    }

    static func rows(from entries: [GdockPromptHistoryEntry], now: Date) -> [GdockPromptHistoryRow] {
        let newestId = entries.last?.id
        return entries.map { entry in
            GdockPromptHistoryRow(
                id: entry.id,
                text: entry.text,
                relativeTime: relativeFormatter.localizedString(for: entry.submittedAt, relativeTo: now),
                isNewest: entry.id == newestId
            )
        }
    }

    /// Localized rather than hand-rolled: "2 min. ago" has to read correctly in
    /// every language cmux ships (`CLAUDE.md` localization rule).
    private static let relativeFormatter: RelativeDateTimeFormatter = {
        let formatter = RelativeDateTimeFormatter()
        formatter.unitsStyle = .short
        return formatter
    }()
}
