import AppKit
import Testing

#if canImport(cmux_DEV)
@testable import cmux_DEV
#elseif canImport(cmux)
@testable import cmux
#endif

// gdock "Keep Window on Top" (PIP): a main window pinned above its siblings and
// shown on every Space, so a monitored workspace stays visible while the user
// works elsewhere.
//
// The window-level transition is expressed as a pure policy so the invariants
// can be verified without constructing windows or depending on the test host's
// display setup:
//
//   * AppKit permits at most ONE of `.fullScreenPrimary`, `.fullScreenAuxiliary`,
//     and `.fullScreenNone` (NSWindow.h). A pinned window uses `.fullScreenAuxiliary`
//     so it can be shown alongside another app's fullscreen window, which means it
//     must NOT simultaneously carry `.fullScreenPrimary`.
//   * Unpinning must restore the EXACT behavior captured at pin time — including
//     `.fullScreenPrimary`, whose loss would silently break native fullscreen the
//     way issue #5933 did, and never a hardcoded default.
@Suite("gdock PIP floating window policy")
struct GdockPipFloatingWindowPolicyTests {
    /// A realistic pre-pin snapshot for a cmux main window: fullscreen-capable,
    /// with an unrelated bit layered on by the window factory.
    private static let mainWindowBehavior: NSWindow.CollectionBehavior = [
        .fullScreenPrimary,
        .fullScreenDisallowsTiling,
    ]

    @Test func pinnedBehaviorJoinsAllSpaces() {
        let pinned = GdockPipFloatingWindowPolicy.floatingCollectionBehavior(Self.mainWindowBehavior)
        #expect(
            pinned.contains(.canJoinAllSpaces),
            "A pinned window must follow the user across Spaces"
        )
    }

    @Test func pinnedBehaviorUsesAuxiliaryFullScreenAndDropsTheOtherTwo() {
        let pinned = GdockPipFloatingWindowPolicy.floatingCollectionBehavior(Self.mainWindowBehavior)
        #expect(
            pinned.contains(.fullScreenAuxiliary),
            "A pinned window must be showable alongside another app's fullscreen window"
        )
        // NSWindow.h: at most one of primary / auxiliary / none may be specified.
        #expect(
            !pinned.contains(.fullScreenPrimary),
            ".fullScreenAuxiliary and .fullScreenPrimary are mutually exclusive"
        )
        #expect(
            !pinned.contains(.fullScreenNone),
            ".fullScreenAuxiliary and .fullScreenNone are mutually exclusive"
        )
    }

    @Test func pinnedBehaviorPreservesUnrelatedBits() {
        let pinned = GdockPipFloatingWindowPolicy.floatingCollectionBehavior(Self.mainWindowBehavior)
        #expect(
            pinned.contains(.fullScreenDisallowsTiling),
            "Pinning must not clobber behavior bits it does not own"
        )
    }

    @Test func pinnedLevelFloatsAboveOrdinaryWindows() {
        #expect(GdockPipFloatingWindowPolicy.floatingLevel.rawValue > NSWindow.Level.normal.rawValue)
    }

    @Test func unpinRestoresTheExactCapturedBehavior() {
        let snapshot = Self.mainWindowBehavior
        let pinned = GdockPipFloatingWindowPolicy.floatingCollectionBehavior(snapshot)
        let restored = GdockPipFloatingWindowPolicy.restoredCollectionBehavior(
            current: pinned,
            snapshot: snapshot
        )
        #expect(
            restored == snapshot,
            "Unpinning must restore the captured pre-pin behavior exactly, not a default"
        )
        #expect(
            restored.contains(.fullScreenPrimary),
            "Native fullscreen capability (#5933) must survive a pin/unpin round trip"
        )
    }

    @Test func unpinKeepsPipBitsThatWereAlreadyPresentBeforePinning() {
        // A window that already joined all Spaces before pinning must keep doing
        // so after unpinning: restore returns the snapshot, not "minus PIP bits".
        let snapshot: NSWindow.CollectionBehavior = [.fullScreenPrimary, .canJoinAllSpaces]
        let pinned = GdockPipFloatingWindowPolicy.floatingCollectionBehavior(snapshot)
        let restored = GdockPipFloatingWindowPolicy.restoredCollectionBehavior(
            current: pinned,
            snapshot: snapshot
        )
        #expect(restored.contains(.canJoinAllSpaces))
        #expect(restored == snapshot)
    }

    @Test func unpinPreservesBitsAppKitAddedWhilePinned() {
        // AppKit (or another cmux path) may layer a bit on while the window is
        // pinned. Restore owns only the bits PIP touches; anything else that
        // appeared meanwhile survives.
        let snapshot: NSWindow.CollectionBehavior = [.fullScreenPrimary]
        var current = GdockPipFloatingWindowPolicy.floatingCollectionBehavior(snapshot)
        current.insert(.participatesInCycle)
        let restored = GdockPipFloatingWindowPolicy.restoredCollectionBehavior(
            current: current,
            snapshot: snapshot
        )
        #expect(restored.contains(.participatesInCycle))
        #expect(restored.contains(.fullScreenPrimary))
        #expect(!restored.contains(.fullScreenAuxiliary))
    }

    @Test func pinningIsIdempotent() {
        let once = GdockPipFloatingWindowPolicy.floatingCollectionBehavior(Self.mainWindowBehavior)
        let twice = GdockPipFloatingWindowPolicy.floatingCollectionBehavior(once)
        #expect(once == twice)
    }
}

