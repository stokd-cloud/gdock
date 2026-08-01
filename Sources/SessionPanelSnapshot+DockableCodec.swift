import Foundation
import CmuxDockable
import OSLog

private let sessionPanelCodecLogger = Logger(
    subsystem: Bundle.main.bundleIdentifier ?? "com.cmuxterm.app",
    category: "SessionPanelCodec"
)

// MARK: - Dual-shape Codable (DockableSnapshot primary + legacy decode)

extension SessionPanelSnapshot: Codable {
    private enum CodingKeys: String, CodingKey {
        case id
        case stableSurfaceId
        case type
        case title
        case customTitle
        case customTitleSource
        case directory
        case directoryIsTrustedRemoteReport
        case directoryRequiresRemoteTrust
        case isPinned
        case isManuallyUnread
        case hasUnreadIndicator
        case restoredUnreadContributesToWorkspace
        case notifications
        case gitBranch
        case listeningPorts
        case ttyName
        /// New primary content shape: ``DockableSnapshot`` { id, kind, payload }.
        case dockable
        /// Flat equivalent accepted on decode (id/kind/payload at panel root).
        case kind
        case payload
        // Legacy per-kind optional fields (decode-only for new write path).
        case terminal
        case browser
        case markdown
        case filePreview
        case rightSidebarTool
        case leftWorkspaceSelector
        case customSidebar
        case agentSession
        case project
        case workspaceTodo
    }

    /// Primary on-disk encode: metadata + nested ``DockableSnapshot``. Does **not**
    /// emit the nine legacy optional type-specific fields.
    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(id, forKey: .id)
        try container.encodeIfPresent(stableSurfaceId, forKey: .stableSurfaceId)
        try container.encode(type, forKey: .type)
        try container.encodeIfPresent(title, forKey: .title)
        try container.encodeIfPresent(customTitle, forKey: .customTitle)
        try container.encodeIfPresent(customTitleSource, forKey: .customTitleSource)
        try container.encodeIfPresent(directory, forKey: .directory)
        try container.encodeIfPresent(directoryIsTrustedRemoteReport, forKey: .directoryIsTrustedRemoteReport)
        try container.encodeIfPresent(directoryRequiresRemoteTrust, forKey: .directoryRequiresRemoteTrust)
        try container.encode(isPinned, forKey: .isPinned)
        try container.encode(isManuallyUnread, forKey: .isManuallyUnread)
        try container.encodeIfPresent(hasUnreadIndicator, forKey: .hasUnreadIndicator)
        try container.encodeIfPresent(restoredUnreadContributesToWorkspace, forKey: .restoredUnreadContributesToWorkspace)
        try container.encodeIfPresent(notifications, forKey: .notifications)
        try container.encodeIfPresent(gitBranch, forKey: .gitBranch)
        try container.encode(listeningPorts, forKey: .listeningPorts)
        try container.encodeIfPresent(ttyName, forKey: .ttyName)
        try container.encode(try makeDockableSnapshot(), forKey: .dockable)
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let decodedId = try container.decode(UUID.self, forKey: .id)
        let decodedType = try container.decodeIfPresent(PanelType.self, forKey: .type)

        id = decodedId
        stableSurfaceId = try container.decodeIfPresent(UUID.self, forKey: .stableSurfaceId)
        title = try container.decodeIfPresent(String.self, forKey: .title)
        customTitle = try container.decodeIfPresent(String.self, forKey: .customTitle)
        customTitleSource = try container.decodeIfPresent(Workspace.CustomTitleSource.self, forKey: .customTitleSource)
        directory = try container.decodeIfPresent(String.self, forKey: .directory)
        directoryIsTrustedRemoteReport = try container.decodeIfPresent(Bool.self, forKey: .directoryIsTrustedRemoteReport)
        directoryRequiresRemoteTrust = try container.decodeIfPresent(Bool.self, forKey: .directoryRequiresRemoteTrust)
        isPinned = try container.decodeIfPresent(Bool.self, forKey: .isPinned) ?? false
        isManuallyUnread = try container.decodeIfPresent(Bool.self, forKey: .isManuallyUnread) ?? false
        hasUnreadIndicator = try container.decodeIfPresent(Bool.self, forKey: .hasUnreadIndicator)
        restoredUnreadContributesToWorkspace = try container.decodeIfPresent(Bool.self, forKey: .restoredUnreadContributesToWorkspace)
        notifications = try container.decodeIfPresent([SessionNotificationSnapshot].self, forKey: .notifications)
        gitBranch = try container.decodeIfPresent(SessionGitBranchSnapshot.self, forKey: .gitBranch)
        listeningPorts = try container.decodeIfPresent([Int].self, forKey: .listeningPorts) ?? []
        ttyName = try container.decodeIfPresent(String.self, forKey: .ttyName)

