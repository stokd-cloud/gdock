import AppKit
import Foundation

/// The one implementation behind a repository group's launcher buttons.
///
/// `AX-GDOCK-REPO-COMMAND-SURFACE` AC-D: the AppKit sidebar list, the SwiftUI
/// sidebar fallback, and the command palette all route here rather than each
/// composing its own URL. AC-B: a hand-named group resolves to no target, so
/// callers get `nil` and render no button.
@MainActor
enum GdockRepoGroupLaunchAction {
    /// Where a launcher button points.
    enum Target: String, CaseIterable, Sendable {
        /// The repository's page on GitHub.
        case gitHub
        /// The repository's detail page in the active stokd environment.
        case stokdRepoDetail

        /// SF Symbol for the header glyph button.
        var symbolName: String {
            switch self {
            case .gitHub: return "chevron.left.forwardslash.chevron.right"
            case .stokdRepoDetail: return "square.grid.2x2"
            }
        }

        var accessibilityLabel: String {
            switch self {
            case .gitHub:
                return String(
                    localized: "gdock.repoGroup.openOnGitHub",
                    defaultValue: "Open repository on GitHub"
                )
            case .stokdRepoDetail:
                return String(
                    localized: "gdock.repoGroup.openStokdRepoDetail",
                    defaultValue: "Open repository in Stokd"
                )
            }
        }
    }

    /// The URL a target resolves to for this group, or `nil` when the group is
    /// not a repository group.
    static func url(
        for target: Target,
        groupName: String,
        stokdPathTemplate: String = GdockStokdRepoDetailSettings.pathTemplate(),
        stokdBaseURL: URL?
    ) -> URL? {
        guard let slug = GdockRepoWorkspaceGroupIdentity.slug(forGroupName: groupName) else {
            return nil
        }
        switch target {
        case .gitHub:
            return GdockRepoWorkspaceGroupIdentity.gitHubURL(forSlug: slug)
        case .stokdRepoDetail:
            return StokdRepoDetailURL.url(
                forSlug: slug,
                baseURL: stokdBaseURL,
                pathTemplate: stokdPathTemplate
            )
        }
    }

    /// Whether this group should show launcher buttons at all.
    static func isAvailable(groupName: String) -> Bool {
        GdockRepoWorkspaceGroupIdentity.isRepositoryGroup(name: groupName)
    }

    /// Opens the target, returning whether anything was opened.
    ///
    /// - Parameter opener: Injected so tests exercise routing without opening a
    ///   browser.
    @discardableResult
    static func open(
        _ target: Target,
        groupName: String,
        stokdPathTemplate: String = GdockStokdRepoDetailSettings.pathTemplate(),
        stokdBaseURL: URL?,
        opener: (URL) -> Void = { NSWorkspace.shared.open($0) }
    ) -> Bool {
        guard let url = url(
            for: target,
            groupName: groupName,
            stokdPathTemplate: stokdPathTemplate,
            stokdBaseURL: stokdBaseURL
        ) else {
            return false
        }
        opener(url)
        return true
    }

    /// UI entry point: opens the target against whatever environment is
    /// currently active.
    ///
    /// The base URL is read here rather than as a default argument, because
    /// default arguments are evaluated outside this type's actor and so cannot
    /// touch ``StokdEnvironmentStore``.
    @discardableResult
    static func openUsingActiveEnvironment(_ target: Target, groupName: String) -> Bool {
        open(target, groupName: groupName, stokdBaseURL: StokdEnvironmentStore.shared.baseURL)
    }
}
