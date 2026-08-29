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

    @Test func loaderFlattensCatalogAndReadsCanonicalAndLegacyConfig() async throws {
        let client = ScriptedStokdModelConfigurationCLI(results: [
            .success(Self.catalogJSON),
            .success(Self.configJSON),
        ])
        let loader = StokdModelConfigurationCLILoader(client: client)

        let snapshot = try await loader.load(directory: "/repo")

        #expect(snapshot.catalog.map(\.id) == ["claude-sonnet-4", "grok-4"])
        #expect(snapshot.catalog[0].providerConfigID == "claudeCode")
        #expect(snapshot.catalog[0].pricing?.inputPer1M == 3)
        #expect(snapshot.defaults == ["default", "claude-sonnet-4"])
        #expect(snapshot.workloads.map(\.slug) == ["analysis", "title"])
        #expect(snapshot.workloads.first { $0.slug == "title" }?.models == ["claude-haiku"])

        let invocations = await client.invocations
        #expect(invocations.map(\.arguments) == [
            ["model", "list", "--json"],
            ["config", "show", "--json"],
        ])
        #expect(invocations.allSatisfy { $0.directory == "/repo" })
    }

    @Test func applyWritesThroughCLIThenVerifiesConfig() async throws {
        let client = ScriptedStokdModelConfigurationCLI(results: [
            .success(""),
            .success(#"{"models":{"defaults":["a","b"]}}"#),
            .success(""),
            .success(#"{"models":{"workloads":{"title":["m1","m2"]}}}"#),
        ])
        let loader = StokdModelConfigurationCLILoader(client: client)

        try await loader.applyDefaults(["a", "b"], scope: .workspace, directory: "/repo")
        try await loader.applyWorkload(slug: "titleGen", models: ["m1", "m2"], scope: .global, directory: "/repo")

        #expect(await client.invocations.map(\.arguments) == [
            ["config", "set", "models.defaults", "a,b", "--workspace"],
            ["config", "show", "--json"],
            ["config", "set", "models.workloads.title", "m1,m2"],
            ["config", "show", "--json"],
        ])
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

    private static let configJSON = #"""
    {
      "models": {
        "defaults": ["default", "claude-sonnet-4"],
        "workloads": {
          "analysis": ["grok-4", "claude-sonnet-4"],
          "titleGen": { "models": ["claude-haiku"] }
        }
      },
      "llm": {
        "fallbackModels": ["legacy-default"],
        "workloads": {
          "summary": ["legacy-summary"]
        }
      }
    }
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
}
