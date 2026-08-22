import CmuxFoundation
import Foundation

struct StokdCLIRunner: Sendable {
    private let commands: any CommandRunning
    private let resolver: StokdExecutableResolver

    init(
        commands: any CommandRunning = CommandRunner(),
        resolver: StokdExecutableResolver = StokdExecutableResolver()
    ) {
        self.commands = commands
        self.resolver = resolver
    }

    func run(
        directory: String,
        arguments: [String],
        timeout: TimeInterval? = 10
    ) async -> CommandResult {
        switch resolver.resolve() {
        case .found(let executable):
            return await commands.run(
                directory: directory,
                executable: executable.path,
                arguments: arguments,
                timeout: timeout
            )
        case .invalidOverride(let path):
            return unavailableResult("STOKD_CLI_PATH is not an executable file: \(path)")
        case .notFound:
            return unavailableResult("stokd executable not found")
        }
    }

    private func unavailableResult(_ message: String) -> CommandResult {
        CommandResult(
            stdout: nil,
            stderr: message,
            exitStatus: 127,
            timedOut: false,
            executionError: message
        )
    }
}
