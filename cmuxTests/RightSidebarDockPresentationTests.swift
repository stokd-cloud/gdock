import Foundation
import Testing
import CmuxSettings

#if canImport(cmux_DEV)
@testable import cmux_DEV
#elseif canImport(cmux)
@testable import cmux
#endif

@Suite("Right sidebar dock presentation", .serialized)
struct RightSidebarDockPresentationTests {
    @Test func sidebarDockSpacesDoNotStackRightTabsByDefault() {
        let suite = "cmux.tests.right-sidebar.presentation.default.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }

        defaults.set(true, forKey: RightSidebarBetaFeatureSettings.sidebarDockEnabledKey)

        #expect(defaults.object(forKey: RightSidebarDockPresentationSettings.userDefaultsKey) == nil)
        #expect(!RightSidebarDockPresentationSettings.isStackedTabsEnabled(defaults: defaults))
        #expect(!RightSidebarDockPresentationPolicy.usesStackedTabs(
            sidebarDockSpacesEnabled: RightSidebarBetaFeatureSettings.isSidebarDockEnabled(defaults: defaults),
            stackedTabsEnabled: RightSidebarDockPresentationSettings.isStackedTabsEnabled(defaults: defaults),
            hasDockRegistry: true
        ))
    }

    @Test func stackedRightTabsRequireExplicitGdockSettingAndRegistry() {
        let suite = "cmux.tests.right-sidebar.presentation.enabled.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }

        defaults.set(true, forKey: RightSidebarBetaFeatureSettings.sidebarDockEnabledKey)
        defaults.set(true, forKey: RightSidebarDockPresentationSettings.userDefaultsKey)

        #expect(RightSidebarDockPresentationSettings.isStackedTabsEnabled(defaults: defaults))
        #expect(RightSidebarDockPresentationPolicy.usesStackedTabs(
            sidebarDockSpacesEnabled: true,
            stackedTabsEnabled: true,
            hasDockRegistry: true
        ))
        #expect(!RightSidebarDockPresentationPolicy.usesStackedTabs(
            sidebarDockSpacesEnabled: false,
            stackedTabsEnabled: true,
            hasDockRegistry: true
        ))
        #expect(!RightSidebarDockPresentationPolicy.usesStackedTabs(
            sidebarDockSpacesEnabled: true,
            stackedTabsEnabled: true,
            hasDockRegistry: false
        ))
    }

    @Test func stackedTabsSettingUsesGdockPrefixEverywhere() throws {
        let key = SettingCatalog().gdock.rightSidebarStackedTabs
        #expect(key.id == "gdock.rightSidebarStackedTabs")
        #expect(key.userDefaultsKey == RightSidebarDockPresentationSettings.userDefaultsKey)
        #expect(key.defaultValue == false)
        #expect(CmuxSettingsFileStore.supportedSettingsJSONPaths.contains("gdock.rightSidebarStackedTabs"))

        let descriptor = try #require(
            CommandPaletteSettingsToggleCommands.descriptor(
                commandId: RightSidebarDockPresentationSettings.commandId
            )
        )
        #expect(descriptor.settingsKey == "gdock.rightSidebarStackedTabs")
        #expect(descriptor.commandId == "palette.toggleSetting.gdock.rightSidebarStackedTabs")
        #expect(descriptor.commandId.hasPrefix("palette.toggleSetting.gdock."))
    }
}
