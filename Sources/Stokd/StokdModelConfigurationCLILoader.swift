import CmuxFoundation
import Foundation

protocol StokdModelConfigurationCLIClient: Sendable {
    func run(
        directory: String,
        arguments: [String],
        timeout: TimeInterval?
    ) async -> CommandResult
}

extension StokdCLIRunner: StokdModelConfigurationCLIClient {}

protocol StokdModelConfigurationLoading: Sendable {
    func load(directory: String) async throws -> StokdModelConfigurationSnapshot
    func applyDefaults(
        _ models: [String],
        scope: StokdModelConfigurationWriteScope,
        directory: String
    ) async throws
    func applyWorkload(
        slug: String,
        models: [String],
        scope: StokdModelConfigurationWriteScope,
        directory: String
    ) async throws
}

enum StokdModelConfigurationCLIArguments {
    static func writeDefaults(
        _ models: [String],
        scope: StokdModelConfigurationWriteScope
    ) -> [String] {
        writeConfigSet(
            key: "models.defaults",
            value: serializeScalarList(models),
            scope: scope
        )
    }

    static func writeWorkload(
        slug: String,
        models: [String],
        scope: StokdModelConfigurationWriteScope
    ) -> [String] {
        writeConfigSet(
            key: "models.workloads.\(workloadWriteSlug(slug))",
            value: serializeScalarList(models),
            scope: scope
        )
    }

    static func workloadWriteSlug(_ slug: String) -> String {
        let trimmed = slug.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return trimmed }
        if trimmed == "titleGen" || trimmed.lowercased() == "titlegen" {
            return "title"
        }
        return trimmed
    }

    private static func writeConfigSet(
        key: String,
        value: String,
        scope: StokdModelConfigurationWriteScope
    ) -> [String] {
        var args = ["config", "set", key, value]
        if scope == .workspace {
            args.append("--workspace")
        }
        return args
    }

    private static func serializeScalarList(_ models: [String]) -> String {
        models
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
            .joined(separator: ",")
    }
}

struct StokdModelConfigurationCLIError: Error, Equatable, Sendable {
    let message: String
}

extension StokdModelConfigurationCLIError: LocalizedError {
    var errorDescription: String? { message }
}

struct StokdModelConfigurationCLILoader: StokdModelConfigurationLoading {
    private let client: any StokdModelConfigurationCLIClient
    private let timeout: TimeInterval?

    init(
        client: any StokdModelConfigurationCLIClient = StokdCLIRunner(),
        timeout: TimeInterval? = 10
    ) {
        self.client = client
        self.timeout = timeout
    }

    func load(directory: String) async throws -> StokdModelConfigurationSnapshot {
        let catalogJSON = try await runChecked(
            directory: directory,
            arguments: ["model", "list", "--json"]
        )
        let configJSON = try await runChecked(
            directory: directory,
            arguments: ["config", "show", "--json"]
        )

        let catalogRoot = try Self.parseJSON(catalogJSON)
        let configRoot = try Self.parseJSON(configJSON)
        return StokdModelConfigurationSnapshot(
            catalog: Self.flattenCatalog(catalogRoot),
            defaults: Self.readDefaults(from: configRoot),
            workloads: Self.readWorkloads(from: configRoot)
        )
    }

    func applyDefaults(
        _ models: [String],
        scope: StokdModelConfigurationWriteScope,
        directory: String
    ) async throws {
        let expected = Self.cleanModelList(models)
        _ = try await runChecked(
            directory: directory,
            arguments: StokdModelConfigurationCLIArguments.writeDefaults(expected, scope: scope)
        )
        let config = try Self.parseJSON(try await runChecked(
            directory: directory,
            arguments: ["config", "show", "--json"]
        ))
        guard Self.readDefaults(from: config) == expected else {
            throw StokdModelConfigurationCLIError(
                message: String(localized: "stokdModelConfiguration.error.verifyDefaults", defaultValue: "Stokd did not persist the requested default model order")
            )
        }
    }

