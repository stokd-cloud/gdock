import Foundation
import CmuxDockable

/// App-owned create/restore context read by ``DockableBootstrap`` factories.
///
/// The package registry remains zero-arg; context-aware create installs this
/// value before calling ``DockableRegistry/make(kind:)`` (or uses
/// ``DockableBootstrap/make(kind:context:)`` which does so).
@MainActor
struct DockableCreateContext: Sendable {
    var workspaceId: UUID
    /// Required for kinds that reattach to a live workspace graph
    /// (rightSidebarTool, customSidebar, workspaceTodo). Not ``Sendable``-safe
    /// across actors; only used on the main actor via the non-Sendable holder.
    var workingDirectory: String?
    var filePath: String?
    var projectPath: String?
    var url: URL?
    var browserProfileID: UUID?
    var rightSidebarMode: RightSidebarMode?
    var customSidebarName: String?
    var customSidebarFileURL: URL?
    var agentProviderID: AgentSessionProviderID
    var agentRendererKind: AgentSessionRendererKind
    var extensionBrowserTitle: String
    var terminalWorkingDirectory: String?
    var cloudVMStartedAt: Date?

    init(
        workspaceId: UUID = UUID(),
        workingDirectory: String? = nil,
        filePath: String? = nil,
        projectPath: String? = nil,
        url: URL? = nil,
        browserProfileID: UUID? = nil,
        rightSidebarMode: RightSidebarMode? = nil,
        customSidebarName: String? = nil,
        customSidebarFileURL: URL? = nil,
        agentProviderID: AgentSessionProviderID = .codex,
        agentRendererKind: AgentSessionRendererKind = .react,
        extensionBrowserTitle: String = String(
            localized: "sidebar.extensions.browser.title",
            defaultValue: "Sidebar Extensions"
        ),
        terminalWorkingDirectory: String? = nil,
        cloudVMStartedAt: Date? = nil
    ) {
        self.workspaceId = workspaceId
        self.workingDirectory = workingDirectory
        self.filePath = filePath
        self.projectPath = projectPath
        self.url = url
        self.browserProfileID = browserProfileID
        self.rightSidebarMode = rightSidebarMode
        self.customSidebarName = customSidebarName
        self.customSidebarFileURL = customSidebarFileURL
        self.agentProviderID = agentProviderID
        self.agentRendererKind = agentRendererKind
        self.extensionBrowserTitle = extensionBrowserTitle
        self.terminalWorkingDirectory = terminalWorkingDirectory
        self.cloudVMStartedAt = cloudVMStartedAt
    }
}

/// Main-actor holder for create context plus an optional live ``Workspace``.
@MainActor
enum DockableCreateContextStorage {
    static var context: DockableCreateContext?
    static weak var workspace: Workspace?

    static func install(context: DockableCreateContext, workspace: Workspace? = nil) {
        self.context = context
        self.workspace = workspace
    }

    static func clear() {
        context = nil
        workspace = nil
    }

    static func withContext<T>(
        _ context: DockableCreateContext,
        workspace: Workspace? = nil,
        _ body: () -> T
    ) -> T {
        install(context: context, workspace: workspace)
        defer { clear() }
        return body()
    }
}
