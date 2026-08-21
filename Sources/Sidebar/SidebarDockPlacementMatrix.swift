import Foundation

/// Placement matrix for rail sections.
///
/// Only tool panels and the workspace selector may occupy a rail section.
/// Terminal, browser, markdown, feed/dock modes, and custom sidebars are refused.
///
/// Stokd kinds (fork-only) are edge-restricted:
/// - ``RightSidebarMode/stokdWork`` → right rail only
/// - worktrees / global config / usage → left rail only
enum SidebarDockPlacementMatrix {
    /// Panel types allowed to occupy a rail section.
    static let allowedPanelTypes: Set<PanelType> = [
        .rightSidebarTool,
        .leftWorkspaceSelector,
    ]

    /// Right-sidebar modes that may live in a rail section when the panel is a tool.
    /// Vault is the user-facing name for `.sessions`. Includes stokd kinds that are
    /// rail-placeable on at least one edge (see ``allows(mode:on:)``).
    static let allowedRightSidebarModes: Set<RightSidebarMode> = [
        .files,
        .find,
        .sessions,
        .stokdWork,
        .stokdWorktrees,
        .stokdGlobalConfig,
        .stokdUsage,
    ]

    static func allows(panelType: PanelType) -> Bool {
        allowedPanelTypes.contains(panelType)
    }

    @MainActor
    static func allows(panel: any Panel) -> Bool {
        allows(panel: panel, on: nil)
    }

    /// Edge-aware panel allowlist. When `edge` is nil, only type/mode membership is checked.
    @MainActor
    static func allows(panel: any Panel, on edge: SidebarDockEdge?) -> Bool {
        guard allows(panelType: panel.panelType) else { return false }
        if let tool = panel as? RightSidebarToolPanel {
            if let edge {
                return allows(mode: tool.mode, on: edge)
            }
            return allows(mode: tool.mode)
        }
        return true
    }

    static func allows(mode: RightSidebarMode) -> Bool {
        allowedRightSidebarModes.contains(mode)
    }

    /// Edge-aware mode placement. Legacy Files/Find/Vault remain dual-edge capable;
    /// stokd kinds are fixed to the §0 layout edges.
    static func allows(mode: RightSidebarMode, on edge: SidebarDockEdge) -> Bool {
        guard allows(mode: mode) else { return false }
        if let kind = StokdRailPanelKind(rightSidebarMode: mode) {
            return kind.preferredEdge == edge
        }
        // Non-stokd allowed modes (files/find/sessions) may occupy either rail.
        return true
    }

    static func allows(kind: StokdRailPanelKind, on edge: SidebarDockEdge) -> Bool {
        kind.preferredEdge == edge
    }
}
