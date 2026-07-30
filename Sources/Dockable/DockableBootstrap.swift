import Foundation
import CmuxDockable

/// Registers real, context-aware create/decode factories for every
/// ``DockableKind`` on ``DockableRegistry/shared``.
///
/// Factories read ``DockableCreateContextStorage`` (context + optional
/// ``Workspace``) so callers that need paths/names/workspace install context
/// before ``make``. Decode rehydrates from Session* JSON payloads produced by
/// ``Dockable/encodeDockPayload()``.
@MainActor
enum DockableBootstrap {
    private static var didRegister = false

    /// Idempotent process-wide registration. Safe to call from app launch and tests.
    static func registerAllIfNeeded() {
        guard !didRegister else { return }
        didRegister = true
        registerAll(into: DockableRegistry.shared)
    }

    /// Registers into an isolated registry (tests).
    static func registerAll(into registry: DockableRegistry) {
        for kind in DockableKind.allCases {
            registry.register(
                kind: kind,
                make: { tryMake(kind: kind) },
                decode: { payload in decodeFactory(kind: kind, payload: payload) }
            )
        }
    }

    /// Context-aware create helper used by tests and open-pane paths.
    static func make(
        kind: DockableKind,
        context: DockableCreateContext,
        workspace: Workspace? = nil,
        registry: DockableRegistry = .shared
    ) -> (any Dockable)? {
        registerAllIfNeeded()
        return DockableCreateContextStorage.withContext(context, workspace: workspace) {
            registry.make(kind: kind)
        }
    }

    /// Context-aware decode helper (workspace needed for some kinds).
    static func decode(
        kind: DockableKind,
        payload: Data,
        context: DockableCreateContext,
        workspace: Workspace? = nil,
        registry: DockableRegistry = .shared
    ) -> (any Dockable)? {
        registerAllIfNeeded()
        return DockableCreateContextStorage.withContext(context, workspace: workspace) {
            registry.decode(kind: kind, payload: payload)
        }
    }

    /// Decode using a fresh empty create context (workspace optional).
    static func decode(
        kind: DockableKind,
        payload: Data,
        workspace: Workspace? = nil,
        registry: DockableRegistry = .shared
    ) -> (any Dockable)? {
        decode(
            kind: kind,
            payload: payload,
            context: DockableCreateContext(),
            workspace: workspace,
            registry: registry
        )
    }

    // MARK: - Factories

    private static func tryMake(kind: DockableKind) -> (any Dockable)? {
        let ctx = DockableCreateContextStorage.context ?? DockableCreateContext()
        let workspace = DockableCreateContextStorage.workspace

        switch kind {
        case .terminal:
            return TerminalPanel(
                workspaceId: ctx.workspaceId,
                workingDirectory: ctx.terminalWorkingDirectory ?? ctx.workingDirectory,
                runtimeSpawnPolicy: .immediate
            )
        case .browser:
            return BrowserPanel(
                workspaceId: ctx.workspaceId,
                profileID: ctx.browserProfileID,
                initialURL: ctx.url,
                renderInitialNavigation: ctx.url != nil
            )
        case .markdown:
            guard let filePath = ctx.filePath, !filePath.isEmpty else { return nil }
            return MarkdownPanel(workspaceId: ctx.workspaceId, filePath: filePath)
        case .filePreview:
            guard let filePath = ctx.filePath, !filePath.isEmpty else { return nil }
            return FilePreviewPanel(workspaceId: ctx.workspaceId, filePath: filePath)
        case .rightSidebarTool:
            guard let workspace,
                  let mode = ctx.rightSidebarMode,
                  mode.canOpenAsPane else { return nil }
            return RightSidebarToolPanel(workspace: workspace, mode: mode)
        case .leftWorkspaceSelector:
            guard let workspace else { return nil }
            return LeftWorkspaceSelectorPanel(workspace: workspace)
        case .customSidebar:
            guard let workspace,
                  let name = ctx.customSidebarName,
                  let fileURL = ctx.customSidebarFileURL else { return nil }
            return CustomSidebarPanel(workspace: workspace, name: name, fileURL: fileURL)
        case .agentSession:
            return AgentSessionPanel(
                workspaceId: ctx.workspaceId,
                rendererKind: ctx.agentRendererKind,
                initialProviderID: ctx.agentProviderID,
                workingDirectory: ctx.workingDirectory
            )
        case .project:
            guard let projectPath = ctx.projectPath, !projectPath.isEmpty else { return nil }
            return ProjectPanel(projectURL: URL(fileURLWithPath: projectPath))
        case .extensionBrowser:
            return CMUXSidebarExtensionBrowserPanel(title: ctx.extensionBrowserTitle)
        case .workspaceTodo:
            guard let workspace else { return nil }
            return WorkspaceTodoPanel(workspace: workspace)
        case .cloudVMLoading:
            return CloudVMLoadingPanel(
                workspaceId: ctx.workspaceId,
                startedAt: ctx.cloudVMStartedAt ?? Date()
            )
        }
    }

