import Foundation
import Testing
import CmuxSettings

#if canImport(cmux_DEV)
@testable import cmux_DEV
#elseif canImport(cmux)
@testable import cmux
#endif

/// Pure-plan coverage for Auto Workspace Group Mode (AX-GDOCK-AUTO-WORKSPACE-GROUP-MODE).
@Suite struct GdockAutoWorkspaceGroupReconcilerTests {
    private let repoA = "manaflow-ai/cmux"
    private let repoB = "stokd-cloud/ghostty-dock"

    private func slugMap(_ pairs: [(String, String)]) -> (String) -> String? {
        let map = Dictionary(uniqueKeysWithValues: pairs)
        return { map[$0] }
    }

    @Test func createsGroupNamedOwnerRepoForMembersSharingSlug() {
        let w1 = UUID()
        let w2 = UUID()
        let plan = GdockAutoWorkspaceGroupReconciler.plan(
            workspaces: [
                .init(id: w1, currentDirectory: "/tmp/a", groupId: nil, isGroupAnchor: false),
                .init(id: w2, currentDirectory: "/tmp/a/sub", groupId: nil, isGroupAnchor: false),
            ],
            groups: [],
            slugForDirectory: slugMap([
                ("/tmp/a", repoA),
                ("/tmp/a/sub", repoA),
            ])
        )
        #expect(plan == [
            .createGroup(name: repoA, memberWorkspaceIds: [w1, w2]),
        ])
    }

    @Test func addsToExistingGroupWhenNameMatchesSlug() {
        let groupId = UUID()
        let w1 = UUID()
        let plan = GdockAutoWorkspaceGroupReconciler.plan(
            workspaces: [
                .init(id: w1, currentDirectory: "/tmp/a", groupId: nil, isGroupAnchor: false),
            ],
            groups: [
                .init(id: groupId, name: repoA),
            ],
            slugForDirectory: slugMap([("/tmp/a", repoA)])
        )
        #expect(plan == [
            .addToGroup(workspaceId: w1, groupId: groupId),
        ])
    }

    @Test func alreadyCorrectMembershipIsNoOp() {
        let groupId = UUID()
        let w1 = UUID()
        let plan = GdockAutoWorkspaceGroupReconciler.plan(
            workspaces: [
                .init(id: w1, currentDirectory: "/tmp/a", groupId: groupId, isGroupAnchor: false),
            ],
            groups: [
                .init(id: groupId, name: repoA),
            ],
            slugForDirectory: slugMap([("/tmp/a", repoA)])
        )
        #expect(plan.isEmpty)
    }

    @Test func neverPlansMovesForGroupAnchors() {
        let groupId = UUID()
        let anchor = UUID()
        let member = UUID()
        let plan = GdockAutoWorkspaceGroupReconciler.plan(
            workspaces: [
                .init(id: anchor, currentDirectory: "/tmp/b", groupId: groupId, isGroupAnchor: true),
                .init(id: member, currentDirectory: "/tmp/b", groupId: nil, isGroupAnchor: false),
            ],
            groups: [
                .init(id: groupId, name: "Manual Group"),
            ],
            slugForDirectory: slugMap([("/tmp/b", repoB)])
        )
        #expect(plan == [
            .createGroup(name: repoB, memberWorkspaceIds: [member]),
        ])
        #expect(!plan.contains(where: {
            if case .addToGroup(let id, _) = $0 { return id == anchor }
            if case .createGroup(_, let members) = $0 { return members.contains(anchor) }
            return false
        }))
    }

    @Test func workspacesWithoutGitHubSlugAreIgnored() {
        let w1 = UUID()
        let plan = GdockAutoWorkspaceGroupReconciler.plan(
            workspaces: [
                .init(id: w1, currentDirectory: "/tmp/not-a-repo", groupId: nil, isGroupAnchor: false),
            ],
            groups: [],
            slugForDirectory: { _ in nil }
        )
        #expect(plan.isEmpty)
    }

    @Test func movesMemberFromWrongGroupToSlugGroup() {
        let wrong = UUID()
        let right = UUID()
        let w1 = UUID()
        let plan = GdockAutoWorkspaceGroupReconciler.plan(
            workspaces: [
                .init(id: w1, currentDirectory: "/tmp/a", groupId: wrong, isGroupAnchor: false),
            ],
            groups: [
                .init(id: wrong, name: "Other"),
                .init(id: right, name: repoA),
            ],
            slugForDirectory: slugMap([("/tmp/a", repoA)])
        )
        #expect(plan == [
            .addToGroup(workspaceId: w1, groupId: right),
        ])
    }

    @Test func settingCatalogKeyUsesGdockPrefix() {
        let key = SettingCatalog().gdock.autoWorkspaceGroupMode
        #expect(key.id == "gdock.autoWorkspaceGroupMode")
        #expect(key.userDefaultsKey == "gdock.autoWorkspaceGroupMode")
        #expect(key.defaultValue == false)
    }

    @Test func paletteToggleUsesGdockPrefixedCommandId() throws {
        let descriptor = try #require(
            CommandPaletteSettingsToggleCommands.descriptor(
                commandId: "palette.toggleSetting.gdock.autoWorkspaceGroupMode"
            )
        )
        #expect(descriptor.settingsKey == "gdock.autoWorkspaceGroupMode")
        #expect(descriptor.commandId.hasPrefix("palette.toggleSetting.gdock."))
    }
}
