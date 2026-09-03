import Foundation

/// One prompt the operator submitted to an agent session.
///
/// A value snapshot reduced from the Feed workstream store *above* the overlay's
/// lazy list, per the SwiftUI list-boundary rule in `CLAUDE.md`: no view in the
/// overlay may hold a store reference (cmux issue 2586).
struct GdockPromptHistoryEntry: Equatable, Identifiable, Sendable {
    /// The feed item's identity, so rows stay stable across refreshes.
    let id: UUID
    /// `<agent>-<sessionId>` the prompt was submitted to.
    let workstreamId: String
    /// Whitespace-collapsed prompt text; the overlay renders one line per entry.
    let text: String
    let submittedAt: Date
}

/// The pane whose prompts the overlay is showing.
struct GdockPromptHistoryFocus: Equatable, Sendable {
    let workspaceId: UUID
    /// The focused panel. Identity is the pane, not the workspace: two panes in
    /// one checkout routinely run different sessions.
    let panelId: UUID
    /// Working directory of the focused pane, used to attribute prompts from
    /// agents that never registered a hook session.
    let directory: String?
}

/// Where a `workstreamId` currently lives, as resolved from the per-agent hook
/// session stores.
struct GdockPromptHistoryTarget: Equatable, Sendable {
    let workspaceId: UUID
    let surfaceId: UUID
}
