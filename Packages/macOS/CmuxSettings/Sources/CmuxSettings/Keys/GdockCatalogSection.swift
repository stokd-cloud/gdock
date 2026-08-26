import Foundation

/// ghostty-dock (gdock) fork-only settings under the dotted-id prefix `gdock.*`.
///
/// All new gdock settings MUST live here (or another `gdock.*` section) so they
/// never collide with upstream cmux keys. See Agents.md / AX-GDOCK-SETTINGS-AND-PALETTE-PREFIX.
public struct GdockCatalogSection: SettingCatalogSection {
    /// When enabled, workspaces whose cwd is inside a GitHub-remote repository
    /// are automatically placed into a workspace group named `owner/repo`.
    public let autoWorkspaceGroupMode = DefaultsKey<Bool>(
        id: "gdock.autoWorkspaceGroupMode",
        defaultValue: false,
        userDefaultsKey: "gdock.autoWorkspaceGroupMode"
    )

    /// When enabled, the right sidebar renders dock rail tools as stacked tab sections.
    public let rightSidebarStackedTabs = DefaultsKey<Bool>(
        id: "gdock.rightSidebarStackedTabs",
        defaultValue: false,
        userDefaultsKey: "gdock.rightSidebarStackedTabs"
    )

    public init() {}
}
