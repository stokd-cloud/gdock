import AppKit

/// Pure window-level policy for the gdock "Keep Window on Top" (PIP) mode: a
/// main window pinned above its siblings and shown on every Space, so the user
/// can park a workspace they want to watch closely anywhere on screen while
/// working in another app.
///
/// The transition is expressed as pure, `nonisolated` transforms — separate from
/// ``GdockPipFloatingWindowController``, which owns the windows — so the
/// invariants below are unit-testable without constructing an `NSWindow` or
/// depending on the test host's display setup.
///
/// Two invariants make this worth a dedicated seam:
///
/// 1. **At most one fullscreen behavior.** `NSWindow.h` states you may specify
///    at most one of `.fullScreenPrimary`, `.fullScreenAuxiliary`, and
///    `.fullScreenNone`. A pinned window wants `.fullScreenAuxiliary` so it can
///    be shown alongside *another* app's fullscreen window, which means it must
///    give up `.fullScreenPrimary` for as long as it is pinned. The visible
///    consequence — a pinned window cannot enter its own native fullscreen — is
///    intended: a PIP window is a small always-visible monitor, and unpinning
///    restores the capability.
/// 2. **Unpin restores what was captured, never a default.** `CmuxMainWindow`
///    declares `.fullScreenPrimary` precisely because losing it silently breaks
///    native fullscreen (issue #5933), and the window factory may layer other
///    bits (e.g. `.fullScreenDisallowsTiling`) on top. Restoring a hardcoded
///    behavior would quietly drop them, so unpin replays the snapshot taken at
///    pin time and leaves every bit PIP does not own alone.
enum GdockPipFloatingWindowPolicy {
    /// The behavior bits this policy owns. Everything else on a window belongs
    /// to whoever set it, and survives a pin/unpin round trip untouched.
    static let managedBehaviorBits: NSWindow.CollectionBehavior = [
        .canJoinAllSpaces,
        .fullScreenAuxiliary,
        .fullScreenPrimary,
        .fullScreenNone,
    ]

    /// The level a pinned window floats at.
    ///
    /// This is the one sanctioned `.floating` level for a cmux *main* window —
    /// see ``NSWindow/adoptCmuxPeerWindowLevel()`` for why floating is opt-in
    /// with a justification rather than inherited (issue #5081). It is justified
    /// here because staying above sibling windows is the entire feature, it is
    /// scoped to a window the user explicitly pinned, and
    /// ``GdockPipFloatingWindowController`` restores the captured level on
    /// unpin so no window is left floating implicitly.
    static let floatingLevel: NSWindow.Level = .floating

    /// The collection behavior a window carries while pinned.
    ///
    /// Idempotent: pinning an already-pinned behavior returns it unchanged.
    nonisolated static func floatingCollectionBehavior(
        _ base: NSWindow.CollectionBehavior
    ) -> NSWindow.CollectionBehavior {
        var behavior = base
        // `.fullScreenAuxiliary` is mutually exclusive with the other two
        // fullscreen bits, so drop them before declaring it.
        behavior.remove(.fullScreenPrimary)
        behavior.remove(.fullScreenNone)
        behavior.insert(.fullScreenAuxiliary)
        behavior.insert(.canJoinAllSpaces)
        return behavior
    }

    /// The collection behavior a window returns to when unpinned: the bits this
    /// policy owns are replayed from `snapshot`, and every other bit currently
    /// on the window — including any AppKit or cmux added while it was pinned —
    /// is preserved.
    ///
    /// For the ordinary round trip (`current == floatingCollectionBehavior(snapshot)`)
    /// this returns exactly `snapshot`.
    nonisolated static func restoredCollectionBehavior(
        current: NSWindow.CollectionBehavior,
        snapshot: NSWindow.CollectionBehavior
    ) -> NSWindow.CollectionBehavior {
        var behavior = current
        behavior.subtract(managedBehaviorBits)
        behavior.formUnion(snapshot.intersection(managedBehaviorBits))
        return behavior
    }
}
