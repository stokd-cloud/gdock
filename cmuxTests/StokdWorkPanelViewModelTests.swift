import Foundation
import Testing

#if canImport(cmux_DEV)
@testable import cmux_DEV
#elseif canImport(cmux)
@testable import cmux
#endif

@Suite("Stokd Work panel model")
@MainActor
struct StokdWorkPanelViewModelTests {
    @Test func rowsAreRepoScopedDeterministicAndFilterable() async {
        let loader = ImmediateStokdWorkLoader(payload: StokdWorkPayload(
            tasks: [
                task(id: "task-old", title: "Older task", updatedAt: "2026-08-20T10:00:00Z"),
                task(id: "task-new", title: "Newer task", updatedAt: "2026-08-20T12:00:00Z"),
            ],
            projects: [
                project(id: "project-mid", title: "Middle project", updatedAt: "2026-08-20T11:00:00Z"),
            ],
            error: nil
        ))
        let model = StokdWorkPanelViewModel(loader: loader, defaults: freshDefaults())

        model.refresh(repoSlug: "owner/repo")
        await waitUntil { model.state == .populated }

        #expect(model.repoSlug == "owner/repo")
        #expect(model.rows.map(\.id) == ["task:task-new", "project:project-mid", "task:task-old"])
        #expect(model.rows.map(\.title) == ["Newer task", "Middle project", "Older task"])

        model.setFilter(.tasks)
        #expect(model.rows.map(\.id) == ["task:task-new", "task:task-old"])

        model.setFilter(.projects)
        #expect(model.rows.map(\.id) == ["project:project-mid"])
    }

    @Test func staleResponseCannotReplaceNewerRepository() async {
        let loader = ControlledStokdWorkLoader()
        let model = StokdWorkPanelViewModel(loader: loader, defaults: freshDefaults())

        model.refresh(repoSlug: "owner/old")
        await loader.waitUntilRequested("owner/old")
        model.refresh(repoSlug: "owner/new")
        await loader.waitUntilRequested("owner/new")

        await loader.resume(
            "owner/new",
            with: StokdWorkPayload(
                tasks: [task(id: "new", title: "New repo", updatedAt: "2026-08-20T12:00:00Z")],
                projects: [],
                error: nil
            )
        )
        await waitUntil { model.rows.map(\.id) == ["task:new"] }

        await loader.resume(
            "owner/old",
            with: StokdWorkPayload(
                tasks: [task(id: "old", title: "Old repo", updatedAt: "2026-08-20T13:00:00Z")],
                projects: [],
                error: nil
            )
        )
        await Task.yield()

        #expect(model.repoSlug == "owner/new")
        #expect(model.rows.map(\.id) == ["task:new"])
    }

    @Test func emptyAndErrorStatesNeverRenderBlankContent() async {
        let empty = StokdWorkPanelViewModel(loader: ImmediateStokdWorkLoader(
            payload: StokdWorkPayload(tasks: [], projects: [], error: nil)
        ), defaults: freshDefaults())
        empty.refresh(repoSlug: "owner/empty")
        await waitUntil { empty.state == .empty }
        #expect(empty.rows.isEmpty)
        #expect(empty.state.message.isEmpty == false)

        let failure = StokdWorkPanelViewModel(loader: ImmediateStokdWorkLoader(
            payload: StokdWorkPayload(
                tasks: [],
                projects: [],
                error: StokdWorkLoadError(kind: .exit(1), message: "Service unavailable")
            )
        ), defaults: freshDefaults())
        failure.refresh(repoSlug: "owner/error")
        await waitUntil { failure.state.isFailure }
        #expect(failure.rows.isEmpty)
        #expect(failure.state.message == "Service unavailable")
    }

    @Test func filteredEmptyStateNamesTheRequestedWorkKind() async {
        let projectsOnly = StokdWorkPanelViewModel(loader: ImmediateStokdWorkLoader(
            payload: StokdWorkPayload(
                tasks: [],
                projects: [project(id: "project", title: "Project", updatedAt: "2026-08-20T11:00:00Z")],
                error: nil
            )
        ), defaults: freshDefaults())
        projectsOnly.refresh(repoSlug: "owner/repo")
        await waitUntil { projectsOnly.state == .populated }

        projectsOnly.setFilter(.tasks)

        #expect(projectsOnly.state == .empty)
        #expect(projectsOnly.stateMessage == String(
            localized: "stokdWork.state.empty.tasks",
            defaultValue: "No tasks found"
        ))

        let tasksOnly = StokdWorkPanelViewModel(loader: ImmediateStokdWorkLoader(
            payload: StokdWorkPayload(
                tasks: [task(id: "task", title: "Task", updatedAt: "2026-08-20T11:00:00Z")],
                projects: [],
                error: nil
            )
        ), defaults: freshDefaults())
        tasksOnly.refresh(repoSlug: "owner/repo")
        await waitUntil { tasksOnly.state == .populated }

        tasksOnly.setFilter(.projects)

        #expect(tasksOnly.state == .empty)
        #expect(tasksOnly.stateMessage == String(
            localized: "stokdWork.state.empty.projects",
            defaultValue: "No projects found"
        ))
    }

    private func freshDefaults() -> UserDefaults {
        let name = "stokdWork.viewModel.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: name)!
        defaults.removePersistentDomain(forName: name)
        return defaults
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

private struct ImmediateStokdWorkLoader: StokdWorkLoading {
    let payload: StokdWorkPayload

    func load(query: StokdWorkListQuery) async -> StokdWorkPayload {
        _ = query
        return payload
    }
}

private actor ControlledStokdWorkLoader: StokdWorkLoading {
    private var continuations: [String: CheckedContinuation<StokdWorkPayload, Never>] = [:]

    func load(query: StokdWorkListQuery) async -> StokdWorkPayload {
        await withCheckedContinuation { continuation in
            continuations[query.repoSlug ?? ""] = continuation
        }
    }

    func waitUntilRequested(_ repoSlug: String) async {
        while continuations[repoSlug] == nil {
            await Task.yield()
        }
    }

    func resume(_ repoSlug: String, with payload: StokdWorkPayload) {
        continuations.removeValue(forKey: repoSlug)?.resume(returning: payload)
    }
}

private func task(id: String, title: String, updatedAt: String) -> StokdTask {
    StokdTask(
        id: id,
        number: nil,
        slug: id,
        title: title,
        description: "",
        status: "pending",
        repoSlug: "owner/repo",
        hashShort: nil,
        createdAt: updatedAt,
        updatedAt: updatedAt
    )
}

private func project(id: String, title: String, updatedAt: String) -> StokdProject {
    StokdProject(
        id: id,
        number: nil,
        slug: id,
        title: title,
        description: "",
        status: "active",
        repoSlug: "owner/repo",
        hashShort: nil,
        createdAt: updatedAt,
        updatedAt: updatedAt
    )
}
