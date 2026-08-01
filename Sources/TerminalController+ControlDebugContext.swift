import AppKit
import CmuxCanvasUI
import CmuxControlSocket
import CmuxSettings
import Foundation
import CmuxTerminal

/// The debug-domain witnesses are the byte-faithful bodies of the former
/// `v2Debug*` dispatchers `processV2Command` routed (DEBUG builds only), minus
/// the per-read `v2MainSync` hops: the coordinator already runs on the main
/// actor inside the socket-command policy scope, so each hop was a no-op.
///
/// Two witness families:
/// - **Lifted state reads/mutations** (`debug.type`, text-box fixtures, the
///   command palette, right sidebar, file-drop simulation): the legacy
///   `v2MainSync` content runs here verbatim against `NSApp`/`AppDelegate`/
///   `TabManager` and crosses the seam as Sendable snapshots.
/// - **v1-shared forwards** (`set_shortcut`, `read_text`, `panel_snapshot`,
///   `screenshot`, …): the v1 string bodies stay in `TerminalController.swift`
///   because the v1 `processCommand` dispatch still calls them; these
///   witnesses forward and return the raw v1 response for the coordinator to
///   parse exactly as the legacy v2 wrappers did.
///
/// In release builds `ControlDebugContext` has no requirements, so the
/// conformance is an empty extension — matching the legacy `#if DEBUG` switch
/// cases that compiled the whole domain out.
#if DEBUG
@MainActor
func debugShowCanvasCommandScrollHint(in workspace: Workspace) -> Bool {
    guard workspace.layoutMode == .canvas,
          let rootView = workspace.canvasModel.viewport as? CanvasRootView else {
        return false
    }
    rootView.debugShowCommandScrollHint()
    return true
}
#endif

extension TerminalController: ControlDebugContext {
#if DEBUG
    // MARK: - Session-snapshot benchmarks

    func controlDebugSessionSnapshotBenchmark(includeScrollback: Bool, persist: Bool) -> JSONValue? {
        // Snapshot capture walks AppKit, SwiftUI, and terminal-panel state, so
        // this DEBUG-only benchmark must run synchronously on the main actor.
        guard let payload = AppDelegate.shared?.debugBenchmarkSessionSnapshot(
            includeScrollback: includeScrollback,
            persist: persist
        ) else {
            return nil
        }
        // The benchmark payload is JSON-safe by construction; a bridge failure
        // would have been the legacy encode_error and collapses to the same
        // `unavailable` outcome here (the `controlDebugTerminals` precedent).
        return JSONValue(foundationObject: payload)
    }

    func controlDebugSessionSnapshotSeedScrollback(charactersPerTerminal: Int) -> JSONValue? {
        // Synthetic scrollback seeding mutates workspace snapshot fallback
        // state, which is owned by the main-thread workspace graph.
        guard let payload = AppDelegate.shared?.debugSeedSessionSnapshotScrollback(
            charactersPerTerminal: charactersPerTerminal
        ) else {
            return nil
        }
        return JSONValue(foundationObject: payload)
    }

    // MARK: - v1-shared forwards (bodies stay in TerminalController.swift)

    func controlDebugSetShortcut(arguments: String) -> String { setShortcut(arguments) }

    func controlDebugSimulateShortcut(combo: String) -> String { simulateShortcut(combo) }

    func controlDebugActivateApp() -> String { activateApp() }

    func controlDebugRequestWorkspaceTodoChecklistAddField() -> UUID? {
        guard let workspace = tabManager?.selectedWorkspace else { return nil }
        WorkspaceTodoActions.requestChecklistAddField(workspaceId: workspace.id)
        return workspace.id
    }

    func controlDebugShowProWelcomeChecklist() {
        ProWelcomeChecklistPresenter.present()
    }

    func controlDebugIsTerminalFocused(surfaceArgument: String) -> String {
        isTerminalFocused(surfaceArgument)
    }

    func controlDebugReadTerminalText(surfaceArgument: String) -> String {
        readTerminalText(surfaceArgument)
    }

    func controlDebugRenderStats(surfaceArgument: String) -> String {
        renderStats(surfaceArgument)
    }

    func controlDebugLayout() -> String { layoutDebug() }

    func controlDebugBonsplitUnderflowCount() -> String { bonsplitUnderflowCount() }

