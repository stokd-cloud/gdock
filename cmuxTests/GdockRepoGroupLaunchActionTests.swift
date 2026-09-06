import AppKit
import Foundation
import Testing

#if canImport(cmux_DEV)
@testable import cmux_DEV
#elseif canImport(cmux)
@testable import cmux
#endif

/// The shared launcher action behind a repo group header's two buttons
/// (AC4, and AC-B / AC-D of AX-GDOCK-REPO-COMMAND-SURFACE).
@MainActor
@Suite struct GdockRepoGroupLaunchActionTests {
    private typealias Action = GdockRepoGroupLaunchAction
    private let repo = "stokd-cloud/gdock"
    private let saas = URL(string: "https://api.stokd.cloud")!

    @Test func repoGroupExposesBothTargets() {
        #expect(Action.isAvailable(groupName: repo))
        for target in Action.Target.allCases {
            #expect(Action.url(for: target, groupName: repo, stokdBaseURL: saas) != nil, "\(target) should resolve")
        }
        #expect(Action.Target.allCases.count == 2)
    }

    /// AC4's "a non-repo group header exposes zero buttons" — expressed as
    /// every target resolving to nothing, which is what makes the UI omit them.
    @Test func handNamedGroupExposesNoTargets() {
        #expect(!Action.isAvailable(groupName: "Scratch"))
        for target in Action.Target.allCases {
            #expect(Action.url(for: target, groupName: "Scratch", stokdBaseURL: saas) == nil, "\(target) should be absent")
        }
    }

    @Test func gitHubTargetResolvesToTheRepositoryPage() {
        #expect(
            Action.url(for: .gitHub, groupName: repo, stokdBaseURL: saas)?.absoluteString
                == "https://github.com/stokd-cloud/gdock"
        )
    }

    @Test func stokdTargetHonoursTheConfiguredTemplate() {
        #expect(
            Action.url(for: .stokdRepoDetail, groupName: repo, stokdPathTemplate: "/r/{slug}", stokdBaseURL: saas)?.path
                == "/r/stokd-cloud/gdock"
        )
    }

    @Test func openRoutesTheResolvedURLToTheOpener() {
        var opened: [URL] = []
        let didOpen = Action.open(.gitHub, groupName: repo, stokdBaseURL: saas) { opened.append($0) }

        #expect(didOpen)
        #expect(opened.map(\.absoluteString) == ["https://github.com/stokd-cloud/gdock"])
    }

    @Test func openDoesNothingForAHandNamedGroup() {
        var opened: [URL] = []
        let didOpen = Action.open(.gitHub, groupName: "Scratch", stokdBaseURL: saas) { opened.append($0) }

        #expect(!didOpen)
        #expect(opened.isEmpty)
    }

    /// Regression: the launcher used the API origin and plural `/repos` route,
    /// which opens a JSON 404 instead of Selfactor's repository page.
    @Test func stokdTargetOpensTheSelfactorRepositoryPage() {
        let url = Action.url(for: .stokdRepoDetail, groupName: repo, stokdBaseURL: saas)

        #expect(url?.absoluteString == "https://selfactor.io/repo/stokd-cloud/gdock")
        #expect(url?.host != "api.stokd.cloud")
    }

    /// Until the environment resolves there is no correct host, and guessing
    /// one would point the user at another environment's data.
    @Test func stokdTargetIsAbsentWhenTheEnvironmentIsUnresolved() {
        #expect(Action.url(for: .stokdRepoDetail, groupName: repo, stokdBaseURL: nil) == nil)
        // GitHub does not depend on the stokd environment and must still work.
        #expect(Action.url(for: .gitHub, groupName: repo, stokdBaseURL: nil) != nil)
    }

    /// Each target uses the real brand mark, not a generic SF Symbol, and the
    /// assets must resolve from the built app bundle.
    @Test func targetsUseTheirBundledBrandMarks() {
        #expect(Action.Target.gitHub.iconAssetName == "GitHubLogo")
        #expect(Action.Target.stokdRepoDetail.iconAssetName == "SelfactorLogo")
        for target in Action.Target.allCases {
            #expect(NSImage(named: target.iconAssetName) != nil, "\(target) brand mark should be bundled")
        }

        let labels = Set(Action.Target.allCases.map(\.accessibilityLabel))

        #expect(labels.count == Action.Target.allCases.count)
    }

    /// The header draws the bundled mark, not the leftover SF Symbol.
    @Test func headerGlyphUsesTheBundledBrandMark() {
        for target in Action.Target.allCases {
            let glyph = target.headerGlyphImage(pointSize: 12)
            #expect(glyph != nil, "\(target) header glyph should resolve")
            #expect(glyph?.isTemplate == true, "\(target) header glyph should tint")
        }
    }
}
