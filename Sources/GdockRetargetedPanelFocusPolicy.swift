import Foundation

/// Decides whether focus follows a panel that auto-grouping just relocated.
///
/// When a terminal is `cd`-ed into a different repository, Auto Workspace Group
/// Mode extracts that panel into a workspace under the new repo's group. If the
/// panel being moved is the one the user is typing in, leaving focus behind
/// means their next keystroke lands somewhere they are no longer looking —
/// they changed directory because they are about to do something *there*.
///
/// The converse matters just as much. This runs off a debounced cwd
/// notification, so a background panel can be relocated at any moment; yanking
/// focus for that would be worse than the mis-grouping it fixes.
///
/// `AX-GDOCK-REPO-COMMAND-SURFACE`, AC-C.
enum GdockRetargetedPanelFocusPolicy {
    /// Whether the destination workspace should be focused after the move.
    ///
    /// - Parameters:
    ///   - extractedPanelId: The panel being relocated.
    ///   - sourceWorkspaceId: The workspace it is leaving.
    ///   - sourceWorkspaceFocusedPanelId: That workspace's focused panel.
    ///   - selectedWorkspaceId: The workspace the user is currently viewing.
    /// - Returns: `true` only when the extracted panel is the focused panel of
    ///   the workspace the user is actually looking at.
    static func shouldFollowFocus(
        extractedPanelId: UUID,
        sourceWorkspaceId: UUID,
        sourceWorkspaceFocusedPanelId: UUID?,
        selectedWorkspaceId: UUID?
    ) -> Bool {
        // Focused-but-not-visible is still a background move: the user is
        // looking at some other workspace, so nothing about their attention
        // should change.
        guard selectedWorkspaceId == sourceWorkspaceId else { return false }
        guard let sourceWorkspaceFocusedPanelId else { return false }
        return sourceWorkspaceFocusedPanelId == extractedPanelId
    }
}