    func controlDebugResetBonsplitUnderflowCount() -> String { resetBonsplitUnderflowCount() }

    func controlDebugEmptyPanelCount() -> String { emptyPanelCount() }

    func controlDebugResetEmptyPanelCount() -> String { resetEmptyPanelCount() }

    func controlDebugFocusNotification(arguments: String) -> String {
        focusFromNotification(arguments)
    }

    func controlDebugFlashCount(surfaceArgument: String) -> String { flashCount(surfaceArgument) }

    func controlDebugResetFlashCounts() -> String { resetFlashCounts() }

    func controlDebugPanelSnapshot(arguments: String) -> String { panelSnapshot(arguments) }

    func controlDebugPanelSnapshotReset(surfaceArgument: String) -> String {
        panelSnapshotReset(surfaceArgument)
    }

    func controlDebugCaptureScreenshot(label: String) -> String { captureScreenshot(label) }

    func controlDebugShowCanvasCommandScrollHint(
        routing: ControlRoutingSelectors
    ) -> ControlCanvasActionResolution {
        guard let workspace = resolveCanvasWorkspace(routing: routing) else {
            return .workspaceNotFound
        }
        guard workspace.layoutMode == .canvas else {
            return .notCanvasMode
        }
        guard debugShowCanvasCommandScrollHint(in: workspace) else {
            return .viewportUnavailable
        }
        return .ok(mode: workspace.layoutMode.rawValue)
    }

    // MARK: - debug.type

    func controlDebugTypeText(_ text: String) -> ControlDebugTypeResolution {
        guard let window = NSApp.keyWindow
            ?? NSApp.mainWindow
            ?? NSApp.windows.first(where: { $0.isVisible })
            ?? NSApp.windows.first else {
            return .noWindow
        }
        if Self.socketCommandAllowsInAppFocusMutations() {
            NSApp.activate(ignoringOtherApps: true)
            window.makeKeyAndOrderFront(nil)
        }
        guard let fr = window.firstResponder else {
            return .noFirstResponder
        }
        if let client = fr as? NSTextInputClient {
            client.insertText(text, replacementRange: NSRange(location: NSNotFound, length: 0))
            return .inserted
        }
        fr.insertText(text)
        return .inserted
    }

    // MARK: - debug.textbox.*

    func controlDebugTabManagerAvailable() -> Bool {
        tabManager != nil
    }

    func controlDebugTextBoxInlineFixture(
        target: String?,
        path: String?,
        beforeText: String,
        afterText: String
    ) -> ControlDebugTextBoxFixtureSnapshot? {
        guard let tabManager else { return nil }
        let panel: TerminalPanel?
        if let target, !target.isEmpty {
            panel = resolveTerminalPanel(from: target, tabManager: tabManager)
        } else {
            panel = tabManager.selectedTerminalPanel
        }

        guard let panel else {
            return nil
        }

        let url = path.map { URL(fileURLWithPath: $0).standardizedFileURL }
        _ = panel.installDebugTextBoxInlineFixture(
            localURL: url,
            beforeText: beforeText,
            afterText: afterText
        )
        let textView = panel.textBoxInputView
        return ControlDebugTextBoxFixtureSnapshot(
            surfaceID: panel.id,
            path: url?.path ?? "",
            isTextBoxActive: panel.isTextBoxActive,
            hasTextView: textView != nil,
            textViewHasWindow: textView?.window != nil,
            textViewMatchesPanelWindow: textView?.window === panel.hostedView.window,
            panelText: panel.textBoxContent,
            panelAttachmentCount: panel.textBoxAttachments.count,
            textViewText: textView?.plainText() ?? "",
            textViewAttachmentCount: textView?.inlineAttachments().count ?? 0
        )
    }

    func controlDebugTextBoxInteract(target: String?, action: String) -> ControlDebugTextBoxInteraction? {
        guard let tabManager else { return nil }
        let panel: TerminalPanel?
        if let target, !target.isEmpty {
            panel = resolveTerminalPanel(from: target, tabManager: tabManager)
        } else {
            panel = tabManager.selectedTerminalPanel
        }

        guard let panel,
              let textView = panel.textBoxInputView,
              let window = textView.window else {
            return nil
        }

        if Self.socketCommandAllowsInAppFocusMutations() {
            NSApp.activate(ignoringOtherApps: true)
            window.makeKeyAndOrderFront(nil)
        }
        let state = textView.performControlInteraction(action: action)
        // `performControlInteraction` emits String/Bool/Int leaves only, so the bridge
        // cannot fail; the empty-object fallback keeps the conversion total.
        return ControlDebugTextBoxInteraction(
            surfaceID: panel.id,
            state: JSONValue(foundationObject: state) ?? .object([:])
        )
    }

