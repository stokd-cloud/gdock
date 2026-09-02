import CmuxFoundation
import Foundation

/// Subprocess seam for the Work panel. Production uses ``StokdCLIRunner``, which
/// resolves the `stokd` executable and lets the CLI pick the environment, org,
/// and credentials; tests inject a fake and never spawn a process.
protocol StokdWorkCLIClient: Sendable {
    func run(directory: String, arguments: [String], timeout: TimeInterval?) async -> CommandResult
}

extension StokdCLIRunner: StokdWorkCLIClient {}

protocol StokdWorkLoading: Sendable {
    func load(query: StokdWorkListQuery) async -> StokdWorkPayload
}

protocol StokdWorkDetailLoading: Sendable {
    func loadDetailText(kind: StokdWorkItemKind, hash: String, directory: String) async -> Result<String, StokdWorkLoadError>
}

/// The exact argument vectors the panel hands to `stokd`.
enum StokdWorkCLIArguments {
    static func list(kind: StokdWorkItemKind, repoSlug: String, limit: Int) -> [String] {
        switch kind {
        case .task:
            return ["task", "list", "--repo", repoSlug, "--all", "--json", "--limit", String(limit)]
        case .project:
            return ["project", "list", "--repo", repoSlug, "--all", "--json", "--limit", String(limit)]
        case .todo:
            // Todos span repositories (a todo owned by one repo can carry items
            // from another), so the CLI is asked for all of them and membership
            // is decided client-side by `StokdWorkCLILoader.todoBelongs`.
            return ["todo", "list", "--all", "--json", "--limit", String(limit)]
        }
    }

    static func detail(kind: StokdWorkItemKind, hash: String) -> [String] {
        switch kind {
        case .task:
            return ["task", "get", hash]
        case .project:
            return ["project", "get", hash]
        case .todo:
            return ["todo", "view", hash, "--json"]
        }
    }
}

enum StokdWorkLoadErrorMessage {
    static var cliUnavailable: String {
        String(
            localized: "stokdWork.error.cliUnavailable",
            defaultValue: "The stokd CLI is not installed or not on PATH"
        )
    }

    static var timeout: String {
        String(localized: "stokdWork.error.timeout", defaultValue: "The stokd command timed out")
    }

    static func exit(_ status: Int32) -> String {
        String(localized: "stokdWork.error.exitStatus", defaultValue: "stokd exited with status \(status)")
    }

    static func decoding(_ detail: String) -> String {
        String(localized: "stokdWork.error.decoding", defaultValue: "Unable to read the stokd output: \(detail)")
    }

    static var cancelled: String {
        String(localized: "stokdWork.error.cancelled", defaultValue: "The stokd command was cancelled")
    }
}

/// Loads work items and their details by shelling out to the resolved `stokd`.
struct StokdWorkCLILoader: StokdWorkLoading, StokdWorkDetailLoading, Sendable {
    private let client: any StokdWorkCLIClient
    private let timeout: TimeInterval?

    init(client: any StokdWorkCLIClient = StokdCLIRunner(), timeout: TimeInterval? = 20) {
        self.client = client
        self.timeout = timeout
    }

    func load(query: StokdWorkListQuery) async -> StokdWorkPayload {
        let repoSlug = query.repoSlug?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        let directory = Self.workingDirectory(for: query.directory)
        let limit = query.limitPerKind

        async let taskResult = run(
            directory: directory,
            arguments: StokdWorkCLIArguments.list(kind: .task, repoSlug: repoSlug, limit: limit),
            as: [StokdTask].self
        )
        async let projectResult = run(
            directory: directory,
            arguments: StokdWorkCLIArguments.list(kind: .project, repoSlug: repoSlug, limit: limit),
            as: [StokdProject].self
        )
        async let todoResult = run(
            directory: directory,
            arguments: StokdWorkCLIArguments.list(kind: .todo, repoSlug: repoSlug, limit: limit),
            as: [StokdTodo].self
        )
        let (tasks, projects, todos) = await (taskResult, projectResult, todoResult)

        if let error = Self.firstError(tasks, projects, todos) {
            return StokdWorkPayload(tasks: [], projects: [], todos: [], limitPerKind: limit, error: error)
        }
        let memberTodos = ((try? todos.get()) ?? []).filter { Self.todoBelongs($0, toRepo: repoSlug) }
        return StokdWorkPayload(
            tasks: (try? tasks.get()) ?? [],
            projects: (try? projects.get()) ?? [],
            todos: memberTodos,
            limitPerKind: limit,
            error: nil
        )
    }

