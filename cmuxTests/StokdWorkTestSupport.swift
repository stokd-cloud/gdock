import CmuxFoundation
import Foundation

#if canImport(cmux_DEV)
@testable import cmux_DEV
#elseif canImport(cmux)
@testable import cmux
#endif

/// Shared fixtures for the Stokd Work panel suites. Everything here is recorded
/// from the real `stokd` CLI (0.2.224) so the tests exercise the same shapes the
/// panel sees in production.
enum StokdWorkFixtures {
    static let taskListJSON = """
    [{"hash":"8b4b164","id":"incidental-895619c39974be907cc094bc85b8c16b","priority":null,"repo_slug":"owner/repo","status":"pending","task_number":16998,"title":"Repair: Distinct gdock tags that differ","updated_at":"2026-09-02T02:19:28.077Z"},
     {"hash":"adb3051","id":"mode-task-1788311265453687000-89326","priority":2,"repo_slug":"owner/repo","status":"in_progress","task_number":16990,"title":"Add a safe packaging-only fast path","updated_at":"2026-09-02T02:17:52.300Z"},
     {"hash":"679cab7","id":"incidental-ced1dc86244fa0cd2d8a54a20dfd4a0b","priority":null,"repo_slug":"owner/repo","status":"completed","task_number":16901,"title":"Repair: Lander removed an active task","updated_at":"2026-09-01T11:01:24.201Z"}]
    """

    static let projectListJSON = """
    [{"created_at":"2026-08-28T09:17:27.716Z","hash":"38f437b","hash_short":"38f437b","id":"9003ceb1-65d3-4967-b074-bb1a02a3ae4c","priority":null,"project_id":"9003ceb1-65d3-4967-b074-bb1a02a3ae4c","project_number":12,"repo_slug":"owner/repo","slug":"stokd-work-panel","status":"active","title":"Stokd Work Panel","updated_at":"2026-08-28T09:17:27.716Z"}]
    """

    static let todoListJSON = """
    [{"hash":"3572f77","id":"d5f9451d-6830-4531-bfdc-baae35588476","ordered":true,"priority":null,"repo_slug":"other/mono","status":"in_progress","title":"CLI data-structure optimization","updated_at":"2026-08-30T10:00:00.000Z",
      "items":[{"id":"i1","kind":"text","order":0,"ref_hash":null,"repo_slug":"owner/repo","status":"completed","task_hash":null,"title":"Shared contracts","work_item_ref":null},
               {"id":"i2","kind":"text","order":1,"ref_hash":null,"repo_slug":"other/mono","status":"pending","task_hash":null,"title":"Daemon types","work_item_ref":null}]},
     {"hash":"f453e66","id":"5ca0b789-3e8b-4b35-ac57-b388427a0115","ordered":false,"priority":null,"repo_slug":"other/mono","status":"pending","title":"stokd worktree tui","updated_at":"2026-08-29T10:00:00.000Z",
      "items":[{"id":"i3","kind":"text","order":0,"ref_hash":null,"repo_slug":"other/mono","status":"pending","task_hash":null,"title":"Rows","work_item_ref":null}]},
     {"hash":"c0ffee1","id":"c0ffee10-0000-0000-0000-000000000001","ordered":false,"priority":null,"repo_slug":"owner/repo","status":"pending","title":"Repo-owned todo","updated_at":"2026-08-31T10:00:00.000Z","items":[]}]
    """

    static let taskGetText = """
    Task #8b4b164  Repair: Distinct gdock tags that differ
    ────────────────────────────────────────────────────────────
    Status:  pending
    ID:      #8b4b164
    Components: scripts/gdock-run

    Description
    ────────────────────────────────────────────────────────────
    Objective:
    Repair the incidental failure: Distinct gdock tags that differ after character 28 alias the same cache.
    Observed evidence:
    Both --path results resolve to the same truncated tag and DerivedData path.

    Acceptance Criteria
    ────────────────────────────────────────────────────────────
    - `a=$(gdock-build --path --tag aaaa1 | head -n1); test "$a" != "$b"` exits 0.
    - The root cause is fixed without weakening the failing gate.

    Notes
    ────────────────────────────────────────────────────────────
    • 2026-09-02 first attempt reproduced the alias.
    """