    func applyWorkload(
        slug: String,
        models: [String],
        scope: StokdModelConfigurationWriteScope,
        directory: String
    ) async throws {
        let writeSlug = StokdModelConfigurationCLIArguments.workloadWriteSlug(slug)
        let expected = Self.cleanModelList(models)
        _ = try await runChecked(
            directory: directory,
            arguments: StokdModelConfigurationCLIArguments.writeWorkload(
                slug: writeSlug,
                models: expected,
                scope: scope
            )
        )
        let config = try Self.parseJSON(try await runChecked(
            directory: directory,
            arguments: ["config", "show", "--json"]
        ))
        guard Self.readWorkloadModels(from: config, slug: writeSlug) == expected else {
            throw StokdModelConfigurationCLIError(
                message: String(localized: "stokdModelConfiguration.error.verifyWorkload", defaultValue: "Stokd did not persist the requested workload model order")
            )
        }
    }

    private func runChecked(
        directory: String,
        arguments: [String]
    ) async throws -> String {
        let result = await client.run(
            directory: directory,
            arguments: arguments,
            timeout: timeout
        )
        if let error = result.executionError, !error.isEmpty {
            throw StokdModelConfigurationCLIError(message: error)
        }
        if result.timedOut {
            throw StokdModelConfigurationCLIError(
                message: String(localized: "stokdModelConfiguration.error.timeout", defaultValue: "Stokd command timed out")
            )
        }
        guard result.exitStatus == 0 else {
            let message = [result.stderr, result.stdout]
                .compactMap { $0?.trimmingCharacters(in: .whitespacesAndNewlines) }
                .first { !$0.isEmpty }
                ?? String(localized: "stokdModelConfiguration.error.commandFailed", defaultValue: "Stokd command failed")
            throw StokdModelConfigurationCLIError(message: message)
        }
        return result.stdout ?? ""
    }

    private static func parseJSON(_ string: String) throws -> Any {
        let data = Data(string.utf8)
        do {
            return try JSONSerialization.jsonObject(with: data)
        } catch {
            throw StokdModelConfigurationCLIError(
                message: String.localizedStringWithFormat(
                    String(localized: "stokdModelConfiguration.error.decoding", defaultValue: "Unable to read Stokd configuration JSON: %@"),
                    error.localizedDescription
                )
            )
        }
    }

    private static func flattenCatalog(_ root: Any) -> [StokdModelConfigurationCatalogModel] {
        guard let entries = root as? [Any] else { return [] }
        return entries.flatMap { entry -> [StokdModelConfigurationCatalogModel] in
            guard let dictionary = entry as? [String: Any] else { return [] }
            if let childModels = dictionary["models"] as? [Any] {
                return childModels.compactMap { child in
                    guard var childDictionary = child as? [String: Any] else { return nil }
                    childDictionary["provider"] = childDictionary["provider"] ?? dictionary["provider"]
                    childDictionary["source"] = childDictionary["source"] ?? dictionary["source"]
                    return catalogModel(from: childDictionary)
                }
            }
            return catalogModel(from: dictionary).map { [$0] } ?? []
        }
    }

    private static func catalogModel(from dictionary: [String: Any]) -> StokdModelConfigurationCatalogModel? {
        guard let id = firstString(dictionary, keys: ["id", "modelId", "model"]) else { return nil }
        let provider = firstString(dictionary, keys: ["provider"]) ?? ""
        let source = firstString(dictionary, keys: ["source"]) ?? ""
        return StokdModelConfigurationCatalogModel(
            id: id,
            displayName: firstString(dictionary, keys: ["display_name", "displayName", "name"]) ?? id,
            provider: provider,
            providerConfigID: providerConfigID(for: provider),
            source: source,
            capability: doubleValue(dictionary["capability"]),
            capabilities: stringList(dictionary["capabilities"]),
            pricing: pricing(from: dictionary["pricing"])
        )
    }

    private static func providerConfigID(for provider: String) -> String {
        switch provider.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() {
        case "claude":
            return "claudeCode"
        case "gemini":
            return "geminiCli"
        default:
            return provider
        }
    }

