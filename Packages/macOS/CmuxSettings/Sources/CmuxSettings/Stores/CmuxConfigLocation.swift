import Foundation

/// Conventional on-disk locations for the Ghostty Dock JSON config.
///
/// A small value-typed bundle of URLs. Construct one with an explicit `home`
/// directory and inject it into the parts of the app that need to know where
/// the config file lives. No shared singletons; tests use a custom `home` URL
/// pointing into a temp directory.
///
/// ```swift
/// let locations = CmuxConfigLocation()
/// let store = JSONConfigStore(fileURL: locations.userConfigFile)
/// ```
public struct CmuxConfigLocation: Sendable, Hashable {
    /// Primary config directory: `<home>/.config/ghostty-dock`.
    public let directory: URL

    /// Legacy config directory from upstream cmux: `<home>/.config/cmux`.
    /// Left intact forever; migration copies from here into ``directory``.
    public let legacyDirectory: URL

    /// The primary config file: `<directory>/cmux.json` (filename kept for merge stability).
    public let userConfigFile: URL

    /// The legacy fallback: `<directory>/settings.json`.
    public let legacyFallbackFile: URL

    /// Dock layout file: `<directory>/dock.json`.
    public let dockFile: URL

    /// Custom sidebars directory: `<directory>/sidebars`.
    public let sidebarsDirectory: URL

    /// Legacy pre-`cmux.json` display default file under the legacy directory.
    public let legacyDevWindowDisplayFile: URL

    /// Creates a location bundle anchored at the given home directory.
    ///
    /// - Parameter home: The home directory to anchor paths to. Defaults to
    ///   `FileManager.default.homeDirectoryForCurrentUser`. Pass a temp URL
    ///   in tests.
    public init(home: URL = FileManager.default.homeDirectoryForCurrentUser) {
        let configRoot = home.appending(path: ".config")
        self.directory = configRoot.appending(path: "ghostty-dock")
        self.legacyDirectory = configRoot.appending(path: "cmux")
        self.userConfigFile = directory.appending(path: "cmux.json")
        self.legacyFallbackFile = directory.appending(path: "settings.json")
        self.dockFile = directory.appending(path: "dock.json")
        self.sidebarsDirectory = directory.appending(path: "sidebars")
        self.legacyDevWindowDisplayFile = legacyDirectory.appending(path: "dev-window-display")
    }
}
