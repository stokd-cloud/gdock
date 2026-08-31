import Foundation
import Testing

import CmuxFoundation
import CmuxSettings
import CmuxWorkspaces

#if canImport(cmux_DEV)
@testable import cmux_DEV
#elseif canImport(cmux)
@testable import cmux
#endif

/// Placement of the agent-session card stack in the sidebar render list
/// (AC3/AC4).
///
/// The stack *replaces* the focused workspace's own row rather than sitting
/// beneath it, so the invariants that matter are: the workspace is never drawn
/// twice, workspace numbering does not shift, and a workspace with no cards is
/// untouched.
@MainActor
@Suite("Sidebar panel card stack placement", .serialized)
struct SidebarWorkspacePanelCardRenderItemTests {
    private typealias Item = SidebarWorkspaceRenderItem

    private func makeTabManager() -> TabManager {
        let suiteName = "cmux.panel-card-stack-tests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defaults.removePersistentDomain(forName: suiteName)
        let manager = TabManager(
            autoWelcomeIfNeeded: false,
            settings: UserDefaultsSettingsClient(defaults: defaults),
            closeTabWarningDefaults: defaults
        )
        manager.addWorkspace(autoWelcomeIfNeeded: false)
        return manager
    }

    private func groupsById(_ manager: TabManager) -> [UUID: WorkspaceGroup] {
        Dictionary(uniqueKeysWithValues: manager.workspaceGroups.map { ($0.id, $0) })
    }

    private func workspaceRowIds(_ items: [Item]) -> [UUID] {
        items.compactMap {
            guard case .workspace(let id) = $0 else { return nil }
            return id
        }
    }

    private func stacks(_ items: [Item]) -> [(workspaceId: UUID, paneIds: [UUID])] {
        items.compactMap {
            guard case .panelCardStack(let workspaceId, let paneIds) = $0 else { return nil }
            return (workspaceId, paneIds)
        }
    }

    // MARK: - Replacement (AC3)

    /// The point of the stack: the focused workspace's ordinary row is gone,
    /// because drawing both would show that workspace twice.
    @Test func theStackReplacesTheFocusedWorkspaceRow() throws {
        let manager = makeTabManager()
        manager.addWorkspace(autoWelcomeIfNeeded: false)
        let ids = manager.tabs.map(\.id)
        let focused = try #require(ids.first)
        let paneIds = [UUID(), UUID()]

        let items = Item.renderItems(
            tabs: manager.tabs,
            groupsById: groupsById(manager),
            focusedWorkspaceId: focused,
            panelCardPaneIds: paneIds
        )

        #expect(!workspaceRowIds(items).contains(focused))
        #expect(stacks(items).count == 1)
        #expect(stacks(items).first?.workspaceId == focused)
        #expect(stacks(items).first?.paneIds == paneIds)
    }

    /// The stack sits exactly where the row was, so the sidebar order does not
    /// jump when an agent starts.
    @Test func theStackOccupiesTheReplacedRowsPosition() throws {
        let manager = makeTabManager()
        manager.addWorkspace(autoWelcomeIfNeeded: false)
        manager.addWorkspace(autoWelcomeIfNeeded: false)
        let ids = manager.tabs.map(\.id)
        let focused = ids[1]

        let base = Item.renderItems(tabs: manager.tabs, groupsById: groupsById(manager))
        let items = Item.renderItems(
            tabs: manager.tabs,
            groupsById: groupsById(manager),
            focusedWorkspaceId: focused,
            panelCardPaneIds: [UUID()]
        )

        #expect(items.count == base.count)
        #expect(items.map(\.rowWorkspaceId) == base.map(\.rowWorkspaceId))
    }

    @Test func otherWorkspaceRowsAreUnchanged() throws {
        let manager = makeTabManager()
        manager.addWorkspace(autoWelcomeIfNeeded: false)
        manager.addWorkspace(autoWelcomeIfNeeded: false)
        let ids = manager.tabs.map(\.id)
        let focused = ids[0]

        let items = Item.renderItems(
            tabs: manager.tabs,
            groupsById: groupsById(manager),
            focusedWorkspaceId: focused,
            panelCardPaneIds: [UUID()]
        )

        #expect(workspaceRowIds(items) == ids.filter { $0 != focused })
    }

