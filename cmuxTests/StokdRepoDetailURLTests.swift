import Foundation
import Testing

#if canImport(cmux_DEV)
@testable import cmux_DEV
#elseif canImport(cmux)
@testable import cmux
#endif

/// The stokd repo-detail launcher target (AC4).
@Suite struct StokdRepoDetailURLTests {
    private let base = URL(string: "http://localhost:8167")!

    @Test func buildsRepoDetailURLFromTheDefaultTemplate() {
        let url = StokdRepoDetailURL.url(forSlug: "stokd-cloud/gdock", baseURL: base)

        #expect(url?.absoluteString == "http://localhost:8167/repos/stokd-cloud/gdock")
    }

    @Test func honoursACustomTemplate() {
        let url = StokdRepoDetailURL.url(
            forSlug: "stokd-cloud/gdock",
            baseURL: base,
            pathTemplate: "/dashboard/repository/{slug}/overview"
        )

        #expect(url?.absoluteString == "http://localhost:8167/dashboard/repository/stokd-cloud/gdock/overview")
    }

    @Test func toleratesATemplateMissingItsLeadingSlash() {
        let url = StokdRepoDetailURL.url(
            forSlug: "stokd-cloud/gdock",
            baseURL: base,
            pathTemplate: "repos/{slug}"
        )

        #expect(url?.absoluteString == "http://localhost:8167/repos/stokd-cloud/gdock")
    }

    /// Same inertness rule as every other repo-only affordance.
    @Test func handNamedGroupHasNoRepoDetailURL() {
        #expect(StokdRepoDetailURL.url(forSlug: "Scratch", baseURL: base) == nil)
        #expect(StokdRepoDetailURL.url(forSlug: "owner/repo/extra", baseURL: base) == nil)
    }

    /// A hostile group name must not reach NSWorkspace.open through this path
    /// any more than through the GitHub one.
    @Test func refusesHostileSlugs() {
        for hostile in ["owner/repo?x=1", "owner/../etc", "https://evil.example.com/x"] {
            #expect(StokdRepoDetailURL.url(forSlug: hostile, baseURL: base) == nil, "expected \(hostile) refused")
        }
    }

    /// A template with no placeholder would send every repository to the same
    /// page, which is worse than showing no button at all.
    @Test func refusesATemplateWithoutTheSlugPlaceholder() {
        #expect(StokdRepoDetailURL.url(forSlug: "stokd-cloud/gdock", baseURL: base, pathTemplate: "/repos") == nil)
        #expect(StokdRepoDetailURL.url(forSlug: "stokd-cloud/gdock", baseURL: base, pathTemplate: "") == nil)
    }

    @Test func mapsTheSaaSAPIOriginToSelfactor() {
        let saas = URL(string: "https://api.stokd.cloud")!
        let url = StokdRepoDetailURL.url(forSlug: "stokd-cloud/gdock", baseURL: saas)

        #expect(url?.absoluteString == "https://selfactor.io/repo/stokd-cloud/gdock")
    }
}
