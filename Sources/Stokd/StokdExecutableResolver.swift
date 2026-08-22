import Foundation

enum StokdExecutableSource: Equatable, Sendable {
    case environmentOverride
    case userInstall
    case path
}

struct StokdExecutable: Equatable, Sendable {
    let path: String
    let source: StokdExecutableSource
}

enum StokdExecutableResolution: Equatable, Sendable {
    case found(StokdExecutable)
    case invalidOverride(String)
    case notFound
}

struct StokdExecutableResolver: Sendable {
    private let environment: [String: String]
    private let homeDirectory: String
    private let isExecutableFile: @Sendable (String) -> Bool

    init(
        environment: [String: String] = ProcessInfo.processInfo.environment,
        homeDirectory: String = NSHomeDirectory(),
        isExecutableFile: (@Sendable (String) -> Bool)? = nil
    ) {
        self.environment = environment
        self.homeDirectory = homeDirectory
        self.isExecutableFile = isExecutableFile ?? { path in
            var isDirectory: ObjCBool = false
            let fileManager = FileManager.default
            return fileManager.fileExists(atPath: path, isDirectory: &isDirectory)
                && !isDirectory.boolValue
                && fileManager.isExecutableFile(atPath: path)
        }
    }

    func resolve() -> StokdExecutableResolution {
        if let override = normalized(environment["STOKD_CLI_PATH"]), !override.isEmpty {
            guard isExecutableFile(override) else {
                return .invalidOverride(override)
            }
            return .found(StokdExecutable(path: override, source: .environmentOverride))
        }

        let userInstall = URL(fileURLWithPath: homeDirectory, isDirectory: true)
            .appendingPathComponent(".stokd/bin/stokd", isDirectory: false)
            .standardizedFileURL.path
        if isExecutableFile(userInstall) {
            return .found(StokdExecutable(path: userInstall, source: .userInstall))
        }

        var seenDirectories = Set<String>()
        for component in (environment["PATH"] ?? "").split(separator: ":") {
            let directory = String(component).trimmingCharacters(in: .whitespacesAndNewlines)
            guard !directory.isEmpty, seenDirectories.insert(directory).inserted else { continue }
            let candidate = URL(fileURLWithPath: directory, isDirectory: true)
                .appendingPathComponent("stokd", isDirectory: false)
                .standardizedFileURL.path
            if isExecutableFile(candidate) {
                return .found(StokdExecutable(path: candidate, source: .path))
            }
        }

        return .notFound
    }

    private func normalized(_ path: String?) -> String? {
        guard let path else { return nil }
        let trimmed = path.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }
        if trimmed == "~" {
            return URL(fileURLWithPath: homeDirectory, isDirectory: true).standardizedFileURL.path
        }
        if trimmed.hasPrefix("~/") {
            return URL(fileURLWithPath: homeDirectory, isDirectory: true)
                .appendingPathComponent(String(trimmed.dropFirst(2)), isDirectory: false)
                .standardizedFileURL.path
        }
        return URL(fileURLWithPath: trimmed, isDirectory: false).standardizedFileURL.path
    }
}
