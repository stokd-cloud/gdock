import Foundation
import Testing

#if canImport(cmux_DEV)
@testable import cmux_DEV
#elseif canImport(cmux)
@testable import cmux
#endif

/// A cycler row identifies its provider from the agent status keys the workspace
/// already tracks (AX-GDOCK-SESSION-CYCLER).
@Suite struct GdockSessionAgentBadgeTests {
    private typealias Badge = GdockSessionAgentBadge

    @Test func claudeCodeStatusKeyResolvesToTheClaudeMark() {
        #expect(Badge.agent(forStatusKey: "claude_code") == .claude)
        #expect(Badge.badge(forStatusKeys: ["claude_code"])?.assetName == "AgentIcons/Claude")
        #expect(Badge.badge(forStatusKeys: ["claude_code"])?.displayName == SessionAgent.claude.displayName)
    }

    @Test func statusKeysThatAlreadyMatchSessionAgentsResolveDirectly() {
        #expect(Badge.badge(forStatusKeys: ["codex"])?.assetName == "AgentIcons/Codex")
        #expect(Badge.badge(forStatusKeys: ["grok"])?.assetName == "AgentIcons/Grok")
        #expect(Badge.badge(forStatusKeys: ["hermes-agent"])?.assetName == "AgentIcons/HermesAgent")
    }

    /// A key gdock cannot name is still a running session; it just has no art.
    @Test func unknownStatusKeyStillProducesABadgeWithoutArt() {
        let badge = Badge.badge(forStatusKeys: ["some-future-agent"])

        #expect(badge?.assetName == nil)
        #expect(badge?.displayName == "some-future-agent")
    }

    @Test func multipleStatusKeysResolveDeterministically() {
        let first = Badge.badge(forStatusKeys: ["codex", "claude_code"])
        let second = Badge.badge(forStatusKeys: ["claude_code", "codex"])

        #expect(first == second)
        #expect(first?.assetName == "AgentIcons/Claude")
    }

    @Test func noStatusKeysProducesNoBadge() {
        #expect(Badge.badge(forStatusKeys: []) == nil)
    }
}
