import CmuxFoundation
import Foundation
import Testing

#if canImport(cmux_DEV)
@testable import cmux_DEV
#elseif canImport(cmux)
@testable import cmux
#endif

@Suite("Stokd CLI runner")
struct StokdCLIRunnerTests {
    @Test func resolverUsesOverrideThenUserInstallThenPath() throws {
        let override = "/fixtures/override/stokd"
        let userInstall = "/fixtures/home/.stokd/bin/stokd"
        let pathInstall = "/fixtures/path/stokd"
        let executablePaths = Set([override, userInstall, pathInstall])

        let overridden = StokdExecutableResolver(
            environment: ["STOKD_CLI_PATH": override, "PATH": "/fixtures/path"],
            homeDirectory: "/fixtures/home",
            isExecutableFile: { executablePaths.contains($0) }
        )
        #expect(
            overridden.resolve()
                == .found(.init(path: override, source: .environmentOverride))
        )

        let userInstalled = StokdExecutableResolver(
            environment: ["PATH": "/fixtures/path"],
            homeDirectory: "/fixtures/home",
            isExecutableFile: { executablePaths.contains($0) }
        )
        #expect(
            userInstalled.resolve()
                == .found(.init(path: userInstall, source: .userInstall))
        )

        let pathOnly = StokdExecutableResolver(
            environment: ["PATH": "/fixtures/path"],
            homeDirectory: "/missing-home",
            isExecutableFile: { $0 == pathInstall }
        )
        #expect(
            pathOnly.resolve()
                == .found(.init(path: pathInstall, source: .path))
        )
    }

    @Test func invalidExplicitOverrideDoesNotSilentlyFallThrough() {
        let resolver = StokdExecutableResolver(
            environment: [
                "STOKD_CLI_PATH": "/invalid/stokd",
                "PATH": "/valid",
            ],
            homeDirectory: "/missing-home",
            isExecutableFile: { $0 == "/valid/stokd" }
        )

        #expect(resolver.resolve() == .invalidOverride("/invalid/stokd"))
    }

    @Test func executablePredicateCanRejectDirectoryShadows() {
        let resolver = StokdExecutableResolver(
            environment: ["PATH": "/directory-shadow:/real"],
            homeDirectory: "/missing-home",
            isExecutableFile: { $0 == "/real/stokd" }
        )

        #expect(
            resolver.resolve()
                == .found(.init(path: "/real/stokd", source: .path))
        )
    }

    @Test func runnerForwardsStructuredInvocation() async throws {
        let expected = CommandResult(
            stdout: #"{"ok":true}"#,
            stderr: "warning",
            exitStatus: 0,
            timedOut: false,
            executionError: nil
        )
        let commands = RecordingStokdCommandRunner(result: expected)
        let runner = StokdCLIRunner(
            commands: commands,
            resolver: StokdExecutableResolver(
                environment: ["STOKD_CLI_PATH": "/fixtures/stokd"],
                homeDirectory: "/fixtures/home",
                isExecutableFile: { $0 == "/fixtures/stokd" }
            )
        )

        let result = await runner.run(
            directory: "/workspace",
            arguments: ["task", "list", "--json"],
            timeout: 4
        )

        #expect(result == expected)
        let invocation = try #require(await commands.lastInvocation)
        #expect(invocation.directory == "/workspace")
        #expect(invocation.executable == "/fixtures/stokd")
        #expect(invocation.arguments == ["task", "list", "--json"])
        #expect(invocation.timeout == 4)
    }

    @Test func missingExecutableReturnsStatus127WithoutInvokingProcess() async {
        let commands = RecordingStokdCommandRunner(result: .init(
            stdout: nil,
            stderr: nil,
            exitStatus: 0,
            timedOut: false,
            executionError: nil
        ))
        let runner = StokdCLIRunner(
            commands: commands,
            resolver: StokdExecutableResolver(
                environment: [:],
                homeDirectory: "/missing-home",
                isExecutableFile: { _ in false }
            )
        )

        let result = await runner.run(directory: "/workspace", arguments: ["--version"])

        #expect(result.exitStatus == 127)
        #expect(result.executionError?.isEmpty == false)
        #expect(await commands.invocationCount == 0)
    }
}

private actor RecordingStokdCommandRunner: CommandRunning {
    struct Invocation: Equatable, Sendable {
        let directory: String
        let executable: String
        let arguments: [String]
        let timeout: TimeInterval?
    }

    private let result: CommandResult
    private(set) var invocations: [Invocation] = []

    init(result: CommandResult) {
        self.result = result
    }

    var lastInvocation: Invocation? { invocations.last }
    var invocationCount: Int { invocations.count }

    func run(
        directory: String,
        executable: String,
        arguments: [String],
        timeout: TimeInterval?
    ) async -> CommandResult {
        invocations.append(.init(
            directory: directory,
            executable: executable,
            arguments: arguments,
            timeout: timeout
        ))
        return result
    }
}
