import AppKit
import Bonsplit
import CmuxSettings
import Foundation

/// The single path both file-explorer surfaces use to open a file the user
/// activated: the Files pane (tree double-click / open shortcut) and the Find
/// pane (search-result activation).
///
/// Local text files open in the internal Monaco editor by spawning the bundled
/// CLI's `cmux edit`. That command is the only component that can mint the
/// editor's trusted diff-viewer session and its save capability: both travel
/// through a uid-owned serving directory rather than socket params, so the app
/// cannot forge them in-process. Every other case keeps the existing
/// `Workspace.openFileSurfaces` behavior — see ``FileExplorerOpenRouting``.
@MainActor
final class FileExplorerFileOpenCoordinator {
    static let shared = FileExplorerFileOpenCoordinator()

    private var editorProcesses: [Int32: Process] = [:]

    /// Opens `filePath` on behalf of a file-explorer activation.
    ///
    /// - Parameters:
    ///   - filePath: The activated path, as the explorer shows it.
    ///   - workspace: Workspace that owns the explorer.
    ///   - remoteMaterializationStore: Store used to materialize a local copy
    ///     when the workspace is remote.
    func open(
        filePath: String,
        in workspace: Workspace?,
        remoteMaterializationStore: FileExplorerStore?
    ) {
        guard let workspace,
              let paneId = workspace.bonsplitController.focusedPaneId
                ?? workspace.bonsplitController.allPaneIds.first else {
            return
        }

        let cliURL = CmuxCLIPathInstaller.bundledCLIExecutableURL()
        switch FileExplorerOpenRouting.target(
            filePath: filePath,
            isRemoteWorkspace: workspace.isRemoteWorkspace,
            isEditorCommandAvailable: cliURL != nil
        ) {
        case .monacoEditor:
            if focusExistingMonacoEditor(filePath: filePath, in: workspace) {
                return
            }
            if let cliURL,
               launchMonacoEditor(filePath: filePath, cliURL: cliURL, workspace: workspace) {
                return
            }
            openWorkspaceFileSurface(
                filePath: filePath,
                in: workspace,
                paneId: paneId,
                remoteMaterializationStore: remoteMaterializationStore
            )
        case .markdown, .project, .filePreview:
            openWorkspaceFileSurface(
                filePath: filePath,
                in: workspace,
                paneId: paneId,
                remoteMaterializationStore: remoteMaterializationStore
            )
        }
    }

    /// Opens the workspace's own file surface, materializing a local copy first
    /// when the workspace is remote.
    private func openWorkspaceFileSurface(
        filePath: String,
        in workspace: Workspace,
        paneId: PaneID,
        remoteMaterializationStore: FileExplorerStore?
    ) {
        guard workspace.isRemoteWorkspace else {
            _ = workspace.openFileSurfaces(
                inPane: paneId,
                filePaths: [filePath],
                focus: true,
                reuseExisting: true
            )
            return
        }
        guard let store = remoteMaterializationStore else {
            NSSound.beep()
            return
        }
        Task { [weak workspace, weak store] in
            guard let workspace, let store else { return }
            do {
                let localURL = try await store.materializeRemoteFileForPreview(path: filePath)
                _ = workspace.openFileSurfaces(
                    inPane: paneId,
                    filePaths: [localURL.path],
                    focus: true,
                    reuseExisting: true
                )
            } catch {
                NSSound.beep()
            }
        }
    }

    /// Focuses an already-open Monaco panel for `filePath` when one exists.
    @discardableResult
    private func focusExistingMonacoEditor(filePath: String, in workspace: Workspace) -> Bool {
        let live = CmuxEditorSaveRegistry.shared.liveEditors()
        guard !live.isEmpty else { return false }
        let openEditors: [(panelId: UUID, filePath: String)] = workspace.panels.values.compactMap { panel in
            guard let browser = panel as? BrowserPanel, browser.editorPageActive else { return nil }
            guard let token = Self.editorToken(from: browser.currentURL) else { return nil }
            guard let path = live.first(where: { $0.token == token })?.filePath else { return nil }
            return (browser.id, path)
        }
        guard let panelId = GdockEditorReusePlanner.panelIdToFocus(
            filePath: filePath,
            openEditors: openEditors
        ) else {
            return false
        }
        AppDelegate.shared?.tabManager?.focusSurface(tabId: workspace.id, surfaceId: panelId)
        return true
    }

