import Foundation

/// The three first-class stokd work item kinds the Work panel lists.
enum StokdWorkItemKind: String, CaseIterable, Codable, Equatable, Hashable, Sendable {
    case task
    case project
    case todo
}

/// One row of `stokd task list --json`.
struct StokdTask: Decodable, Equatable, Identifiable, Sendable {
    let id: String
    let number: Int?
    let slug: String
    let title: String
    let description: String
    let status: String
    let repoSlug: String?
    let hashShort: String?
    let createdAt: String?
    let updatedAt: String
    let priority: Int?

    init(
        id: String,
        number: Int?,
        slug: String,
        title: String,
        description: String,
        status: String,
        repoSlug: String?,
        hashShort: String?,
        createdAt: String?,
        updatedAt: String,
        priority: Int? = nil
    ) {
        self.id = id
        self.number = number
        self.slug = slug
        self.title = title
        self.description = description
        self.status = status
        self.repoSlug = repoSlug
        self.hashShort = hashShort
        self.createdAt = createdAt
        self.updatedAt = updatedAt
        self.priority = priority
    }

    private enum CodingKeys: String, CodingKey {
        case id
        case taskID = "task_id"
        case number = "task_number"
        case slug
        case title
        case description
        case status
        case repoSlug = "repo_slug"
        case hash
        case hashShort = "hash_short"
        case createdAt = "created_at"
        case updatedAt = "updated_at"
        case priority
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let id = try container.decodeIfPresent(String.self, forKey: .id)
            ?? container.decodeIfPresent(String.self, forKey: .taskID)
            ?? ""
        self.id = id
        number = try container.decodeIfPresent(Int.self, forKey: .number)
        slug = try container.decodeIfPresent(String.self, forKey: .slug) ?? id
        title = try container.decodeIfPresent(String.self, forKey: .title) ?? ""
        description = try container.decodeIfPresent(String.self, forKey: .description) ?? ""
        status = try container.decodeIfPresent(String.self, forKey: .status) ?? ""
        repoSlug = try container.decodeIfPresent(String.self, forKey: .repoSlug)
        hashShort = try container.decodeIfPresent(String.self, forKey: .hash)
            ?? container.decodeIfPresent(String.self, forKey: .hashShort)
        createdAt = try container.decodeIfPresent(String.self, forKey: .createdAt)
        updatedAt = try container.decodeIfPresent(String.self, forKey: .updatedAt) ?? ""
        priority = try container.decodeIfPresent(Int.self, forKey: .priority)
    }
}

/// One row of `stokd project list --json`.
struct StokdProject: Decodable, Equatable, Identifiable, Sendable {
    let id: String
    let number: Int?
    let slug: String
    let title: String
    let description: String
    let status: String
    let repoSlug: String?
    let hashShort: String?
    let createdAt: String?
    let updatedAt: String
    let priority: Int?

    init(
        id: String,
        number: Int?,
        slug: String,
        title: String,
        description: String,
        status: String,
        repoSlug: String?,
        hashShort: String?,
        createdAt: String?,
        updatedAt: String,
        priority: Int? = nil
    ) {
        self.id = id
        self.number = number
        self.slug = slug
        self.title = title
        self.description = description
        self.status = status
        self.repoSlug = repoSlug
        self.hashShort = hashShort
        self.createdAt = createdAt
        self.updatedAt = updatedAt
        self.priority = priority
    }

    private enum CodingKeys: String, CodingKey {
        case id
        case projectID = "project_id"
        case number = "project_number"
        case slug
        case title
        case description
        case status
        case repoSlug = "repo_slug"
        case hash
        case hashShort = "hash_short"
        case createdAt = "created_at"
        case updatedAt = "updated_at"
        case priority
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let id = try container.decodeIfPresent(String.self, forKey: .id)
            ?? container.decodeIfPresent(String.self, forKey: .projectID)
            ?? ""
        self.id = id
        number = try container.decodeIfPresent(Int.self, forKey: .number)
        slug = try container.decodeIfPresent(String.self, forKey: .slug) ?? id
        title = try container.decodeIfPresent(String.self, forKey: .title) ?? ""
        description = try container.decodeIfPresent(String.self, forKey: .description) ?? ""
        status = try container.decodeIfPresent(String.self, forKey: .status) ?? ""
        repoSlug = try container.decodeIfPresent(String.self, forKey: .repoSlug)
        hashShort = try container.decodeIfPresent(String.self, forKey: .hash)
            ?? container.decodeIfPresent(String.self, forKey: .hashShort)
        createdAt = try container.decodeIfPresent(String.self, forKey: .createdAt)
        updatedAt = try container.decodeIfPresent(String.self, forKey: .updatedAt) ?? ""
        priority = try container.decodeIfPresent(Int.self, forKey: .priority)
    }
}

/// One checklist entry nested in a todo.
struct StokdTodoItem: Decodable, Equatable, Identifiable, Sendable {
    let id: String
    let title: String
    let status: String
    let kind: String
    let order: Int
    let repoSlug: String?
    let taskHash: String?

    init(id: String, title: String, status: String, kind: String, order: Int, repoSlug: String?, taskHash: String?) {
        self.id = id
        self.title = title
        self.status = status
        self.kind = kind
        self.order = order
        self.repoSlug = repoSlug
        self.taskHash = taskHash
    }

