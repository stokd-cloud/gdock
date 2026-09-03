import Foundation
import Testing

#if canImport(cmux_DEV)
@testable import cmux_DEV
#elseif canImport(cmux)
@testable import cmux
#endif

/// Accordion collapse of repository workspace groups (AC2 / AC3, and AC-B of
/// AX-GDOCK-REPO-COMMAND-SURFACE).
@Suite struct GdockRepoGroupAccordionReconcilerTests {
    private typealias Reconciler = GdockRepoGroupAccordionReconciler
    private typealias Group = GdockRepoGroupAccordionReconciler.GroupSnapshot

    private func group(
        _ name: String,
        collapsed: Bool = false,
        pinned: Bool = false,
        id: UUID = UUID()
    ) -> Group {
        Group(id: id, name: name, isCollapsed: collapsed, isPinned: pinned)
    }

    @Test func expandsSelectedRepoGroupAndCollapsesOtherRepoGroups() {
        let a = group("stokd-cloud/gdock", collapsed: true)
        let b = group("manaflow-ai/cmux", collapsed: false)

        let plan = Reconciler.plan(groups: [a, b], selectedGroupId: a.id, isEnabled: true)

        #expect(plan == [.expand(groupId: a.id), .collapse(groupId: b.id)])
    }

    /// Only genuine state changes are planned, so re-selecting inside the same
    /// group does nothing.
    @Test func alreadyCorrectStateIsANoOp() {
        let a = group("stokd-cloud/gdock", collapsed: false)
        let b = group("manaflow-ai/cmux", collapsed: true)

        let plan = Reconciler.plan(groups: [a, b], selectedGroupId: a.id, isEnabled: true)

        #expect(plan.isEmpty)
    }

    @Test func selectingInsideAHandNamedGroupPlansNothing() {
        let scratch = group("Scratch")
        let repo = group("stokd-cloud/gdock")

        let plan = Reconciler.plan(groups: [scratch, repo], selectedGroupId: scratch.id, isEnabled: true)

        #expect(plan.isEmpty)
    }

    /// A hand-named group is inert in both directions: it is never collapsed to
    /// make room for a repo group either.
    @Test func handNamedGroupsAreNeverCollapsed() {
        let repo = group("stokd-cloud/gdock", collapsed: true)
        let scratch = group("Scratch", collapsed: false)

        let plan = Reconciler.plan(groups: [repo, scratch], selectedGroupId: repo.id, isEnabled: true)

        #expect(plan == [.expand(groupId: repo.id)])
    }

    /// Pinning orders a group above the unpinned tier; it does not keep the
    /// group open. A pinned repo group collapses like any other when the
    /// selection moves to a different repo.
    @Test func pinnedRepoGroupsCollapseLikeAnyOther() {
        let a = group("stokd-cloud/gdock", collapsed: true)
        let pinned = group("manaflow-ai/cmux", collapsed: false, pinned: true)

        let plan = Reconciler.plan(groups: [a, pinned], selectedGroupId: a.id, isEnabled: true)

        #expect(plan == [.expand(groupId: a.id), .collapse(groupId: pinned.id)])
    }

    /// The pinned group stays open while it owns the selection, so pinning a
    /// repo and working inside it never fights the accordion.
    @Test func aPinnedRepoGroupStaysOpenWhileSelected() {
        let pinned = group("manaflow-ai/cmux", collapsed: false, pinned: true)
        let other = group("stokd-cloud/gdock", collapsed: false)

        let plan = Reconciler.plan(groups: [pinned, other], selectedGroupId: pinned.id, isEnabled: true)

        #expect(plan == [.collapse(groupId: other.id)])
    }

    /// A pinned hand-named group is still a hand-named group: never touched.
    @Test func pinnedHandNamedGroupsAreStillNeverCollapsed() {
        let a = group("stokd-cloud/gdock", collapsed: true)
        let scratch = group("Scratch", collapsed: false, pinned: true)

        let plan = Reconciler.plan(groups: [a, scratch], selectedGroupId: a.id, isEnabled: true)

        #expect(plan == [.expand(groupId: a.id)])
    }

    @Test func ungroupedSelectionPlansNothing() {
        let a = group("stokd-cloud/gdock")
        let b = group("manaflow-ai/cmux")

        let plan = Reconciler.plan(groups: [a, b], selectedGroupId: nil, isEnabled: true)

        #expect(plan.isEmpty)
    }

    @Test func disabledSettingPlansNothing() {
        let a = group("stokd-cloud/gdock", collapsed: true)
        let b = group("manaflow-ai/cmux", collapsed: false)

        let plan = Reconciler.plan(groups: [a, b], selectedGroupId: a.id, isEnabled: false)

        #expect(plan.isEmpty)
    }

    @Test func collapsesEveryOtherExpandedRepoGroup() {
        let a = group("stokd-cloud/gdock", collapsed: true)
        let b = group("manaflow-ai/cmux")
        let c = group("stokd-cloud/mono")

        let plan = Reconciler.plan(groups: [a, b, c], selectedGroupId: a.id, isEnabled: true)

        #expect(plan == [
            .expand(groupId: a.id),
            .collapse(groupId: b.id),
            .collapse(groupId: c.id),
        ])
    }
}
