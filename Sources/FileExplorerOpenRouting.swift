import Foundation

/// Where a file activated in the file explorer is opened.
///
/// The Files pane and the Find pane's search results share one open path
/// (``FileExplorerFileOpenCoordinator``); this is the decision that path makes.
enum FileExplorerOpenTarget: Equatable {
    /// The internal Monaco editor surface, opened through the bundled CLI's
    /// `cmux edit`, which is the only component that can mint the trusted
    /// diff-viewer session and the editor save capability for a webview.
    case monacoEditor
    /// The existing rendered-markdown surface.
    case markdown
    /// The existing Xcode project surface.
    case project
    /// The existing native file preview panel.
    case filePreview
}

/// Pure routing policy for file-explorer file activation.
enum FileExplorerOpenRouting {
    /// Decides which surface a file explorer open should produce.
    ///
    /// - Parameters:
    ///   - filePath: The activated path.
    ///   - isRemoteWorkspace: Whether the owning workspace is remote.
    ///   - isEditorCommandAvailable: Whether the bundled CLI that opens the
    ///     Monaco editor could be resolved.
    /// - Returns: The surface to open.
    static func target(
        filePath: String,
        isRemoteWorkspace: Bool,
        isEditorCommandAvailable: Bool
    ) -> FileExplorerOpenTarget {
        // Rendered markdown and Xcode projects are deliberate surfaces of their
        // own, so they win regardless of whether the editor is reachable.
        let pathExtension = (filePath as NSString).pathExtension.lowercased()
        if pathExtension == "xcodeproj" || pathExtension == "xcworkspace" {
            return .project
        }
        if MarkdownPanelFileLinkResolver.isMarkdownPathLike(filePath) {
            return .markdown
        }
        // A remote open materializes a temporary local copy, and the editor's
        // save capability writes the path it was opened with — that copy, not
        // the remote file. Keep the read-oriented preview panel there rather
        // than offering a save that silently goes nowhere.
        guard !isRemoteWorkspace, isEditorCommandAvailable else {
            return .filePreview
        }
        return .monacoEditor
    }

    /// Builds the bundled-CLI argument vector that opens `filePath` in the
    /// Monaco editor next to the given surface.
    ///
    /// - Parameters:
    ///   - filePath: Absolute path to open.
    ///   - socketPath: Control socket of this app instance.
    ///   - workspaceId: Workspace that owns the open.
    ///   - surfaceId: Surface to split from, or `nil` to let the CLI choose.
    /// - Returns: Arguments for the bundled `cmux` executable.
    static func editorCommandArguments(
        filePath: String,
        socketPath: String,
        workspaceId: UUID,
        surfaceId: UUID?
    ) -> [String] {
        var arguments = [
            "--socket", socketPath,
            "edit", filePath,
            "--workspace", workspaceId.uuidString,
        ]
        if let surfaceId {
            arguments.append(contentsOf: ["--surface", surfaceId.uuidString])
        }
        arguments.append("--focus")
        return arguments
    }
}
