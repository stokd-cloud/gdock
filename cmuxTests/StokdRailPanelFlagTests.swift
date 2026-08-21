import Foundation
import Testing

#if canImport(cmux_DEV)
@testable import cmux_DEV
#elseif canImport(cmux)
@testable import cmux
#endif

@Suite("Stokd Work availability", .serialized)
struct StokdWorkDefaultAvailabilityTests {
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

/// AC-1.2 / VAL-STOKD-FLAG: stokd rail panels feature gate.
///
/// Phase 1.2 **Option A**: reuses `sidebar.beta.dock.enabled` (no dedicated
/// `sidebar.beta.stokdPanels.enabled`). Default off when key absent; enable path
/// is true only when the shared rails key is set true.
@Suite("Stokd rail panels feature gate", .serialized)
struct StokdRailPanelFlagTests {
    @Test func defaultIsFalseWhenKeyAbsent() {
        // AC-1.2.a
        let suite = "cmux.tests.stokd-rail-panels.flag.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }

        #expect(defaults.object(forKey: StokdRailPanelFeatureSettings.enabledKey) == nil)
        #expect(StokdRailPanelFeatureSettings.isEnabled(defaults: defaults) == false)
        #expect(StokdRailPanelFeatureSettings.defaultEnabled == false)
        // Option A: shared key is the rails dock beta key.
        #expect(StokdRailPanelFeatureSettings.enabledKey == "sidebar.beta.dock.enabled")
        #expect(
            StokdRailPanelFeatureSettings.enabledKey
                == RightSidebarBetaFeatureSettings.sidebarDockEnabledKey
        )
    }

    @Test func enablePathTrueOnlyWhenRailsKeySetTrue() {
        // AC-1.2.b (Option A: no separate stokdPanels key; rail gate is the only gate)
        let suite = "cmux.tests.stokd-rail-panels.flag.enable.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }

        #expect(StokdRailPanelFeatureSettings.isEnabled(defaults: defaults) == false)

        defaults.set(true, forKey: StokdRailPanelFeatureSettings.enabledKey)
        #expect(StokdRailPanelFeatureSettings.isEnabled(defaults: defaults) == true)
        // Rails accessor stays in lockstep under Option A.
        #expect(RightSidebarBetaFeatureSettings.isSidebarDockEnabled(defaults: defaults) == true)

        defaults.set(false, forKey: StokdRailPanelFeatureSettings.enabledKey)
        #expect(StokdRailPanelFeatureSettings.isEnabled(defaults: defaults) == false)
        #expect(RightSidebarBetaFeatureSettings.isSidebarDockEnabled(defaults: defaults) == false)
    }

    @Test func neverThrowsWhenReadingMissingOrPresentKey() {
        let suite = "cmux.tests.stokd-rail-panels.flag.safe.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }

        // Missing key → false, no throw.
        #expect(StokdRailPanelFeatureSettings.isEnabled(defaults: defaults) == false)

        defaults.set(true, forKey: StokdRailPanelFeatureSettings.enabledKey)
        #expect(StokdRailPanelFeatureSettings.isEnabled(defaults: defaults) == true)

        defaults.removeObject(forKey: StokdRailPanelFeatureSettings.enabledKey)
        #expect(StokdRailPanelFeatureSettings.isEnabled(defaults: defaults) == false)
    }

    @Test func optionADocumentsNoDedicatedStokdPanelsKey() {
        // Guard against accidental Option B drift: the public enabled key must
        // remain the shared rails key, not a dedicated stokdPanels key.
        #expect(StokdRailPanelFeatureSettings.enabledKey == "sidebar.beta.dock.enabled")
        #expect(StokdRailPanelFeatureSettings.enabledKey != "sidebar.beta.stokdPanels.enabled")
        #expect(StokdRailPanelFeatureSettings.usesDedicatedStokdPanelsKey == false)
    }
}
