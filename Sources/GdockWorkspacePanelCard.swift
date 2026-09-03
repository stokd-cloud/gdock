import AppKit
import Foundation

/// One card describing an agent session running in a panel of the focused
/// workspace.
///
/// Cards are emitted only for panels that are actually running an agent
/// (AX-GDOCK-PANEL-CARD-SESSION-SUMMARY): a plain shell panel gets no card, so a
/// four-pane workspace with one agent shows one card, not four rows of nothing.
/// Every panel counts, not only the one showing in each pane: an agent in a
/// background tab of a pane is still a session in this workspace, and the
/// stack is the one place all of them are listed.
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

    /// Panel identity (one tab in one pane); also the card's identity. A pane
    /// can host several panels, so the pane is not specific enough.
    let id: UUID
    /// Position in the workspace's pane-tree order among carded panels, 0-based.
    let index: Int
    /// Pane title, resolved through the workspace rather than read from the raw
    /// reporting map, so it is never blank.
    let title: String
    /// Working directory, resolved through the workspace's own fallback chain.
    let directory: String
    /// Git branch when the pane's directory is in a repository.
    let branch: String?
    /// Whether this panel is the focused one.
    let isSelected: Bool
    /// Whether this panel is the one its pane is currently showing. A card for
    /// a background tab is still a full card, but it says so.
    let isVisible: Bool
    /// Agent kind exactly as recorded on the pane's agent PID key (`claude`,
    /// `codex`, …). Drives the leading glyph.
    let agentKindRaw: String
    /// Agent/session state line, when the pane is running one.
    let sessionState: String?
    /// The stokd work item this pane's repository is working on.
    let workItem: WorkItem?
    /// What this pane's stokd session has been doing, reduced from the
    /// session's append-only outcome log.
    let sessionSummary: StokdSessionOutcomeSummary?

    init(
        id: UUID,
        index: Int,
        title: String,
        directory: String,
        branch: String?,
        isSelected: Bool,
        isVisible: Bool = true,
        agentKindRaw: String,
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
        self.isVisible = isVisible
        self.agentKindRaw = agentKindRaw
        self.sessionState = sessionState
        self.workItem = workItem
        self.sessionSummary = sessionSummary
    }
}

/// Resolves the leading agent glyph for a card.
///
/// Reuses the asset names the task-manager agent registry already declares
/// rather than keeping a second mapping, and falls back rather than rendering an
/// empty image for an agent gdock has no artwork for.
enum GdockAgentSessionGlyph {
    /// SF Symbol used when no bundled artwork exists for the agent.
    static let fallbackSymbolName = "sparkles"

    /// Asset catalog name for `agentKindRaw`, or nil when there is no artwork.
    ///
    /// The registry records `assetName: nil` for some agents whose artwork does
    /// exist in `Assets.xcassets/AgentIcons`, so a direct catalog name is tried
    /// second before giving up.
    static func assetName(
        forAgentKindRaw agentKindRaw: String,
        assetExists: (String) -> Bool = { NSImage(named: $0) != nil }
    ) -> String? {
        let id = agentKindRaw.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !id.isEmpty else { return nil }

        if let declared = CmuxTaskManagerCodingAgentDefinition.builtIns
            .first(where: { $0.id == id })?
            .assetName,
            assetExists(declared) {
            return declared
        }

        let candidate = "AgentIcons/\(capitalizedAssetLeaf(id))"
        return assetExists(candidate) ? candidate : nil
    }

    /// `hermesagent` -> `HermesAgent`, `opencode` -> `OpenCode`, `claude` ->
    /// `Claude`. Matches the imageset names in the catalog.
    private static func capitalizedAssetLeaf(_ id: String) -> String {
        switch id {
        case "hermesagent": return "HermesAgent"
        case "opencode": return "OpenCode"
        case "rovodev": return "RovoDev"
        default: return id.prefix(1).uppercased() + id.dropFirst()
        }
    }
}

/// Builds the single metadata line under a card's headline.
///
/// Deliberately carries only values that exist in the session's outcome log and
/// runtime record. The mockup showed "% Complete" and "Estimated Time left";
/// neither is recorded anywhere gdock can read, so they are omitted rather than
/// invented (AX-GDOCK-PANEL-CARD-SESSION-SUMMARY).
enum GdockAgentSessionCardMetadata {
    static let separator = " · "

    static func line(summary: StokdSessionOutcomeSummary, now: Date = Date()) -> String {
        var parts: [String] = []

        if let elapsed = summary.startedAt.map({ now.timeIntervalSince($0) }), elapsed >= 0 {
            let duration = compactDuration(elapsed)
            parts.append(
                summary.isRunning
                    ? String(
                        localized: "gdock.panelCard.meta.running",
                        defaultValue: "running \(duration)"
                    )
                    : String(
                        localized: "gdock.panelCard.meta.ran",
                        defaultValue: "ran \(duration)"
                    )
            )
        } else if summary.isRunning {
            parts.append(String(
                localized: "gdock.panelCard.meta.runningNoStart",
                defaultValue: "running"
            ))
        }

        if let counts = countsText(summary.countsByKind) {
            parts.append(counts)
        }

        let age = now.timeIntervalSince(summary.updatedAt)
        if age >= 0 {
            parts.append(String(
                localized: "gdock.panelCard.meta.last",
                defaultValue: "last \(compactDuration(age)) ago"
            ))
        }

        return parts.joined(separator: separator)
    }

