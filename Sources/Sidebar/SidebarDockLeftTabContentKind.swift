import Foundation

/// Resolved left-rail tab content kind for dispatch (not the workspace selector clone).
///
/// The left rail seeds a workspace selector, but Files/Find/Vault may be docked under
/// it. Hosts must map each tab's live panel to the matching tool content — never the
/// selector view for every tab.
enum SidebarDockLeftTabContentKind: Equatable, Sendable {
    case workspaceSelector
    case files
    case find
    case vault
    case empty

    /// Resolve content kind from the panel bound to a left-rail tab.
    @MainActor
    static func resolve(panel: (any Panel)?) -> SidebarDockLeftTabContentKind {
        if panel is LeftWorkspaceSelectorPanel {
            return .workspaceSelector
        }
        guard let tool = panel as? RightSidebarToolPanel else {
            return .empty
        }
        switch tool.mode {
        case .files:
            return .files
        case .find:
            return .find
        case .sessions:
            return .vault
        case .feed, .dock, .customSidebar:
            return .empty
        }
    }
}
