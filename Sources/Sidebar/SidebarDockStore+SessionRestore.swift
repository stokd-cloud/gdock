import Bonsplit
import Foundation
import os

extension SidebarDockStore {
    /// Outcome of restoring a rail session snapshot (VAL-PERSIST-002).
    struct SessionRestoreResult: Equatable, Sendable {
        var didReseedCanonical: Bool
        var didLogRecovery: Bool
        var restoredSectionCount: Int
        var prunedPanelCount: Int
    }

    /// RED stub: ignores the snapshot payload and always reseeds canonical rails.
    /// Partial/all-invalid recovery, stable ids, and collapse round-trips fail.
    @discardableResult
    func restoreSessionSnapshot(
        _ snapshot: SessionSidebarDockSnapshot?,
        workspace: Workspace,
        preferredLegacyMode: RightSidebarMode? = nil,
        recoveryLogSink: ((String) -> Void)? = nil
    ) -> SessionRestoreResult {
        _ = snapshot
        _ = recoveryLogSink
        switch edge {
        case .left:
            _ = SidebarDockSeeding.seedLeftIfEmpty(store: self, workspace: workspace)
        case .right:
            _ = SidebarDockSeeding.seedRightIfEmpty(
                store: self,
                workspace: workspace,
                preferredMode: preferredLegacyMode
            )
        }
        return SessionRestoreResult(
            didReseedCanonical: true,
            didLogRecovery: false,
            restoredSectionCount: sectionCount,
            prunedPanelCount: 0
        )
    }

    /// RED stub: no-op reattachment (workspace tool roots stay stale).
    func reattachAllPanels(to workspace: Workspace) {
        _ = workspace
    }
}

extension SidebarDockStoreRegistry {
    @discardableResult
    func restoreSessionRails(
        leftSnapshot: SessionSidebarDockSnapshot?,
        rightSnapshot: SessionSidebarDockSnapshot?,
        workspace: Workspace,
        preferredLegacyMode: RightSidebarMode?,
        recoveryLogSink: ((String) -> Void)? = nil
    ) -> (left: SidebarDockStore.SessionRestoreResult, right: SidebarDockStore.SessionRestoreResult) {
        let leftResult = left.restoreSessionSnapshot(
            leftSnapshot,
            workspace: workspace,
            preferredLegacyMode: nil,
            recoveryLogSink: recoveryLogSink
        )
        let rightResult = right.restoreSessionSnapshot(
            rightSnapshot,
            workspace: workspace,
            preferredLegacyMode: preferredLegacyMode,
            recoveryLogSink: recoveryLogSink
        )
        return (leftResult, rightResult)
    }

    /// RED stub: apply fails closed — named layouts never reproduce rails.
    @discardableResult
    func applyNamedLayoutDefinition(
        _ definition: CmuxSidebarDockDefinition,
        workspace: Workspace,
        preferredLegacyMode: RightSidebarMode? = nil
    ) -> Bool {
        _ = definition
        _ = workspace
        _ = preferredLegacyMode
        return false
    }

    /// RED stub: empty capture (UUID-free definitions never recorded).
    func captureNamedLayoutDefinition() -> CmuxSidebarDockDefinition {
        CmuxSidebarDockDefinition()
    }
}
