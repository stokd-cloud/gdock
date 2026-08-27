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

    /// Regression: the launcher hard-coded localhost:8167, so on `saas` it
    /// opened `http://localhost:8167/repos/...` — a dead link into an
    /// environment the user was not on.
    @Test func stokdTargetFollowsTheActiveEnvironmentHost() {
        let url = Action.url(for: .stokdRepoDetail, groupName: repo, stokdBaseURL: saas)

        #expect(url?.absoluteString == "https://api.stokd.cloud/repos/stokd-cloud/gdock")
        #expect(url?.host != "localhost")
    }

    /// Until the environment resolves there is no correct host, and guessing
    /// one would point the user at another environment's data.
    @Test func stokdTargetIsAbsentWhenTheEnvironmentIsUnresolved() {
        #expect(Action.url(for: .stokdRepoDetail, groupName: repo, stokdBaseURL: nil) == nil)
        // GitHub does not depend on the stokd environment and must still work.
        #expect(Action.url(for: .gitHub, groupName: repo, stokdBaseURL: nil) != nil)
    }

    /// Each target needs its own glyph and its own label, or the two buttons
    /// are indistinguishable in the header.
    @Test func targetsHaveDistinctPresentation() {
        let symbols = Set(Action.Target.allCases.map(\.symbolName))
        let labels = Set(Action.Target.allCases.map(\.accessibilityLabel))

        #expect(symbols.count == Action.Target.allCases.count)
        #expect(labels.count == Action.Target.allCases.count)
    }
}
