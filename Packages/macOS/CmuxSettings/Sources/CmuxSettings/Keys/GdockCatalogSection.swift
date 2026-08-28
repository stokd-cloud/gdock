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

    /// When enabled, every workspace is kept in the enforced grid split shape
    /// (`gridModeShape`); non-activated cells hold unspawned terminals and
    /// Cmd+T fills the next free cell instead of adding a surface tab.
    public let gridMode = DefaultsKey<Bool>(
        id: "gdock.gridMode",
        defaultValue: false,
        userDefaultsKey: "gdock.gridMode"
    )

    /// The enforced grid shape while `gridMode` is on, encoded `"<rows>x<cols>"`
    /// (e.g. `"2x2"`). The last chosen shape is remembered across restarts.
    public let gridModeShape = DefaultsKey<String>(
        id: "gdock.gridModeShape",
        defaultValue: "2x2",
        userDefaultsKey: "gdock.gridModeShape"
    )

    public init() {}
}
