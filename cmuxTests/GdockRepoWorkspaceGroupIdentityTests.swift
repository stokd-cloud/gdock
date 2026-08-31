import Foundation
import Testing

#if canImport(cmux_DEV)
@testable import cmux_DEV
#elseif canImport(cmux)
@testable import cmux
#endif

/// The single resolver that decides whether a workspace group names a repository
/// (AX-GDOCK-REPO-COMMAND-SURFACE, AC-A / AC-B).
///
/// Every repo-only affordance — accordion collapse, the GitHub and stokd
/// repo-detail launchers, the stokd quad launch — gates on this type. A group
/// that does not resolve here must stay inert, so the negative cases below are
/// as load-bearing as the positive one.
@Suite struct GdockRepoWorkspaceGroupIdentityTests {
    @Test func resolvesOwnerRepoSlug() {
        #expect(GdockRepoWorkspaceGroupIdentity.slug(forGroupName: "manaflow-ai/cmux") == "manaflow-ai/cmux")
        #expect(GdockRepoWorkspaceGroupIdentity.slug(forGroupName: "stokd-cloud/gdock") == "stokd-cloud/gdock")
    }

    @Test func trimsSurroundingWhitespace() {
        #expect(GdockRepoWorkspaceGroupIdentity.slug(forGroupName: "  stokd-cloud/gdock  ") == "stokd-cloud/gdock")
    }

    @Test func rejectsHandWrittenNames() {
        #expect(GdockRepoWorkspaceGroupIdentity.slug(forGroupName: "Scratch") == nil)
        #expect(GdockRepoWorkspaceGroupIdentity.slug(forGroupName: "owner/repo/extra") == nil)
        #expect(GdockRepoWorkspaceGroupIdentity.slug(forGroupName: "owner /repo") == nil)
        #expect(GdockRepoWorkspaceGroupIdentity.slug(forGroupName: "") == nil)
    }

    @Test func rejectsEmptySlugComponents() {
        #expect(GdockRepoWorkspaceGroupIdentity.slug(forGroupName: "/repo") == nil)
        #expect(GdockRepoWorkspaceGroupIdentity.slug(forGroupName: "owner/") == nil)
        #expect(GdockRepoWorkspaceGroupIdentity.slug(forGroupName: "/") == nil)
    }

    /// `isRepositoryGroup` is the boolean every affordance branches on; it must
    /// agree with `slug(forGroupName:)` rather than re-deriving the answer.
    @Test func isRepositoryGroupAgreesWithSlug() {
        #expect(GdockRepoWorkspaceGroupIdentity.isRepositoryGroup(name: "stokd-cloud/gdock"))
        #expect(!GdockRepoWorkspaceGroupIdentity.isRepositoryGroup(name: "Scratch"))
    }

    /// The GitHub launcher target (AC4). Owner/repo are already constrained to a
    /// single slash-free segment each, so the URL is a direct composition.
    @Test func buildsGitHubURL() {
        #expect(
            GdockRepoWorkspaceGroupIdentity.gitHubURL(forSlug: "stokd-cloud/gdock")
                == URL(string: "https://github.com/stokd-cloud/gdock")
        )
        #expect(GdockRepoWorkspaceGroupIdentity.gitHubURL(forSlug: "Scratch") == nil)
    }

    /// A group name is user-controlled text. Rather than escaping it into a URL,
    /// the resolver refuses anything that is not a clean two-segment slug, so a
    /// name that would inject a query, a fragment, or a traversal never reaches
    /// `NSWorkspace.open`.
    @Test func refusesSlugsThatWouldChangeURLMeaning() {
        for hostile in [
            "owner/repo?x=1",
            "owner/repo#frag",
            "owner/../etc",
            "owner/repo name",
            "owner\\repo",
            "https://evil.example.com/x",
        ] {
            #expect(
                GdockRepoWorkspaceGroupIdentity.gitHubURL(forSlug: hostile) == nil,
                "expected \(hostile) to be refused"
            )
        }
    }
}
