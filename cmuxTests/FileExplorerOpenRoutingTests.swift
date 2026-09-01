import Foundation
import Testing

#if canImport(cmux_DEV)
    @testable import cmux_DEV
#elseif canImport(cmux)
    @testable import cmux
#endif

/// Opening a file from the Files pane or the Find pane's search results routes to
/// the internal Monaco editor; the surfaces that exist for a reason (rendered
/// markdown, Xcode projects) and the cases Monaco cannot serve honestly (remote
/// workspaces, a missing bundled CLI) keep the native preview path.
@Suite("FileExplorerOpenRouting")
struct FileExplorerOpenRoutingTests {
    private func target(
        _ filePath: String,
        isRemoteWorkspace: Bool = false,
        isEditorCommandAvailable: Bool = true
    ) -> FileExplorerOpenTarget {
        FileExplorerOpenRouting.target(
            filePath: filePath,
            isRemoteWorkspace: isRemoteWorkspace,
            isEditorCommandAvailable: isEditorCommandAvailable
        )
    }

    @Test("local source files open in the Monaco editor")
    func localSourceFilesOpenInMonacoEditor() {
        #expect(target("/repo/Sources/AppDelegate.swift") == .monacoEditor)
        #expect(target("/repo/notes.txt") == .monacoEditor)
        #expect(target("/repo/.gitignore") == .monacoEditor)
        #expect(target("/repo/Makefile") == .monacoEditor)
    }

    @Test("markdown keeps the rendered markdown surface")
    func markdownKeepsMarkdownSurface() {
        #expect(target("/repo/README.md") == .markdown)
        #expect(target("/repo/docs/GUIDE.MARKDOWN") == .markdown)
        #expect(target("/repo/page.mdx") == .markdown)
    }

    @Test("Xcode projects keep the project surface")
    func xcodeProjectsKeepProjectSurface() {
        #expect(target("/repo/cmux.xcodeproj") == .project)
        #expect(target("/repo/cmux.xcworkspace") == .project)
    }

    @Test("remote workspaces keep the native preview")
    func remoteWorkspacesKeepFilePreview() {
        // A remote open materializes a temporary local copy; Monaco's save
        // capability would write that copy, not the remote file.
        #expect(target("/remote/main.swift", isRemoteWorkspace: true) == .filePreview)
    }

    @Test("a missing bundled CLI keeps the native preview")
    func missingEditorCommandKeepsFilePreview() {
        #expect(target("/repo/main.swift", isEditorCommandAvailable: false) == .filePreview)
    }

    @Test("markdown and projects are routed before the editor availability check")
    func markdownAndProjectsIgnoreEditorAvailability() {
        #expect(target("/repo/README.md", isEditorCommandAvailable: false) == .markdown)
        #expect(target("/repo/cmux.xcodeproj", isRemoteWorkspace: true) == .project)
    }
}

/// The app spawns its own bundled CLI to reach the Monaco editor, and this fork
/// ships that binary as `bin/gdock`. A spawn that probes only the upstream
/// `bin/cmux` name resolves to nothing, so the feature silently does nothing.
@Suite("Bundled CLI resolution")
struct BundledCLIExecutableResolutionTests {
    private func resolve(executablePaths: Set<String>) -> URL? {
        CmuxCLIPathInstaller.bundledCLIExecutableURL(
            bundle: .main,
            isExecutable: { executablePaths.contains(($0 as NSString).lastPathComponent) }
        )
    }

    @Test("the fork's bin/gdock is preferred")
    func prefersForkBundledCLIName() {
        let url = resolve(executablePaths: ["gdock", "cmux"])
        #expect(url?.lastPathComponent == "gdock")
    }

    @Test("bin/cmux still resolves for bundles that ship the upstream name")
    func fallsBackToUpstreamBundledCLIName() {
        let url = resolve(executablePaths: ["cmux"])
        #expect(url?.lastPathComponent == "cmux")
    }

    @Test("no executable candidate resolves to nil")
    func missingBundledCLIResolvesToNil() {
        #expect(resolve(executablePaths: []) == nil)
    }

    @Test("the fork name leads the candidate list")
    func candidateOrderPutsForkNameFirst() {
        #expect(CmuxCLIPathInstaller.bundledCLIResourceRelativePathCandidates == [
            "bin/gdock",
            "bin/cmux",
        ])
    }
}

@Suite("FileExplorerOpenRouting editor command")
struct FileExplorerOpenRoutingEditorCommandTests {
    private let workspaceId = UUID(uuidString: "11111111-2222-3333-4444-555555555555")!
    private let surfaceId = UUID(uuidString: "66666666-7777-8888-9999-000000000000")!

    @Test("the editor command targets this app's socket, workspace, and surface")
    func editorCommandCarriesSocketWorkspaceAndSurface() {
        let arguments = FileExplorerOpenRouting.editorCommandArguments(
            filePath: "/repo/Sources/AppDelegate.swift",
            socketPath: "/tmp/cmux-debug-tagged.sock",
            workspaceId: workspaceId,
            surfaceId: surfaceId
        )

        #expect(arguments == [
            "--socket", "/tmp/cmux-debug-tagged.sock",
            "edit", "/repo/Sources/AppDelegate.swift",
            "--workspace", workspaceId.uuidString,
            "--surface", surfaceId.uuidString,
            "--focus",
        ])
    }

    @Test("the surface flag is omitted when no surface is focused")
    func editorCommandOmitsMissingSurface() {
        let arguments = FileExplorerOpenRouting.editorCommandArguments(
            filePath: "/repo/notes.txt",
            socketPath: "/tmp/cmux.sock",
            workspaceId: workspaceId,
            surfaceId: nil
        )

        #expect(arguments == [
            "--socket", "/tmp/cmux.sock",
            "edit", "/repo/notes.txt",
            "--workspace", workspaceId.uuidString,
            "--focus",
        ])
        #expect(!arguments.contains("--surface"))
    }
}
