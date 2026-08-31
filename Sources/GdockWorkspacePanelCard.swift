import Foundation

/// One card describing a visible pane of the focused workspace.
///
/// The sidebar shows a card per visible pane — one pane, one card; four panes,
/// four cards — so the workspace you are looking at is legible from the
/// sidebar alone.
///
/// This is a value snapshot on purpose. Per the SwiftUI list-boundary rule in
/// `CLAUDE.md`, nothing below a lazy container may hold an observable store
/// reference, so the cards are reduced from live state *above* the boundary and
/// the views only ever read these fields.
struct GdockWorkspacePanelCard: Equatable, Identifiable, Sendable {
    /// Work item associated with a pane, as reported by stokd.
    struct WorkItem: Equatable, Sendable {
        enum Kind: String, Equatable, Sendable {
            case project
            case task
            case todo
        }

        let kind: Kind
        let title: String
        let status: String
        /// Short hash, when stokd has assigned one.
        let hashShort: String?

        init(kind: Kind, title: String, status: String, hashShort: String? = nil) {
            self.kind = kind
            self.title = title
            self.status = status
            self.hashShort = hashShort
        }
    }

    /// Bonsplit pane identity; also the card's identity.
    let id: UUID
    /// Position in the workspace's pane tree order, 0-based.
    let index: Int
    /// Pane title (terminal title, browser title, and so on).
    let title: String
    /// Working directory, already display-shortened by the caller.
    let directory: String
    /// Git branch when the pane's directory is in a repository.
    let branch: String?
    /// Whether this pane is the focused one.
    let isSelected: Bool
    /// Agent/session state line, when the pane is running one.
    let sessionState: String?
    /// The stokd work item this pane's repository is working on.
    let workItem: WorkItem?
    /// What this pane's stokd session has been doing, reduced from the
    /// session's append-only outcome log
    /// (AX-GDOCK-PANEL-CARD-SESSION-SUMMARY).
    let sessionSummary: StokdSessionOutcomeSummary?

    init(
        id: UUID,
        index: Int,
        title: String,
        directory: String,
        branch: String?,
        isSelected: Bool,
        sessionState: String?,
        workItem: WorkItem?,
        sessionSummary: StokdSessionOutcomeSummary? = nil
    ) {
        self.id = id
        self.index = index
        self.title = title
        self.directory = directory
        self.branch = branch
        self.isSelected = isSelected
        self.sessionState = sessionState
        self.workItem = workItem
        self.sessionSummary = sessionSummary
    }
}

/// Reduces live workspace state into ``GdockWorkspacePanelCard`` values.
///
/// Pure so the whole shape — count, order, which card is selected — is
/// unit-tested without a live workspace.
enum GdockWorkspacePanelCardBuilder {
    /// One visible pane as it exists in the workspace.
    struct PaneInput: Equatable, Sendable {
        let paneId: UUID
        let title: String
        let directory: String
        let branch: String?
        let sessionState: String?

        init(
            paneId: UUID,
            title: String,
            directory: String,
            branch: String? = nil,
            sessionState: String? = nil
        ) {
            self.paneId = paneId
            self.title = title
            self.directory = directory
            self.branch = branch
            self.sessionState = sessionState
        }
    }

    /// Builds the cards for one workspace.
    ///
    /// - Parameters:
    ///   - panes: Visible panes in pane-tree order. Panes with no surface are
    ///     excluded by the caller; a workspace always renders exactly as many
    ///     cards as it shows panes.
    ///   - focusedPaneId: The workspace's focused pane.
    ///   - workItemsByDirectory: Resolved stokd work items keyed by the pane
    ///     directory they belong to.
    ///   - summariesByPaneId: Session outcome summaries keyed by the pane whose
    ///     session they describe. Two panes in one directory can be running
    ///     different sessions, so these are keyed by pane rather than by
    ///     directory. Empty — the default — reproduces the pre-summary output
    ///     exactly.
    /// - Returns: One card per pane, in order. At most one card is selected —
    ///   when `focusedPaneId` names no visible pane, the first card is selected
    ///   so the sidebar never shows a workspace with nothing highlighted.
    static func cards(
        panes: [PaneInput],
        focusedPaneId: UUID?,
        workItemsByDirectory: [String: GdockWorkspacePanelCard.WorkItem] = [:],
        summariesByPaneId: [UUID: StokdSessionOutcomeSummary] = [:]
    ) -> [GdockWorkspacePanelCard] {
        guard !panes.isEmpty else { return [] }

        let selectedPaneId: UUID = {
            if let focusedPaneId, panes.contains(where: { $0.paneId == focusedPaneId }) {
                return focusedPaneId
            }
            return panes[0].paneId
        }()

        return panes.enumerated().map { index, pane in
            GdockWorkspacePanelCard(
                id: pane.paneId,
                index: index,
                title: pane.title,
                directory: pane.directory,
                branch: pane.branch,
                isSelected: pane.paneId == selectedPaneId,
                sessionState: pane.sessionState,
                workItem: workItemsByDirectory[pane.directory],
                sessionSummary: summariesByPaneId[pane.paneId]
            )
        }
    }
}