        terminal = nil
        browser = nil
        markdown = nil
        filePreview = nil
        rightSidebarTool = nil
        leftWorkspaceSelector = nil
        customSidebar = nil
        agentSession = nil
        project = nil
        workspaceTodo = nil

        // Prefer nested DockableSnapshot (new primary shape).
        if let dockable = try container.decodeIfPresent(DockableSnapshot.self, forKey: .dockable) {
            type = decodedType
                ?? PanelType(rawValue: dockable.kind.rawValue)
                ?? .terminal
            applyDockablePayload(dockable.payload, kind: dockable.kind)
            if id != dockable.id {
                // Keep the panel-level id as restore identity; dockable.id should match.
                sessionPanelCodecLogger.debug(
                    "SessionPanelSnapshot id/dockable.id mismatch panel=\(decodedId.uuidString, privacy: .public) dockable=\(dockable.id.uuidString, privacy: .public)"
                )
            }
            return
        }

        // Flat id/kind/payload equivalent schema.
        if container.contains(.payload) {
            let payload = try container.decode(Data.self, forKey: .payload)
            let kind: DockableKind = {
                if let kind = try? container.decode(DockableKind.self, forKey: .kind) {
                    return kind
                }
                if let decodedType, let kind = DockableKind(rawValue: decodedType.rawValue) {
                    return kind
                }
                return .terminal
            }()
            type = decodedType ?? PanelType(rawValue: kind.rawValue) ?? .terminal
            applyDockablePayload(payload, kind: kind)
            return
        }

        // Legacy multi-optional-field SessionPanelSnapshot.
        type = try container.decode(PanelType.self, forKey: .type)
        terminal = try container.decodeIfPresent(SessionTerminalPanelSnapshot.self, forKey: .terminal)
        browser = try container.decodeIfPresent(SessionBrowserPanelSnapshot.self, forKey: .browser)
        markdown = try container.decodeIfPresent(SessionMarkdownPanelSnapshot.self, forKey: .markdown)
        filePreview = try container.decodeIfPresent(SessionFilePreviewPanelSnapshot.self, forKey: .filePreview)
        rightSidebarTool = try container.decodeIfPresent(SessionRightSidebarToolPanelSnapshot.self, forKey: .rightSidebarTool)
        leftWorkspaceSelector = try container.decodeIfPresent(
            SessionLeftWorkspaceSelectorPanelSnapshot.self,
            forKey: .leftWorkspaceSelector
        )
        customSidebar = try container.decodeIfPresent(SessionCustomSidebarPanelSnapshot.self, forKey: .customSidebar)
        agentSession = try container.decodeIfPresent(SessionAgentSessionPanelSnapshot.self, forKey: .agentSession)
        project = try container.decodeIfPresent(SessionProjectPanelSnapshot.self, forKey: .project)
        workspaceTodo = try container.decodeIfPresent(SessionWorkspaceTodoPanelSnapshot.self, forKey: .workspaceTodo)

        let legacyFieldCount = legacyStatefulFieldCount
        let typeRaw = type.rawValue
        if legacyFieldCount > 1 {
            sessionPanelCodecLogger.warning(
                "Legacy SessionPanelSnapshot has \(legacyFieldCount, privacy: .public) typed payload fields; keeping type=\(typeRaw, privacy: .public) only"
            )
            retainOnlyMatchingLegacyField(for: type)
        } else if legacyFieldCount == 0, type.requiresStatefulDockPayload {
            sessionPanelCodecLogger.warning(
                "Legacy SessionPanelSnapshot missing payload for stateful type=\(typeRaw, privacy: .public); restore will skip"
            )
        }
    }
}

