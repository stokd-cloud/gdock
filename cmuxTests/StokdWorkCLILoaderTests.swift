import CmuxFoundation
import Foundation
import Testing

#if canImport(cmux_DEV)
@testable import cmux_DEV
#elseif canImport(cmux)
@testable import cmux
#endif

/// VAL-DATA-001 / VAL-DATA-002 / VAL-TODO-001 / VAL-LIST-001: the panel lists
/// exactly what the `stokd` CLI lists, through the resolved executable.
@Suite("Stokd Work CLI loader")
struct StokdWorkCLILoaderTests {
    @Test func loaderShellsOutWithTheDocumentedArgumentVectors() async {
        let client = FakeStokdWorkCLIClient()
        let loader = StokdWorkCLILoader(client: client)

        _ = await loader.load(query: StokdWorkListQuery(repoSlug: "owner/repo", directory: "/repos/x", limitPerKind: 100))

        let invocations = await client.invocations
        #expect(invocations.allSatisfy { $0.directory == "/repos/x" })
        let arguments = Set(invocations.map(\.arguments))
        #expect(arguments.contains(["task", "list", "--repo", "owner/repo", "--all", "--json", "--limit", "100", "--sort-by", "updated_at", "--desc"]))
        #expect(arguments.contains(["project", "list", "--repo", "owner/repo", "--all", "--json", "--limit", "100", "--sort-by", "updated_at", "--desc"]))
        #expect(arguments.contains(["todo", "list", "--all", "--json", "--limit", "100", "--sort-by", "updated_at", "--desc"]))
        #expect(invocations.count == 3)
    }

    @Test func listArgumentsFollowThePanelSortSoTheTopPageIsTheRightPage() async {
        let client = FakeStokdWorkCLIClient()
        let loader = StokdWorkCLILoader(client: client)

        _ = await loader.load(query: StokdWorkListQuery(
            repoSlug: "owner/repo", directory: "/repos/x", limitPerKind: 100,
            sortField: .createdAt, sortAscending: true
        ))

        let arguments = Set(await client.recordedArguments())
        #expect(arguments.contains(["task", "list", "--repo", "owner/repo", "--all", "--json", "--limit", "100", "--sort-by", "created_at"]))
        #expect(StokdWorkListQuery.defaultLimitPerKind == 100)
    }

    @Test func recordedCLIOutputDecodesIntoTasksProjectsAndRepoMemberTodos() async {
        let client = FakeStokdWorkCLIClient()
        await client.respond(to: ["task", "list"], with: StokdWorkFixtures.success(StokdWorkFixtures.taskListJSON))
        await client.respond(to: ["project", "list"], with: StokdWorkFixtures.success(StokdWorkFixtures.projectListJSON))
        await client.respond(to: ["todo", "list"], with: StokdWorkFixtures.success(StokdWorkFixtures.todoListJSON))
        let loader = StokdWorkCLILoader(client: client)

        let payload = await loader.load(query: StokdWorkListQuery(repoSlug: "owner/repo", directory: "/repos/x"))

        #expect(payload.error == nil)
        #expect(payload.tasks.map(\.hashShort) == ["8b4b164", "adb3051", "679cab7"])
        #expect(payload.tasks.first?.number == 16998)
        #expect(payload.tasks.first?.updatedAt == "2026-09-02T02:19:28.077Z")
        #expect(payload.tasks.first?.createdAt == nil)
        #expect(payload.projects.map(\.hashShort) == ["38f437b"])
        #expect(payload.projects.first?.createdAt == "2026-08-28T09:17:27.716Z")
        // A todo belongs to the repo when the todo itself or any checklist item
        // names the repo; the unrelated mono-only todo is dropped.
        #expect(payload.todos.map(\.hashShort) == ["3572f77", "c0ffee1"])
        #expect(payload.todos.first?.items.count == 2)
        #expect(payload.todos.first?.items.first?.status == "completed")
    }

