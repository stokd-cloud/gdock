import Bonsplit
import Foundation

extension SidebarDockStore {
    /// RED stub: incomplete capture — omits stable section ids / collapse / extents
    /// so round-trip and fingerprint assertions fail until the green fix lands.
    func sessionSnapshot() -> SessionSidebarDockSnapshot {
        let layoutCodec = SessionSplitContainerLayoutCodec(controller: bonsplitController)
        let rawLayout = layoutCodec.snapshot(panelIdForTabId: { [self] in surfaceIdToPanelId[$0] })
        let panelSnapshots: [SessionPanelSnapshot] = []
        return SessionSidebarDockSnapshot(
            focusedPanelId: nil,
            layout: rawLayout,
            panels: panelSnapshots,
            sectionIds: nil,
            collapsedSectionIds: nil,
            rememberedExtentsBySectionId: nil
        )
    }

    /// RED stub: constant fingerprint — no dimension mutates the dirty hash.
    func sessionAutosaveFingerprint() -> Int {
        0
    }
}

extension SidebarDockStoreRegistry {
    func sessionAutosaveFingerprint() -> Int {
        0
    }

    /// RED stub: ignores flag — always emits rail fields (breaks VAL-FLAG-004).
    func sessionWindowRailSnapshots(
        flagEnabled: Bool = RightSidebarBetaFeatureSettings.isSidebarDockEnabled()
    ) -> (left: SessionSidebarDockSnapshot?, right: SessionSidebarDockSnapshot?) {
        _ = flagEnabled
        return (left.sessionSnapshot(), right.sessionSnapshot())
    }
}
