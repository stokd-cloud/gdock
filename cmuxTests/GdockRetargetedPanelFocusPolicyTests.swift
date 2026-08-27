import Foundation
import Testing

#if canImport(cmux_DEV)
@testable import cmux_DEV
#elseif canImport(cmux)
@testable import cmux
#endif

/// Focus follows a `cd`-retargeted panel only when it is the panel the user is
/// working in (AC9, and AC-C of AX-GDOCK-REPO-COMMAND-SURFACE).
@Suite struct GdockRetargetedPanelFocusPolicyTests {
    private typealias Policy = GdockRetargetedPanelFocusPolicy

    @Test func followsTheFocusedPanelOfTheVisibleWorkspace() {
        let panel = UUID()
        let workspace = UUID()

        #expect(Policy.shouldFollowFocus(
            extractedPanelId: panel,
            sourceWorkspaceId: workspace,
            sourceWorkspaceFocusedPanelId: panel,
            selectedWorkspaceId: workspace
        ))
    }

    /// The regression this feature exists to fix ran the other way: a
    /// background pane being relocated must not yank the user out of what they
    /// are doing.
    @Test func doesNotFollowABackgroundPanel() {
        let extracted = UUID()
        let focused = UUID()
        let workspace = UUID()

        #expect(!Policy.shouldFollowFocus(
            extractedPanelId: extracted,
            sourceWorkspaceId: workspace,
            sourceWorkspaceFocusedPanelId: focused,
            selectedWorkspaceId: workspace
        ))
    }

    /// Focused inside a workspace the user is not looking at is still a
    /// background move.
    @Test func doesNotFollowWhenTheSourceWorkspaceIsNotVisible() {
        let panel = UUID()
        let sourceWorkspace = UUID()
        let viewedWorkspace = UUID()

        #expect(!Policy.shouldFollowFocus(
            extractedPanelId: panel,
            sourceWorkspaceId: sourceWorkspace,
            sourceWorkspaceFocusedPanelId: panel,
            selectedWorkspaceId: viewedWorkspace
        ))
    }

    @Test func doesNotFollowWhenNothingIsFocused() {
        let panel = UUID()
        let workspace = UUID()

        #expect(!Policy.shouldFollowFocus(
            extractedPanelId: panel,
            sourceWorkspaceId: workspace,
            sourceWorkspaceFocusedPanelId: nil,
            selectedWorkspaceId: workspace
        ))
    }

    @Test func doesNotFollowWhenNoWorkspaceIsSelected() {
        let panel = UUID()
        let workspace = UUID()

        #expect(!Policy.shouldFollowFocus(
            extractedPanelId: panel,
            sourceWorkspaceId: workspace,
            sourceWorkspaceFocusedPanelId: panel,
            selectedWorkspaceId: nil
        ))
    }
}
