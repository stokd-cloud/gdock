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
        defaultValue: true,
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
    /// work at a time. Hand-named groups are never touched; a pinned repo
    /// group collapses like any other unless it owns the selection.
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

    /// When enabled, each focused-workspace pane card shows a summary of what
    /// that pane's stokd agent session has been doing, read from the session's
    /// append-only outcome log. Off makes the cards render exactly as they did
    /// before summaries existed.
    public let panelCardSessionSummaries = DefaultsKey<Bool>(
        id: "gdock.panelCardSessionSummaries",
        defaultValue: true,
        userDefaultsKey: "gdock.panelCardSessionSummaries"
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

    /// Explicit origin for stokd links (e.g. `https://api.stokd.cloud`). Empty
    /// means "ask the stokd CLI which environment is active" — the env's host
    /// differs between local, stage, and saas, so it is never hard-coded.
    public let stokdWebBaseURL = DefaultsKey<String>(
        id: "gdock.stokdWebBaseURL",
        defaultValue: "",
        userDefaultsKey: "gdock.stokdWebBaseURL"
    )

    /// When enabled, every workspace is kept in the enforced grid split shape
    /// (`gridModeShape`); non-activated cells hold unspawned terminals and
    /// Cmd+T fills the next free cell instead of adding a surface tab.
    public let gridMode = DefaultsKey<Bool>(
        id: "gdock.gridMode",
        defaultValue: true,
        userDefaultsKey: "gdock.gridMode"
    )

    /// The enforced grid shape while `gridMode` is on, encoded `"<rows>x<cols>"`
    /// (e.g. `"2x2"`). The last chosen shape is remembered across restarts.
    public let gridModeShape = DefaultsKey<String>(
        id: "gdock.gridModeShape",
        defaultValue: "2x2",
        userDefaultsKey: "gdock.gridModeShape"
    )

    /// Work panel kind filter: `all`, `tasks`, `projects`, or `todos`.
    public let workPanelKindFilter = DefaultsKey<String>(
        id: "gdock.workPanel.kindFilter",
        defaultValue: "all",
        userDefaultsKey: "gdock.workPanel.kindFilter"
    )

    /// When off (the default) the Work panel hides completed, cancelled, and
    /// failed items so the list shows what still needs doing.
    public let workPanelShowCompleted = DefaultsKey<Bool>(
        id: "gdock.workPanel.showCompleted",
        defaultValue: false,
        userDefaultsKey: "gdock.workPanel.showCompleted"
    )

    /// Work panel sort field: `updated_at` (default) or `created_at`.
    public let workPanelSortField = DefaultsKey<String>(
        id: "gdock.workPanel.sortField",
        defaultValue: "updated_at",
        userDefaultsKey: "gdock.workPanel.sortField"
    )

    /// Work panel sort direction; `false` (the default) lists newest first.
    public let workPanelSortAscending = DefaultsKey<Bool>(
        id: "gdock.workPanel.sortAscending",
        defaultValue: false,
        userDefaultsKey: "gdock.workPanel.sortAscending"
    )

    /// Height in points of the Work panel's detail pane (the resizable split
    /// under the list). Remembered across restarts.
    public let workPanelDetailHeight = DefaultsKey<Double>(
        id: "gdock.workPanel.detailHeight",
        defaultValue: 280,
        userDefaultsKey: "gdock.workPanel.detailHeight"
    )

    /// Row count for the Auto Split action. Runtime clamps to `1...6`.
    public let autoSplitRows = DefaultsKey<Int>(
        id: "gdock.autoSplitRows",
        defaultValue: 2,
        userDefaultsKey: "gdock.autoSplitRows"
    )

    /// Column count for the Auto Split action. Runtime clamps to `1...6`.
    public let autoSplitColumns = DefaultsKey<Int>(
        id: "gdock.autoSplitColumns",
        defaultValue: 2,
        userDefaultsKey: "gdock.autoSplitColumns"
    )

    /// When enabled, the last split-tab-bar button becomes Auto Split.
    public let forceAutoSplitter = DefaultsKey<Bool>(
        id: "gdock.forceAutoSplitter",
        defaultValue: false,
        userDefaultsKey: "gdock.forceAutoSplitter"
    )

    public init() {}
}