    /// No cards means nothing changes at all — the gate-off path and every
    /// workspace without an agent go through this.
    @Test func noPanesReproducesTheBaseListExactly() throws {
        let manager = makeTabManager()
        manager.addWorkspace(autoWelcomeIfNeeded: false)
        let focused = try #require(manager.tabs.first?.id)

        let base = Item.renderItems(tabs: manager.tabs, groupsById: groupsById(manager))
        let items = Item.renderItems(
            tabs: manager.tabs,
            groupsById: groupsById(manager),
            focusedWorkspaceId: focused,
            panelCardPaneIds: []
        )

        #expect(items.map(\.id) == base.map(\.id))
        #expect(stacks(items).isEmpty)
    }

    @Test func noFocusedWorkspaceReproducesTheBaseListExactly() {
        let manager = makeTabManager()
        manager.addWorkspace(autoWelcomeIfNeeded: false)

        let base = Item.renderItems(tabs: manager.tabs, groupsById: groupsById(manager))
        let items = Item.renderItems(
            tabs: manager.tabs,
            groupsById: groupsById(manager),
            focusedWorkspaceId: nil,
            panelCardPaneIds: [UUID()]
        )

        #expect(items.map(\.id) == base.map(\.id))
    }

    /// A focused workspace with no visible row — hidden inside a collapsed
    /// group — has nothing to stand in for, so it contributes no stack.
    @Test func aFocusedWorkspaceWithNoVisibleRowContributesNoStack() throws {
        let manager = makeTabManager()
        manager.addWorkspace(autoWelcomeIfNeeded: false)
        let ids = manager.tabs.map(\.id)
        let hidden = UUID()

        let items = Item.renderItems(
            tabs: manager.tabs,
            groupsById: groupsById(manager),
            focusedWorkspaceId: hidden,
            panelCardPaneIds: [UUID()]
        )

        #expect(stacks(items).isEmpty)
        #expect(workspaceRowIds(items) == ids)
    }

    // MARK: - Identity and row semantics (AC4)

    /// The stack is the workspace's row, so it must stay in the reorderable set
    /// — excluding it would drop the row from drop-indicator placement.
    @Test func theStackIsAReorderableRow() {
        #expect(Item.workspace(workspaceId: UUID()).isReorderableRow)
        #expect(Item.groupHeader(groupId: UUID(), anchorWorkspaceId: UUID()).isReorderableRow)
        #expect(Item.panelCardStack(workspaceId: UUID(), paneIds: [UUID()]).isReorderableRow)
    }

    /// Identity is the workspace, not the panes, so cards appearing and
    /// disappearing inside the stack does not recreate the row.
    @Test func stackIdentityIsStableAcrossCardChanges() {
        let workspaceId = UUID()

        let one = Item.panelCardStack(workspaceId: workspaceId, paneIds: [UUID()]).id
        let two = Item.panelCardStack(workspaceId: workspaceId, paneIds: [UUID(), UUID()]).id

        #expect(one == two)
    }

    /// It must still not collide with that workspace's ordinary row id, or the
    /// table would reuse the wrong cell when the stack appears.
    @Test func stackIdentityNeverCollidesWithTheWorkspaceRow() {
        let workspaceId = UUID()

        let stack = Item.panelCardStack(workspaceId: workspaceId, paneIds: [UUID()]).id
        let row = Item.workspace(workspaceId: workspaceId).id
        let group = Item.groupHeader(groupId: workspaceId, anchorWorkspaceId: workspaceId).id

        #expect(stack != row)
        #expect(stack != group)
    }

    @Test func theStackReportsItsOwningWorkspace() {
        let workspaceId = UUID()
        let item = Item.panelCardStack(workspaceId: workspaceId, paneIds: [UUID()])

        #expect(item.rowWorkspaceId == workspaceId)
    }

    /// Numbering drives ⌘1..⌘9. Replacing a row with a stack must not renumber
    /// the workspaces after it.
    @Test func theStackKeepsWorkspaceNumberingStable() {
        let a = UUID()
        let b = UUID()
        let c = UUID()
        let withRows: [Item] = [
            .workspace(workspaceId: a),
            .workspace(workspaceId: b),
            .workspace(workspaceId: c),
        ]
        let withStack: [Item] = [
            .workspace(workspaceId: a),
            .panelCardStack(workspaceId: b, paneIds: [UUID(), UUID()]),
            .workspace(workspaceId: c),
        ]

        #expect(Item.numberedWorkspaceIds(from: withStack) == [a, b, c])
        #expect(
            Item.numberedWorkspaceIndexById(from: withStack)
                == Item.numberedWorkspaceIndexById(from: withRows)
        )
    }
}