@MainActor
@Suite("gdock PIP floating window state")
struct GdockPipFloatingWindowStateTests {
    private func makeDefaults(_ name: String) -> UserDefaults {
        let suiteName = "gdock.pip.tests.\(name).\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defaults.removePersistentDomain(forName: suiteName)
        return defaults
    }

    @Test func windowsAreNotPinnedByDefault() {
        let defaults = makeDefaults("default")
        let store = GdockPipFloatingWindowStore(defaults: defaults)
        #expect(store.isPinned(windowId: UUID()) == false)
    }

    @Test func togglingOnRecordsTheWindow() {
        let defaults = makeDefaults("on")
        let store = GdockPipFloatingWindowStore(defaults: defaults)
        let windowId = UUID()

        #expect(store.togglePinned(windowId: windowId) == true)
        #expect(store.isPinned(windowId: windowId))
    }

    @Test func togglingOffRemovesTheWindow() {
        let defaults = makeDefaults("off")
        let store = GdockPipFloatingWindowStore(defaults: defaults)
        let windowId = UUID()

        _ = store.togglePinned(windowId: windowId)
        #expect(store.togglePinned(windowId: windowId) == false)
        #expect(store.isPinned(windowId: windowId) == false)
    }

    @Test func pinnedStateIsPerWindow() {
        let defaults = makeDefaults("perWindow")
        let store = GdockPipFloatingWindowStore(defaults: defaults)
        let pinned = UUID()
        let other = UUID()

        _ = store.togglePinned(windowId: pinned)
        #expect(store.isPinned(windowId: pinned))
        #expect(store.isPinned(windowId: other) == false)
    }

    @Test func pinnedStateSurvivesAFreshStoreOverTheSameDefaults() {
        let defaults = makeDefaults("persist")
        let windowId = UUID()

        let writer = GdockPipFloatingWindowStore(defaults: defaults)
        _ = writer.togglePinned(windowId: windowId)

        let reader = GdockPipFloatingWindowStore(defaults: defaults)
        #expect(
            reader.isPinned(windowId: windowId),
            "Pinned windows must come back pinned after a relaunch"
        )
    }

    @Test func stateIsPersistedUnderTheGdockPrefixedKey() {
        // The fork convention (CLAUDE.md) requires every gdock-owned UserDefaults
        // id to carry the `gdock.` prefix so it can never collide with upstream.
        let defaults = makeDefaults("key")
        let store = GdockPipFloatingWindowStore(defaults: defaults)
        _ = store.togglePinned(windowId: UUID())

        #expect(GdockPipFloatingWindowStore.userDefaultsKey == "gdock.pipFloatingWindowIds")
        #expect(defaults.object(forKey: "gdock.pipFloatingWindowIds") != nil)
    }

    @Test func corruptPersistedStateIsIgnoredRatherThanCrashing() {
        let defaults = makeDefaults("corrupt")
        defaults.set("not-an-array", forKey: GdockPipFloatingWindowStore.userDefaultsKey)
        let store = GdockPipFloatingWindowStore(defaults: defaults)
        #expect(store.isPinned(windowId: UUID()) == false)
    }

    @Test func unpinningTheLastWindowLeavesNoStaleIds() {
        let defaults = makeDefaults("drain")
        let store = GdockPipFloatingWindowStore(defaults: defaults)
        let windowId = UUID()

        _ = store.togglePinned(windowId: windowId)
        _ = store.togglePinned(windowId: windowId)

        let persisted = defaults.stringArray(forKey: GdockPipFloatingWindowStore.userDefaultsKey) ?? []
        #expect(persisted.isEmpty)
    }
}

@MainActor
@Suite("gdock PIP command surface")
struct GdockPipFloatingWindowCommandTests {
    // The fork convention (CLAUDE.md) requires gdock one-shot palette commands to
    // be namespaced `palette.gdock.*`, so they can never collide with an upstream
    // cmux command id.
    @Test func paletteContributionUsesTheGdockPrefixedCommandId() {
        let contributions = ContentView.commandPaletteViewCommandContributions()
        #expect(
            contributions.contains { $0.commandId == "palette.gdock.togglePipFloatingWindow" },
            "PIP toggle must be reachable from the command palette under its gdock-prefixed id"
        )
    }

    @Test func paletteContributionIdMatchesTheControllerCommandId() {
        #expect(GdockPipFloatingWindowController.commandId == "palette.gdock.togglePipFloatingWindow")
    }
}
