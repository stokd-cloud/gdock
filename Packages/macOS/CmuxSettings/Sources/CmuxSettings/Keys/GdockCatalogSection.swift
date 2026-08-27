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

    /// When enabled, selecting a workspace expands its repository group and
    /// collapses the other repository groups, so the sidebar shows one repo's
    /// work at a time. Hand-named and pinned groups are never touched.
    public let repoGroupAccordion = DefaultsKey<Bool>(
        id: "gdock.repoGroupAccordion",
        defaultValue: true,
        userDefaultsKey: "gdock.repoGroupAccordion"
    )

    /// The four commands a repository group's quad launch loads, in quadrant
    /// order: top-left, top-right, bottom-left, bottom-right. An empty list
    /// uses the built-in stokd defaults.
    public let repoGroupQuadCommands = DefaultsKey<[String]>(
        id: "gdock.repoGroupQuadCommands",
        defaultValue: [],
        userDefaultsKey: "gdock.repoGroupQuadCommands"
    )

    /// Path template for a repository's detail page in the active stokd
    /// environment, where `{slug}` is the `owner/repo`. Templated because the
    /// stokd web app's repo route is not fixed yet; the host comes from the
    /// environment's base URL, not from here.
    public let stokdRepoDetailURLTemplate = DefaultsKey<String>(
        id: "gdock.stokdRepoDetailURLTemplate",
        defaultValue: "/repos/{slug}",
        userDefaultsKey: "gdock.stokdRepoDetailURLTemplate"
    )

    public init() {}
}
