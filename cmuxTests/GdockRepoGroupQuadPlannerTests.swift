import Foundation
import Testing

#if canImport(cmux_DEV)
@testable import cmux_DEV
#elseif canImport(cmux)
@testable import cmux
#endif

/// The stokd quad a repository group header launches (AC5 / AC6, and AC-B of
/// AX-GDOCK-REPO-COMMAND-SURFACE).
@Suite struct GdockRepoGroupQuadPlannerTests {
    private typealias Planner = GdockRepoGroupQuadPlanner
    private let repo = "stokd-cloud/gdock"
    private let directory = "/opt/worktrees/stokd-cloud/gdock/main"

    @Test func plansTheFourStokdSurfacesInQuadrantOrder() {
        let plan = Planner.plan(groupName: repo, directory: directory)

        #expect(plan?.map(\.command) == [
            "stokd worktree",
            "stokd project",
            "stokd task",
            "stokd todo",
        ])
        #expect(plan?.count == 4)
        #expect(plan?.allSatisfy { $0.directory == directory } == true)
    }

    @Test func handNamedGroupPlansNothing() {
        #expect(Planner.plan(groupName: "Scratch", directory: directory) == nil)
        #expect(Planner.plan(groupName: "owner/repo/extra", directory: directory) == nil)
    }

    @Test func blankDirectoryPlansNothing() {
        #expect(Planner.plan(groupName: repo, directory: "") == nil)
        #expect(Planner.plan(groupName: repo, directory: "   ") == nil)
    }

    /// Re-activating a group that already shows the quad re-focuses rather than
    /// dealing a second set of shells.
    @Test func alreadyQuaddedGroupPlansNothing() {
        let plan = Planner.plan(
            groupName: repo,
            directory: directory,
            existingCommands: [
                "stokd worktree",
                "stokd project",
                "stokd task",
                "stokd todo",
            ]
        )

        #expect(plan == nil)
    }

    /// A workspace showing only some of the surfaces is not "already quadded" —
    /// the user should still get the full set.
    @Test func partiallyQuaddedGroupStillPlans() {
        let plan = Planner.plan(
            groupName: repo,
            directory: directory,
            existingCommands: ["stokd worktree", "stokd task"]
        )

        #expect(plan?.count == 4)
    }

    @Test func overrideReplacesDefaultsInQuadrantOrder() {
        let plan = Planner.plan(
            groupName: repo,
            directory: directory,
            overrideCommands: ["a", "b", "c", "d"]
        )

        #expect(plan?.map(\.command) == ["a", "b", "c", "d"])
    }

    /// A half-filled override is a misconfiguration. Falling back to the
    /// defaults beats launching a quad with two blank panes.
    @Test func incompleteOverrideFallsBackToDefaults() {
        for override in [["only-one"], ["a", "b"], ["a", "b", "c", "d", "e"], ["a", "", "c", "d"]] {
            let plan = Planner.plan(
                groupName: repo,
                directory: directory,
                overrideCommands: override
            )
            #expect(plan?.map(\.command) == Planner.defaultCommands, "override \(override)")
        }
    }

    @Test func trimsDirectoryAndOverrideWhitespace() {
        let plan = Planner.plan(
            groupName: repo,
            directory: "  \(directory)  ",
            overrideCommands: ["  a  ", "b", "c", "d"]
        )

        #expect(plan?.first?.directory == directory)
        #expect(plan?.first?.command == "a")
    }
}
