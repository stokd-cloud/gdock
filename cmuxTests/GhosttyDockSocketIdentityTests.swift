import CmuxSettings
import Foundation
import Testing

struct GhosttyDockSocketIdentityTests {
    @Test func markerFilesUseGhosttyDockBundleIds() {
        #expect(SocketPathMarkerFiles.defaultBaseDebugBundleIdentifier == "cloud.stokd.ghostty-dock.debug")
        #expect(SocketPathMarkerFiles.nightlyBundleIdentifier == "cloud.stokd.ghostty-dock.nightly")
        #expect(SocketPathMarkerFiles.stagingBundleIdentifier == "cloud.stokd.ghostty-dock.staging")
    }

    @Test func debugBundleMapsToDevSocketVariant() {
        let variant = SocketPathMarkerFiles.variant(
            bundleIdentifier: "cloud.stokd.ghostty-dock.debug",
            environment: [:]
        )
        // Stable/dev distinction: debug base without CMUX_TAG is .dev(slug: nil)
        switch variant {
        case .dev:
            break
        default:
            Issue.record("expected .dev variant for debug bundle id, got \(variant)")
        }
    }

    @Test func taggedDebugBundleMapsToDevSlug() {
        let variant = SocketPathMarkerFiles.variant(
            bundleIdentifier: "cloud.stokd.ghostty-dock.debug",
            environment: ["CMUX_TAG": "ghostty-dock-rebrand"]
        )
        switch variant {
        case .dev(let slug):
            #expect(slug == "ghostty-dock-rebrand")
        default:
            Issue.record("expected tagged .dev variant, got \(variant)")
        }
    }

    @Test func socketControlSettingsBaseDebugIdMatches() {
        #expect(SocketControlSettings.baseDebugBundleIdentifier == "cloud.stokd.ghostty-dock.debug")
        #expect(SocketControlSettings.isDebugLikeBundleIdentifier("cloud.stokd.ghostty-dock.debug"))
        #expect(SocketControlSettings.isDebugLikeBundleIdentifier("cloud.stokd.ghostty-dock.debug.my-tag"))
        #expect(!SocketControlSettings.isDebugLikeBundleIdentifier("com.cmuxterm.app.debug"))
        #expect(!SocketControlSettings.isDebugLikeBundleIdentifier("cloud.stokd.ghostty-dock"))
    }
}