    // MARK: - debug.command_palette.*

    func controlDebugPostCommandPaletteEvent(
        _ event: ControlDebugCommandPaletteEvent,
        windowID: UUID?
    ) -> Bool {
        let targetWindow: NSWindow?
        if let windowID {
            guard let window = AppDelegate.shared?.mainWindow(for: windowID) else {
                return false
            }
            targetWindow = window
        } else {
            targetWindow = NSApp.keyWindow ?? NSApp.mainWindow
        }
        let name: Notification.Name
        switch event {
        case .toggle:
            name = .commandPaletteToggleRequested
        case .renameTabOpen:
            name = .commandPaletteRenameTabRequested
        case .renameInputInteraction:
            name = .commandPaletteRenameInputInteractionRequested
        case .renameInputDeleteBackward:
            name = .commandPaletteRenameInputDeleteBackwardRequested
        }
        NotificationCenter.default.post(name: name, object: targetWindow)
        return true
    }

    func controlDebugCommandPaletteVisible(windowID: UUID) -> Bool {
        AppDelegate.shared?.isCommandPaletteVisible(windowId: windowID) ?? false
    }

    func controlDebugCommandPaletteSelectionIndex(windowID: UUID) -> Int {
        AppDelegate.shared?.commandPaletteSelectionIndex(windowId: windowID) ?? 0
    }

    func controlDebugCommandPaletteSnapshot(windowID: UUID) -> ControlDebugCommandPaletteSnapshot {
        let snapshot = AppDelegate.shared?.commandPaletteSnapshot(windowId: windowID) ?? .empty
        return ControlDebugCommandPaletteSnapshot(
            query: snapshot.query,
            mode: snapshot.mode,
            results: snapshot.results.map { row in
                ControlDebugCommandPaletteResult(
                    commandID: row.commandId,
                    title: row.title,
                    shortcutHint: row.shortcutHint,
                    trailingLabel: row.trailingLabel,
                    score: row.score
                )
            }
        )
    }

    func controlDebugCommandPaletteRenameInputSelection(
        windowID: UUID
    ) -> ControlDebugRenameInputSelectionResolution {
        guard let window = AppDelegate.shared?.mainWindow(for: windowID) else {
            return .windowNotFound
        }
        guard let editor = window.firstResponder as? NSTextView, editor.isFieldEditor else {
            return .inactive
        }
        let selectedRange = editor.selectedRange()
        let textLength = (editor.string as NSString).length
        return .active(
            location: selectedRange.location,
            length: selectedRange.length,
            textLength: textLength
        )
    }

    func controlDebugCommandPaletteRenameSelectAll(updating enabled: Bool?) -> Bool {
        if let enabled {
            UserDefaults.standard.set(
                enabled,
                forKey: AppCatalogSection().renameSelectsExistingName.userDefaultsKey
            )
        }
        return CommandPaletteSettingsStore(defaults: .standard).renameSelectsAllOnFocus
    }

    // MARK: - debug.command_palette.query_run