    static let projectGetText = """
    Project #38f437b  Stokd Work Panel
    ──────────────────────────────────────────────────────────────────────
    Slug:      stokd-work-panel
    Status:    active
    Workspace: owner/repo
    ID:        9003ceb1-65d3-4967-b074-bb1a02a3ae4c
    Sessions:  interactive-claude-67324

    ══════════════════════════════════════════════════════════════════════
    PRD
    ══════════════════════════════════════════════════════════════════════
    # Stokd Work Panel

    ## 0. Source Context
    Port the Work surface with a rhubarb search keyword inside the body.

    ══════════════════════════════════════════════════════════════════════
    Status
    ══════════════════════════════════════════════════════════════════════
    [Phase 1]  Make Work a real, CLI-backed work surface  [PENDING]
      · [bee7b3c9]  Un-gate Work and render it on the non-dock path

    ══════════════════════════════════════════════════════════════════════
    Notes
    ══════════════════════════════════════════════════════════════════════
    • Session 2026-09-02 executing Phase 1.
    """

    static let todoViewJSON = """
    {"hash":"3572f77","todo_id":"d5f9451d-6830-4531-bfdc-baae35588476","ordered":true,"priority":null,"repo_slug":"other/mono","status":"in_progress","title":"CLI data-structure optimization",
     "items":[{"id":"i1","kind":"text","order":0,"ref_hash":null,"repo_slug":"owner/repo","status":"completed","task_hash":null,"title":"Shared contracts","work_item_ref":null},
              {"id":"i2","kind":"text","order":1,"ref_hash":null,"repo_slug":"other/mono","status":"pending","task_hash":null,"title":"Daemon types","work_item_ref":null}]}
    """

    static func task(
        id: String,
        hash: String? = nil,
        title: String,
        status: String = "pending",
        repoSlug: String = "owner/repo",
        updatedAt: String,
        createdAt: String? = nil,
        number: Int? = nil
    ) -> StokdTask {
        StokdTask(
            id: id,
            number: number,
            slug: id,
            title: title,
            description: "",
            status: status,
            repoSlug: repoSlug,
            hashShort: hash ?? id,
            createdAt: createdAt,
            updatedAt: updatedAt
        )
    }

    static func project(
        id: String,
        hash: String? = nil,
        title: String,
        status: String = "active",
        repoSlug: String = "owner/repo",
        updatedAt: String,
        createdAt: String? = nil
    ) -> StokdProject {
        StokdProject(
            id: id,
            number: nil,
            slug: id,
            title: title,
            description: "",
            status: status,
            repoSlug: repoSlug,
            hashShort: hash ?? id,
            createdAt: createdAt,
            updatedAt: updatedAt
        )
    }

    static func todo(
        id: String,
        hash: String? = nil,
        title: String,
        status: String = "pending",
        repoSlug: String = "owner/repo",
        updatedAt: String,
        items: [StokdTodoItem] = []
    ) -> StokdTodo {
        StokdTodo(
            id: id,
            hashShort: hash ?? id,
            title: title,
            status: status,
            repoSlug: repoSlug,
            ordered: false,
            priority: nil,
            updatedAt: updatedAt,
            items: items
        )
    }

    static func todoItem(id: String, title: String, status: String, repoSlug: String = "owner/repo") -> StokdTodoItem {
        StokdTodoItem(id: id, title: title, status: status, kind: "text", order: 0, repoSlug: repoSlug, taskHash: nil)
    }

    static func success(_ stdout: String) -> CommandResult {
        CommandResult(stdout: stdout, stderr: nil, exitStatus: 0, timedOut: false, executionError: nil)
    }

    static func failure(exit: Int32, stderr: String) -> CommandResult {
        CommandResult(stdout: nil, stderr: stderr, exitStatus: exit, timedOut: false, executionError: nil)
    }
}

