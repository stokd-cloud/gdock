import Foundation

extension GitMetadataService {
    /// A Vault-friendly label for a directory inside a git repository that has
    /// a GitHub remote: `owner/repo` on the primary branch, or
    /// `owner/repo (branch)` when checked out elsewhere.
    ///
    /// Returns `nil` when `directory` is not inside a git repository or the
    /// repository has no GitHub remote (callers keep their non-git path
    /// labeling). Detached HEAD is labeled `owner/repo (detached)`.
    ///
    /// Primary branch resolution prefers the symbolic target of
    /// `refs/remotes/origin/HEAD`, then `refs/remotes/upstream/HEAD`. When
    /// neither exists, `main` and `master` are treated as primary (same set
    /// used by ``PullRequestProbeService/shouldSkipLookup(branch:)``).
    ///
    /// - Parameter directory: An absolute path (file or directory) to label.
    /// - Returns: The repository display name, or `nil` when unavailable.
    public nonisolated static func repositoryDirectoryDisplayName(for directory: String) -> String? {
        guard let repository = resolveGitRepository(containing: directory),
              let output = gitRemoteVOutput(repository: repository) else {
            return nil
        }
        let slugs = githubRepositorySlugs(fromGitRemoteVOutput: output)
        guard let slug = slugs.first else {
            return nil
        }

        switch gitCheckedOutBranch(repository: repository) {
        case .branch(let branch):
            if isPrimaryBranch(branch, repository: repository) {
                return slug
            }
            return "\(slug) (\(branch))"
        case .detached:
            return "\(slug) (detached)"
        case .notARepository, .unreadable:
            // Repository resolved but HEAD is unusable; still surface the slug
            // so Vault folders do not fall back to a branch-named basename.
            return slug
        }
    }

    /// Whether `branch` is the repository's primary (default) branch.
    nonisolated static func isPrimaryBranch(_ branch: String, repository: ResolvedGitRepository) -> Bool {
        guard let normalized = normalizedBranchName(branch) else {
            return false
        }
        if let primary = primaryBranchName(repository: repository) {
            return normalized == primary
        }
        switch normalized {
        case "main", "master":
            return true
        default:
            return false
        }
    }

    /// The configured primary branch name from remote HEAD refs, or `nil` when
    /// neither origin nor upstream advertises a symbolic default.
    nonisolated static func primaryBranchName(repository: ResolvedGitRepository) -> String? {
        for remote in ["origin", "upstream"] {
            if let branch = primaryBranchName(fromRemoteHead: remote, repository: repository) {
                return branch
            }
        }
        return nil
    }

    /// Reads `refs/remotes/<remote>/HEAD` and returns the branch name it points
    /// at when the value is a symbolic ref of the form
    /// `ref: refs/remotes/<remote>/<branch>`.
    nonisolated static func primaryBranchName(
        fromRemoteHead remote: String,
        repository: ResolvedGitRepository
    ) -> String? {
        let headRef = "refs/remotes/\(remote)/HEAD"
        let headURLCandidates = [
            URL(fileURLWithPath: repository.gitDirectory).appendingPathComponent(headRef),
            URL(fileURLWithPath: repository.commonDirectory).appendingPathComponent(headRef),
        ]
        var seenPaths: Set<String> = []
        for headURL in headURLCandidates {
            let path = headURL.standardizedFileURL.path
            guard seenPaths.insert(path).inserted,
                  let contents = try? String(contentsOf: headURL, encoding: .utf8) else {
                continue
            }
            let trimmed = contents.trimmingCharacters(in: .whitespacesAndNewlines)
            let prefix = "ref: refs/remotes/\(remote)/"
            guard trimmed.hasPrefix(prefix) else {
                continue
            }
            return normalizedBranchName(String(trimmed.dropFirst(prefix.count)))
        }
        return nil
    }
}
