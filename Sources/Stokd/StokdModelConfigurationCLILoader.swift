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
    func applyProviders(
        _ providers: [StokdModelConfigurationProviderEntry],
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
        let defaults = try await runOptionalConfigGet(
            directory: directory,
            key: "models.defaults"
        )
        let providers = try await runOptionalConfigGet(
            directory: directory,
            key: "providers"
        )
        let workloadJSON = try await runChecked(
            directory: directory,
            arguments: ["model", "workload", "--json"]
        )

        let catalogRoot = try Self.parseJSON(catalogJSON)
        return StokdModelConfigurationSnapshot(
            catalog: Self.flattenCatalog(catalogRoot),
            defaults: Self.cleanModelList(Self.stringList(defaults)),
            workloads: try Self.readWorkloads(fromJSON: workloadJSON),
            providers: try Self.readProviders(fromYAML: providers ?? "")
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
        let persisted = try await runRequiredConfigGet(
            directory: directory,
            key: "models.defaults"
        )
        guard Self.cleanModelList(Self.stringList(persisted)) == expected else {
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
        let workloads = try Self.readWorkloads(fromJSON: try await runChecked(
            directory: directory,
            arguments: ["model", "workload", "--json"]
        ))
        guard workloads.first(where: { $0.slug == writeSlug })?.models == expected else {
            throw StokdModelConfigurationCLIError(
                message: String(localized: "stokdModelConfiguration.error.verifyWorkload", defaultValue: "Stokd did not persist the requested workload model order")
            )
        }
    }

    func applyProviders(
        _ providers: [StokdModelConfigurationProviderEntry],
        scope: StokdModelConfigurationWriteScope,
        directory: String
    ) async throws {
        let expected = providers.filter { !$0.name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
        var arguments = ["config", "set", "providers", try Self.serializeProviders(expected)]
        if scope == .workspace {
            arguments.append("--workspace")
        }
        _ = try await runChecked(directory: directory, arguments: arguments)
        let persisted = try await runRequiredConfigGet(directory: directory, key: "providers")
        guard try Self.readProviders(fromYAML: persisted) == expected else {
            throw StokdModelConfigurationCLIError(
                message: String(localized: "stokdModelConfiguration.error.verifyProviders", defaultValue: "Stokd did not persist the requested providers")
            )
        }
    }

    private func runOptionalConfigGet(
        directory: String,
        key: String
    ) async throws -> String? {
        let result = await client.run(
            directory: directory,
            arguments: ["config", "get", key],
            timeout: timeout
        )
        if result.exitStatus != 0,
           [result.stderr, result.stdout]
            .compactMap({ $0?.lowercased() })
            .contains(where: { $0.contains("not found") }) {
            return nil
        }
        return try Self.checkedOutput(result)
    }

    private func runRequiredConfigGet(
        directory: String,
        key: String
    ) async throws -> String {
        guard let output = try await runOptionalConfigGet(directory: directory, key: key) else {
            throw StokdModelConfigurationCLIError(message: "Stokd configuration key '\(key)' was not found")
        }
        return output
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
        return try Self.checkedOutput(result)
    }

    private static func checkedOutput(_ result: CommandResult) throws -> String {
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

    private static func readWorkloads(fromJSON string: String) throws -> [StokdModelConfigurationWorkload] {
        guard let entries = try parseJSON(string) as? [[String: Any]] else { return [] }
        return entries.compactMap { entry in
            guard let rawSlug = entry["workload"] as? String else { return nil }
            let slug = StokdModelConfigurationCLIArguments.workloadWriteSlug(rawSlug)
            guard !slug.isEmpty else { return nil }
            return StokdModelConfigurationWorkload(
                slug: slug,
                models: cleanModelList(stringList(entry["models"])),
                inheritsDefault: entry["inherits_default"] as? Bool ?? false
            )
        }
        .sorted { $0.slug < $1.slug }
    }

    private static func readProviders(fromYAML string: String) throws -> [StokdModelConfigurationProviderEntry] {
        var providers: [StokdModelConfigurationProviderEntry] = []
        var name: String?
        var fields: [StokdModelConfigurationProviderEntry.Field] = []

        func finishObject() {
            guard let name else { return }
            providers.append(StokdModelConfigurationProviderEntry(name: name, objectFields: fields))
        }

        for rawLine in string.split(whereSeparator: \.isNewline) {
            let line = String(rawLine)
            if line.hasPrefix("- ") {
                finishObject()
                name = nil
                fields = []
                let value = String(line.dropFirst(2)).trimmingCharacters(in: .whitespaces)
                if let pair = yamlPair(value), pair.key == "name" {
                    name = yamlString(pair.value)
                } else if !value.isEmpty {
                    providers.append(StokdModelConfigurationProviderEntry(name: yamlString(value)))
                }
                continue
            }

            guard name != nil else { continue }
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            guard let pair = yamlPair(trimmed), pair.key != "name" else { continue }
            fields.append(.init(key: pair.key, value: yamlValue(pair.value)))
        }
        finishObject()
        return providers
    }

    private static func yamlPair(_ string: String) -> (key: String, value: String)? {
        guard let colon = string.firstIndex(of: ":") else { return nil }
        let key = String(string[..<colon]).trimmingCharacters(in: .whitespaces)
        guard !key.isEmpty else { return nil }
        let value = String(string[string.index(after: colon)...]).trimmingCharacters(in: .whitespaces)
        return (key, value)
    }

    private static func yamlString(_ rawValue: String) -> String {
        guard rawValue.count >= 2 else { return rawValue }
        if rawValue.first == "'", rawValue.last == "'" {
            return String(rawValue.dropFirst().dropLast()).replacingOccurrences(of: "''", with: "'")
        }
        if rawValue.first == "\"", rawValue.last == "\"",
           let data = "[\(rawValue)]".data(using: .utf8),
           let decoded = try? JSONSerialization.jsonObject(with: data) as? [String] {
            return decoded.first ?? ""
        }
        return rawValue
    }

    private static func yamlValue(_ rawValue: String) -> StokdModelConfigurationProviderEntry.Field.Value {
        let string = yamlString(rawValue)
        switch string.lowercased() {
        case "null", "~": return .null
        case "true": return .bool(true)
        case "false": return .bool(false)
        default: break
        }
        if let int = Int(string) { return .int(int) }
        if let double = Double(string) { return .double(double) }
        return .string(string)
    }

    private static func serializeProviders(_ providers: [StokdModelConfigurationProviderEntry]) throws -> String {
        if providers.allSatisfy({ $0.objectFields == nil }) {
            return providers.map(\.name).joined(separator: ",")
        }
        let payload: [Any] = providers.map { provider in
            guard let fields = provider.objectFields else { return provider.name }
            var object: [String: Any] = ["name": provider.name]
            for field in fields {
                object[field.key] = jsonValue(field.value)
            }
            return object
        }
        let data = try JSONSerialization.data(withJSONObject: payload, options: [.sortedKeys])
        guard let string = String(data: data, encoding: .utf8) else {
            throw StokdModelConfigurationCLIError(message: "Unable to serialize Stokd providers")
        }
        return string
    }

    private static func jsonValue(_ value: StokdModelConfigurationProviderEntry.Field.Value) -> Any {
        switch value {
        case let .string(value): return value
        case let .int(value): return value
        case let .double(value): return value
        case let .bool(value): return value
        case .null: return NSNull()
        }
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
