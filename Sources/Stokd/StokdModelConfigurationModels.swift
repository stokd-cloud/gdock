import Foundation

enum StokdModelConfigurationTab: String, CaseIterable, Identifiable, Sendable {
    case defaults
    case workloads

    var id: String { rawValue }

    var title: String {
        switch self {
        case .defaults:
            return String(localized: "stokdModelConfiguration.tab.defaults", defaultValue: "Defaults")
        case .workloads:
            return String(localized: "stokdModelConfiguration.tab.workloads", defaultValue: "Workloads")
        }
    }
}

enum StokdModelConfigurationWriteScope: String, CaseIterable, Identifiable, Sendable {
    case global
    case workspace

    var id: String { rawValue }

    var title: String {
        switch self {
        case .global:
            return String(localized: "stokdModelConfiguration.scope.global", defaultValue: "Global")
        case .workspace:
            return String(localized: "stokdModelConfiguration.scope.workspace", defaultValue: "Workspace")
        }
    }
}

struct StokdModelConfigurationLaunchAction: Equatable, Identifiable, Sendable {
    let id: String
    let localizationKey: String
    let defaultTitle: String
    let symbolName: String
    let initialTab: StokdModelConfigurationTab

    var title: String {
        switch initialTab {
        case .defaults:
            return String(localized: "stokdModelConfiguration.action.model", defaultValue: "Model Configuration")
        case .workloads:
            return String(localized: "stokdModelConfiguration.action.workload", defaultValue: "Workload Configuration")
        }
    }
}

enum StokdModelConfigurationLaunchBar {
    static let actions: [StokdModelConfigurationLaunchAction] = [
        StokdModelConfigurationLaunchAction(
            id: "gdock.modelConfiguration",
            localizationKey: "stokdModelConfiguration.action.model",
            defaultTitle: "Model Configuration",
            symbolName: "server.rack",
            initialTab: .defaults
        ),
        StokdModelConfigurationLaunchAction(
            id: "gdock.workloadConfiguration",
            localizationKey: "stokdModelConfiguration.action.workload",
            defaultTitle: "Workload Configuration",
            symbolName: "gearshape.2",
            initialTab: .workloads
        ),
    ]
}

struct StokdModelConfigurationModalRequest: Equatable, Identifiable {
    let initialTab: StokdModelConfigurationTab

    var id: String { initialTab.rawValue }
}

struct StokdModelConfigurationPricing: Equatable, Sendable {
    let inputPer1M: Double?
    let outputPer1M: Double?
}

struct StokdModelConfigurationCatalogModel: Equatable, Identifiable, Sendable {
    let id: String
    let displayName: String
    let provider: String
    let providerConfigID: String
    let source: String
    let capability: Double?
    let capabilities: [String]
    let pricing: StokdModelConfigurationPricing?
}

struct StokdModelConfigurationWorkload: Equatable, Identifiable, Sendable {
    let slug: String
    let models: [String]
    let inheritsDefault: Bool

    var id: String { slug }
}

struct StokdModelConfigurationProviderEntry: Equatable, Identifiable, Sendable {
    struct Field: Equatable, Sendable {
        enum Value: Equatable, Sendable {
            case string(String)
            case int(Int)
            case double(Double)
            case bool(Bool)
            case null
        }

        let key: String
        let value: Value
    }

    let name: String
    let objectFields: [Field]?

    init(name: String, objectFields: [Field]? = nil) {
        self.name = name
        self.objectFields = objectFields
    }

    var id: String { name }
}

struct StokdModelConfigurationSnapshot: Equatable, Sendable {
    let catalog: [StokdModelConfigurationCatalogModel]
    let defaults: [String]
    let workloads: [StokdModelConfigurationWorkload]
    let providers: [StokdModelConfigurationProviderEntry]
}
