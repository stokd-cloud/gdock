import Combine
import Foundation

struct StokdWorkPayload: Equatable, Sendable {
    let tasks: [StokdTask]
    let projects: [StokdProject]
    let error: StokdWorkAPIError?
}

protocol StokdWorkLoading: Sendable {
    func load(query: StokdWorkListQuery) async -> StokdWorkPayload
}

extension StokdWorkAPIClient: StokdWorkLoading {
    func load(query: StokdWorkListQuery) async -> StokdWorkPayload {
        async let taskResult = tasks(query)
        async let projectResult = projects(query)
        let (tasks, projects) = await (taskResult, projectResult)
        return StokdWorkPayload(
            tasks: tasks.page.items,
            projects: projects.page.items,
            error: tasks.error ?? projects.error
        )
    }
}

@MainActor
final class StokdWorkPanelViewModel: ObservableObject {
    enum Filter: String, CaseIterable, Equatable, Sendable {
        case all
        case tasks
        case projects
    }

    enum State: Equatable, Sendable {
        case idle
        case loading
        case populated
        case empty
        case failure(String)

        var isFailure: Bool {
            if case .failure = self { return true }
            return false
        }

        var message: String {
            switch self {
            case .idle:
                return String(localized: "stokdWork.state.idle", defaultValue: "Select a repository to view work")
            case .loading:
                return String(localized: "stokdWork.state.loading", defaultValue: "Loading work")
            case .populated:
                return ""
            case .empty:
                return String(localized: "stokdWork.state.empty", defaultValue: "No tasks or projects found")
            case let .failure(message):
                return message
            }
        }
    }

    struct RowSnapshot: Equatable, Identifiable, Sendable {
        enum Kind: String, Equatable, Sendable {
            case task
            case project
        }

        let id: String
        let rawID: String
        let kind: Kind
        let title: String
        let detail: String
        let status: String
        let updatedAt: String
    }

    @Published private(set) var state: State = .idle
    @Published private(set) var rows: [RowSnapshot] = []
    @Published private(set) var repoSlug: String?
    @Published private(set) var filter: Filter = .all

    private let loader: any StokdWorkLoading
    private var allRows: [RowSnapshot] = []
    private var requestGeneration: UInt64 = 0
    private var loadTask: Task<Void, Never>?

    init(loader: any StokdWorkLoading = StokdWorkAPIClient()) {
        self.loader = loader
    }

    func refresh(repoSlug: String?) {
        let normalizedRepo = repoSlug?
            .trimmingCharacters(in: .whitespacesAndNewlines)
        requestGeneration &+= 1
        let generation = requestGeneration
        loadTask?.cancel()
        self.repoSlug = normalizedRepo?.isEmpty == false ? normalizedRepo : nil
        allRows = []
        rows = []

        guard let repoSlug = self.repoSlug else {
            state = .failure(String(
                localized: "stokdWork.state.noRepository",
                defaultValue: "No repository is associated with this workspace"
            ))
            return
        }

        state = .loading
        let loader = self.loader
        loadTask = Task { [weak self] in
            let payload = await loader.load(query: StokdWorkListQuery(repoSlug: repoSlug))
            guard let self, self.requestGeneration == generation else { return }
            self.apply(payload)
        }
    }

    func setFilter(_ filter: Filter) {
        guard self.filter != filter else { return }
        self.filter = filter
        applyFilter()
    }

    private func apply(_ payload: StokdWorkPayload) {
        guard let error = payload.error else {
            allRows = Self.sortedRows(tasks: payload.tasks, projects: payload.projects)
            applyFilter()
            return
        }
        allRows = []
        rows = []
        state = .failure(error.message)
    }

    private func applyFilter() {
        switch filter {
        case .all:
            rows = allRows
        case .tasks:
            rows = allRows.filter { $0.kind == .task }
        case .projects:
            rows = allRows.filter { $0.kind == .project }
        }
        state = rows.isEmpty ? .empty : .populated
    }

    private static func sortedRows(tasks: [StokdTask], projects: [StokdProject]) -> [RowSnapshot] {
        let taskRows = tasks.map { task in
            RowSnapshot(
                id: "task:\(task.id)",
                rawID: task.id,
                kind: .task,
                title: task.title,
                detail: task.description,
                status: task.status,
                updatedAt: task.updatedAt
            )
        }
        let projectRows = projects.map { project in
            RowSnapshot(
                id: "project:\(project.id)",
                rawID: project.id,
                kind: .project,
                title: project.title,
                detail: project.description,
                status: project.status,
                updatedAt: project.updatedAt
            )
        }
        return (taskRows + projectRows).sorted { lhs, rhs in
            if lhs.updatedAt != rhs.updatedAt { return lhs.updatedAt > rhs.updatedAt }
            if lhs.title != rhs.title { return lhs.title < rhs.title }
            return lhs.id < rhs.id
        }
    }
}