    /// Diff-viewer custom scheme uses the token as host; the HTTP form uses
    /// the first path component.
    private static func editorToken(from url: URL?) -> String? {
        guard let url else { return nil }
        if url.scheme == CmuxDiffViewerURLSchemeHandler.scheme {
            return url.host
        }
        if url.scheme?.lowercased() == "http", url.host == "127.0.0.1" {
            return url.path.split(separator: "/").first.map(String.init)
        }
        return url.host
    }

    /// Spawns the bundled CLI's `cmux edit` against this app's control socket.
    ///
    /// Mirrors `AppDelegate.launchDiffViewerProcess(...)`: the CLI writes the
    /// editor page plus its trusted manifest, then calls back over the socket to
    /// open the webview surface next to the focused one.
    ///
    /// - Returns: `true` when the child process started.
    private func launchMonacoEditor(
        filePath: String,
        cliURL: URL,
        workspace: Workspace
    ) -> Bool {
        let socketPath = TerminalController.shared.activeSocketPath(
            preferredPath: SocketControlSettings.socketPath()
        )
        let surfaceId = workspace.focusedPanelId
        let process = Process()
        process.executableURL = cliURL
        process.arguments = FileExplorerOpenRouting.editorCommandArguments(
            filePath: filePath,
            socketPath: socketPath,
            workspaceId: workspace.id,
            surfaceId: surfaceId
        )
        var environment = ProcessInfo.processInfo.environment
        environment["CMUX_SOCKET_PATH"] = socketPath
        environment["CMUX_BUNDLED_CLI_PATH"] = cliURL.path
        environment["CMUX_WORKSPACE_ID"] = workspace.id.uuidString
        if let surfaceId {
            environment["CMUX_SURFACE_ID"] = surfaceId.uuidString
        }
        // The GUI process can itself have been launched from a cmux terminal;
        // an inherited CMUX_SOCKET would point the child at another instance.
        environment.removeValue(forKey: "CMUX_SOCKET")
        process.environment = environment
        process.standardInput = FileHandle.nullDevice

        let stdoutPipe = Pipe()
        let stderrPipe = Pipe()
        process.standardOutput = stdoutPipe
        process.standardError = stderrPipe
        let outputCollector = ProcessOutputCollector(stdout: stdoutPipe, stderr: stderrPipe)
        outputCollector.start()
        process.terminationHandler = { terminatedProcess in
            let output = outputCollector.finish()
            let processIdentifier = terminatedProcess.processIdentifier
            let terminationStatus = terminatedProcess.terminationStatus
            // Capture only Sendable values; the fallback re-resolves its target
            // on the main actor.
            Task { @MainActor in
                FileExplorerFileOpenCoordinator.shared.editorProcesses
                    .removeValue(forKey: processIdentifier)
                guard terminationStatus != 0 else { return }
#if DEBUG
                // Log only non-sensitive metadata: the child's stdout/stderr can
                // echo repo paths and file contents, so report a byte count.
                cmuxDebugLog(
                    "fileExplorerEditorOpen exited status=\(terminationStatus) outputBytes=\(output.utf8.count)"
                )
#endif
                // `cmux edit` refuses non-UTF-8 and unreadable files, so fall
                // back to the native preview instead of the activation no-oping.
                AppDelegate.shared?.openFilePreviewInPreferredMainWindow(
                    filePath: filePath,
                    debugSource: "fileExplorerEditorFallback"
                )
            }
        }

        do {
            try process.run()
            let processIdentifier = process.processIdentifier
            editorProcesses[processIdentifier] = process
            if !process.isRunning {
                editorProcesses.removeValue(forKey: processIdentifier)
            }
#if DEBUG
            cmuxDebugLog("fileExplorerEditorOpen pid=\(process.processIdentifier)")
#endif
            return true
        } catch {
            outputCollector.cancel()
#if DEBUG
            cmuxDebugLog("fileExplorerEditorOpen failed errorType=\(type(of: error))")
#endif
            return false
        }
    }
}
