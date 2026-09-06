import Testing

#if canImport(cmux_DEV)
@testable import cmux_DEV
#elseif canImport(cmux)
@testable import cmux
#endif

@Suite
struct AppIconDockTilePresentationTests {
    @Test
    func automaticModeDoesNotSelectABakedRaster() {
        #expect(AppIconRuntimeOverride.rasterResourceName(modeRawValue: nil) == nil)
        #expect(AppIconRuntimeOverride.rasterResourceName(modeRawValue: "automatic") == nil)
        #expect(AppIconRuntimeOverride.rasterResourceName(modeRawValue: "") == nil)
    }

    @Test
    func lightAndDarkPinsSelectTheMatchingRaster() {
        #expect(AppIconRuntimeOverride.rasterResourceName(modeRawValue: "light") == "AppIconLight")
        #expect(AppIconRuntimeOverride.rasterResourceName(modeRawValue: "dark") == "AppIconDark")
    }
}