    private enum CodingKeys: String, CodingKey {
        case id, title, status, kind, order
        case repoSlug = "repo_slug"
        case taskHash = "task_hash"
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decodeIfPresent(String.self, forKey: .id) ?? UUID().uuidString
        title = try container.decodeIfPresent(String.self, forKey: .title) ?? ""
        status = try container.decodeIfPresent(String.self, forKey: .status) ?? ""
        kind = try container.decodeIfPresent(String.self, forKey: .kind) ?? "text"
        order = try container.decodeIfPresent(Int.self, forKey: .order) ?? 0
        repoSlug = try container.decodeIfPresent(String.self, forKey: .repoSlug)
        taskHash = try container.decodeIfPresent(String.self, forKey: .taskHash)
    }

    var isCompleted: Bool {
        StokdWorkStatus.isTerminal(status)
    }
}

/// One row of `stokd todo list --json` / `stokd todo view --json`.
struct StokdTodo: Decodable, Equatable, Identifiable, Sendable {
    let id: String
    let hashShort: String?
    let title: String
    let status: String
    let repoSlug: String?
    let ordered: Bool
    let priority: Int?
    let updatedAt: String
    let items: [StokdTodoItem]

    init(
        id: String,
        hashShort: String?,
        title: String,
        status: String,
        repoSlug: String?,
        ordered: Bool,
        priority: Int?,
        updatedAt: String,
        items: [StokdTodoItem]
    ) {
        self.id = id
        self.hashShort = hashShort
        self.title = title
        self.status = status
        self.repoSlug = repoSlug
        self.ordered = ordered
        self.priority = priority
        self.updatedAt = updatedAt
        self.items = items
    }

    private enum CodingKeys: String, CodingKey {
        case id
        case todoID = "todo_id"
        case hash
        case title, status, ordered, priority, items
        case repoSlug = "repo_slug"
        case updatedAt = "updated_at"
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decodeIfPresent(String.self, forKey: .id)
            ?? container.decodeIfPresent(String.self, forKey: .todoID)
            ?? ""
        hashShort = try container.decodeIfPresent(String.self, forKey: .hash)
        title = try container.decodeIfPresent(String.self, forKey: .title) ?? ""
        status = try container.decodeIfPresent(String.self, forKey: .status) ?? ""
        repoSlug = try container.decodeIfPresent(String.self, forKey: .repoSlug)
        ordered = try container.decodeIfPresent(Bool.self, forKey: .ordered) ?? false
        priority = try container.decodeIfPresent(Int.self, forKey: .priority)
        updatedAt = try container.decodeIfPresent(String.self, forKey: .updatedAt) ?? ""
        items = try container.decodeIfPresent([StokdTodoItem].self, forKey: .items) ?? []
    }

    var completedItemCount: Int { items.filter(\.isCompleted).count }
}

/// Status vocabulary shared by every kind.
enum StokdWorkStatus {
    /// Statuses hidden by the "hide completed" filter and for which
    /// `complete` is no longer a valid verb.
    static let terminalStatuses: Set<String> = ["completed", "cancelled", "failed", "done"]

    static func isTerminal(_ rawValue: String) -> Bool {
        terminalStatuses.contains(rawValue.trimmingCharacters(in: .whitespacesAndNewlines).lowercased())
    }
}

/// What the panel asks the loader for: the repository scope, the directory the
/// CLI resolves its environment from, and the per-kind row cap.
struct StokdWorkListQuery: Equatable, Sendable {
    /// One page. The list grows by this much each time the operator scrolls
    /// past the midpoint of what is loaded.
    static let defaultLimitPerKind = 100

    var repoSlug: String?
    var directory: String
    var limitPerKind: Int
    var sortField: StokdWorkSortField
    var sortAscending: Bool

    init(
        repoSlug: String? = nil,
        directory: String = "",
        limitPerKind: Int = StokdWorkListQuery.defaultLimitPerKind,
        sortField: StokdWorkSortField = .updatedAt,
        sortAscending: Bool = false
    ) {
        self.repoSlug = repoSlug
        self.directory = directory
        self.limitPerKind = max(1, limitPerKind)
        self.sortField = sortField
        self.sortAscending = sortAscending
    }
}

/// A failure to obtain work through the stokd CLI.
struct StokdWorkLoadError: Error, Equatable, Sendable {
    enum Kind: Equatable, Sendable {
        case cliUnavailable
        case exit(Int32)
        case timeout
        case decoding
        case cancelled
    }

    let kind: Kind
    let message: String
}

/// Everything one refresh produced.
struct StokdWorkPayload: Equatable, Sendable {
    let tasks: [StokdTask]
    let projects: [StokdProject]
    let todos: [StokdTodo]
    let limitPerKind: Int
    let error: StokdWorkLoadError?

    init(
        tasks: [StokdTask],
        projects: [StokdProject],
        todos: [StokdTodo],
        limitPerKind: Int,
        error: StokdWorkLoadError?
    ) {
        self.tasks = tasks
        self.projects = projects
        self.todos = todos
        self.limitPerKind = limitPerKind
        self.error = error
    }

    /// Two-kind convenience used by hosts and tests that predate todos.
    init(tasks: [StokdTask], projects: [StokdProject], error: StokdWorkLoadError?) {
        self.init(
            tasks: tasks,
            projects: projects,
            todos: [],
            limitPerKind: StokdWorkListQuery.defaultLimitPerKind,
            error: error
        )
    }

    /// Kinds whose row count hit the per-kind cap, so the list may be incomplete.
    var truncatedKinds: [StokdWorkItemKind] {
        guard limitPerKind > 0 else { return [] }
        var kinds: [StokdWorkItemKind] = []
        if tasks.count >= limitPerKind { kinds.append(.task) }
        if projects.count >= limitPerKind { kinds.append(.project) }
        if todos.count >= limitPerKind { kinds.append(.todo) }
        return kinds
    }
}
