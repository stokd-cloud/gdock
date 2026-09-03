import CMUXAgentLaunch
import Foundation
import Testing

#if canImport(cmux_DEV)
@testable import cmux_DEV
#elseif canImport(cmux)
@testable import cmux
#endif

/// Reduces Feed workstream telemetry into the prompts one agent session has
/// been given (AX-GDOCK-PROMPT-HISTORY).
///
/// Everything here is a pure function over value inputs: the overlay renders
/// below a lazy container, where holding a store reference is what reintroduces
/// the spin loop (CLAUDE.md; cmux issue 2586). The session lookup is injected
/// so the rules are testable without the on-disk hook-session stores.
@Suite struct GdockPromptHistoryCollectorTests {
    private typealias Collector = GdockPromptHistoryCollector
    private typealias Focus = GdockPromptHistoryFocus
    private typealias Target = GdockPromptHistoryTarget

    private static let workspaceId = UUID(uuidString: "11111111-1111-1111-1111-111111111111")!
    private static let panelId = UUID(uuidString: "22222222-2222-2222-2222-222222222222")!
    private static let otherPanelId = UUID(uuidString: "33333333-3333-3333-3333-333333333333")!

    private static func focus(directory: String? = "/repo/gdock") -> Focus {
        Focus(workspaceId: workspaceId, panelId: panelId, directory: directory)
    }

    private static func item(
        workstreamId: String = "claude-focused",
        kind: WorkstreamKind = .userPrompt,
        payload: WorkstreamPayload? = nil,
        cwd: String? = "/repo/gdock",
        secondsAgo: TimeInterval
    ) -> WorkstreamItem {
        WorkstreamItem(
            workstreamId: workstreamId,
            source: .claude,
            kind: kind,
            createdAt: Date(timeIntervalSince1970: 1_788_120_000 - secondsAgo),
            cwd: cwd,
            payload: payload ?? .userPrompt(text: "prompt \(Int(secondsAgo))")
        )
    }

    /// Resolves only `claude-focused` onto the focused pane; everything else is
    /// either another pane or unknown to the hook stores.
    private static func resolve(_ workstreamId: String) -> Target? {
        switch workstreamId {
        case "claude-focused":
            return Target(workspaceId: workspaceId, surfaceId: panelId)
        case "claude-other-pane":
            return Target(workspaceId: workspaceId, surfaceId: otherPanelId)
        default:
            return nil
        }
    }

    // MARK: - Scoping

    @Test func keepsOnlyUserPromptsFromTheFocusedSession() {
        let entries = Collector.entries(
            items: [
                Self.item(secondsAgo: 300),
                Self.item(
                    kind: .toolUse,
                    payload: .toolUse(toolName: "Bash", toolInputJSON: "{}"),
                    secondsAgo: 200
                ),
                Self.item(
                    kind: .assistantMessage,
                    payload: .assistantMessage(text: "done"),
                    secondsAgo: 100
                ),
                Self.item(workstreamId: "claude-other-pane", secondsAgo: 50),
            ],
            focus: Self.focus(),
            resolveTarget: Self.resolve
        )

        #expect(entries.map(\.text) == ["prompt 300"])
    }

    @Test func ordersOldestFirstSoTheNewestPromptRendersAtTheBottom() {
        let entries = Collector.entries(
            items: [
                Self.item(secondsAgo: 60),
                Self.item(secondsAgo: 600),
                Self.item(secondsAgo: 180),
            ],
            focus: Self.focus(),
            resolveTarget: Self.resolve
        )

        #expect(entries.map(\.text) == ["prompt 600", "prompt 180", "prompt 60"])
        #expect(entries.last?.submittedAt == Date(timeIntervalSince1970: 1_788_120_000 - 60))
    }

    /// A session the hook stores never registered still belongs to the pane when
    /// it ran in the pane's directory — otherwise the overlay is empty for every
    /// agent that does not write a hook-session file.
    @Test func fallsBackToTheWorkingDirectoryForUnresolvableSessions() {
        let entries = Collector.entries(
            items: [
                Self.item(workstreamId: "codex-unregistered", secondsAgo: 120),
                Self.item(workstreamId: "codex-elsewhere", cwd: "/repo/other", secondsAgo: 90),
            ],
            focus: Self.focus(),
            resolveTarget: Self.resolve
        )

        #expect(entries.map(\.text) == ["prompt 120"])
    }

    /// A session that resolves to a *different* pane is never rescued by a
    /// matching directory: two panes in one checkout is the normal case.
    @Test func resolvedOtherPaneSessionsAreNotRescuedByMatchingDirectory() {
        let entries = Collector.entries(
            items: [Self.item(workstreamId: "claude-other-pane", secondsAgo: 30)],
            focus: Self.focus(),
            resolveTarget: Self.resolve
        )

        #expect(entries.isEmpty)
    }

    // MARK: - Text

    @Test func collapsesWhitespaceAndDropsEmptyPrompts() {
        let entries = Collector.entries(
            items: [
                Self.item(payload: .userPrompt(text: "  fix\n  the   build \n"), secondsAgo: 200),
                Self.item(payload: .userPrompt(text: "   \n  "), secondsAgo: 100),
            ],
            focus: Self.focus(),
            resolveTarget: Self.resolve
        )

        #expect(entries.map(\.text) == ["fix the build"])
    }

    @Test func withoutAFocusedDirectoryOnlyResolvedSessionsCount() {
        let entries = Collector.entries(
            items: [
                Self.item(secondsAgo: 200),
                Self.item(workstreamId: "codex-unregistered", secondsAgo: 100),
            ],
            focus: Self.focus(directory: nil),
            resolveTarget: Self.resolve
        )

        #expect(entries.map(\.text) == ["prompt 200"])
    }
}
