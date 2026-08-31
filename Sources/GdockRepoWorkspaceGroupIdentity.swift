import Foundation

/// The single resolver deciding whether a workspace group names a repository.
///
/// See `AX-GDOCK-REPO-COMMAND-SURFACE` in `docs/gdock-agent-conventions.md`: a
/// group whose name resolves to an `owner/repo` slug is a command surface for
/// that repository; a hand-named group is inert. Every repo-only affordance
/// gates on this type and none of them re-parses `owner/repo` on its own.
///
/// Validation is deliberately stricter than "two slash-separated segments". A
/// group name is user-controlled text that ends up composed into a URL and
/// handed to `NSWorkspace.open`, so a name that could change the URL's meaning
/// — a query, a fragment, a `..` traversal — is refused outright rather than
/// escaped. Refusing costs a user with an exotic group name nothing but the
/// launcher buttons; escaping would risk opening something they did not intend.
enum GdockRepoWorkspaceGroupIdentity {
    /// Characters GitHub permits in an owner or repository name.
    private static let legalSegmentCharacters = Set(
        "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789._-"
    )

    /// The `owner/repo` slug this group name denotes, or `nil` when the name is
    /// a hand-written label rather than a repository.
    ///
    /// - Parameter name: The group's display name, leading/trailing whitespace
    ///   tolerated.
    /// - Returns: The trimmed slug, or `nil` when `name` is not exactly two
    ///   non-empty GitHub-legal segments.
    static func slug(forGroupName name: String) -> String? {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }

        let segments = trimmed.split(separator: "/", omittingEmptySubsequences: false)
        guard segments.count == 2,
              isLegalSegment(segments[0]),
              isLegalSegment(segments[1]) else {
            return nil
        }
        return trimmed
    }

    /// Whether this group is a repository command surface.
    ///
    /// Every affordance branches on this rather than re-deriving the answer, so
    /// the boolean and the slug can never disagree.
    static func isRepositoryGroup(name: String) -> Bool {
        slug(forGroupName: name) != nil
    }

    /// The GitHub page for a slug, or `nil` when the string is not a valid slug.
    ///
    /// Re-validates rather than trusting its caller: this is the last gate
    /// before a URL is opened.
    static func gitHubURL(forSlug slug: String) -> URL? {
        guard let validated = self.slug(forGroupName: slug) else { return nil }
        return URL(string: "https://github.com/\(validated)")
    }

    /// A single owner or repository segment.
    ///
    /// `.` and `..` are rejected explicitly: both are built from otherwise-legal
    /// characters, and a name like `../..` would compose into a URL that walks
    /// out of the intended path.
    private static func isLegalSegment(_ segment: Substring) -> Bool {
        guard !segment.isEmpty, segment != ".", segment != ".." else { return false }
        return segment.allSatisfy { legalSegmentCharacters.contains($0) }
    }
}
