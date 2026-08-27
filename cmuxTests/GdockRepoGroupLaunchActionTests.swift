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

    @Test func repoGroupExposesBothTargets() {
        #expect(Action.isAvailable(groupName: repo))
        for target in Action.Target.allCases {
            #expect(Action.url(for: target, groupName: repo) != nil, "\(target) should resolve")
        }
        #expect(Action.Target.allCases.count == 2)
    }

    /// AC4's "a non-repo group header exposes zero buttons" — expressed as
    /// every target resolving to nothing, which is what makes the UI omit them.
    @Test func handNamedGroupExposesNoTargets() {
        #expect(!Action.isAvailable(groupName: "Scratch"))
        for target in Action.Target.allCases {
            #expect(Action.url(for: target, groupName: "Scratch") == nil, "\(target) should be absent")
        }
    }

    @Test func gitHubTargetResolvesToTheRepositoryPage() {
        #expect(
            Action.url(for: .gitHub, groupName: repo)?.absoluteString
                == "https://github.com/stokd-cloud/gdock"
        )
    }

    @Test func stokdTargetHonoursTheConfiguredTemplate() {
        #expect(
            Action.url(for: .stokdRepoDetail, groupName: repo, stokdPathTemplate: "/r/{slug}")?.path
                == "/r/stokd-cloud/gdock"
        )
    }

    @Test func openRoutesTheResolvedURLToTheOpener() {
        var opened: [URL] = []
        let didOpen = Action.open(.gitHub, groupName: repo) { opened.append($0) }

        #expect(didOpen)
        #expect(opened.map(\.absoluteString) == ["https://github.com/stokd-cloud/gdock"])
    }

    @Test func openDoesNothingForAHandNamedGroup() {
        var opened: [URL] = []
        let didOpen = Action.open(.gitHub, groupName: "Scratch") { opened.append($0) }

        #expect(!didOpen)
        #expect(opened.isEmpty)
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