    private static func decodeFactory(kind: DockableKind, payload: Data) -> (any Dockable)? {
        let ctx = DockableCreateContextStorage.context ?? DockableCreateContext()
        let workspace = DockableCreateContextStorage.workspace
        let decoder = JSONDecoder()

        switch kind {
        case .terminal:
            guard let snap = try? decoder.decode(SessionTerminalPanelSnapshot.self, from: payload) else {
                return nil
            }
            return TerminalPanel(
                workspaceId: ctx.workspaceId,
                workingDirectory: snap.workingDirectory ?? ctx.terminalWorkingDirectory,
                tmuxStartCommand: snap.tmuxStartCommand,
                runtimeSpawnPolicy: .immediate
            )
        case .browser:
            guard let snap = try? decoder.decode(SessionBrowserPanelSnapshot.self, from: payload) else {
                return nil
            }
            let url = snap.urlString.flatMap { URL(string: $0) }
            return BrowserPanel(
                workspaceId: ctx.workspaceId,
                profileID: snap.profileID ?? ctx.browserProfileID,
                initialURL: url,
                renderInitialNavigation: url != nil,
                omnibarVisible: snap.omnibarVisible ?? true,
                transparentBackground: snap.transparentBackground ?? false
            )
        case .markdown:
            guard let snap = try? decoder.decode(SessionMarkdownPanelSnapshot.self, from: payload) else {
                return nil
            }
            return MarkdownPanel(workspaceId: ctx.workspaceId, filePath: snap.filePath)
        case .filePreview:
            guard let snap = try? decoder.decode(SessionFilePreviewPanelSnapshot.self, from: payload) else {
                return nil
            }
            return FilePreviewPanel(workspaceId: ctx.workspaceId, filePath: snap.filePath)
        case .rightSidebarTool:
            guard let snap = try? decoder.decode(SessionRightSidebarToolPanelSnapshot.self, from: payload),
                  let mode = snap.mode,
                  mode.canOpenAsPane,
                  let workspace else {
                return nil
            }
            return RightSidebarToolPanel(workspace: workspace, mode: mode)
        case .leftWorkspaceSelector:
            guard let workspace else { return nil }
            if !payload.isEmpty {
                guard (try? decoder.decode(SessionLeftWorkspaceSelectorPanelSnapshot.self, from: payload)) != nil else {
                    return nil
                }
            }
            return LeftWorkspaceSelectorPanel(workspace: workspace)
        case .customSidebar:
            guard let snap = try? decoder.decode(SessionCustomSidebarPanelSnapshot.self, from: payload),
                  let workspace else {
                return nil
            }
            // File URL is not in the Session snapshot; require context for rehydrate fidelity of name,
            // and a context file URL when the sidebar file must be re-opened.
            let fileURL = ctx.customSidebarFileURL ?? URL(fileURLWithPath: "/tmp/\(snap.name).cmuxsidebar")
            return CustomSidebarPanel(workspace: workspace, name: snap.name, fileURL: fileURL)
        case .agentSession:
            guard let snap = try? decoder.decode(SessionAgentSessionPanelSnapshot.self, from: payload) else {
                return nil
            }
            return AgentSessionPanel(
                workspaceId: ctx.workspaceId,
                rendererKind: snap.rendererKind,
                initialProviderID: snap.providerID,
                workingDirectory: snap.workingDirectory
            )
        case .project:
            guard let snap = try? decoder.decode(SessionProjectPanelSnapshot.self, from: payload) else {
                return nil
            }
            let panel = ProjectPanel(projectURL: URL(fileURLWithPath: snap.projectPath))
            if let selected = snap.selectedNodePath {
                panel.selectedFilePath = selected
            }
            if let tabRaw = snap.activeTab, let tab = ProjectPanelTab(rawValue: tabRaw) {
                panel.activeTab = tab
            }
            panel.selectedSchemeName = snap.selectedSchemeName
            panel.selectedConfigurationName = snap.selectedConfigurationName
            return panel
        case .extensionBrowser:
            // Content-less: empty payload + make.
            return CMUXSidebarExtensionBrowserPanel(title: ctx.extensionBrowserTitle)
        case .workspaceTodo:
            guard let workspace else { return nil }
            // Empty marker payload is enough; type is carried by kind.
            if !payload.isEmpty {
                guard (try? decoder.decode(SessionWorkspaceTodoPanelSnapshot.self, from: payload)) != nil else {
                    return nil
                }
            }
            return WorkspaceTodoPanel(workspace: workspace)
        case .cloudVMLoading:
            // Content-less: empty payload + make.
            return CloudVMLoadingPanel(
                workspaceId: ctx.workspaceId,
                startedAt: ctx.cloudVMStartedAt ?? Date()
            )
        }
    }
}
