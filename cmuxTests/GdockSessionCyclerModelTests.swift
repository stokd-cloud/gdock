import Foundation
import Testing

#if canImport(cmux_DEV)
@testable import cmux_DEV
#elseif canImport(cmux)
@testable import cmux
#endif

/// Scope filtering, query filtering, wrap-around selection and
/// summary-on-the-highlighted-row-only (AX-GDOCK-SESSION-CYCLER).
///
/// Every rule lives in pure functions over value inputs because the overlay
/// renders below a lazy container, where holding an observable store reference
/// is what reintroduces the spin loop (CLAUDE.md; cmux issue 2586).
@Suite struct GdockSessionCyclerModelTests {
    private typealias Model = GdockSessionCyclerModel
    private typealias Session = GdockCyclableSession

    private static func summary(
        headline: String,
        sessionID: String = "captured-claude-1-1",
        kind: String = "fixed"
    ) -> StokdSessionOutcomeSummary {
        StokdSessionOutcomeSummary(
            sessionID: sessionID,
            latestKindRaw: kind,
            headline: headline,
            countsByKind: [kind: 1],
            entryCount: 1,
            updatedAt: Date(timeIntervalSince1970: 1_788_120_000),
            startedAt: nil,
            disposition: nil,
            isRunning: true
        )
    }

    private static func session(
        title: String,
        repoSlug: String? = "stokd-cloud/gdock",
        workspaceName: String = "main",
        branch: String? = nil,
        headline: String? = nil
    ) -> Session {
        Session(
            panelId: UUID(),
            workspaceId: UUID(),
            workspaceName: workspaceName,
            repoSlug: repoSlug,
            title: title,
            branch: branch,
            agentAssetName: "AgentIcons/Claude",
            agentDisplayName: "Claude Code",
            summary: headline.map { summary(headline: $0) },
            lastActivity: Date(timeIntervalSince1970: 1_788_120_000)
        )
    }

    private static func listing(
        _ sessions: [Session],
        scope: GdockSessionCycleScope = .currentRepo,
        currentRepoSlug: String? = "stokd-cloud/gdock",
        groupedRepoMode: Bool = true,
        query: String = "",
        selected: UUID? = nil
    ) -> GdockSessionCyclerListing {
        Model.listing(
            sessions: sessions,
            scope: scope,
            currentRepoSlug: currentRepoSlug,
            isGroupedRepoModeEnabled: groupedRepoMode,
            query: query,
            selectedPanelId: selected
        )
    }

    // MARK: - Scope filtering

    @Test func currentRepoScopeKeepsOnlyTheCurrentRepositorysSessions() {
        let mine = Self.session(title: "gdock agent")
        let other = Self.session(title: "cli agent", repoSlug: "stokd-cloud/cli")

        let listing = Self.listing([mine, other], scope: .currentRepo)

        #expect(listing.rows.map(\.session.panelId) == [mine.panelId])
    }

    @Test func allSessionsScopeKeepsEverySession() {
        let mine = Self.session(title: "gdock agent")
        let other = Self.session(title: "cli agent", repoSlug: "stokd-cloud/cli")

        let listing = Self.listing([mine, other], scope: .allSessions)

        #expect(listing.rows.count == 2)
    }

    /// Without grouped workspace-repo mode there is no repository grouping to
    /// narrow to, so narrowing to nothing would hand the operator an empty
    /// cycler instead of their sessions.
    @Test func currentRepoScopeFallsBackToEverySessionWhenGroupedRepoModeIsOff() {
        let mine = Self.session(title: "gdock agent")
        let other = Self.session(title: "cli agent", repoSlug: "stokd-cloud/cli")

        let listing = Self.listing([mine, other], scope: .currentRepo, groupedRepoMode: false)

        #expect(listing.rows.count == 2)
    }

    @Test func currentRepoScopeFallsBackToEverySessionWhenNoRepositoryResolves() {
        let mine = Self.session(title: "gdock agent")
        let other = Self.session(title: "cli agent", repoSlug: "stokd-cloud/cli")

        let listing = Self.listing([mine, other], scope: .currentRepo, currentRepoSlug: nil)

        #expect(listing.rows.count == 2)
    }

    // MARK: - Query filtering

    @Test func queryMatchesTitleCaseInsensitively() {
        let claude = Self.session(title: "Claude — rebase")
        let codex = Self.session(title: "Codex — tests")

        let listing = Self.listing([claude, codex], query: "cLaUdE")

        #expect(listing.rows.map(\.session.panelId) == [claude.panelId])
    }