// MARK: - DockableSnapshot bridge

extension SessionPanelSnapshot {
    /// Builds the primary on-disk panel content shape from in-memory typed fields.
    func makeDockableSnapshot() throws -> DockableSnapshot {
        guard let kind = DockableKind(rawValue: type.rawValue) else {
            throw SessionPanelDockableCodecError.unknownPanelType(type.rawValue)
        }
        let payload = try encodeDockPayloadData()
        return DockableSnapshot(id: id, kind: kind, payload: payload)
    }

    /// JSON payload for the panel's kind, matching ``Dockable/encodeDockPayload()`` schemas.
    func encodeDockPayloadData() throws -> Data {
        let encoder = SessionPanelDockableCodec.jsonEncoder
        switch type {
        case .terminal:
            guard let terminal else {
                throw SessionPanelDockableCodecError.missingTypedPayload(type.rawValue)
            }
            return try encoder.encode(terminal)
        case .browser:
            guard let browser else {
                throw SessionPanelDockableCodecError.missingTypedPayload(type.rawValue)
            }
            return try encoder.encode(browser)
        case .markdown:
            guard let markdown else {
                throw SessionPanelDockableCodecError.missingTypedPayload(type.rawValue)
            }
            return try encoder.encode(markdown)
        case .filePreview:
            guard let filePreview else {
                throw SessionPanelDockableCodecError.missingTypedPayload(type.rawValue)
            }
            return try encoder.encode(filePreview)
        case .rightSidebarTool:
            guard let rightSidebarTool else {
                throw SessionPanelDockableCodecError.missingTypedPayload(type.rawValue)
            }
            return try encoder.encode(rightSidebarTool)
        case .customSidebar:
            guard let customSidebar else {
                throw SessionPanelDockableCodecError.missingTypedPayload(type.rawValue)
            }
            return try encoder.encode(customSidebar)
        case .agentSession:
            guard let agentSession else {
                throw SessionPanelDockableCodecError.missingTypedPayload(type.rawValue)
            }
            return try encoder.encode(agentSession)
        case .project:
            guard let project else {
                throw SessionPanelDockableCodecError.missingTypedPayload(type.rawValue)
            }
            return try encoder.encode(project)
        case .workspaceTodo:
            // Marker payload; empty object is fine.
            return try encoder.encode(workspaceTodo ?? SessionWorkspaceTodoPanelSnapshot())
        case .leftWorkspaceSelector:
            return try encoder.encode(leftWorkspaceSelector ?? SessionLeftWorkspaceSelectorPanelSnapshot())
        case .extensionBrowser, .cloudVMLoading:
            // Content-less kinds: empty payload.
            return Data()
        }
    }

    /// Hydrates in-memory typed fields from an opaque dockable payload.
    mutating func applyDockablePayload(_ payload: Data, kind: DockableKind) {
        let decoder = SessionPanelDockableCodec.jsonDecoder
        switch kind {
        case .terminal:
            terminal = try? decoder.decode(SessionTerminalPanelSnapshot.self, from: payload)
        case .browser:
            browser = try? decoder.decode(SessionBrowserPanelSnapshot.self, from: payload)
        case .markdown:
            markdown = try? decoder.decode(SessionMarkdownPanelSnapshot.self, from: payload)
        case .filePreview:
            filePreview = try? decoder.decode(SessionFilePreviewPanelSnapshot.self, from: payload)
        case .rightSidebarTool:
            rightSidebarTool = try? decoder.decode(SessionRightSidebarToolPanelSnapshot.self, from: payload)
        case .customSidebar:
            customSidebar = try? decoder.decode(SessionCustomSidebarPanelSnapshot.self, from: payload)
        case .agentSession:
            agentSession = try? decoder.decode(SessionAgentSessionPanelSnapshot.self, from: payload)
        case .project:
            project = try? decoder.decode(SessionProjectPanelSnapshot.self, from: payload)
        case .workspaceTodo:
            if payload.isEmpty {
                workspaceTodo = SessionWorkspaceTodoPanelSnapshot()
            } else {
                workspaceTodo = (try? decoder.decode(SessionWorkspaceTodoPanelSnapshot.self, from: payload))
                    ?? SessionWorkspaceTodoPanelSnapshot()
            }
        case .leftWorkspaceSelector:
            if payload.isEmpty {
                leftWorkspaceSelector = SessionLeftWorkspaceSelectorPanelSnapshot()
            } else {
                leftWorkspaceSelector = (try? decoder.decode(SessionLeftWorkspaceSelectorPanelSnapshot.self, from: payload))
                    ?? SessionLeftWorkspaceSelectorPanelSnapshot()
            }
        case .extensionBrowser, .cloudVMLoading:
            break
        }
    }

