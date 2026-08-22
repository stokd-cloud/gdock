import Foundation
import Testing

#if canImport(cmux_DEV)
@testable import cmux_DEV
#elseif canImport(cmux)
@testable import cmux
#endif

@Suite("Stokd Work rail availability", .serialized)
struct StokdRailPanelFlagTests {
    @Test func existingDockFlagIsTheOnlyAvailabilityGate() {
        let suite = "cmux.tests.stokd-work.flag.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }

        #expect(!StokdRailPanelAvailability.isEnabled(defaults: defaults))
        #expect(!RightSidebarMode.availableModes(defaults: defaults).contains(.stokdWork))
        #expect(!RightSidebarMode.stokdWork.isAvailable(defaults: defaults))

        defaults.set(true, forKey: RightSidebarBetaFeatureSettings.sidebarDockEnabledKey)

        #expect(StokdRailPanelAvailability.isEnabled(defaults: defaults))
        #expect(RightSidebarMode.availableModes(defaults: defaults).contains(.stokdWork))
        #expect(RightSidebarMode.stokdWork.isAvailable(defaults: defaults))
    }

    @Test func semanticGateDelegatesToTheExistingSettingKey() {
        #expect(
            StokdRailPanelAvailability.settingKey
                == RightSidebarBetaFeatureSettings.sidebarDockEnabledKey
        )
        #expect(StokdRailPanelAvailability.settingKey == "sidebar.beta.dock.enabled")
    }

    @Test func disablingDockGateClampsSelectedWorkMode() {
        #expect(
            RightSidebarMode.stokdWork.resolvedAfterSidebarDockGateChange(isEnabled: false)
                == .files
        )
        #expect(
            RightSidebarMode.stokdWork.resolvedAfterSidebarDockGateChange(isEnabled: true)
                == .stokdWork
        )
        #expect(
            RightSidebarMode.find.resolvedAfterSidebarDockGateChange(isEnabled: false)
                == .find
        )
    }
}
