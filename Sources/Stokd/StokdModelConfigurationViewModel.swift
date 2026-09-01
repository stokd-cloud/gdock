import Combine
import Foundation

@MainActor
final class StokdModelConfigurationViewModel: ObservableObject {
    enum State: Equatable, Sendable {
        case idle
        case loading
        case populated
        case empty
        case failure(String)

        var message: String {
            switch self {
            case .idle:
                return String(localized: "stokdModelConfiguration.state.idle", defaultValue: "Open a workspace to edit Stokd model configuration")
            case .loading:
                return String(localized: "stokdModelConfiguration.state.loading", defaultValue: "Loading model configuration")
            case .populated:
                return ""
            case .empty:
                return String(localized: "stokdModelConfiguration.state.empty", defaultValue: "No model configuration found")
            case let .failure(message):
                return message
            }
        }
    }

    @Published var selectedTab: StokdModelConfigurationTab
    @Published var scope: StokdModelConfigurationWriteScope = .workspace
    @Published var searchText = ""
    @Published var defaultsText = ""
    @Published var selectedWorkloadSlug = ""
    @Published var selectedWorkloadModelsText = ""
    @Published private(set) var state: State = .idle
    @Published private(set) var catalog: [StokdModelConfigurationCatalogModel] = []
    @Published private(set) var workloads: [StokdModelConfigurationWorkload] = []
    @Published private(set) var isApplying = false
    @Published private(set) var successMessage: String?

    private let loader: any StokdModelConfigurationLoading
    private var requestGeneration: UInt64 = 0
    private var loadTask: Task<Void, Never>?
    private var applyTask: Task<Void, Never>?

    init(
        initialTab: StokdModelConfigurationTab,
        loader: any StokdModelConfigurationLoading = StokdModelConfigurationCLILoader()
    ) {
        self.selectedTab = initialTab
        self.loader = loader
    }

    var filteredCatalog: [StokdModelConfigurationCatalogModel] {
        let query = searchText.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !query.isEmpty else { return catalog }
        return catalog.filter { model in
            model.id.lowercased().contains(query)
                || model.displayName.lowercased().contains(query)
                || model.provider.lowercased().contains(query)
                || model.providerConfigID.lowercased().contains(query)
        }
    }

    var defaults: [String] {
        Self.parseModelText(defaultsText)
    }

    var selectedWorkloadModels: [String] {
        Self.parseModelText(selectedWorkloadModelsText)
    }

    func refresh(directory: String) {
        requestGeneration &+= 1
        let generation = requestGeneration
        loadTask?.cancel()
        state = .loading
        successMessage = nil
        let loader = self.loader
        loadTask = Task { [weak self] in
            do {
                let snapshot = try await loader.load(directory: directory)
                guard let self, self.requestGeneration == generation else { return }
                self.apply(snapshot)
            } catch {
                guard let self, self.requestGeneration == generation else { return }
                self.catalog = []
                self.workloads = []
                self.defaultsText = ""
                self.selectedWorkloadSlug = ""
                self.selectedWorkloadModelsText = ""
                self.state = .failure(error.localizedDescription)
            }
        }
    }

    func applyDefaults(directory: String) {
        let models = defaults
        applyTask?.cancel()
        isApplying = true
        successMessage = nil
        let loader = self.loader
        let scope = self.scope
        applyTask = Task { [weak self] in
            do {
                try await loader.applyDefaults(models, scope: scope, directory: directory)
                guard let self else { return }
                self.defaultsText = Self.modelText(models)
                self.successMessage = String(localized: "stokdModelConfiguration.success", defaultValue: "Saved")
                self.isApplying = false
            } catch {
                guard let self else { return }
                self.state = .failure(error.localizedDescription)
                self.isApplying = false
            }
        }
    }

    func applySelectedWorkload(directory: String) {
        let slug = selectedWorkloadSlug.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !slug.isEmpty else { return }
        let models = selectedWorkloadModels
        applyTask?.cancel()
        isApplying = true
        successMessage = nil
        let loader = self.loader
        let scope = self.scope
        applyTask = Task { [weak self] in
            do {
                try await loader.applyWorkload(slug: slug, models: models, scope: scope, directory: directory)
                guard let self else { return }
                let writeSlug = StokdModelConfigurationCLIArguments.workloadWriteSlug(slug)
                self.upsertWorkload(slug: writeSlug, models: models)
                self.selectedWorkloadSlug = writeSlug
                self.selectedWorkloadModelsText = Self.modelText(models)
                self.successMessage = String(localized: "stokdModelConfiguration.success", defaultValue: "Saved")
                self.isApplying = false
            } catch {
                guard let self else { return }
                self.state = .failure(error.localizedDescription)
                self.isApplying = false
            }
        }
    }

    func selectWorkload(slug: String) {
        selectedWorkloadSlug = slug
        selectedWorkloadModelsText = Self.modelText(
            workloads.first { $0.slug == slug }?.models ?? []
        )
    }

    func addModelToDefaults(_ id: String) {
        var models = defaults
        guard !models.contains(id) else { return }
        models.append(id)
        defaultsText = Self.modelText(models)
    }

    func removeDefault(_ id: String) {
        defaultsText = Self.modelText(defaults.filter { $0 != id })
    }

    func addModelToSelectedWorkload(_ id: String) {
        var models = selectedWorkloadModels
        guard !models.contains(id) else { return }
        models.append(id)
        selectedWorkloadModelsText = Self.modelText(models)
    }

    func removeWorkloadModel(_ id: String) {
        selectedWorkloadModelsText = Self.modelText(selectedWorkloadModels.filter { $0 != id })
    }

    private func apply(_ snapshot: StokdModelConfigurationSnapshot) {
        catalog = snapshot.catalog
        workloads = snapshot.workloads
        defaultsText = Self.modelText(snapshot.defaults)
        if let current = snapshot.workloads.first(where: { $0.slug == selectedWorkloadSlug }) {
            selectedWorkloadModelsText = Self.modelText(current.models)
        } else if let first = snapshot.workloads.first {
            selectedWorkloadSlug = first.slug
            selectedWorkloadModelsText = Self.modelText(first.models)
        } else {
            selectedWorkloadSlug = ""
            selectedWorkloadModelsText = ""
        }
        state = snapshot.catalog.isEmpty && snapshot.defaults.isEmpty && snapshot.workloads.isEmpty
            ? .empty
            : .populated
    }

    private func upsertWorkload(slug: String, models: [String]) {
        var next = workloads.filter { $0.slug != slug }
        next.append(StokdModelConfigurationWorkload(slug: slug, models: models, inheritsDefault: false))
        workloads = next.sorted { $0.slug < $1.slug }
        state = .populated
    }

    private static func parseModelText(_ text: String) -> [String] {
        text
            .replacingOccurrences(of: "\n", with: ",")
            .split(separator: ",")
            .map { String($0).trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
    }

    private static func modelText(_ models: [String]) -> String {
        models.joined(separator: "\n")
    }
}
