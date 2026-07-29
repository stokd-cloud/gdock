import Foundation
import CmuxDockable

/// Whether a kind can be created through the registry with the given context.
enum DockableCreateSupport: Equatable, Sendable {
    /// Create succeeds when the listed context fields are present.
    case yes(requiredContext: [DockableContextRequirement])
    /// Create is not supported and must fail closed (return nil / throw path).
    case no
}

/// Whether a kind can be restored from an encoded dock payload.
enum DockableRestoreSupport: Equatable, Sendable {
    /// Decode from a non-empty Session* JSON payload with field fidelity.
    case yes
    /// Content-less kinds: empty payload + make (or explicit empty rehydrate).
    case emptyPayload
    /// Restore is not supported; decode fails closed without crashing.
    case failClosed
}

/// Whether a kind can move onto the freeform canvas host.
enum DockableMoveSupport: Equatable, Sendable {
    case yes
    /// Ephemeral UI (loading/chrome); not a durable canvas object.
    case ephemeral
}

/// Named context fields the matrix / factories check.
enum DockableContextRequirement: String, Equatable, Sendable, CaseIterable {
    case workspaceId
    case workspace
    case filePath
    case projectPath
    case rightSidebarMode
    case customSidebarName
    case customSidebarFileURL
    case workingDirectory
}

/// One row of the executable support matrix for a ``DockableKind``.
struct DockableKindSupportRow: Equatable, Sendable {
    var kind: DockableKind
    var create: DockableCreateSupport
    var restore: DockableRestoreSupport
    var move: DockableMoveSupport
    /// Human-readable required context/payload description for tests and docs.
    var requiredContextSummary: String
}

/// Executable, checked-in support matrix for all dockable kinds.
///
/// Tests load ``allRows``, assert count and kind set, and probe create/restore
/// using real fixtures for every non-ephemeral create/restore-capable row.
enum DockableSupportMatrix {
    static let allRows: [DockableKindSupportRow] = [
        DockableKindSupportRow(
            kind: .terminal,
            create: .yes(requiredContext: [.workspaceId]),
            restore: .yes,
            move: .yes,
            requiredContextSummary: "workspaceId; optional terminalWorkingDirectory. Payload: SessionTerminalPanelSnapshot JSON."
        ),
        DockableKindSupportRow(
            kind: .browser,
            create: .yes(requiredContext: [.workspaceId]),
            restore: .yes,
            move: .yes,
            requiredContextSummary: "workspaceId; optional url/profile. Payload: SessionBrowserPanelSnapshot JSON."
        ),
        DockableKindSupportRow(
            kind: .markdown,
            create: .yes(requiredContext: [.workspaceId, .filePath]),
            restore: .yes,
            move: .yes,
            requiredContextSummary: "workspaceId + filePath. Payload: SessionMarkdownPanelSnapshot JSON."
        ),
        DockableKindSupportRow(
            kind: .filePreview,
            create: .yes(requiredContext: [.workspaceId, .filePath]),
            restore: .yes,
            move: .yes,
            requiredContextSummary: "workspaceId + filePath. Payload: SessionFilePreviewPanelSnapshot JSON."
        ),
        DockableKindSupportRow(
            kind: .rightSidebarTool,
            create: .yes(requiredContext: [.workspace, .rightSidebarMode]),
            restore: .yes,
            move: .yes,
            requiredContextSummary: "Workspace + RightSidebarMode (pane mode). Payload: SessionRightSidebarToolPanelSnapshot JSON."
        ),
        DockableKindSupportRow(
            kind: .leftWorkspaceSelector,
            create: .yes(requiredContext: [.workspace]),
            restore: .yes,
            move: .yes,
            requiredContextSummary: "Workspace. Payload: SessionLeftWorkspaceSelectorPanelSnapshot JSON (empty marker)."
        ),
        DockableKindSupportRow(
            kind: .customSidebar,
            create: .yes(requiredContext: [.workspace, .customSidebarName, .customSidebarFileURL]),
            restore: .yes,
            move: .yes,
            requiredContextSummary: "Workspace + name + fileURL. Payload: SessionCustomSidebarPanelSnapshot JSON."
        ),
        DockableKindSupportRow(
            kind: .agentSession,
            create: .yes(requiredContext: [.workspaceId]),
            restore: .yes,
            move: .yes,
            requiredContextSummary: "workspaceId; optional provider/renderer/workingDirectory. Payload: SessionAgentSessionPanelSnapshot JSON."
        ),
        DockableKindSupportRow(
            kind: .project,
            create: .yes(requiredContext: [.projectPath]),
            restore: .yes,
            move: .yes,
            requiredContextSummary: "projectPath. Payload: SessionProjectPanelSnapshot JSON."
        ),
        DockableKindSupportRow(
            kind: .extensionBrowser,
            create: .yes(requiredContext: []),
            restore: .emptyPayload,
            move: .ephemeral,
            requiredContextSummary: "Optional title. Content-less: empty payload + make. Session restore returns nil today."
        ),
        DockableKindSupportRow(
            kind: .workspaceTodo,
            create: .yes(requiredContext: [.workspace]),
            restore: .yes,
            move: .yes,
            requiredContextSummary: "Workspace. Payload: SessionWorkspaceTodoPanelSnapshot JSON (empty marker)."
        ),
        DockableKindSupportRow(
            kind: .cloudVMLoading,
            create: .yes(requiredContext: [.workspaceId]),
            restore: .emptyPayload,
            move: .ephemeral,
            requiredContextSummary: "workspaceId. Content-less: empty payload + make. Session restore returns nil today (loading chrome)."
        ),
    ]

    static var kindSet: Set<DockableKind> {
        Set(allRows.map(\.kind))
    }

    static func row(for kind: DockableKind) -> DockableKindSupportRow? {
        allRows.first { $0.kind == kind }
    }
}
