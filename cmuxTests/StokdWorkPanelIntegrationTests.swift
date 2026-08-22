import CmuxGit
import Foundation
import Testing

#if canImport(cmux_DEV)
@testable import cmux_DEV
#elseif canImport(cmux)
@testable import cmux
#endif

@Suite("Stokd Work panel integration")
@MainActor
struct StokdWorkPanelIntegrationTests {
    @Test func panelOwnsOneModelScopedToItsWorkspaceRepository() async {
        let workspace = Workspace(title: "Work", workingDirectory: "/repos/first", portOrdinal: 0)
        let loader = RecordingStokdWorkLoader()
        let repositories = FixtureStokdRepositoryDiscoverer(slugs: [
            "/repos/first": ["owner/first"],
            "/repos/second": ["owner/second"],
        ])
        let panel = RightSidebarToolPanel(
            workspace: workspace,
            mode: .stokdWork,
            stokdLoader: loader,
            stokdRepositoryDiscovering: repositories
        )

        let firstModel = panel.stokdWorkViewModel
        #expect(firstModel === panel.stokdWorkViewModel)
        await waitUntil { firstModel.repoSlug == "owner/first" && firstModel.state == .empty }
        #expect(await loader.requestedRepoSlugs() == ["owner/first"])

        workspace.currentDirectory = "/repos/second"
        panel.syncWorkspaceRoot(from: workspace)
        await waitUntil { firstModel.repoSlug == "owner/second" && firstModel.state == .empty }

        #expect(firstModel === panel.stokdWorkViewModel)
        #expect(await loader.requestedRepoSlugs() == ["owner/first", "owner/second"])
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

private struct FixtureStokdRepositoryDiscoverer: GitRepositoryDiscovering {
    let slugs: [String: [String]]

    func repositorySlugs(forDirectory directory: String) async -> [String] {
        slugs[directory] ?? []
    }

    func checkedOutBranch(forDirectory directory: String) async -> GitCheckedOutBranch {
        _ = directory
        return .notARepository
    }
}

private actor RecordingStokdWorkLoader: StokdWorkLoading {
    private var requested: [String] = []

    func load(query: StokdWorkListQuery) async -> StokdWorkPayload {
        requested.append(query.repoSlug ?? "")
        return StokdWorkPayload(tasks: [], projects: [], error: nil)
    }

    func requestedRepoSlugs() -> [String] {
        requested
    }
}
