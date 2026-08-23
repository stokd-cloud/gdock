import Foundation
import Testing

#if canImport(cmux_DEV)
@testable import cmux_DEV
#elseif canImport(cmux)
@testable import cmux
#endif

@Suite("Stokd Work availability", .serialized)
struct StokdRailPanelFlagTests {
    @Test func workIsAvailableWithoutAnyBetaFlag() {
        let suite = "cmux.tests.stokd-work.flag.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }

        // No dock/rail flag is set in this domain at all.
        #expect(defaults.object(forKey: RightSidebarBetaFeatureSettings.sidebarDockEnabledKey) == nil)

        #expect(RightSidebarMode.stokdWork.isAvailable(defaults: defaults))
        #expect(RightSidebarMode.availableModes(defaults: defaults).contains(.stokdWork))
    }

    @Test func workStaysAvailableWhenTheRailFlagIsOn() {
        let suite = "cmux.tests.stokd-work.flag.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }

        defaults.set(true, forKey: RightSidebarBetaFeatureSettings.sidebarDockEnabledKey)

        #expect(RightSidebarMode.stokdWork.isAvailable(defaults: defaults))
        #expect(RightSidebarMode.availableModes(defaults: defaults).contains(.stokdWork))
    }

    /// Work takes the mode-bar slot the Dock beta used to occupy, so a default
    /// install shows exactly Files / Find / Vault / Work.
    @Test func workOccupiesTheDockSlotWhenBetasAreOff() {
        #expect(
            RightSidebarMode.availableModes(
                feedEnabled: false,
                dockEnabled: false
            ) == [.files, .find, .sessions, .stokdWork]
        )
    }

    /// A user who selects Work keeps it across a mode-availability refresh with
    /// no beta flags set; it must not be clamped back to Files.
    @Test func selectedWorkModeSurvivesWithNoBetaFlags() {
        let modeKey = "rightSidebar.mode"
        let standard = UserDefaults.standard
        let previousMode = standard.object(forKey: modeKey)
        defer {
            if let previousMode {
                standard.set(previousMode, forKey: modeKey)
            } else {
                standard.removeObject(forKey: modeKey)
            }
        }

        let suite = "cmux.tests.stokd-work.mode.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }

        let state = FileExplorerState()
        state.mode = .stokdWork
        #expect(state.mode == .stokdWork)

        state.refreshModeAvailability(defaults: defaults)
        #expect(state.mode == .stokdWork)
    }

    /// Ungating Work must not ungate the Feed/Dock betas alongside it.
    @Test func feedAndDockRemainIndependentlyGated() {
        #expect(!RightSidebarMode.dock.isAvailable(feedEnabled: false, dockEnabled: false))
        #expect(!RightSidebarMode.feed.isAvailable(feedEnabled: false, dockEnabled: false))
        #expect(RightSidebarMode.dock.isAvailable(feedEnabled: false, dockEnabled: true))
        #expect(RightSidebarMode.feed.isAvailable(feedEnabled: true, dockEnabled: false))
    }
}