    /// Sets the real palette query, returns production registry results
    /// (command ids), and optionally executes a hit through its registered
    /// handler. Does not call `SidebarDockActionInvoker` / store APIs directly.
    ///
    /// Schema:
    /// ```
    /// debug.command_palette.query_run
    /// params: {
    ///   window_id: uuid,
    ///   query: string,              // matching query (commands prefix optional)
    ///   command_id?: string,        // execute when present and in results
    ///   limit?: int                 // 1...100, default 48
    /// }
    /// result: {
    ///   window_id, query, matching_query, visible,
    ///   results:[{command_id,title,score}],
    ///   executed_command_id?, handled?,
    ///   uses: [sidebarDockPaletteRegistryResults, sidebarDockPaletteRegisteredHandler]
    /// }
    /// ```
    func controlDebugCommandPaletteQueryRun(params: [String: JSONValue]) -> ControlCallResult {
        guard let windowID = uuidValue(params["window_id"]) else {
            return .err(code: "invalid_params", message: "Missing or invalid window_id", data: nil)
        }
        guard let window = AppDelegate.shared?.mainWindow(for: windowID) else {
            return .err(
                code: "not_found",
                message: "Window not found",
                data: .object([
                    "window_id": .string(windowID.uuidString),
                ])
            )
        }
        let rawQuery: String = {
            if case let .string(value) = params["query"] { return value }
            return ""
        }()
        let limit: Int = {
            if case let .int(value) = params["limit"] {
                return max(1, min(100, Int(value)))
            }
            if case let .double(value) = params["limit"] {
                return max(1, min(100, Int(value)))
            }
            return 48
        }()
        let executeCommandId: String? = {
            if case let .string(value) = params["command_id"], !value.isEmpty {
                return value
            }
            return nil
        }()

        let matchingQuery = ContentView.sidebarDockPaletteMatchingQuery(rawQuery)
        // Drive the real ContentView query so debug.command_palette.results
        // and the overlay reflect the same production search state.
        let commandsQuery = matchingQuery.isEmpty ? ">" : ">" + matchingQuery
        NotificationCenter.default.post(
            name: .commandPaletteDebugSetQueryRequested,
            object: window,
            userInfo: ["query": commandsQuery]
        )
        // Allow SwiftUI onReceive to apply the query and refresh the snapshot.
        for _ in 0..<8 {
            RunLoop.current.run(mode: .default, before: Date(timeIntervalSinceNow: 0.01))
        }

        let target = SidebarDockActionInvoker.resolveTarget(
            windowId: windowID,
            preferredWindow: window
        )
        let flagEnabled = RightSidebarBetaFeatureSettings.isSidebarDockEnabled()
        let registryResults = ContentView.sidebarDockPaletteRegistryResults(
            query: matchingQuery,
            flagEnabled: flagEnabled,
            target: target,
            limit: limit
        )

        var handled: Bool?
        var executed: String?
        if let executeCommandId {
            guard registryResults.contains(where: { $0.commandId == executeCommandId }) else {
                return .err(
                    code: "not_found",
                    message: "command_id not present in production registry results for query",
                    data: .object([
                        "command_id": .string(executeCommandId),
                        "query": .string(matchingQuery),
                        "result_ids": .array(registryResults.map { .string($0.commandId) }),
                    ])
                )
            }
            // Execute only through the registered-handler factory — never
            // SidebarDockActionInvoker/store directly from this dogfood method.
            let run = ContentView.sidebarDockPaletteRegisteredHandler(
                commandId: executeCommandId,
                windowId: windowID,
                preferredWindow: window
            )
            handled = run()
            executed = executeCommandId
        }

        let visible = controlDebugCommandPaletteVisible(windowID: windowID)
        let snapshot = controlDebugCommandPaletteSnapshot(windowID: windowID)
        let rows: [JSONValue] = registryResults.map { row in
            .object([
                "command_id": .string(row.commandId),
                "title": .string(row.title),
                "score": .int(Int64(row.score)),
            ])
        }
        var payload: [String: JSONValue] = [
            "window_id": .string(windowID.uuidString),
            "query": .string(matchingQuery),
            "matching_query": .string(matchingQuery),
            "palette_query": .string(snapshot.query),
            "visible": .bool(visible),
            "results": .array(rows),
            "result_count": .int(Int64(registryResults.count)),
            "uses": .array([
                .string("sidebarDockPaletteRegistryResults"),
                .string("sidebarDockPaletteRegisteredHandler"),
            ]),
        ]
        if let executed {
            payload["executed_command_id"] = .string(executed)
        }
        if let handled {
            payload["handled"] = .bool(handled)
        }
        return .ok(.object(payload))
    }

    private func uuidValue(_ value: JSONValue?) -> UUID? {
        guard case let .string(raw) = value else { return nil }
        return UUID(uuidString: raw)
    }

    // MARK: - debug.browser.*

    func controlDebugFocusedBrowserAddressBarSurfaceID() -> UUID? {
        AppDelegate.shared?.focusedBrowserAddressBarPanelId()
    }

