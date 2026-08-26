import CmuxGit
import Foundation

/// Resolves a workspace directory to a stokd repo slug and pushes it into a
/// ``StokdWorkPanelViewModel``.
///
/// Both Work hosts share this one implementation — the dock-rail
/// ``RightSidebarToolPanel`` and the legacy right-sidebar host in `ContentView` —
/// so repo scoping never forks per entrypoint (see `skills/cmux-shared-behavior`).
@MainActor
final class StokdWorkRepositoryBinder {
    private let discovering: any GitRepositoryDiscovering
    private var resolutionTask: Task<Void, Never>?
    private var generation: UInt64 = 0
    private var boundDirectory: String?

    init(discovering: any GitRepositoryDiscovering = GitMetadataService()) {
        self.discovering = discovering
    }

    /// Scopes `model` to the repository containing `rawDirectory`.
    ///
    /// An empty directory (no local cwd, or a remote workspace) clears the model
    /// to "no repository". Returns `false` when the trimmed directory is
    /// unchanged since the last bind, in which case no work is performed and any
    /// in-flight resolution is left running.
    @discardableResult
    func bind(directory rawDirectory: String, to model: StokdWorkPanelViewModel) -> Bool {
        let directory = rawDirectory.trimmingCharacters(in: .whitespacesAndNewlines)
        guard directory != boundDirectory else { return false }
        boundDirectory = directory
        generation &+= 1
        let generation = self.generation
        resolutionTask?.cancel()

        guard !directory.isEmpty else {
            model.refresh(repoSlug: nil)
            return true
        }

        let discovering = self.discovering
        resolutionTask = Task { [weak self, weak model] in
            let repoSlug = await discovering.repositorySlugs(forDirectory: directory).first
            // A newer bind supersedes this one; never let a slow resolution
            // overwrite the current repository.
            guard let self, let model, self.generation == generation else { return }
            model.refresh(repoSlug: repoSlug)
        }
        return true
    }

    /// Drops any in-flight resolution. The next ``bind(directory:to:)`` for the
    /// same directory is treated as a fresh bind.
    func cancel() {
        resolutionTask?.cancel()
        resolutionTask = nil
        boundDirectory = nil
    }
}