    /// `38 fixed, 29 decided` — highest count first so the dominant activity
    /// leads, with the raw stokd kind token preserved.
    static func countsText(_ countsByKind: [String: Int]) -> String? {
        guard !countsByKind.isEmpty else { return nil }
        let ordered = countsByKind
            .filter { $0.value > 0 }
            .sorted { lhs, rhs in
                lhs.value != rhs.value ? lhs.value > rhs.value : lhs.key < rhs.key
            }
        guard !ordered.isEmpty else { return nil }
        return ordered.map { "\($0.value) \($0.key)" }.joined(separator: ", ")
    }

    /// `12s`, `4m`, `2h 14m`, `3d`. Compact so the line survives a narrow
    /// sidebar without wrapping.
    static func compactDuration(_ seconds: TimeInterval) -> String {
        let total = Int(max(0, seconds.rounded()))
        if total < 60 { return "\(total)s" }
        if total < 3600 { return "\(total / 60)m" }
        if total < 86_400 {
            let hours = total / 3600
            let minutes = (total % 3600) / 60
            return minutes == 0 ? "\(hours)h" : "\(hours)h \(minutes)m"
        }
        let days = total / 86_400
        let hours = (total % 86_400) / 3600
        return hours == 0 ? "\(days)d" : "\(days)d \(hours)h"
    }
}

/// Reduces live workspace state into ``GdockWorkspacePanelCard`` values.
///
/// Pure so the whole shape — which panels qualify, count, order, which card is
/// selected — is unit-tested without a live workspace.
enum GdockWorkspacePanelCardBuilder {
    /// One panel as it exists in the workspace: a tab in a pane, whether or
    /// not it is the tab that pane is currently showing.
    struct PanelInput: Equatable, Sendable {
        let panelId: UUID
        let title: String
        let directory: String
        let branch: String?
        /// Agent kind running in this panel, or nil when the panel runs no
        /// agent. Nil is what excludes the panel from producing a card.
        let agentKindRaw: String?
        let sessionState: String?
        /// Whether the panel's pane is currently showing it.
        let isVisible: Bool

        init(
            panelId: UUID,
            title: String,
            directory: String,
            branch: String? = nil,
            agentKindRaw: String? = nil,
            sessionState: String? = nil,
            isVisible: Bool = true
        ) {
            self.panelId = panelId
            self.title = title
            self.directory = directory
            self.branch = branch
            self.agentKindRaw = agentKindRaw
            self.sessionState = sessionState
            self.isVisible = isVisible
        }
    }

    /// Builds the cards for one workspace.
    ///
    /// - Parameters:
    ///   - panels: Every panel in the workspace, in pane-tree order with each
    ///     pane's tabs in tab order — background tabs included.
    ///   - focusedPanelId: The panel the workspace's focused pane is showing.
    ///   - workItemsByDirectory: Resolved stokd work items keyed by the panel
    ///     directory they belong to.
    ///   - summariesByPanelId: Session outcome summaries keyed by the panel
    ///     whose session they describe. Two panels in one directory can be
    ///     running different sessions, so these are keyed by panel rather
    ///     than by directory.
    /// - Returns: One card per *agent* panel, in the given order. Panels
    ///   running no agent are skipped entirely. At most one card is selected —
    ///   when the focused panel runs no agent, the first card is selected so
    ///   the stack never renders with nothing highlighted.
    static func cards(
        panels: [PanelInput],
        focusedPanelId: UUID?,
        workItemsByDirectory: [String: GdockWorkspacePanelCard.WorkItem] = [:],
        summariesByPanelId: [UUID: StokdSessionOutcomeSummary] = [:]
    ) -> [GdockWorkspacePanelCard] {
        let agentPanels = panels.filter { panel in
            guard let kind = panel.agentKindRaw else { return false }
            return !kind.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        }
        guard !agentPanels.isEmpty else { return [] }

        let selectedPanelId: UUID = {
            if let focusedPanelId, agentPanels.contains(where: { $0.panelId == focusedPanelId }) {
                return focusedPanelId
            }
            return agentPanels[0].panelId
        }()

        return agentPanels.enumerated().map { index, panel in
            GdockWorkspacePanelCard(
                id: panel.panelId,
                index: index,
                title: panel.title,
                directory: panel.directory,
                branch: panel.branch,
                isSelected: panel.panelId == selectedPanelId,
                isVisible: panel.isVisible,
                agentKindRaw: panel.agentKindRaw ?? "",
                sessionState: panel.sessionState,
                workItem: workItemsByDirectory[panel.directory],
                sessionSummary: summariesByPanelId[panel.panelId]
            )
        }
    }
}
