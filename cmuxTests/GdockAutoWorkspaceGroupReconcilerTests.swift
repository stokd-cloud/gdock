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

    // MARK: - Per-panel extraction

    private func panel(_ id: UUID, _ directory: String)
        -> GdockAutoWorkspaceGroupReconciler.PanelSnapshot {
        .init(id: id, currentDirectory: directory)
    }

    /// The reported defect: `cd`-ing one panel into another repo moved the whole
    /// workspace — dragging every unrelated sibling panel into the new group.
    @Test func extractsOnlyTheRetargetedPanelFromAGroupedWorkspace() {
        let groupId = UUID()
        let w1 = UUID()
        let stays = UUID()
        let moves = UUID()
        let plan = GdockAutoWorkspaceGroupReconciler.plan(
            workspaces: [
                .init(
                    id: w1,
                    // Workspace cwd already follows the retargeted panel; the group
                    // name is what pins the workspace's home repo.
                    currentDirectory: "/tmp/b",
                    groupId: groupId,
                    isGroupAnchor: false,
                    panels: [panel(stays, "/tmp/a"), panel(moves, "/tmp/b")]
                ),
            ],
            groups: [.init(id: groupId, name: repoA)],
            slugForDirectory: slugMap([("/tmp/a", repoA), ("/tmp/b", repoB)])
        )
        #expect(plan == [
            .extractPanel(panelId: moves, fromWorkspaceId: w1, slug: repoB),
        ])
        // The workspace itself must not be re-grouped.
        #expect(!plan.contains { if case .addToGroup = $0 { return true } else { return false } })
    }

    @Test func extractsEachDivergentPanelSeparately() {
        let groupId = UUID()
        let w1 = UUID()
        let stays = UUID()
        let movesB = UUID()
        let movesC = UUID()
        let repoC = "third/repo"
        let plan = GdockAutoWorkspaceGroupReconciler.plan(
            workspaces: [
                .init(
                    id: w1,
                    currentDirectory: "/tmp/a",
                    groupId: groupId,
                    isGroupAnchor: false,
                    panels: [panel(stays, "/tmp/a"), panel(movesB, "/tmp/b"), panel(movesC, "/tmp/c")]
                ),
            ],
            groups: [.init(id: groupId, name: repoA)],
            slugForDirectory: slugMap([("/tmp/a", repoA), ("/tmp/b", repoB), ("/tmp/c", repoC)])
        )
        #expect(plan == [
            .extractPanel(panelId: movesB, fromWorkspaceId: w1, slug: repoB),
            .extractPanel(panelId: movesC, fromWorkspaceId: w1, slug: repoC),
        ])
    }

    @Test func singlePanelWorkspaceStillMovesWholesale() {
        let groupId = UUID()
        let target = UUID()
        let w1 = UUID()
        let only = UUID()
        let plan = GdockAutoWorkspaceGroupReconciler.plan(
            workspaces: [
                .init(
                    id: w1,
                    currentDirectory: "/tmp/b",
                    groupId: groupId,
                    isGroupAnchor: false,
                    panels: [panel(only, "/tmp/b")]
                ),
            ],
            groups: [.init(id: groupId, name: repoA), .init(id: target, name: repoB)],
            slugForDirectory: slugMap([("/tmp/b", repoB)])
        )
        #expect(plan == [.addToGroup(workspaceId: w1, groupId: target)])
    }

    /// Every panel moving means the workspace genuinely relocated; extracting
    /// each one would empty it panel by panel.
    @Test func allPanelsDivergingMovesTheWholeWorkspace() {
        let groupId = UUID()
        let target = UUID()
        let w1 = UUID()
        let plan = GdockAutoWorkspaceGroupReconciler.plan(
            workspaces: [
                .init(
                    id: w1,
                    currentDirectory: "/tmp/b",
                    groupId: groupId,
                    isGroupAnchor: false,
                    panels: [panel(UUID(), "/tmp/b"), panel(UUID(), "/tmp/b")]
                ),
            ],
            groups: [.init(id: groupId, name: repoA), .init(id: target, name: repoB)],
            slugForDirectory: slugMap([("/tmp/b", repoB)])
        )
        #expect(plan == [.addToGroup(workspaceId: w1, groupId: target)])
    }

    /// A hand-named group carries no repo identity, so panel-level extraction
    /// must not fire off it.
    @Test func manuallyNamedGroupDoesNotDriveExtraction() {
        let groupId = UUID()
        let w1 = UUID()
        let plan = GdockAutoWorkspaceGroupReconciler.plan(
            workspaces: [
                .init(
                    id: w1,
                    currentDirectory: "/tmp/a",
                    groupId: groupId,
                    isGroupAnchor: false,
                    panels: [panel(UUID(), "/tmp/a"), panel(UUID(), "/tmp/b")]
                ),
            ],
            groups: [.init(id: groupId, name: "My Stuff")],
            slugForDirectory: slugMap([("/tmp/a", repoA), ("/tmp/b", repoB)])
        )
        #expect(!plan.contains { if case .extractPanel = $0 { return true } else { return false } })
    }

    @Test func panelsMatchingTheHomeSlugAreLeftAlone() {
        let groupId = UUID()
        let w1 = UUID()
        let plan = GdockAutoWorkspaceGroupReconciler.plan(
            workspaces: [
                .init(
                    id: w1,
                    currentDirectory: "/tmp/a",
                    groupId: groupId,
                    isGroupAnchor: false,
                    panels: [panel(UUID(), "/tmp/a"), panel(UUID(), "/tmp/a/sub")]
                ),
            ],
            groups: [.init(id: groupId, name: repoA)],
            slugForDirectory: slugMap([("/tmp/a", repoA), ("/tmp/a/sub", repoA)])
        )
        #expect(plan.isEmpty)
    }

    // MARK: - Group anchors

    /// The reported defect: a workspace promoted to (or created as) its group's
    /// anchor fell out of Auto Workspace Group Mode entirely — `cd`-ing into
    /// another repo left it sitting in the old repo's group forever.
    @Test func soleAnchorRenamesItsGroupWhenItsRepoChanges() {
        let groupId = UUID()
        let anchor = UUID()
        let plan = GdockAutoWorkspaceGroupReconciler.plan(
            workspaces: [
                .init(
                    id: anchor,
                    currentDirectory: "/tmp/b",
                    groupId: groupId,
                    isGroupAnchor: true,
                    panels: [panel(UUID(), "/tmp/b")]
                ),
            ],
            groups: [.init(id: groupId, name: repoA)],
            slugForDirectory: slugMap([("/tmp/b", repoB)])
        )
        #expect(plan == [.renameGroup(groupId: groupId, name: repoB)])
    }

    /// Two groups may not carry the same repository slug, so the rename yields
    /// to the group that already owns the name.
    @Test func soleAnchorDoesNotRenameOntoAnExistingSlugGroup() {
        let groupId = UUID()
        let existing = UUID()
        let anchor = UUID()
        let plan = GdockAutoWorkspaceGroupReconciler.plan(
            workspaces: [
                .init(
                    id: anchor,
                    currentDirectory: "/tmp/b",
                    groupId: groupId,
                    isGroupAnchor: true,
                    panels: [panel(UUID(), "/tmp/b")]
                ),
            ],
            groups: [.init(id: groupId, name: repoA), .init(id: existing, name: repoB)],
            slugForDirectory: slugMap([("/tmp/b", repoB)])
        )
        #expect(!plan.contains { if case .renameGroup = $0 { return true } else { return false } })
    }

    /// An anchor with siblings keeps its group; only the retargeted panel moves.
    @Test func anchorExtractsOnlyTheRetargetedPanel() {
        let groupId = UUID()
        let anchor = UUID()
        let member = UUID()
        let stays = UUID()
        let moves = UUID()
        let plan = GdockAutoWorkspaceGroupReconciler.plan(
            workspaces: [
                .init(
                    id: anchor,
                    currentDirectory: "/tmp/b",
                    groupId: groupId,
                    isGroupAnchor: true,
                    panels: [panel(stays, "/tmp/a"), panel(moves, "/tmp/b")]
                ),
                .init(
                    id: member,
                    currentDirectory: "/tmp/a",
                    groupId: groupId,
                    isGroupAnchor: false,
                    panels: [panel(UUID(), "/tmp/a")]
                ),
            ],
            groups: [.init(id: groupId, name: repoA)],
            slugForDirectory: slugMap([("/tmp/a", repoA), ("/tmp/b", repoB)])
        )
        #expect(plan == [.extractPanel(panelId: moves, fromWorkspaceId: anchor, slug: repoB)])
    }

    /// A group header must keep at least one panel, so the last divergent panel
    /// of an anchor stays put even when every panel moved.
    @Test func anchorExtractionNeverEmptiesTheWorkspace() {
        let groupId = UUID()
        let anchor = UUID()
        let member = UUID()
        let first = UUID()
        let second = UUID()
        let plan = GdockAutoWorkspaceGroupReconciler.plan(
            workspaces: [
                .init(
                    id: anchor,
                    currentDirectory: "/tmp/b",
                    groupId: groupId,
                    isGroupAnchor: true,
                    panels: [panel(first, "/tmp/b"), panel(second, "/tmp/b")]
                ),
                .init(
                    id: member,
                    currentDirectory: "/tmp/a",
                    groupId: groupId,
                    isGroupAnchor: false,
                    panels: [panel(UUID(), "/tmp/a")]
                ),
            ],
            groups: [.init(id: groupId, name: repoA)],
            slugForDirectory: slugMap([("/tmp/a", repoA), ("/tmp/b", repoB)])
        )
        #expect(plan == [.extractPanel(panelId: first, fromWorkspaceId: anchor, slug: repoB)])
    }

    @Test func groupNameIsReadAsSlugOnlyWhenItLooksLikeOne() {
        #expect(GdockAutoWorkspaceGroupReconciler.repositorySlug(from: "owner/repo") == "owner/repo")
        #expect(GdockAutoWorkspaceGroupReconciler.repositorySlug(from: "  owner/repo  ") == "owner/repo")
        #expect(GdockAutoWorkspaceGroupReconciler.repositorySlug(from: "My Stuff") == nil)
        #expect(GdockAutoWorkspaceGroupReconciler.repositorySlug(from: "owner") == nil)
        #expect(GdockAutoWorkspaceGroupReconciler.repositorySlug(from: "a/b/c") == nil)
        #expect(GdockAutoWorkspaceGroupReconciler.repositorySlug(from: "owner/") == nil)
        #expect(GdockAutoWorkspaceGroupReconciler.repositorySlug(from: "own er/repo") == nil)
    }

    @Test func settingCatalogKeyUsesGdockPrefix() {
        let key = SettingCatalog().gdock.autoWorkspaceGroupMode
        #expect(key.id == "gdock.autoWorkspaceGroupMode")
        #expect(key.userDefaultsKey == "gdock.autoWorkspaceGroupMode")
        #expect(key.defaultValue == true)
    }

    @Test func skipsGridPlaceholderPanelsWhenExtracting() {
        let groupId = UUID()
        let workspaceId = UUID()
        let home = UUID()
        let placeholder = UUID()
        let plan = GdockAutoWorkspaceGroupReconciler.plan(
            workspaces: [
                .init(
                    id: workspaceId,
                    currentDirectory: "/tmp/a",
                    groupId: groupId,
                    isGroupAnchor: false,
                    panels: [
                        .init(id: home, currentDirectory: "/tmp/a"),
                        .init(
                            id: placeholder,
                            currentDirectory: "/tmp/b",
                            isGridPlaceholder: true
                        ),
                    ]
                ),
            ],
            groups: [
                .init(id: groupId, name: repoA),
            ],
            slugForDirectory: slugMap([
                ("/tmp/a", repoA),
                ("/tmp/b", repoB),
            ])
        )
        #expect(plan.isEmpty)
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
