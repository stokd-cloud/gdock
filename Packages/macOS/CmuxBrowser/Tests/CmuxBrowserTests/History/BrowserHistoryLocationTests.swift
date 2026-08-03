import Foundation
import Testing
@testable import CmuxBrowser

@Suite struct BrowserHistoryLocationTests {
    @Test func foldsDebugAndStagingNamespaces() {
        #expect(BrowserHistoryLocation.normalizedNamespace(bundleIdentifier: "cloud.stokd.ghostty-dock.debug.my-tag") == "cloud.stokd.ghostty-dock.debug")
        #expect(BrowserHistoryLocation.normalizedNamespace(bundleIdentifier: "cloud.stokd.ghostty-dock.staging.rc") == "cloud.stokd.ghostty-dock.staging")
        #expect(BrowserHistoryLocation.normalizedNamespace(bundleIdentifier: "cloud.stokd.ghostty-dock") == "cloud.stokd.ghostty-dock")
    }

    @Test func historyFileURLNestsUnderNamespace() {
        let root = URL(fileURLWithPath: "/tmp/appsupport", isDirectory: true)
        let location = BrowserHistoryLocation(applicationSupportDirectory: root, bundleIdentifier: "cloud.stokd.ghostty-dock.debug.tag")
        #expect(location.namespace == "cloud.stokd.ghostty-dock.debug")
        #expect(location.historyFileURL.path == "/tmp/appsupport/cloud.stokd.ghostty-dock.debug/browser_history.json")
    }

    @Test func legacyURLPresentOnlyWhenNamespaceDiffers() {
        let root = URL(fileURLWithPath: "/tmp/appsupport", isDirectory: true)
        let tagged = BrowserHistoryLocation(applicationSupportDirectory: root, bundleIdentifier: "cloud.stokd.ghostty-dock.debug.tag")
        #expect(tagged.legacyTaggedHistoryFileURL?.path == "/tmp/appsupport/cloud.stokd.ghostty-dock.debug.tag/browser_history.json")

        let prod = BrowserHistoryLocation(applicationSupportDirectory: root, bundleIdentifier: "cloud.stokd.ghostty-dock")
        #expect(prod.legacyTaggedHistoryFileURL == nil)
    }
}
