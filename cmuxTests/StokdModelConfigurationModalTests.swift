import CmuxFoundation
import Foundation
import Testing

#if canImport(cmux_DEV)
@testable import cmux_DEV
#elseif canImport(cmux)
@testable import cmux
#endif

@MainActor
@Suite("Stokd model configuration modal", .serialized)
struct StokdModelConfigurationModalTests {
    @Test func launchBarActionsRouteToModalTabsWithoutSidebarModes() {
        let actions = StokdModelConfigurationLaunchBar.actions

        #expect(actions.map(\.id) == [
            "gdock.modelConfiguration",
            "gdock.workloadConfiguration",
        ])
        #expect(actions.map(\.initialTab) == [.defaults, .workloads])
        #expect(actions.map(\.localizationKey) == [
            "stokdModelConfiguration.action.model",
            "stokdModelConfiguration.action.workload",
        ])
        #expect(actions.map(\.symbolName) == ["server.rack", "gearshape.2"])

        let forbiddenSidebarRawValues: Set<String> = [
            "stokdModelConfiguration",
            "stokdWorkloadConfiguration",
            "stokdModelConfig",
            "stokdWorkloadConfig",
        ]
        #expect(RightSidebarMode.allCases.allSatisfy { !forbiddenSidebarRawValues.contains($0.rawValue) })
        #expect(StokdRailPanelKind.allCases.allSatisfy { !forbiddenSidebarRawValues.contains($0.rawValue) })
    }

    @Test func cliArgumentBuildersMatchStokdCodeWriteSemantics() {
        #expect(
            StokdModelConfigurationCLIArguments.writeDefaults(
                ["claude-sonnet-4", "grok-4"],
                scope: .workspace
            ) == [
                "config", "set", "models.defaults", "claude-sonnet-4,grok-4", "--workspace",
            ]
        )

        #expect(
            StokdModelConfigurationCLIArguments.writeWorkload(
                slug: "analysis",
                models: ["m1", "m2"],
                scope: .global
            ) == [
                "config", "set", "models.workloads.analysis", "m1,m2",
            ]
        )

        #expect(
            StokdModelConfigurationCLIArguments.writeWorkload(
                slug: "titleGen",
                models: ["haiku"],
                scope: .workspace
            ) == [
                "config", "set", "models.workloads.title", "haiku", "--workspace",
            ]
        )
    }

    @Test func loaderReadsThroughSupportedCLIVerbsOnly() async throws {
        let client = ScriptedStokdModelConfigurationCLI(results: [
            .success(Self.catalogJSON),
            .success("default,claude-sonnet-4"),
            .success(Self.providersYAML),
            .success(Self.workloadJSON),
        ])
        let loader = StokdModelConfigurationCLILoader(client: client)

        let snapshot = try await loader.load(directory: "/repo")

        #expect(snapshot.catalog.map(\.id) == ["claude-sonnet-4", "grok-4"])
        #expect(snapshot.catalog[0].providerConfigID == "claudeCode")
        #expect(snapshot.catalog[0].pricing?.inputPer1M == 3)
        #expect(snapshot.defaults == ["default", "claude-sonnet-4"])
        #expect(snapshot.workloads.map(\.slug) == ["analysis", "prd", "title"])
        #expect(snapshot.workloads.first { $0.slug == "title" }?.models == ["claude-haiku"])
        #expect(snapshot.workloads.first { $0.slug == "title" }?.inheritsDefault == false)
        #expect(snapshot.workloads.first { $0.slug == "prd" }?.inheritsDefault == true)
        #expect(snapshot.workloads.first { $0.slug == "prd" }?.models == [])
        #expect(snapshot.providers.map(\.name) == ["claude", "codex", "lmStudio"])
        #expect(snapshot.providers[0].objectFields == nil)
        #expect(
            snapshot.providers[2].objectFields == [
                StokdModelConfigurationProviderEntry.Field(key: "endpoint", value: .string("http://localhost")),
                StokdModelConfigurationProviderEntry.Field(key: "port", value: .int(1234)),
                StokdModelConfigurationProviderEntry.Field(key: "apiKey", value: .string("")),
            ]
        )

        let invocations = await client.invocations
        #expect(invocations.map(\.arguments) == [
            ["model", "list", "--json"],
            ["config", "get", "models.defaults"],
            ["config", "get", "providers"],
            ["model", "workload", "--json"],
        ])
        #expect(invocations.allSatisfy { $0.directory == "/repo" })
    }

    @Test func loaderTreatsMissingKeysAsEmptyInsteadOfFailing() async throws {
        let client = ScriptedStokdModelConfigurationCLI(results: [
            .success(Self.catalogJSON),
            .failure("Key 'models.defaults' not found in effective config"),
            .failure("Key 'providers' not found in effective config"),
            .success("[]"),
        ])
        let loader = StokdModelConfigurationCLILoader(client: client)

        let snapshot = try await loader.load(directory: "/repo")

        #expect(snapshot.defaults == [])
        #expect(snapshot.providers.isEmpty)
        #expect(snapshot.workloads.isEmpty)
    }

    @Test func applyWritesThroughCLIThenVerifiesWithSupportedVerbs() async throws {
        let client = ScriptedStokdModelConfigurationCLI(results: [
            .success(""),
            .success("a,b"),
            .success(""),
            .success(#"[{"workload":"title","models":["m1","m2"],"inherits_default":false}]"#),
        ])
        let loader = StokdModelConfigurationCLILoader(client: client)

        try await loader.applyDefaults(["a", "b"], scope: .workspace, directory: "/repo")
        try await loader.applyWorkload(slug: "titleGen", models: ["m1", "m2"], scope: .global, directory: "/repo")

        #expect(await client.invocations.map(\.arguments) == [
            ["config", "set", "models.defaults", "a,b", "--workspace"],
            ["config", "get", "models.defaults"],
            ["config", "set", "models.workloads.title", "m1,m2"],
            ["model", "workload", "--json"],
        ])
    }

    @Test func applyProvidersUsesCommaListForScalarsAndJSONForObjectEntries() async throws {
        let scalarOnly = ScriptedStokdModelConfigurationCLI(results: [
            .success(""),
            .success("- claude\n- codex\n"),
        ])
        let loader = StokdModelConfigurationCLILoader(client: scalarOnly)
        try await loader.applyProviders(
            [
                StokdModelConfigurationProviderEntry(name: "claude"),
                StokdModelConfigurationProviderEntry(name: "codex"),
            ],
            scope: .global,
            directory: "/repo"
        )
        #expect(await scalarOnly.invocations.map(\.arguments) == [
            ["config", "set", "providers", "claude,codex"],
            ["config", "get", "providers"],
        ])

        let withObject = ScriptedStokdModelConfigurationCLI(results: [
            .success(""),
            .success("- claude\n- name: lmStudio\n  endpoint: http://localhost\n  port: 1234\n  apiKey: ''\n"),
        ])
        let objectLoader = StokdModelConfigurationCLILoader(client: withObject)
        try await objectLoader.applyProviders(
            [
                StokdModelConfigurationProviderEntry(name: "claude"),
                StokdModelConfigurationProviderEntry(
                    name: "lmStudio",
                    objectFields: [
                        .init(key: "endpoint", value: .string("http://localhost")),
                        .init(key: "port", value: .int(1234)),
                        .init(key: "apiKey", value: .string("")),
                    ]
                ),
            ],
            scope: .workspace,
            directory: "/repo"
        )
        let objectInvocations = await withObject.invocations
        #expect(objectInvocations.count == 2)
        #expect(Array(objectInvocations[0].arguments.prefix(3)) == ["config", "set", "providers"])
        #expect(objectInvocations[0].arguments.last == "--workspace")
        let payload = objectInvocations[0].arguments[3]
        let decoded = try JSONSerialization.jsonObject(with: Data(payload.utf8)) as? [Any]
        #expect(decoded?.count == 2)
        #expect(decoded?.first as? String == "claude")
        let object = decoded?.last as? [String: Any]
        #expect(object?["name"] as? String == "lmStudio")
        #expect(object?["endpoint"] as? String == "http://localhost")
        #expect(object?["port"] as? Int == 1234)
        #expect(object?["apiKey"] as? String == "")
        #expect(objectInvocations[1].arguments == ["config", "get", "providers"])
    }

    private static let catalogJSON = #"""
    [
      {
        "provider": "claude",
        "source": "cli",
        "models": [
          {
            "id": "claude-sonnet-4",
            "display_name": "Claude Sonnet 4",
            "capability": 92,
            "capabilities": ["text", "vision"],
            "pricing": { "inputPer1M": 3, "outputPer1M": 15 },
            "benchmarks": { "swe": 71 }
          }
        ]
      },
      {
        "id": "grok-4",
        "displayName": "Grok 4",
        "provider": "grok",
        "source": "cli",
        "capability": 88
      }
    ]
    """#

    private static let providersYAML = """
    - claude
    - codex
    - name: lmStudio
      endpoint: http://localhost
      port: 1234
      apiKey: ''
    """

    private static let workloadJSON = #"""
    [
      { "workload": "analysis", "models": ["grok-4", "claude-sonnet-4"], "inherits_default": false },
      { "workload": "prd", "inherits_default": true },
      { "workload": "titleGen", "models": ["claude-haiku"], "inherits_default": false }
    ]
    """#
}

private actor ScriptedStokdModelConfigurationCLI: StokdModelConfigurationCLIClient {
    struct Invocation: Equatable, Sendable {
        let directory: String
        let arguments: [String]
        let timeout: TimeInterval?
    }

    private var results: [CommandResult]
    private(set) var invocations: [Invocation] = []

    init(results: [CommandResult]) {
        self.results = results
    }

    func run(
        directory: String,
        arguments: [String],
        timeout: TimeInterval?
    ) async -> CommandResult {
        invocations.append(Invocation(directory: directory, arguments: arguments, timeout: timeout))
        guard !results.isEmpty else {
            return CommandResult(
                stdout: nil,
                stderr: "missing scripted result",
                exitStatus: 1,
                timedOut: false,
                executionError: nil
            )
        }
        return results.removeFirst()
    }
}

private extension CommandResult {
    static func success(_ stdout: String) -> CommandResult {
        CommandResult(
            stdout: stdout,
            stderr: "",
            exitStatus: 0,
            timedOut: false,
            executionError: nil
        )
    }

    static func failure(_ stderr: String) -> CommandResult {
        CommandResult(
            stdout: nil,
            stderr: stderr,
            exitStatus: 1,
            timedOut: false,
            executionError: nil
        )
    }
}