    func loadDetailText(kind: StokdWorkItemKind, hash: String, directory: String) async -> Result<String, StokdWorkLoadError> {
        let result = await client.run(
            directory: Self.workingDirectory(for: directory),
            arguments: StokdWorkCLIArguments.detail(kind: kind, hash: hash),
            timeout: timeout
        )
        if let error = Self.error(from: result) {
            return .failure(error)
        }
        return .success(result.stdout ?? "")
    }

    /// A todo is part of a repository when the todo itself or any of its
    /// checklist items names that repository.
    static func todoBelongs(_ todo: StokdTodo, toRepo repoSlug: String) -> Bool {
        let wanted = repoSlug.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !wanted.isEmpty else { return true }
        if todo.repoSlug?.lowercased() == wanted { return true }
        return todo.items.contains { $0.repoSlug?.lowercased() == wanted }
    }

    /// Maps a finished command to a structured failure, or `nil` on success.
    static func error(from result: CommandResult) -> StokdWorkLoadError? {
        if let executionError = result.executionError {
            if executionError.lowercased().contains("cancel") {
                return StokdWorkLoadError(kind: .cancelled, message: StokdWorkLoadErrorMessage.cancelled)
            }
            return StokdWorkLoadError(kind: .cliUnavailable, message: StokdWorkLoadErrorMessage.cliUnavailable)
        }
        if result.timedOut {
            return StokdWorkLoadError(kind: .timeout, message: StokdWorkLoadErrorMessage.timeout)
        }
        guard let status = result.exitStatus else {
            return StokdWorkLoadError(kind: .cliUnavailable, message: StokdWorkLoadErrorMessage.cliUnavailable)
        }
        if status == 127 {
            return StokdWorkLoadError(kind: .cliUnavailable, message: StokdWorkLoadErrorMessage.cliUnavailable)
        }
        guard status == 0 else {
            let stderr = result.stderr?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            let message = stderr.isEmpty ? StokdWorkLoadErrorMessage.exit(status) : stderr
            return StokdWorkLoadError(kind: .exit(status), message: message)
        }
        return nil
    }

    private func run<Value: Decodable & Sendable>(
        directory: String,
        arguments: [String],
        as type: Value.Type
    ) async -> Result<Value, StokdWorkLoadError> {
        let result = await client.run(directory: directory, arguments: arguments, timeout: timeout)
        if let error = Self.error(from: result) {
            return .failure(error)
        }
        let data = Data((result.stdout ?? "").utf8)
        do {
            return .success(try JSONDecoder().decode(type, from: data))
        } catch {
            return .failure(StokdWorkLoadError(
                kind: .decoding,
                message: StokdWorkLoadErrorMessage.decoding(error.localizedDescription)
            ))
        }
    }

    private static func firstError<A, B, C>(
        _ a: Result<A, StokdWorkLoadError>,
        _ b: Result<B, StokdWorkLoadError>,
        _ c: Result<C, StokdWorkLoadError>
    ) -> StokdWorkLoadError? {
        if case let .failure(error) = a { return error }
        if case let .failure(error) = b { return error }
        if case let .failure(error) = c { return error }
        return nil
    }

    private static func workingDirectory(for directory: String) -> String {
        let trimmed = directory.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? NSHomeDirectory() : trimmed
    }
}
