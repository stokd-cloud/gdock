import CmuxGit
import Foundation
import Testing

#if canImport(cmux_DEV)
@testable import cmux_DEV
#elseif canImport(cmux)
@testable import cmux
#endif

/// The binder is the single repo-scoping path shared by the legacy right-sidebar
/// host and the dock-rail tool panel.
@MainActor
@Suite("Stokd Work repository binder")
struct StokdWorkRepositoryBinderTests {
    @Test func bindsResolvedSlugIntoTheModel() async {
        let loader = RecordingBinderLoader()
        let model = StokdWorkPanelViewModel(loader: loader)
        let binder = StokdWorkRepositoryBinder(
            discovering: FixtureBinderDiscoverer(slugs: ["/repos/first": ["owner/first"]])
        )

        #expect(binder.bind(directory: "/repos/first", to: model))
        await waitUntilLoaded(model, repoSlug: "owner/first")
        #expect(await loader.requestedRepoSlugs() == ["owner/first"])
    }

    @Test func repeatBindsForTheSameDirectoryAreNoOps() async {
        let loader = RecordingBinderLoader()
        let model = StokdWorkPanelViewModel(loader: loader)
        let binder = StokdWorkRepositoryBinder(
            discovering: FixtureBinderDiscoverer(slugs: ["/repos/first": ["owner/first"]])
        )

        #expect(binder.bind(directory: "/repos/first", to: model))
        await waitUntilLoaded(model, repoSlug: "owner/first")

        // Same path, and the same path with surrounding whitespace, both no-op.
        #expect(!binder.bind(directory: "/repos/first", to: model))
        #expect(!binder.bind(directory: "  /repos/first  ", to: model))
        #expect(await loader.requestedRepoSlugs() == ["owner/first"])
    }

    @Test func emptyDirectoryClearsToNoRepository() async {
        let loader = RecordingBinderLoader()
        let model = StokdWorkPanelViewModel(loader: loader)
        let binder = StokdWorkRepositoryBinder(
            discovering: FixtureBinderDiscoverer(slugs: ["/repos/first": ["owner/first"]])
        )

        #expect(binder.bind(directory: "/repos/first", to: model))
        await waitUntil { model.repoSlug == "owner/first" }

        #expect(binder.bind(directory: "", to: model))
        #expect(model.repoSlug == nil)
        #expect(model.state.isFailure)
    }

    /// A directory with no GitHub remote resolves to no slug rather than keeping
    /// the previous repository's work on screen.
    @Test func directoryWithoutARepositoryResolvesToNoSlug() async {
        let loader = RecordingBinderLoader()
        let model = StokdWorkPanelViewModel(loader: loader)
        let binder = StokdWorkRepositoryBinder(
            discovering: FixtureBinderDiscoverer(slugs: ["/repos/first": ["owner/first"]])
        )

        #expect(binder.bind(directory: "/repos/first", to: model))
        await waitUntilLoaded(model, repoSlug: "owner/first")

        #expect(binder.bind(directory: "/not/a/repo", to: model))
        await waitUntil { model.repoSlug == nil }
        #expect(await loader.requestedRepoSlugs() == ["owner/first"])
    }

    @Test func latestDirectoryWinsAcrossSuccessiveBinds() async {
        let loader = RecordingBinderLoader()
        let model = StokdWorkPanelViewModel(loader: loader)
        let binder = StokdWorkRepositoryBinder(
            discovering: FixtureBinderDiscoverer(slugs: [
                "/repos/first": ["owner/first"],
                "/repos/second": ["owner/second"],
            ])
        )

        #expect(binder.bind(directory: "/repos/first", to: model))
        #expect(binder.bind(directory: "/repos/second", to: model))
        await waitUntil { model.repoSlug == "owner/second" }

        // The superseded resolution must never land after the newer one.
        for _ in 0..<50 { await Task.yield() }
        #expect(model.repoSlug == "owner/second")
    }

    /// Waits until `model` is scoped to `repoSlug` *and* its load has completed,
    /// so loader assertions do not race the refresh task.
    private func waitUntilLoaded(
        _ model: StokdWorkPanelViewModel,
        repoSlug: String
    ) async {
        await waitUntil { model.repoSlug == repoSlug && model.state == .empty }
    }

    private func waitUntil(
        attempts: Int = 200,
        _ condition: @escaping @MainActor () -> Bool
    ) async {
        for _ in 0..<attempts {
            if condition() { return }
            await Task.yield()
        }
        Issue.record("Condition did not become true")
    }
}

private struct FixtureBinderDiscoverer: GitRepositoryDiscovering {
    let slugs: [String: [String]]

    func repositorySlugs(forDirectory directory: String) async -> [String] {
        slugs[directory] ?? []
    }

    func checkedOutBranch(forDirectory directory: String) async -> GitCheckedOutBranch {
        _ = directory
        return .notARepository
    }
}

private actor RecordingBinderLoader: StokdWorkLoading {
    private var requested: [String] = []

    func load(query: StokdWorkListQuery) async -> StokdWorkPayload {
        if let repoSlug = query.repoSlug {
            requested.append(repoSlug)
        }
        return StokdWorkPayload(tasks: [], projects: [], error: nil)
    }

    func requestedRepoSlugs() -> [String] {
        requested
    }
}