    @Test func nonZeroExitTimeoutAndMissingExecutableBecomeStructuredErrors() async {
        let failing = FakeStokdWorkCLIClient(fallback: StokdWorkFixtures.failure(exit: 2, stderr: "error: not logged in"))
        let failure = await StokdWorkCLILoader(client: failing).load(query: StokdWorkListQuery(repoSlug: "owner/repo"))
        #expect(failure.error?.kind == .exit(2))
        #expect(failure.error?.message.contains("not logged in") == true)
        #expect(failure.tasks.isEmpty && failure.projects.isEmpty && failure.todos.isEmpty)

        let timedOut = FakeStokdWorkCLIClient(fallback: CommandResult(stdout: nil, stderr: nil, exitStatus: nil, timedOut: true, executionError: nil))
        let timeout = await StokdWorkCLILoader(client: timedOut).load(query: StokdWorkListQuery(repoSlug: "owner/repo"))
        #expect(timeout.error?.kind == .timeout)

        let missing = FakeStokdWorkCLIClient(fallback: CommandResult(stdout: nil, stderr: "stokd executable not found", exitStatus: 127, timedOut: false, executionError: "stokd executable not found"))
        let unavailable = await StokdWorkCLILoader(client: missing).load(query: StokdWorkListQuery(repoSlug: "owner/repo"))
        #expect(unavailable.error?.kind == .cliUnavailable)

        let garbage = FakeStokdWorkCLIClient(fallback: StokdWorkFixtures.success("not json"))
        let decoding = await StokdWorkCLILoader(client: garbage).load(query: StokdWorkListQuery(repoSlug: "owner/repo"))
        #expect(decoding.error?.kind == .decoding)
    }

    @Test func aKindReturningExactlyTheLimitIsReportedAsTruncated() async {
        let client = FakeStokdWorkCLIClient()
        let rows = (0..<3).map { index in
            "{\"hash\":\"h\(index)\",\"id\":\"id\(index)\",\"priority\":null,\"repo_slug\":\"owner/repo\",\"status\":\"pending\",\"task_number\":\(index),\"title\":\"T\(index)\",\"updated_at\":\"2026-09-01T00:00:0\(index)Z\"}"
        }
        await client.respond(to: ["task", "list"], with: StokdWorkFixtures.success("[\(rows.joined(separator: ","))]"))
        let loader = StokdWorkCLILoader(client: client)

        let payload = await loader.load(query: StokdWorkListQuery(repoSlug: "owner/repo", limitPerKind: 3))

        #expect(payload.limitPerKind == 3)
        #expect(payload.truncatedKinds == [.task])
    }

    @Test func detailVerbsUseGetForTextAndViewJSONForTodos() async {
        let client = FakeStokdWorkCLIClient()
        await client.respond(to: ["task", "get"], with: StokdWorkFixtures.success(StokdWorkFixtures.taskGetText))
        await client.respond(to: ["todo", "view"], with: StokdWorkFixtures.success(StokdWorkFixtures.todoViewJSON))
        let loader = StokdWorkCLILoader(client: client)

        let task = await loader.loadDetailText(kind: .task, hash: "8b4b164", directory: "/repos/x")
        let project = await loader.loadDetailText(kind: .project, hash: "38f437b", directory: "/repos/x")
        let todo = await loader.loadDetailText(kind: .todo, hash: "3572f77", directory: "/repos/x")

        let arguments = await client.recordedArguments()
        #expect(arguments == [
            ["task", "get", "8b4b164"],
            ["project", "get", "38f437b"],
            ["todo", "view", "3572f77", "--json"],
        ])
        #expect((try? task.get())?.hasPrefix("Task #8b4b164") == true)
        #expect((try? project.get()) == "[]")
        #expect((try? todo.get())?.contains("\"todo_id\"") == true)
    }

    @Test func todoMembershipCountsTheTodoRepoOrAnyItemRepo() {
        let owned = StokdWorkFixtures.todo(id: "a", title: "A", repoSlug: "owner/repo", updatedAt: "2026-09-01T00:00:00Z")
        let viaItem = StokdWorkFixtures.todo(
            id: "b", title: "B", repoSlug: "other/mono", updatedAt: "2026-09-01T00:00:00Z",
            items: [StokdWorkFixtures.todoItem(id: "i", title: "I", status: "pending", repoSlug: "owner/repo")]
        )
        let unrelated = StokdWorkFixtures.todo(id: "c", title: "C", repoSlug: "other/mono", updatedAt: "2026-09-01T00:00:00Z")

        #expect(StokdWorkCLILoader.todoBelongs(owned, toRepo: "owner/repo"))
        #expect(StokdWorkCLILoader.todoBelongs(viaItem, toRepo: "owner/repo"))
        #expect(!StokdWorkCLILoader.todoBelongs(unrelated, toRepo: "owner/repo"))
        #expect(StokdWorkCLILoader.todoBelongs(unrelated, toRepo: "OWNER/REPO") == false)
        #expect(StokdWorkCLILoader.todoBelongs(owned, toRepo: "Owner/Repo"))
    }
}
