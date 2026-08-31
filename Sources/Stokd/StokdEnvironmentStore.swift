import CmuxSettings
import Foundation

/// Caches the active stokd environment's base URL for UI that needs to build
/// stokd links.
///
/// Resolution order:
/// 1. `gdock.stokdWebBaseURL` — an explicit override always wins.
/// 2. `stokd env`, parsed by ``StokdEnvironmentBaseURL``.
/// 3. Nothing. Callers render no link rather than a link to the wrong
///    environment.
///
/// The CLI call is async and its result is cached, because the alternative —
/// resolving during a sidebar render — would put a subprocess in the list path.
/// A launcher that fires before the first resolve completes falls back to the
/// override, which is why the override exists as more than a debug knob.
@MainActor
final class StokdEnvironmentStore {
    static let shared = StokdEnvironmentStore()

    private let runner: StokdCLIRunner
    private var cachedBaseURL: URL?
    private var isRefreshing = false

    init(runner: StokdCLIRunner = StokdCLIRunner()) {
        self.runner = runner
    }

    /// The best currently-known base URL, or `nil` when the environment has not
    /// resolved and no override is configured.
    var baseURL: URL? {
        if let override = Self.configuredOverride() { return override }
        return cachedBaseURL
    }

    /// Kicks off a refresh if one is not already running.
    ///
    /// Safe to call often; the guard keeps repeated sidebar builds from
    /// spawning a subprocess each time.
    func refreshIfNeeded(directory: String) {
        guard !directory.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return }
        guard Self.configuredOverride() == nil, cachedBaseURL == nil, !isRefreshing else { return }
        isRefreshing = true
        Task { [weak self, runner] in
            let result = await runner.run(directory: directory, arguments: ["env"])
            let parsed = result.stdout.flatMap(StokdEnvironmentBaseURL.parse(cliOutput:))
            await MainActor.run {
                guard let self else { return }
                self.isRefreshing = false
                if let parsed { self.cachedBaseURL = parsed }
            }
        }
    }

    /// Drops the cached value so the next refresh re-asks the CLI. Call after
    /// the user switches environments.
    func invalidate() {
        cachedBaseURL = nil
    }

    private static func configuredOverride() -> URL? {
        let raw = UserDefaults.standard
            .string(forKey: SettingCatalog().gdock.stokdWebBaseURL.userDefaultsKey)?
            .trimmingCharacters(in: .whitespacesAndNewlines)
        guard let raw, !raw.isEmpty else { return nil }
        return StokdEnvironmentBaseURL.parse(cliOutput: raw)
    }
}