    func controlDebugBrowserFavicon(params: [String: JSONValue]) -> ControlCallResult {
        // Documented passthrough: panel resolution lives in the still-shared
        // `v2BrowserWithPanel` (the whole `browser.*` domain's resolver), so
        // the legacy `[String: Any]` params are reconstructed exactly
        // (`foundationObject` is the inverse of the dispatcher's bridging) and
        // the favicon body runs verbatim.
        let result = v2BrowserWithPanel(params: params.mapValues(\.foundationObject)) { workspaceId, surfaceId, browserPanel in
            let pngData = browserPanel.faviconPNGData
            return .ok([
                "workspace_id": workspaceId.uuidString,
                "workspace_ref": v2Ref(kind: .workspace, uuid: workspaceId),
                "surface_id": surfaceId.uuidString,
                "surface_ref": v2Ref(kind: .surface, uuid: surfaceId),
                "has_favicon": pngData != nil,
                "png_base64": pngData?.base64EncodedString() ?? "",
                "current_url": v2OrNull(browserPanel.currentURL?.absoluteString)
            ])
        }
        switch result {
        case let .ok(payload):
            return .ok(JSONValue(foundationObject: payload) ?? .object([:]))
        case let .err(code, message, data):
            return .err(
                code: code,
                message: message,
                data: data.flatMap { JSONValue(foundationObject: $0) }
            )
        }
    }

    // MARK: - debug.right_sidebar.focus / debug.sidebar.visible

    func controlDebugRightSidebarFocus(
        modeName: String?,
        windowID: UUID?,
        focusFirstItem: Bool
    ) -> ControlDebugRightSidebarFocusResolution {
        let resolvedModeName = modeName ?? RightSidebarMode.dock.rawValue
        guard let mode = RightSidebarMode(rawValue: resolvedModeName) else {
            return .invalidMode(resolvedModeName)
        }
        let preferredWindow: NSWindow?
        if let windowID {
            preferredWindow = AppDelegate.shared?.mainWindow(for: windowID)
            guard preferredWindow != nil else {
                return .windowNotFound
            }
        } else {
            preferredWindow = NSApp.keyWindow ?? NSApp.mainWindow
        }
        let result = AppDelegate.shared?.debugRevealRightSidebarInActiveMainWindow(
            mode: mode,
            focusFirstItem: focusFirstItem,
            preferredWindow: preferredWindow
        )
        return .revealed(ControlDebugRightSidebarFocusState(
            revealed: result?.revealed ?? false,
            focusApplied: result?.focusApplied ?? false,
            contextFound: result?.contextFound ?? false,
            stateFound: result?.stateFound ?? false,
            visible: result?.visible ?? false,
            activeMode: result?.activeMode,
            mode: mode.rawValue
        ))
    }

    func controlDebugSidebarVisibility(windowID: UUID) -> Bool? {
        AppDelegate.shared?.sidebarVisibility(windowId: windowID)
    }

    // MARK: - debug.terminal.simulate_file_drop

    func controlDebugSimulateTerminalFileDrop(
        surfaceArgument: String,
        paths: [String],
        route: ControlDebugFileDropRoute,
        payloadKind: ControlDebugFileDropPayloadKind
    ) -> ControlDebugFileDropResolution {
        guard let tabManager,
              let panel = resolveTerminalPanel(from: surfaceArgument, tabManager: tabManager) else {
            return .panelNotFound
        }

        switch route {
        case .terminal:
            let handled = panel.hostedView.debugSimulateFileDrop(
                paths: paths,
                asImageData: payloadKind == .imageData
            )
            return .terminalDrop(handled: handled)
        case .textDestination:
            guard payloadKind == .fileURLs else {
                return .imageDataRequiresTerminalRoute
            }
            guard let workspace = tabManager.tabs.first(where: { $0.id == panel.workspaceId }) else {
                return .workspaceNotFound(workspaceID: panel.workspaceId)
            }
            let urls = paths.map { URL(fileURLWithPath: $0).standardizedFileURL }
            let handled = FileDropTextDropController.performTerminalFileDrop(
                workspace: workspace,
                panelId: panel.id,
                hostedView: panel.hostedView,
                urls: urls,
                window: panel.surface.uiWindow
            )
            return .textDestinationDrop(handled: handled)
        }
    }

    // MARK: - debug.portal.stats

    func controlDebugPortalStats() -> JSONValue? {
        JSONValue(foundationObject: TerminalWindowPortalRegistry.debugPortalStats())
    }

    func controlDebugRemoteTmuxSizingSettled() -> JSONValue? {
        JSONValue(foundationObject: remoteTmuxSizingSettlementPayload())
    }
#endif
}
