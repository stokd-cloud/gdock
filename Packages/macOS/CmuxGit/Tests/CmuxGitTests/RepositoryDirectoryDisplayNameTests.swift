import Foundation
import Testing
@testable import CmuxGit

@Suite struct RepositoryDirectoryDisplayNameTests {
    @Test func primaryBranchViaOriginHeadShowsOwnerRepoOnly() throws {
        let fixture = try GitRepositoryFixture()
        try fixture.writeBranch("main")
        try fixture.writeConfig("""
        [remote "origin"]
            url = https://github.com/stokd-cloud/ghostty-dock.git
            fetch = +refs/heads/*:refs/remotes/origin/*
        """)
        try fixture.writeRemoteHead(remote: "origin", branch: "main")

        #expect(
            GitMetadataService.repositoryDirectoryDisplayName(for: fixture.root.path)
                == "stokd-cloud/ghostty-dock"
        )
    }

    @Test func nonPrimaryBranchShowsOwnerRepoAndBranch() throws {
        let fixture = try GitRepositoryFixture()
        try fixture.writeBranch("feature/vault-labels")
        try fixture.writeConfig("""
        [remote "origin"]
            url = git@github.com:stokd-cloud/ghostty-dock.git
            fetch = +refs/heads/*:refs/remotes/origin/*
        """)
        try fixture.writeRemoteHead(remote: "origin", branch: "main")

        #expect(
            GitMetadataService.repositoryDirectoryDisplayName(for: fixture.root.path)
                == "stokd-cloud/ghostty-dock (feature/vault-labels)"
        )
    }

    @Test func mainWithoutRemoteHeadStillPrimaryWhenNamedMain() throws {
        let fixture = try GitRepositoryFixture()
        try fixture.writeBranch("main")
        try fixture.writeConfig("""
        [remote "origin"]
            url = https://github.com/owner/repo.git
        """)

        #expect(
            GitMetadataService.repositoryDirectoryDisplayName(for: fixture.root.path)
                == "owner/repo"
        )
    }

    @Test func masterWithoutRemoteHeadStillPrimaryWhenNamedMaster() throws {
        let fixture = try GitRepositoryFixture()
        try fixture.writeBranch("master")
        try fixture.writeConfig("""
        [remote "origin"]
            url = https://github.com/owner/repo.git
        """)

        #expect(
            GitMetadataService.repositoryDirectoryDisplayName(for: fixture.root.path)
                == "owner/repo"
        )
    }

    @Test func detachedHeadShowsDetachedSuffix() throws {
        let fixture = try GitRepositoryFixture()
        try fixture.writeDetachedHead(commit: String(repeating: "a", count: 40))
        try fixture.writeConfig("""
        [remote "origin"]
            url = https://github.com/owner/repo.git
        """)
        try fixture.writeRemoteHead(remote: "origin", branch: "main")

        #expect(
            GitMetadataService.repositoryDirectoryDisplayName(for: fixture.root.path)
                == "owner/repo (detached)"
        )
    }

    @Test func nestedDirectoryUsesSameRepoLabelAsRoot() throws {
        let fixture = try GitRepositoryFixture()
        try fixture.writeBranch("feature/x")
        try fixture.writeConfig("""
        [remote "origin"]
            url = https://github.com/owner/repo.git
        """)
        try fixture.writeRemoteHead(remote: "origin", branch: "main")
        let nested = fixture.root.appendingPathComponent("Sources/Vault")
        try FileManager.default.createDirectory(at: nested, withIntermediateDirectories: true)

        #expect(
            GitMetadataService.repositoryDirectoryDisplayName(for: nested.path)
                == "owner/repo (feature/x)"
        )
    }

    @Test func nonRepositoryReturnsNil() {
        #expect(
            GitMetadataService.repositoryDirectoryDisplayName(
                for: FileManager.default.temporaryDirectory.path
            ) == nil
        )
    }

    @Test func repositoryWithoutGitHubRemoteReturnsNil() throws {
        let fixture = try GitRepositoryFixture()
        try fixture.writeBranch("main")
        try fixture.writeConfig("""
        [remote "origin"]
            url = git@gitlab.com:owner/repo.git
        """)

        #expect(GitMetadataService.repositoryDirectoryDisplayName(for: fixture.root.path) == nil)
    }

    @Test func prefersUpstreamSlugThenOrigin() throws {
        let fixture = try GitRepositoryFixture()
        try fixture.writeBranch("main")
        try fixture.writeConfig("""
        [remote "origin"]
            url = https://github.com/me/fork.git
        [remote "upstream"]
            url = https://github.com/owner/canonical.git
        """)
        try fixture.writeRemoteHead(remote: "origin", branch: "main")

        #expect(
            GitMetadataService.repositoryDirectoryDisplayName(for: fixture.root.path)
                == "owner/canonical"
        )
    }

    @Test func primaryFromUpstreamHeadWhenOriginHeadMissing() throws {
        let fixture = try GitRepositoryFixture()
        try fixture.writeBranch("develop")
        try fixture.writeConfig("""
        [remote "upstream"]
            url = https://github.com/owner/repo.git
        """)
        try fixture.writeRemoteHead(remote: "upstream", branch: "develop")

        #expect(
            GitMetadataService.repositoryDirectoryDisplayName(for: fixture.root.path)
                == "owner/repo"
        )
    }
}

extension GitRepositoryFixture {
    /// Writes `refs/remotes/<remote>/HEAD` as a symbolic ref to
    /// `refs/remotes/<remote>/<branch>` (the shape `git remote set-head` leaves).
    func writeRemoteHead(remote: String, branch: String) throws {
        let headURL = gitDirectory
            .appendingPathComponent("refs/remotes/\(remote)/HEAD")
        try FileManager.default.createDirectory(
            at: headURL.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        try "ref: refs/remotes/\(remote)/\(branch)\n".write(
            to: headURL,
            atomically: true,
            encoding: .utf8
        )
    }
}