    private static func pricing(from value: Any?) -> StokdModelConfigurationPricing? {
        guard let dictionary = value as? [String: Any] else { return nil }
        let input = doubleValue(dictionary["inputPer1M"] ?? dictionary["input_per_1m"])
        let output = doubleValue(dictionary["outputPer1M"] ?? dictionary["output_per_1m"])
        guard input != nil || output != nil else { return nil }
        return StokdModelConfigurationPricing(inputPer1M: input, outputPer1M: output)
    }

    private static func readDefaults(from root: Any) -> [String] {
        guard let dictionary = root as? [String: Any] else { return [] }
        let models = dictionary["models"] as? [String: Any]
        if let value = models?["defaults"] {
            return cleanModelList(stringList(value))
        }
        let llm = dictionary["llm"] as? [String: Any]
        return cleanModelList(stringList(llm?["fallbackModels"]))
    }

    private static func readWorkloads(from root: Any) -> [StokdModelConfigurationWorkload] {
        let workloads = readWorkloadDictionary(from: root)
        var bySlug: [String: [String]] = [:]
        for key in workloads.keys.sorted() {
            let slug = StokdModelConfigurationCLIArguments.workloadWriteSlug(key)
            guard !slug.isEmpty else { continue }
            let models = readWorkloadEntry(workloads[key])
            if key == slug || bySlug[slug] == nil {
                bySlug[slug] = models
            }
        }
        return bySlug.keys.sorted().map { slug in
            StokdModelConfigurationWorkload(slug: slug, models: bySlug[slug] ?? [])
        }
    }

    private static func readWorkloadModels(from root: Any, slug: String) -> [String] {
        let workloads = readWorkloadDictionary(from: root)
        for key in workloadReadKeys(slug) {
            guard let value = workloads[key] else { continue }
            let models = readWorkloadEntry(value)
            if !models.isEmpty || value is [Any] {
                return models
            }
        }
        return []
    }

    private static func readWorkloadDictionary(from root: Any) -> [String: Any] {
        guard let dictionary = root as? [String: Any] else { return [:] }
        if let models = dictionary["models"] as? [String: Any],
           let workloads = models["workloads"] as? [String: Any] {
            return workloads
        }
        if let llm = dictionary["llm"] as? [String: Any],
           let workloads = llm["workloads"] as? [String: Any] {
            return workloads
        }
        return [:]
    }

    private static func readWorkloadEntry(_ value: Any?) -> [String] {
        if let dictionary = value as? [String: Any],
           let models = dictionary["models"] {
            return cleanModelList(stringList(models))
        }
        return cleanModelList(stringList(value))
    }

    private static func workloadReadKeys(_ slug: String) -> [String] {
        let trimmed = slug.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return [] }
        if trimmed == "title" || trimmed == "titleGen" || trimmed.lowercased() == "titlegen" {
            return ["title", "titleGen"]
        }
        return [trimmed]
    }

    private static func cleanModelList(_ models: [String]) -> [String] {
        models
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
    }

    private static func stringList(_ value: Any?) -> [String] {
        if let values = value as? [Any] {
            return values.compactMap { item in
                if let string = item as? String { return string }
                if let number = item as? NSNumber { return number.stringValue }
                return nil
            }
        }
        if let string = value as? String {
            return string
                .split(separator: ",")
                .map { String($0) }
        }
        if let number = value as? NSNumber {
            return [number.stringValue]
        }
        return []
    }

    private static func firstString(_ dictionary: [String: Any], keys: [String]) -> String? {
        for key in keys {
            if let string = dictionary[key] as? String,
               !string.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                return string
            }
        }
        return nil
    }

    private static func doubleValue(_ value: Any?) -> Double? {
        if let double = value as? Double { return double }
        if let int = value as? Int { return Double(int) }
        if let number = value as? NSNumber { return number.doubleValue }
        if let string = value as? String { return Double(string) }
        return nil
    }
}
