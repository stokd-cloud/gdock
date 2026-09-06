import Foundation

/// Builds the active stokd environment's repo-detail URL for an `owner/repo`.
///
/// The base URL comes from the *active* environment — see
/// ``StokdEnvironmentStore`` — never a hard-coded host. `local`, `stage`, and
/// `saas` are different hosts, and assuming the local one sends a user on saas
/// to a dead link at the old hardcoded local API port. When the environment has not
/// resolved yet, this returns `nil` and the caller shows no link rather than a
/// link into the wrong environment. Only the path shape is configurable, via
/// `gdock.stokdRepoDetailURLTemplate`.
///
/// The path is templated because, at the time this shipped, the stokd web app
/// exposed no repo-detail route — there is no `/api/repos` endpoint and no
/// matching route in its bundle. Rather than hard-code a guess that silently
/// rots, the template makes the correct path a one-line setting change once
/// that page exists.
enum StokdRepoDetailURL {
    /// `{slug}` is replaced with the `owner/repo` slug.
    static let defaultPathTemplate = "/repos/{slug}"

    /// The repo-detail URL, or `nil` when the group is not a repository group
    /// or the template cannot form a valid URL.
    ///
    /// - Parameters:
    ///   - slug: Candidate `owner/repo`; re-validated through
    ///     ``GdockRepoWorkspaceGroupIdentity`` so an unvalidated group name can
    ///     never reach `NSWorkspace.open`.
    ///   - baseURL: The stokd environment's base URL.
    ///   - pathTemplate: Path containing `{slug}`.
    static func url(
        forSlug slug: String,
        baseURL: URL?,
        pathTemplate: String = StokdRepoDetailURL.defaultPathTemplate
    ) -> URL? {
        guard let baseURL else { return nil }
        guard let validated = GdockRepoWorkspaceGroupIdentity.slug(forGroupName: slug) else {
            return nil
        }
        let template = pathTemplate.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !template.isEmpty, template.contains("{slug}") else { return nil }

        // The SaaS API origin serves JSON, not the repo page. Default-template
        // links go to Selfactor; a custom template still rides the given base
        // so operators can point at a different path without losing the host.
        if baseURL.host == "api.stokd.cloud" {
            let normalizedDefault = defaultPathTemplate.hasPrefix("/")
                ? defaultPathTemplate
                : "/" + defaultPathTemplate
            let normalizedTemplate = template.hasPrefix("/") ? template : "/" + template
            if normalizedTemplate == normalizedDefault {
                return URL(string: "https://selfactor.io/repo/\(validated)")
            }
        }

        let path = template.replacingOccurrences(of: "{slug}", with: validated)
        guard var components = URLComponents(url: baseURL, resolvingAgainstBaseURL: false) else {
            return nil
        }
        // The validated slug is restricted to GitHub-legal characters, so the
        // path needs no escaping; assigning it through URLComponents keeps any
        // future template change from smuggling in a query or fragment.
        components.path = path.hasPrefix("/") ? path : "/" + path
        return components.url
    }
}
