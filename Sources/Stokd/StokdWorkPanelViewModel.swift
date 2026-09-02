import AppKit
import Combine
import Foundation

/// State for the Work panel: the loaded set, the kind / completed / sort /
/// search filters, the in-panel detail, and the per-kind context actions.
///
/// All data enters through ``StokdWorkLoading`` and ``StokdWorkDetailLoading``
/// (the resolved `stokd` CLI in production); nothing here spawns a process from
/// `body` or per keystroke — search recomputes over the loaded array and the
/// body search runs debounced in a bounded background queue.
@MainActor
final class StokdWorkPanelViewModel: ObservableObject {
    typealias Filter = StokdWorkKindFilter

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
                return String(localized: "stokdWork.state.empty", defaultValue: "No tasks, projects, or todos found")
            case let .failure(message):
                return message
            }
        }
    }

    struct RowSnapshot: Equatable, Identifiable, Sendable {
        let id: String
        let rawID: String
        let kind: StokdWorkItemKind
        let hash: String
        let number: Int?
        let title: String
        let detail: String
        let status: String
        let repoSlug: String?
        let updatedAt: String
        let createdAt: String?
        let checklistCompleted: Int?
        let checklistTotal: Int?
        var matchedInBody: Bool = false

        var sortCreatedAt: String { createdAt ?? updatedAt }
    }

    struct DetailState: Equatable, Sendable {
        var isLoading: Bool
        var detail: StokdWorkDetail?
        var errorMessage: String?

        var isLoaded: Bool { detail != nil }
    }

    struct PendingAction: Equatable, Sendable {
        let action: StokdWorkAction
        let row: RowSnapshot

        var needsConfirmation: Bool { action.needsConfirmation }
        var needsInput: Bool { action.needsInput }
    }

    @Published private(set) var state: State = .idle
    @Published private(set) var rows: [RowSnapshot] = []
    @Published private(set) var repoSlug: String?
    @Published private(set) var directory: String = ""
    @Published private(set) var filter: Filter
    @Published private(set) var showCompleted: Bool
    @Published private(set) var sortField: StokdWorkSortField
    @Published private(set) var sortAscending: Bool
    @Published private(set) var searchQuery: String = ""
    @Published private(set) var isBodySearchRunning: Bool = false
    @Published private(set) var truncatedKinds: [StokdWorkItemKind] = []
    @Published private(set) var limitPerKind: Int
    @Published private(set) var isLoadingMore: Bool = false
    @Published private(set) var isRefreshing: Bool = false
    @Published private(set) var selectedRow: RowSnapshot?
    @Published private(set) var detailState: DetailState?
    @Published private(set) var pendingAction: PendingAction?
    @Published private(set) var isPerformingAction: Bool = false
    @Published private(set) var actionErrorMessage: String?

    /// Opens a terminal surface running `command` in `directory`. Hosts install
    /// their own launcher; without one, interactive actions are unavailable.
    var terminalLauncher: ((_ command: String, _ directory: String) -> Void)?

    var stateMessage: String {
        guard state == .empty else { return state.message }
        switch filter {
        case .all:
            return state.message
        case .tasks:
            return String(localized: "stokdWork.state.empty.tasks", defaultValue: "No tasks found")
        case .projects:
            return String(localized: "stokdWork.state.empty.projects", defaultValue: "No projects found")
        case .todos:
            return String(localized: "stokdWork.state.empty.todos", defaultValue: "No todos found")
        }
    }

    /// "N of M" while a query is active; qualified with "at least" when any kind
    /// hit its cap so a miss is not mistaken for an absence.
    var searchCountText: String? {
        guard !normalizedQuery.isEmpty else { return nil }
        let shown = rows.count
        let total = filteredBase.count
        if truncatedKinds.isEmpty {
            return String(localized: "stokdWork.search.count", defaultValue: "\(shown) of \(total)")
        }
        return String(localized: "stokdWork.search.countAtLeast", defaultValue: "\(shown) of at least \(total)")
    }

    var isShowingNoMatches: Bool {
        !normalizedQuery.isEmpty && rows.isEmpty && state == .populated
    }

    var noMatchesText: String {
        String(localized: "stokdWork.search.noMatches", defaultValue: "No matches for “\(searchQuery)”")
    }

    /// True while some kind came back exactly full, so scrolling can ask for more.
    var hasMoreRows: Bool { !truncatedKinds.isEmpty }

    func isRowSelected(_ rowID: String) -> Bool {
        selectedRow?.id == rowID
    }

    /// Page size; the list grows by this much per page.
    private let pageSize: Int

    private let loader: any StokdWorkLoading
    private let detailLoader: any StokdWorkDetailLoading
    private let actionClient: any StokdWorkCLIClient
    private let defaults: UserDefaults
    private let searchDebounce: Duration
    private let bodySearchConcurrency = 2

    private var allRows: [RowSnapshot] = []
    private var filteredBase: [RowSnapshot] = []
    private var bodyMatchedHashes: Set<String> = []
    private var bodyTextCache: [String: String] = [:]
    private var detailCache: [String: StokdWorkDetail] = [:]
    private var requestGeneration: UInt64 = 0
    private var loadTask: Task<Void, Never>?
    private var searchGeneration: UInt64 = 0
    private var bodySearchTask: Task<Void, Never>?
    private var detailTask: Task<Void, Never>?
    private var detailGeneration: UInt64 = 0

    init(
        loader: any StokdWorkLoading = StokdWorkCLILoader(),
        detailLoader: (any StokdWorkDetailLoading)? = nil,
        actionClient: (any StokdWorkCLIClient)? = nil,
        defaults: UserDefaults = .standard,
        initialLimitPerKind: Int = StokdWorkListQuery.defaultLimitPerKind,
        searchDebounce: Duration = .milliseconds(300),
        terminalLauncher: ((_ command: String, _ directory: String) -> Void)? = nil
    ) {
        self.loader = loader
        if let detailLoader {
            self.detailLoader = detailLoader
        } else if let cli = loader as? StokdWorkCLILoader {
            self.detailLoader = cli
        } else {
            self.detailLoader = StokdWorkCLILoader()
        }
        self.actionClient = actionClient ?? StokdCLIRunner()
        self.defaults = defaults
        self.searchDebounce = searchDebounce
        self.terminalLauncher = terminalLauncher
        self.limitPerKind = max(1, initialLimitPerKind)
        self.pageSize = max(1, initialLimitPerKind)
        filter = StokdWorkPanelSettings.kindFilter(defaults: defaults)
        showCompleted = StokdWorkPanelSettings.showCompleted(defaults: defaults)
        sortField = StokdWorkPanelSettings.sortField(defaults: defaults)
        sortAscending = StokdWorkPanelSettings.sortAscending(defaults: defaults)
    }

    // MARK: - Loading

    func refresh(repoSlug: String?, directory: String = "") {
        let normalizedRepo = repoSlug?.trimmingCharacters(in: .whitespacesAndNewlines)
        self.repoSlug = normalizedRepo?.isEmpty == false ? normalizedRepo : nil
        self.directory = directory.trimmingCharacters(in: .whitespacesAndNewlines)
        closeDetail()
        bodyTextCache = [:]
        detailCache = [:]
        limitPerKind = pageSize
        reload(preservingRows: false)
    }

    func refreshCurrentRepository() {
        bodyTextCache = [:]
        detailCache = [:]
        reload(preservingRows: true)
    }

    /// Infinite scroll: called as rows appear. Once the operator has scrolled
    /// past the midpoint of what is loaded and a kind is still full, the next
    /// page is requested. Never replaces the list with a spinner.
    func rowDidAppear(id: String) {
        guard hasMoreRows, !isLoadingMore, !isRefreshing, state == .populated else { return }
        guard let index = rows.firstIndex(where: { $0.id == id }) else { return }
        guard index >= rows.count / 2 else { return }
        loadMore()
    }

    /// Grows the per-kind cap by one page and reloads in place.
    func loadMore() {
        guard !isLoadingMore else { return }
        isLoadingMore = true
        limitPerKind = min(limitPerKind + pageSize, 100_000)
        reload(preservingRows: true)
    }

    private func reload(preservingRows: Bool) {
        requestGeneration &+= 1
        let generation = requestGeneration
        loadTask?.cancel()
        cancelBodySearch()
        if !preservingRows {
            allRows = []
            bodyMatchedHashes = []
            recompute()
        }

        guard let repoSlug else {
            allRows = []
            rows = []
            truncatedKinds = []
            isLoadingMore = false
            isRefreshing = false
            state = .failure(String(
                localized: "stokdWork.state.noRepository",
                defaultValue: "No repository is associated with this workspace"
            ))
            return
        }

        // Keep the rows on screen while a page or refresh is in flight; only
        // a first load shows the loading state.
        if preservingRows, !allRows.isEmpty {
            isRefreshing = true
        } else {
            state = .loading
        }
        let query = StokdWorkListQuery(
            repoSlug: repoSlug,
            directory: directory,
            limitPerKind: limitPerKind,
            sortField: sortField,
            sortAscending: sortAscending
        )
        let loader = self.loader
        loadTask = Task { [weak self] in
            let payload = await loader.load(query: query)
            guard let self, self.requestGeneration == generation else { return }
            self.apply(payload)
        }
    }

    /// Sorting is server-side for the page cut and client-side for the merged
    /// set, so a sort change starts over from the first page.
    private func reloadForSortChange() {
        limitPerKind = pageSize
        reload(preservingRows: true)
    }

    private func apply(_ payload: StokdWorkPayload) {
        isLoadingMore = false
        isRefreshing = false
        if let error = payload.error {
            if allRows.isEmpty {
                rows = []
                truncatedKinds = []
                state = .failure(error.message)
            } else {
                // A failed page keeps what is already on screen.
                actionErrorMessage = error.message
            }
            return
        }
        allRows = Self.rows(from: payload)
        truncatedKinds = payload.truncatedKinds
        bodyMatchedHashes = []
        // The load is over: let `recompute()` derive the presented state again.
        state = .populated
        recompute()
        scheduleBodySearch()
    }

    // MARK: - Filters

    func setFilter(_ filter: Filter) {
        guard self.filter != filter else { return }
        self.filter = filter
        StokdWorkPanelSettings.setKindFilter(filter, defaults: defaults)
        recompute()
        scheduleBodySearch()
    }

    func setShowCompleted(_ show: Bool) {
        guard showCompleted != show else { return }
        showCompleted = show
        StokdWorkPanelSettings.setShowCompleted(show, defaults: defaults)
        recompute()
        scheduleBodySearch()
    }

    func toggleShowCompleted() {
        setShowCompleted(!showCompleted)
    }

    func toggleSortDirection() {
        sortAscending.toggle()
        StokdWorkPanelSettings.setSortAscending(sortAscending, defaults: defaults)
        recompute()
        reloadForSortChange()
    }

    func setSortField(_ field: StokdWorkSortField) {
        guard sortField != field else { return }
        sortField = field
        StokdWorkPanelSettings.setSortField(field, defaults: defaults)
        recompute()
        reloadForSortChange()
    }

    func setDetailPaneHeight(_ height: Double) {
        StokdWorkPanelSettings.setDetailPaneHeight(height, defaults: defaults)
    }

    var detailPaneHeight: Double {
        StokdWorkPanelSettings.detailPaneHeight(defaults: defaults)
    }

    // MARK: - Search

    func setSearchQuery(_ query: String) {
        guard searchQuery != query else { return }
        searchQuery = query
        bodyMatchedHashes = []
        recompute()
        scheduleBodySearch()
    }

    func clearSearch() {
        setSearchQuery("")
    }

    private var normalizedQuery: String {
        Self.normalize(searchQuery)
    }

    nonisolated static func normalize(_ text: String) -> String {
        text.folding(options: [.caseInsensitive, .diacriticInsensitive, .widthInsensitive], locale: nil)
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    nonisolated private static func tierOneMatches(_ row: RowSnapshot, query: String) -> Bool {
        guard !query.isEmpty else { return true }
        let haystacks = [row.title, row.hash, row.status, row.repoSlug ?? "", row.detail]
        return haystacks.contains { normalize($0).contains(query) }
    }

    /// Recomputes `filteredBase` and `rows` from `allRows`; never shells out.
    private func recompute() {
        var base = allRows
        if let kind = filter.kind {
            base = base.filter { $0.kind == kind }
        }
        if !showCompleted {
            base = base.filter { !StokdWorkStatus.isTerminal($0.status) }
        }
        base.sort(by: comparator)
        filteredBase = base

        let query = normalizedQuery
        if query.isEmpty {
            rows = base
        } else {
            var tierOne: [RowSnapshot] = []
            var tierTwo: [RowSnapshot] = []
            for row in base {
                if Self.tierOneMatches(row, query: query) {
                    tierOne.append(row)
                } else if bodyMatchedHashes.contains(row.hash) {
                    var marked = row
                    marked.matchedInBody = true
                    tierTwo.append(marked)
                }
            }
            rows = tierOne + tierTwo
        }

        if state == .loading || state.isFailure { return }
        if allRows.isEmpty {
            state = .empty
        } else if rows.isEmpty, query.isEmpty {
            state = .empty
        } else {
            state = .populated
        }
    }

    private func comparator(_ lhs: RowSnapshot, _ rhs: RowSnapshot) -> Bool {
        let lhsKey: String
        let rhsKey: String
        switch sortField {
        case .updatedAt:
            lhsKey = lhs.updatedAt
            rhsKey = rhs.updatedAt
        case .createdAt:
            lhsKey = lhs.sortCreatedAt
            rhsKey = rhs.sortCreatedAt
        }
        if lhsKey != rhsKey {
            return sortAscending ? lhsKey < rhsKey : lhsKey > rhsKey
        }
        if lhs.title != rhs.title { return lhs.title < rhs.title }
        return lhs.id < rhs.id
    }

    // MARK: - Tier-2 body search

    private func cancelBodySearch() {
        searchGeneration &+= 1
        bodySearchTask?.cancel()
        bodySearchTask = nil
        isBodySearchRunning = false
    }

    private func scheduleBodySearch() {
        cancelBodySearch()
        let query = normalizedQuery
        guard !query.isEmpty, !allRows.isEmpty, repoSlug != nil else { return }
        let candidates = filteredBase.filter { !Self.tierOneMatches($0, query: query) }
        guard !candidates.isEmpty else { return }

        let generation = searchGeneration
        let debounce = searchDebounce
        let directory = self.directory
        let detailLoader = self.detailLoader
        let concurrency = bodySearchConcurrency
        let cached = bodyTextCache
        isBodySearchRunning = true

        bodySearchTask = Task { [weak self] in
            if debounce > .zero {
                try? await Task.sleep(for: debounce)
            }
            guard !Task.isCancelled else { return }

            // Cached bodies are checked synchronously; the rest are fetched
            // through a queue that never has more than `concurrency` in flight.
            var pending: [RowSnapshot] = []
            for row in candidates {
                if let text = cached[row.hash] {
                    if Self.normalize(text).contains(query) {
                        await self?.recordBodyMatch(hash: row.hash, generation: generation)
                    }
                } else {
                    pending.append(row)
                }
            }

            await withTaskGroup(of: (String, String?).self) { group in
                var iterator = pending.makeIterator()
                var active = 0
                func enqueueNext() {
                    guard let row = iterator.next() else { return }
                    active += 1
                    group.addTask {
                        let result = await detailLoader.loadDetailText(kind: row.kind, hash: row.hash, directory: directory)
                        return (row.hash, try? result.get())
                    }
                }
                for _ in 0..<concurrency { enqueueNext() }
                while active > 0, let next = await group.next() {
                    let (hash, text) = next
                    active -= 1
                    if Task.isCancelled { break }
                    if let text {
                        await self?.cacheBodyText(text, for: hash, generation: generation)
                        if Self.normalize(text).contains(query) {
                            await self?.recordBodyMatch(hash: hash, generation: generation)
                        }
                    }
                    enqueueNext()
                }
                group.cancelAll()
            }
            await self?.finishBodySearch(generation: generation)
        }
    }

    private func cacheBodyText(_ text: String, for hash: String, generation: UInt64) {
        bodyTextCache[hash] = text
        _ = generation
    }

    private func recordBodyMatch(hash: String, generation: UInt64) {
        guard generation == searchGeneration else { return }
        bodyMatchedHashes.insert(hash)
        recompute()
    }

    private func finishBodySearch(generation: UInt64) {
        guard generation == searchGeneration else { return }
        isBodySearchRunning = false
        bodySearchTask = nil
    }

    // MARK: - Detail

    /// Opens the detail pane for a row; selecting the open row again closes it.
    func select(rowID: String) {
        if selectedRow?.id == rowID {
            closeDetail()
            return
        }
        guard let row = rows.first(where: { $0.id == rowID }) ?? allRows.first(where: { $0.id == rowID }) else { return }
        selectedRow = row
        loadDetail(for: row, force: false)
    }

    func closeDetail() {
        detailGeneration &+= 1
        detailTask?.cancel()
        detailTask = nil
        selectedRow = nil
        detailState = nil
    }

    func retryDetail() {
        guard let row = selectedRow else { return }
        loadDetail(for: row, force: true)
    }

    private func loadDetail(for row: RowSnapshot, force: Bool) {
        detailGeneration &+= 1
        let generation = detailGeneration
        detailTask?.cancel()

        if !force, let cached = detailCache[row.hash] {
            detailState = DetailState(isLoading: false, detail: cached, errorMessage: nil)
            return
        }
        detailState = DetailState(isLoading: true, detail: nil, errorMessage: nil)
        let detailLoader = self.detailLoader
        let directory = self.directory
        detailTask = Task { [weak self] in
            let result = await detailLoader.loadDetailText(kind: row.kind, hash: row.hash, directory: directory)
            guard let self, self.detailGeneration == generation else { return }
            switch result {
            case let .success(text):
                let detail = StokdWorkDetailParser.parse(kind: row.kind, output: text)
                self.detailCache[row.hash] = detail
                self.bodyTextCache[row.hash] = text
                self.detailState = DetailState(isLoading: false, detail: detail, errorMessage: nil)
            case let .failure(error):
                self.detailState = DetailState(isLoading: false, detail: nil, errorMessage: error.message)
            }
        }
    }

    // MARK: - Actions

    func actions(for row: RowSnapshot) -> [StokdWorkAction] {
        StokdWorkActionTable.actions(kind: row.kind, status: row.status)
    }

    /// Entry point for every action surface (row menu, detail bar). Interactive
    /// verbs open a terminal at once; destructive and input verbs park in
    /// `pendingAction` until the view confirms; the rest dispatch immediately.
    func requestAction(_ action: StokdWorkAction, on row: RowSnapshot) {
        if action == .copyHash {
            let pasteboard = NSPasteboard.general
            pasteboard.clearContents()
            pasteboard.setString(row.hash, forType: .string)
            return
        }
        if action.runsInTerminal {
            guard let command = StokdWorkActionTable.terminalCommand(for: action, kind: row.kind, hash: row.hash) else { return }
            guard let terminalLauncher else {
                actionErrorMessage = String(
                    localized: "stokdWork.action.noTerminal",
                    defaultValue: "No terminal is available to run “\(command)”"
                )
                return
            }
            terminalLauncher(command, directory)
            return
        }
        if action.needsConfirmation || action.needsInput {
            pendingAction = PendingAction(action: action, row: row)
            return
        }
        perform(action, on: row, input: nil)
    }

    func confirmPendingAction(input: String?) {
        guard let pending = pendingAction else { return }
        pendingAction = nil
        perform(pending.action, on: pending.row, input: input)
    }

    func cancelPendingAction() {
        pendingAction = nil
    }

    func dismissActionError() {
        actionErrorMessage = nil
    }

    private func perform(_ action: StokdWorkAction, on row: RowSnapshot, input: String?) {
        guard let arguments = StokdWorkActionTable.arguments(for: action, kind: row.kind, hash: row.hash, input: input) else {
            actionErrorMessage = String(
                localized: "stokdWork.action.invalidInput",
                defaultValue: "“\(action.title)” needs a valid value"
            )
            return
        }
        isPerformingAction = true
        let client = actionClient
        let directory = self.directory.isEmpty ? NSHomeDirectory() : self.directory
        Task { [weak self] in
            let result = await client.run(directory: directory, arguments: arguments, timeout: 60)
            guard let self else { return }
            self.isPerformingAction = false
            if let error = StokdWorkCLILoader.error(from: result) {
                self.actionErrorMessage = error.message
                return
            }
            self.detailCache.removeValue(forKey: row.hash)
            self.bodyTextCache.removeValue(forKey: row.hash)
            if action == .delete, self.selectedRow?.hash == row.hash {
                self.closeDetail()
            } else if self.selectedRow?.hash == row.hash {
                self.retryDetail()
            }
            self.reload(preservingRows: true)
        }
    }

    // MARK: - Rows

    private static func rows(from payload: StokdWorkPayload) -> [RowSnapshot] {
        var seen = Set<String>()
        var result: [RowSnapshot] = []
        func append(_ row: RowSnapshot) {
            guard seen.insert(row.id).inserted else { return }
            result.append(row)
        }
        for task in payload.tasks {
            append(RowSnapshot(
                id: "task:\(task.id)",
                rawID: task.id,
                kind: .task,
                hash: task.hashShort ?? task.id,
                number: task.number,
                title: task.title,
                detail: task.description,
                status: task.status,
                repoSlug: task.repoSlug,
                updatedAt: task.updatedAt,
                createdAt: task.createdAt,
                checklistCompleted: nil,
                checklistTotal: nil
            ))
        }
        for project in payload.projects {
            append(RowSnapshot(
                id: "project:\(project.id)",
                rawID: project.id,
                kind: .project,
                hash: project.hashShort ?? project.id,
                number: project.number,
                title: project.title,
                detail: project.description,
                status: project.status,
                repoSlug: project.repoSlug,
                updatedAt: project.updatedAt,
                createdAt: project.createdAt,
                checklistCompleted: nil,
                checklistTotal: nil
            ))
        }
        for todo in payload.todos {
            append(RowSnapshot(
                id: "todo:\(todo.id)",
                rawID: todo.id,
                kind: .todo,
                hash: todo.hashShort ?? todo.id,
                number: nil,
                title: todo.title,
                detail: "",
                status: todo.status,
                repoSlug: todo.repoSlug,
                updatedAt: todo.updatedAt,
                createdAt: nil,
                checklistCompleted: todo.completedItemCount,
                checklistTotal: todo.items.count
            ))
        }
        return result
    }
}