    /// Rehydrates a dockable via the registry (VAL-PERSIST restore path).
    @MainActor
    func decodeDockable(
        workspace: Workspace? = nil,
        context: DockableCreateContext? = nil,
        registry: DockableRegistry = .shared
    ) -> (any Dockable)? {
        guard let dockable = try? makeDockableSnapshot() else { return nil }
        let resolvedContext = context ?? DockableCreateContext(workspaceId: workspace?.id ?? UUID())
        return DockableBootstrap.decode(
            kind: dockable.kind,
            payload: dockable.payload,
            context: resolvedContext,
            workspace: workspace,
            registry: registry
        )
    }

    /// Whether this snapshot carries enough typed state for create/restore of its kind.
    var hasRestorableTypedPayload: Bool {
        switch type {
        case .terminal: return terminal != nil
        case .browser: return browser != nil
        case .markdown: return markdown != nil
        case .filePreview: return filePreview != nil
        case .rightSidebarTool: return rightSidebarTool != nil
        case .leftWorkspaceSelector: return true
        case .customSidebar: return customSidebar != nil
        case .agentSession: return agentSession != nil
        case .project: return project != nil
        case .workspaceTodo: return true
        case .extensionBrowser, .cloudVMLoading: return false
        }
    }

    private var legacyStatefulFieldCount: Int {
        [
            terminal != nil,
            browser != nil,
            markdown != nil,
            filePreview != nil,
            rightSidebarTool != nil,
            leftWorkspaceSelector != nil,
            customSidebar != nil,
            agentSession != nil,
            project != nil,
            workspaceTodo != nil
        ].filter { $0 }.count
    }

    private mutating func retainOnlyMatchingLegacyField(for type: PanelType) {
        let keepTerminal = type == .terminal ? terminal : nil
        let keepBrowser = type == .browser ? browser : nil
        let keepMarkdown = type == .markdown ? markdown : nil
        let keepFilePreview = type == .filePreview ? filePreview : nil
        let keepRightSidebar = type == .rightSidebarTool ? rightSidebarTool : nil
        let keepLeftSelector = type == .leftWorkspaceSelector ? leftWorkspaceSelector : nil
        let keepCustomSidebar = type == .customSidebar ? customSidebar : nil
        let keepAgent = type == .agentSession ? agentSession : nil
        let keepProject = type == .project ? project : nil
        let keepTodo = type == .workspaceTodo ? workspaceTodo : nil
        terminal = keepTerminal
        browser = keepBrowser
        markdown = keepMarkdown
        filePreview = keepFilePreview
        rightSidebarTool = keepRightSidebar
        leftWorkspaceSelector = keepLeftSelector
        customSidebar = keepCustomSidebar
        agentSession = keepAgent
        project = keepProject
        workspaceTodo = keepTodo
    }
}

// MARK: - Migration helpers

enum SessionPanelDockableCodec {
    static let jsonEncoder: JSONEncoder = {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        return encoder
    }()

    static let jsonDecoder = JSONDecoder()

