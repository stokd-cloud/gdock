import Foundation
import Testing
import CmuxSettings

#if canImport(cmux_DEV)
@testable import cmux_DEV
#elseif canImport(cmux)
@testable import cmux
#endif

@Suite("Right sidebar stacked presentation", .serialized)
struct RightSidebarDockPresentationTests {
    @Test func stackedSectionsFollowTheGdockSettingAlone() {
        let suite = "cmux.tests.right-sidebar.presentation.default.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }

        #expect(defaults.object(forKey: RightSidebarDockPresentationSettings.userDefaultsKey) == nil)
        #expect(!RightSidebarDockPresentationSettings.isStackedTabsEnabled(defaults: defaults))
        #expect(!RightSidebarDockPresentationPolicy.usesStackedTabs(stackedTabsEnabled: false))

        defaults.set(true, forKey: RightSidebarDockPresentationSettings.userDefaultsKey)
        #expect(RightSidebarDockPresentationSettings.isStackedTabsEnabled(defaults: defaults))
        #expect(RightSidebarDockPresentationPolicy.usesStackedTabs(stackedTabsEnabled: true))
    }

    @Test func allSidebarToolsIncludingWorkAreStackable() {
        #expect(RightSidebarMode.stackableModes == [.files, .find, .sessions, .stokdWork])
        #expect(RightSidebarMode.stokdWork.canStackAsSection)
        #expect(RightSidebarMode.files.canStackAsSection)
        #expect(RightSidebarMode.find.canStackAsSection)
        #expect(RightSidebarMode.sessions.canStackAsSection)
        #expect(!RightSidebarMode.feed.canStackAsSection)
        #expect(!RightSidebarMode.dock.canStackAsSection)
        #expect(!RightSidebarMode.customSidebar.canStackAsSection)

        var layout = RightSidebarSectionLayout()
        layout.insert(.stokdWork, at: 0)
        #expect(layout.contains(.stokdWork))
    }

    @Test func sidebarDockSpacesSettingIsRemovedEverywhere() {
        #expect(!CmuxSettingsFileStore.supportedSettingsJSONPaths.contains("betaFeatures.sidebarDock"))
        #expect(CommandPaletteSettingsToggleCommands.descriptor(
            commandId: "palette.toggleSetting.sidebarDock"
        ) == nil)
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
