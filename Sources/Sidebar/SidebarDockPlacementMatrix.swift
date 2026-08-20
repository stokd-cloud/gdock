import Foundation

/// Placement matrix for rail sections.
///
/// Only tool panels and the workspace selector may occupy a rail section.
/// Terminal, browser, markdown, feed/dock modes, and custom sidebars are refused.
enum SidebarDockPlacementMatrix {
    /// Panel types allowed to occupy a rail section.
    static let allowedPanelTypes: Set<PanelType> = [
        .rightSidebarTool,
        .leftWorkspaceSelector,
    ]

    /// Right-sidebar modes that may live in a rail section when the panel is a tool.
    /// Vault is the user-facing name for `.sessions`.
    static let allowedRightSidebarModes: Set<RightSidebarMode> = [
        .files,
        .find,
        .sessions,
        .stokdWork,
    ]

    static func allows(panelType: PanelType) -> Bool {
        allowedPanelTypes.contains(panelType)
    }

    @MainActor
    static func allows(panel: any Panel) -> Bool {
        guard allows(panelType: panel.panelType) else { return false }
        if let tool = panel as? RightSidebarToolPanel {
            return allowedRightSidebarModes.contains(tool.mode)
        }
        return true
    }

    @MainActor
    static func allows(panel: any Panel, on edge: SidebarDockEdge) -> Bool {
        guard allows(panel: panel) else { return false }
        guard let tool = panel as? RightSidebarToolPanel else { return true }
        return allows(mode: tool.mode, on: edge)
    }

    static func allows(mode: RightSidebarMode) -> Bool {
        allowedRightSidebarModes.contains(mode)
    }

    static func allows(mode: RightSidebarMode, on edge: SidebarDockEdge) -> Bool {
        allows(mode: mode) && (mode != .stokdWork || edge == .right)
    }
}