    /// Maps a legacy typed field into a ``DockableSnapshot`` payload.
    static func dockableSnapshot(
        id: UUID,
        type: PanelType,
        terminal: SessionTerminalPanelSnapshot? = nil,
        browser: SessionBrowserPanelSnapshot? = nil,
        markdown: SessionMarkdownPanelSnapshot? = nil,
        filePreview: SessionFilePreviewPanelSnapshot? = nil,
        rightSidebarTool: SessionRightSidebarToolPanelSnapshot? = nil,
        leftWorkspaceSelector: SessionLeftWorkspaceSelectorPanelSnapshot? = nil,
        customSidebar: SessionCustomSidebarPanelSnapshot? = nil,
        agentSession: SessionAgentSessionPanelSnapshot? = nil,
        project: SessionProjectPanelSnapshot? = nil,
        workspaceTodo: SessionWorkspaceTodoPanelSnapshot? = nil
    ) throws -> DockableSnapshot {
        let snapshot = SessionPanelSnapshot(
            id: id,
            type: type,
            title: nil,
            customTitle: nil,
            directory: nil,
            isPinned: false,
            isManuallyUnread: false,
            listeningPorts: [],
            ttyName: nil,
            terminal: terminal,
            browser: browser,
            markdown: markdown,
            filePreview: filePreview,
            rightSidebarTool: rightSidebarTool,
            leftWorkspaceSelector: leftWorkspaceSelector,
            customSidebar: customSidebar,
            agentSession: agentSession,
            project: project,
            workspaceTodo: workspaceTodo
        )
        return try snapshot.makeDockableSnapshot()
    }
}

enum SessionPanelDockableCodecError: Error, LocalizedError {
    case unknownPanelType(String)
    case missingTypedPayload(String)

    var errorDescription: String? {
        switch self {
        case .unknownPanelType(let raw):
            return "Unknown panel type for DockableSnapshot: \(raw)"
        case .missingTypedPayload(let raw):
            return "Missing typed payload for panel type: \(raw)"
        }
    }
}

private extension PanelType {
    var requiresStatefulDockPayload: Bool {
        switch self {
        case .terminal, .browser, .markdown, .filePreview, .rightSidebarTool,
                .leftWorkspaceSelector, .customSidebar, .agentSession, .project, .workspaceTodo:
            return true
        case .extensionBrowser, .cloudVMLoading:
            return false
        }
    }
}

// Ensure browser/right-sidebar snapshots remain Codable-complete for payload encode.
extension SessionBrowserPanelSnapshot {
    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: BrowserPayloadCodingKeys.self)
        try container.encodeIfPresent(urlString, forKey: .urlString)
        try container.encodeIfPresent(profileID, forKey: .profileID)
        try container.encode(shouldRenderWebView, forKey: .shouldRenderWebView)
        try container.encode(pageZoom, forKey: .pageZoom)
        try container.encode(developerToolsVisible, forKey: .developerToolsVisible)
        try container.encode(isMuted, forKey: .isMuted)
        try container.encodeIfPresent(omnibarVisible, forKey: .omnibarVisible)
        try container.encodeIfPresent(backHistoryURLStrings, forKey: .backHistoryURLStrings)
        try container.encodeIfPresent(forwardHistoryURLStrings, forKey: .forwardHistoryURLStrings)
        try container.encodeIfPresent(transparentBackground, forKey: .transparentBackground)
        try container.encodeIfPresent(diffViewerToken, forKey: .diffViewerToken)
        try container.encodeIfPresent(diffViewerRequestPath, forKey: .diffViewerRequestPath)
    }

    private enum BrowserPayloadCodingKeys: String, CodingKey {
        case urlString
        case profileID
        case shouldRenderWebView
        case pageZoom
        case developerToolsVisible
        case isMuted
        case omnibarVisible
        case backHistoryURLStrings
        case forwardHistoryURLStrings
        case transparentBackground
        case diffViewerToken
        case diffViewerRequestPath
    }
}

extension SessionRightSidebarToolPanelSnapshot {
    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: RightSidebarPayloadCodingKeys.self)
        try container.encodeIfPresent(mode?.rawValue, forKey: .mode)
    }

    private enum RightSidebarPayloadCodingKeys: String, CodingKey {
        case mode
    }
}
