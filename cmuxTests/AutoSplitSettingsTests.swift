import Foundation
import Testing
import CmuxSettings

#if canImport(cmux_DEV)
@testable import cmux_DEV
#elseif canImport(cmux)
@testable import cmux
#endif

@Suite("Auto Split settings")
struct AutoSplitSettingsTests {
    @Test("catalog keys are gdock-prefixed with conservative defaults")
    func catalogKeysAreGdockPrefixed() {
        let catalog = SettingCatalog().gdock
        #expect(catalog.autoSplitRows.id == "gdock.autoSplitRows")
        #expect(catalog.autoSplitColumns.id == "gdock.autoSplitColumns")
        #expect(catalog.forceAutoSplitter.id == "gdock.forceAutoSplitter")
        #expect(catalog.autoSplitRows.defaultValue == 2)
        #expect(catalog.autoSplitColumns.defaultValue == 2)
        #expect(catalog.forceAutoSplitter.defaultValue == false)
        #expect(CmuxSettingsFileStore.supportedSettingsJSONPaths.contains("gdock.autoSplitRows"))
        #expect(CmuxSettingsFileStore.supportedSettingsJSONPaths.contains("gdock.autoSplitColumns"))
        #expect(CmuxSettingsFileStore.supportedSettingsJSONPaths.contains("gdock.forceAutoSplitter"))
    }

    @Test("missing UserDefaults returns defaults")
    func missingDefaultsReturnFactoryValues() throws {
        let suite = "AutoSplitSettingsTests.missing.\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suite))
        defaults.removePersistentDomain(forName: suite)
        #expect(GdockAutoSplitterSettings.rows(defaults: defaults) == 2)
        #expect(GdockAutoSplitterSettings.columns(defaults: defaults) == 2)
        #expect(GdockAutoSplitterSettings.isForceEnabled(defaults: defaults) == false)
        let shape = GdockAutoSplitterSettings.shape(defaults: defaults)
        #expect(shape.rows == 2)
        #expect(shape.cols == 2)
        #expect(shape.isQuad)
    }

    @Test(arguments: [
        (-4, 1),
        (0, 1),
        (1, 1),
        (2, 2),
        (6, 6),
        (7, 6),
        (99, 6),
    ])
    func clampDimension(_ pair: (Int, Int)) {
        let shape = GdockAutoSplitterSettings.Shape.clamped(rows: pair.0, cols: pair.0)
        #expect(shape.rows == pair.1)
        #expect(shape.cols == pair.1)
    }

    @Test("persisted invalid integers clamp on read")
    func persistedInvalidIntegersClamp() throws {
        let suite = "AutoSplitSettingsTests.clamp.\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suite))
        defaults.removePersistentDomain(forName: suite)
        defaults.set(0, forKey: "gdock.autoSplitRows")
        defaults.set(99, forKey: "gdock.autoSplitColumns")
        #expect(GdockAutoSplitterSettings.rows(defaults: defaults) == 1)
        #expect(GdockAutoSplitterSettings.columns(defaults: defaults) == 6)
        defaults.set(-3, forKey: "gdock.autoSplitRows")
        #expect(GdockAutoSplitterSettings.rows(defaults: defaults) == 1)
    }

    @Test("1x1 is a no-op shape")
    func oneByOneIsNoOp() {
        #expect(GdockAutoSplitterSettings.Shape.clamped(rows: 1, cols: 1).isNoOp)
        #expect(!GdockAutoSplitterSettings.Shape.clamped(rows: 1, cols: 2).isNoOp)
    }

    @Test("force palette toggle uses gdock prefix")
    func forcePaletteToggleUsesGdockPrefix() {
        #expect(GdockAutoSplitterSettings.forceCommandId == "palette.toggleSetting.gdock.forceAutoSplitter")
        #expect(GdockAutoSplitterSettings.autoSplitCommandId == "palette.gdock.autoSplit")
        let descriptor = CommandPaletteSettingsToggleCommands.descriptor(
            commandId: GdockAutoSplitterSettings.forceCommandId
        )
        #expect(descriptor?.settingsKey == "gdock.forceAutoSplitter")
        #expect(descriptor?.commandId.hasPrefix("palette.toggleSetting.gdock.") == true)
    }
}