/// A `StokdWorkCLIClient` that records every invocation and replays canned
/// results keyed by the leading argument vector.
actor FakeStokdWorkCLIClient: StokdWorkCLIClient {
    struct Invocation: Equatable, Sendable {
        let directory: String
        let arguments: [String]
    }

    private(set) var invocations: [Invocation] = []
    private var responses: [[String]: CommandResult] = [:]
    private var fallback: CommandResult
    private var inFlight = 0
    private(set) var maxInFlight = 0
    private var delayNanoseconds: UInt64 = 0

    init(fallback: CommandResult = StokdWorkFixtures.success("[]")) {
        self.fallback = fallback
    }

    func respond(to prefix: [String], with result: CommandResult) {
        responses[prefix] = result
    }

    func setDelay(nanoseconds: UInt64) {
        delayNanoseconds = nanoseconds
    }

    func run(directory: String, arguments: [String], timeout: TimeInterval?) async -> CommandResult {
        _ = timeout
        invocations.append(Invocation(directory: directory, arguments: arguments))
        inFlight += 1
        maxInFlight = max(maxInFlight, inFlight)
        if delayNanoseconds > 0 {
            try? await Task.sleep(nanoseconds: delayNanoseconds)
        }
        inFlight -= 1
        for (prefix, result) in responses where arguments.starts(with: prefix) {
            return result
        }
        return fallback
    }

    func recordedArguments() -> [[String]] {
        invocations.map(\.arguments)
    }
}

struct FixtureStokdWorkLoader: StokdWorkLoading {
    let payload: StokdWorkPayload

    func load(query: StokdWorkListQuery) async -> StokdWorkPayload {
        _ = query
        return payload
    }
}

actor RecordingLimitStokdWorkLoader: StokdWorkLoading {
    private(set) var limits: [Int] = []
    private(set) var queries: [StokdWorkListQuery] = []
    private let payloadForLimit: @Sendable (Int) -> StokdWorkPayload

    init(payloadForLimit: @escaping @Sendable (Int) -> StokdWorkPayload) {
        self.payloadForLimit = payloadForLimit
    }

    func load(query: StokdWorkListQuery) async -> StokdWorkPayload {
        limits.append(query.limitPerKind)
        queries.append(query)
        return payloadForLimit(query.limitPerKind)
    }

    func recordedLimits() -> [Int] { limits }
    func recordedQueries() -> [StokdWorkListQuery] { queries }
}

/// Detail loader whose bodies are keyed by hash; used for detail and body-search tests.
actor FixtureStokdWorkDetailLoader: StokdWorkDetailLoading {
    private let bodies: [String: Result<String, StokdWorkLoadError>]
    private(set) var requestedHashes: [String] = []
    private var inFlight = 0
    private(set) var maxInFlight = 0
    private let delayNanoseconds: UInt64

    init(bodies: [String: Result<String, StokdWorkLoadError>], delayNanoseconds: UInt64 = 0) {
        self.bodies = bodies
        self.delayNanoseconds = delayNanoseconds
    }

    func loadDetailText(kind: StokdWorkItemKind, hash: String, directory: String) async -> Result<String, StokdWorkLoadError> {
        _ = kind
        _ = directory
        requestedHashes.append(hash)
        inFlight += 1
        maxInFlight = max(maxInFlight, inFlight)
        if delayNanoseconds > 0 {
            try? await Task.sleep(nanoseconds: delayNanoseconds)
        }
        inFlight -= 1
        return bodies[hash] ?? .failure(StokdWorkLoadError(kind: .exit(1), message: "no such item \(hash)"))
    }

    func recordedHashes() -> [String] { requestedHashes }
    func recordedMaxInFlight() -> Int { maxInFlight }
}

@MainActor
func stokdWorkWaitUntil(
    attempts: Int = 400,
    _ condition: @escaping @MainActor () -> Bool
) async {
    for _ in 0..<attempts {
        if condition() { return }
        try? await Task.sleep(nanoseconds: 2_000_000)
    }
}

func stokdWorkWaitUntilAsync(
    attempts: Int = 400,
    _ condition: @escaping @Sendable () async -> Bool
) async {
    for _ in 0..<attempts {
        if await condition() { return }
        try? await Task.sleep(nanoseconds: 2_000_000)
    }
}