    @Test func queryMatchesWorkspaceNameBranchAndSummaryHeadline() {
        let byWorkspace = Self.session(title: "one", workspaceName: "task-fix-login")
        let byBranch = Self.session(title: "two", branch: "feature/session-cycler")
        let byHeadline = Self.session(title: "three", headline: "Resolved all six conflicted paths")
        let sessions = [byWorkspace, byBranch, byHeadline]

        #expect(Self.listing(sessions, query: "fix-login").rows.map(\.session.panelId) == [byWorkspace.panelId])
        #expect(Self.listing(sessions, query: "CYCLER").rows.map(\.session.panelId) == [byBranch.panelId])
        #expect(Self.listing(sessions, query: "conflicted").rows.map(\.session.panelId) == [byHeadline.panelId])
    }

    @Test func queryThatMatchesNothingYieldsAnEmptyListingWithNoSelection() {
        let listing = Self.listing([Self.session(title: "claude")], query: "zzzz")

        #expect(listing.rows.isEmpty)
        #expect(listing.isEmpty)
        #expect(listing.selectedIndex == nil)
        #expect(listing.highlightedSession == nil)
    }

    // MARK: - Highlighting

    @Test func exactlyTheHighlightedRowCarriesItsSessionSummary() {
        let first = Self.session(title: "one", headline: "First headline")
        let second = Self.session(title: "two", headline: "Second headline")

        let listing = Self.listing([first, second], selected: second.panelId)

        #expect(listing.rows.filter(\.isHighlighted).count == 1)
        #expect(listing.rows[1].isHighlighted)
        #expect(listing.rows[1].summary?.headline == "Second headline")
        #expect(listing.rows[0].summary == nil)
    }

    /// Unhighlighted rows still identify their agent: logo plus title is the
    /// whole of an unhighlighted row.
    @Test func everyRowCarriesItsProviderAssetAndTitle() {
        let listing = Self.listing([Self.session(title: "one"), Self.session(title: "two")])

        #expect(listing.rows.allSatisfy { $0.agentAssetName == "AgentIcons/Claude" })
        #expect(listing.rows.map(\.title) == ["one", "two"])
    }

    @Test func selectionClampsToTheFirstRowWhenTheSelectedSessionIsFilteredOut() {
        let kept = Self.session(title: "claude")
        let dropped = Self.session(title: "codex")

        let listing = Self.listing([kept, dropped], query: "claude", selected: dropped.panelId)

        #expect(listing.selectedIndex == 0)
        #expect(listing.highlightedSession?.panelId == kept.panelId)
    }

    @Test func scopeChangeKeepsTheSameSessionSelectedWhenItSurvives() {
        let mine = Self.session(title: "gdock agent")
        let other = Self.session(title: "cli agent", repoSlug: "stokd-cloud/cli")
        let sessions = [mine, other]

        let narrow = Self.listing(sessions, scope: .currentRepo, selected: mine.panelId)
        let wide = Self.listing(sessions, scope: .allSessions, selected: narrow.highlightedSession?.panelId)

        #expect(wide.highlightedSession?.panelId == mine.panelId)
    }

    @Test func scopeChangeClampsToTheFirstRowWhenTheSelectedSessionDoesNotSurvive() {
        let mine = Self.session(title: "gdock agent")
        let other = Self.session(title: "cli agent", repoSlug: "stokd-cloud/cli")

        let narrowed = Self.listing([mine, other], scope: .currentRepo, selected: other.panelId)

        #expect(narrowed.highlightedSession?.panelId == mine.panelId)
    }

    // MARK: - Wrap-around cycling

    @Test func advancingPastTheLastRowWrapsToTheFirst() {
        let first = Self.session(title: "one")
        let last = Self.session(title: "two")
        let listing = Self.listing([first, last], selected: last.panelId)

        let moved = Model.selection(movedBy: 1, from: last.panelId, in: listing)

        #expect(moved == first.panelId)
    }

    @Test func retreatingPastTheFirstRowWrapsToTheLast() {
        let first = Self.session(title: "one")
        let last = Self.session(title: "two")
        let listing = Self.listing([first, last], selected: first.panelId)

        let moved = Model.selection(movedBy: -1, from: first.panelId, in: listing)

        #expect(moved == last.panelId)
    }

    @Test func movingSelectionInAnEmptyListingYieldsNoSelection() {
        let listing = Self.listing([Self.session(title: "one")], query: "zzzz")

        #expect(Model.selection(movedBy: 1, from: nil, in: listing) == nil)
    }

    /// A first press with nothing selected must land on a row rather than
    /// no-op, otherwise the chord appears dead until a second press.
    @Test func movingSelectionWithNothingSelectedStartsAtTheFirstRow() {
        let first = Self.session(title: "one")
        let listing = Self.listing([first, Self.session(title: "two")])

        #expect(Model.selection(movedBy: 1, from: nil, in: listing) == first.panelId)
    }
}
