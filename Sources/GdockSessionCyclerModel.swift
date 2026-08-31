import Foundation

/// One agent session the cycler can move to.
///
/// A value snapshot reduced from live state *above* the overlay's lazy list, per
/// the SwiftUI list-boundary rule in `CLAUDE.md`: no view in the overlay may
/// hold a store reference (cmux issue 2586).
///
/// Identity is the panel, not the workspace: two panes in one directory
/// routinely run different sessions, which is the same reason
/// `GdockWorkspacePanelCardBuilder` keys summaries by pane.
struct GdockCyclableSession: Equatable, Identifiable, Sendable {
    /// The panel running the agent. Also the row's identity.
    let panelId: UUID
    let workspaceId: UUID
    /// Workspace display name, used as the row's secondary text and searched.
    let workspaceName: String
    /// `owner/repo` when the workspace sits in a repository group.
    let repoSlug: String?
    /// Pane title — the terminal or agent title the operator recognizes.
    let title: String
    let branch: String?
    /// Asset-catalog name of the provider's brand mark (`AgentIcons/*`).
    let agentAssetName: String?
    let agentDisplayName: String
    /// What this session's stokd outcome log says it has been doing, when it has
    /// one. Rendered only on the highlighted row.
    let summary: StokdSessionOutcomeSummary?
    /// Newest activity known for the session, used to order rows.
    let lastActivity: Date?

    var id: UUID { panelId }
}

/// One rendered row of the cycler.
struct GdockSessionCyclerRow: Equatable, Identifiable {
    let session: GdockCyclableSession
    let isHighlighted: Bool
    /// Non-nil only on the highlighted row: a wall of summaries would defeat
    /// the point of a fast cycler (AX-GDOCK-SESSION-CYCLER).
    let summary: StokdSessionOutcomeSummary?

    var id: UUID { session.panelId }
    var title: String { session.title }
    var agentAssetName: String? { session.agentAssetName }
}

/// The rows for one (scope, query, selection) triple.
struct GdockSessionCyclerListing: Equatable {
    let rows: [GdockSessionCyclerRow]
    /// Index of the highlighted row, or nil when there is nothing to highlight.
    let selectedIndex: Int?

    static let empty = GdockSessionCyclerListing(rows: [], selectedIndex: nil)

    var isEmpty: Bool { rows.isEmpty }

    var highlightedSession: GdockCyclableSession? {
        guard let selectedIndex, rows.indices.contains(selectedIndex) else { return nil }
        return rows[selectedIndex].session
    }
}

/// Pure reduction of sessions + scope + query + selection into rows.
///
/// Everything the overlay needs to decide what to draw and where the selection
/// goes lives here, so scope filtering, query filtering and wrap-around are
/// tested without a window, a workspace, or a filesystem.
enum GdockSessionCyclerModel {
    static func listing(
        sessions: [GdockCyclableSession],
        scope: GdockSessionCycleScope,
        currentRepoSlug: String?,
        isGroupedRepoModeEnabled: Bool,
        query: String,
        selectedPanelId: UUID?
    ) -> GdockSessionCyclerListing {
        let scoped = inScope(
            sessions,
            scope: scope,
            currentRepoSlug: currentRepoSlug,
            isGroupedRepoModeEnabled: isGroupedRepoModeEnabled
        )
        let matching = matches(scoped, query: query)
        guard !matching.isEmpty else { return .empty }

        // A selection that did not survive the scope or the filter clamps to the
        // first row: the operator always has something highlighted to act on.
        let selectedIndex = selectedPanelId
            .flatMap { panelId in matching.firstIndex(where: { $0.panelId == panelId }) } ?? 0

        let rows = matching.enumerated().map { index, session in
            let isHighlighted = index == selectedIndex
            return GdockSessionCyclerRow(
                session: session,
                isHighlighted: isHighlighted,
                summary: isHighlighted ? session.summary : nil
            )
        }
        return GdockSessionCyclerListing(rows: rows, selectedIndex: selectedIndex)
    }

    static func selection(
        movedBy offset: Int,
        from selectedPanelId: UUID?,
        in listing: GdockSessionCyclerListing
    ) -> UUID? {
        let rows = listing.rows
        guard !rows.isEmpty else { return nil }

        // With nothing selected the first press must land on a row rather than
        // no-op, otherwise the chord reads as a dead key.
        guard let panelId = selectedPanelId,
              let index = rows.firstIndex(where: { $0.session.panelId == panelId }) else {
            return rows[0].session.panelId
        }

        let count = rows.count
        let destination = ((index + offset) % count + count) % count
        return rows[destination].session.panelId
    }

    // MARK: - Filtering

    /// Sessions this scope shows.
    ///
    /// `currentRepo` falls back to everything when there is no repository
    /// grouping to narrow by — grouped workspace-repo mode off, or a selected
    /// workspace that is not in an `owner/repo` group. Narrowing to nothing
    /// would hand the operator an empty cycler instead of their sessions.
    private static func inScope(
        _ sessions: [GdockCyclableSession],
        scope: GdockSessionCycleScope,
        currentRepoSlug: String?,
        isGroupedRepoModeEnabled: Bool
    ) -> [GdockCyclableSession] {
        switch scope {
        case .allSessions:
            return sessions
        case .currentRepo:
            guard isGroupedRepoModeEnabled, let currentRepoSlug else { return sessions }
            return sessions.filter { $0.repoSlug == currentRepoSlug }
        }
    }

    /// Case-insensitive substring match over what identifies a session: its
    /// title, where it is, and what it last did.
    ///
    /// The provider name is deliberately *not* searched. Every row already
    /// shows its provider mark, and including it would make "claude" match
    /// every Claude session regardless of title — turning a filter that narrows
    /// into one that mostly does not.
    private static func matches(
        _ sessions: [GdockCyclableSession],
        query: String
    ) -> [GdockCyclableSession] {
        let needle = query.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !needle.isEmpty else { return sessions }

        return sessions.filter { session in
            let haystack = [
                session.title,
                session.workspaceName,
                session.repoSlug ?? "",
                session.branch ?? "",
                session.summary?.headline ?? "",
            ]
            return haystack.contains { $0.lowercased().contains(needle) }
        }
    }
}
