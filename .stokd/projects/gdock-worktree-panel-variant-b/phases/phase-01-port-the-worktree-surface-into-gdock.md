# Phase 1: Port the worktree surface into gdock

**Project:** Gdock Worktree Panel — Variant B
**Slug:** gdock-worktree-panel-variant-b
**Review Mode:** complete

## Work Items

### 1.1: Snapshot source and background refresh

**Implementation Details**

- Add `GdockWorktreeBSnapshot` value types mirroring the documented `stokd worktree list --json`
  fields: branch, path, rel_path, dirty, merged, ahead, behind, active_agents,
  last_change_secs_ago, last_change, hash, title, status, land_state, disposition, primary.
  Decoding is tolerant of unknown keys so a CLI addition does not break the panel.
- Add `GdockWorktreeBSnapshotLoader` over `StokdCLIRunner` (`worktree list --json`) plus a git seam
  for per-worktree dirty paths, commits ahead of base, and commit file lists. All work runs off the
  main thread; results are published as immutable value snapshots.
- Fields the JSON cannot supply — `queue_position`, `land_detail`, lander presence and queue — are
  modeled as an explicit `.unknown` case, never as a default zero or empty string.
- Add a refresh scheduler with a 2.5-second cadence while presented, an in-flight guard that
  collapses overlapping requests, a manual refresh entry point, last-good snapshot retention on
  failure, and in-flight row-operation preservation across merges.
- Route every child-derived string through a `GdockWorktreeBText.sanitize` helper that strips control
  and escape sequences and bounds length.

**Acceptance Criteria**

- AC-1.1.a: decoding a captured `--json` document yields one row per entry with every documented
- field populated.
- AC-1.1.b: a document containing an unknown key still decodes.
- AC-1.1.c: with the panel not presented, the scheduler performs zero refreshes.
- AC-1.1.d: a failed refresh leaves the previous rows intact and surfaces an error string.
- AC-1.1.e: a row marked in-flight keeps that state after a refresh merges new data.
- AC-1.1.f: sanitizing text containing ANSI escapes, `\r`, and 10,000 characters yields plain,
- bounded text.
- AC-1.1.g: absent queue position, land detail, and lander presence each decode to the unknown case.
- AC-1.1.h: no worktrees, missing `stokd`, not-a-repository, and command-failed each produce a
- distinct explanatory state, and none of them renders as a bare empty table.

### 1.2: Rows, sorting, filtering, detail, and panes

**Dependencies:** 1.1

**Implementation Details**

- Add `GdockWorktreeBRowPresentation` producing the nine cells per row, transcribing the oracle
  renderers listed in `### Oracle`, including the operation cell's four-way precedence and the
  `PRJ:` / `TSK:` identity prefixes.
- Add `GdockWorktreeBVisibleRows` applying the TUI's operator-view exclusion — primary, bare hub, and
  lander scratch worktrees are dropped — before any sorting or filtering. `--json` deliberately keeps
  those rows, so this exclusion is the panel's own and must not be pushed into the decoder.
- Add `GdockWorktreeBSort` implementing the four-level comparator, and `GdockWorktreeBFilter` matching
  case-insensitively over the six documented fields and deriving from the last-good snapshot.
- Add `GdockWorktreeBDetail` producing exactly five lines with the land-failure swap, and
  `GdockWorktreeBFilesPane` producing the dirty, commits, empty, and loading states with the 200 /
  200 / 30 caps and overflow counts.
- Add `GdockWorktreeBLanderLines` producing the two lander rows and the ACTION line, with explicit
  unknown text for unavailable presence or queue data.
- Add `GdockWorktreeBKeyMap` as the single registry of panel operations, so the parity test can
  enumerate it.
- All of these are pure functions over value inputs; no view holds a store reference.

**Acceptance Criteria**

- AC-1.2.a: each of the nine columns renders the oracle's value for idle, shoving, killing,
- disposing, land-failed, and queued fixtures.
- AC-1.2.b: sorting a fixture that exercises all four tie-break levels produces the oracle order.
- AC-1.2.c: each of the six filter fields matches case-insensitively, and clearing restores rows.
- AC-1.2.d: the detail block is five lines for a normal row, no selection, and a land-failed row.
- AC-1.2.e: the files pane produces distinct output for dirty, commits, empty, and loading, with
- correct overflow counts at 201 dirty paths and 31 commits.
- AC-1.2.f: lander lines differ across available, unavailable, and error states, and the unavailable
- state contains no numeric queue total.
- AC-1.2.g: the key map covers every key transcribed from the oracle help frame, and every mapped key
- dispatches to a named operation.
- AC-1.2.h: a fixture containing a primary, a bare hub, a lander scratch, and two ordinary worktrees
- yields exactly the two ordinary rows, while the same document decodes to five rows.

### 1.3: Chord lifecycle, panel presentation, and pin

**Dependencies:** 1.2

**Implementation Details**

- Add `gdock.worktreePanelB` to `ShortcutAction` and the `KeyboardShortcutSettings` mirror with the
  `⌃⇧W` default, a display name, a group, dock-routing disposition, and entries in
  `web/data/cmux-shortcuts.ts` and `web/data/cmux.schema.json`.
- Add `GdockWorktreeBPanelHoldMonitor` modeled on `WindowScopedShortcutHintModifierMonitor`: a
  flags-changed monitor for modifier release, a key-down entry point that ignores auto-repeat, and
  `NSApplication.didResignActiveNotification`, key-window-change, and screen-sleep observers that
  force a hide. Every one of those is an injectable entry point on the monitor, so each termination
  path named in VAL-CHORD-002 is drivable from a unit test without the real notification.
- Add `GdockWorktreeBPanelWindowController` modeled on `GdockSessionCyclerWindowController`: a
  floating panel centered on the key window's frame, a local key monitor while presented, recorded
  restore-focus target, and dismissal paths for release, `Esc`, activation, and unpin.
- Pin model: an explicit pin action (and any mode that requires typing) sets pinned; released
  modifiers dismiss only when not pinned.
- Wire the SwiftUI panel view over the 1.2 value types; row views are `Equatable` value views.
- Register `palette.gdock.worktreePanelB` so the surface is reachable without the chord.

**Acceptance Criteria**

- AC-1.3.a: chord key-down presents; dropping either modifier hides.
- AC-1.3.b: auto-repeat while held leaves the presentation count at one.
- AC-1.3.c: app deactivation, key-window change, screen sleep, and `W` key-up while unpinned each
- hide exactly once.
- AC-1.3.d: pinning then releasing the modifiers leaves it visible; `Esc` then hides it.
- AC-1.3.e: the computed frame is centered on an injected reference frame.
- AC-1.3.f: dismissal makes the recorded restore target key.
- AC-1.3.g: `gdock.worktreePanelB` defaults to `⌃⇧W` on both types and no other action's default
- matches it.
- AC-1.3.h: with the panel hidden the refresh scheduler reports zero work.

### 1.4: Operations: shove, kill, disposition, enqueue, discard

**Dependencies:** 1.3

**Implementation Details**

- Add `GdockWorktreeBOperations` as the single dispatch path for every mutation, over an injected
  command seam so every argument vector is testable without running anything.
- Shove: `stokd shove` with the row's path as working directory; row enters the shoving state.
- Kill: `GdockWorktreeBKillEligibility` refuses primary, detached, empty, and protected branches;
  eligible rows require a confirmation naming the worktree; removal is followed by a branch delete
  that refuses when the branch is checked out in another worktree, reporting the reason.
- Disposition: picker for the four kinds, free-text collection for reason, blocker, and question,
  then `stokd disposition <kind> [--hash --reason --blocker --question]` in the worktree.
- Enqueue: `GdockWorktreeBEnqueuePlanner` maps each target to stage / already-queued / skip-in-flight,
  stages via disposition only, clears marks, and reports the three counts. A test asserts no planned
  action maps to a land invocation.
- Discard: per-file discard from the dirty pane behind a confirmation naming the path.
- Busy guard: any row whose operation is in flight refuses shove, kill, and disposition.

**Acceptance Criteria**

- AC-1.4.a: shove dispatches `stokd shove` with the selected row's directory.
- AC-1.4.b: kill is refused with no dispatch for primary, detached, empty, and protected branches.
- AC-1.4.c: no kill or discard command is dispatched before its confirmation is accepted.
- AC-1.4.d: a branch checked out in another worktree survives kill, with a reported reason.
- AC-1.4.e: each picker key maps to its kind spelling, and optional fields reach the argument vector.
- AC-1.4.f: the enqueue planner produces the correct per-row action and no land invocation.
- AC-1.4.g: a busy row refuses every operation while another row still dispatches.

### 1.5: Handovers

**Dependencies:** 1.4

**Implementation Details**

- Add `GdockWorktreeBHandover` with the three cases and their argument vectors: integrate by hash,
  land by `--cwd`, review by `--worktree`.
- Each handover dismisses the panel before dispatching, and the command's outcome is surfaced to the
  operator rather than discarded.
- Integrate is refused with a message when the selected row carries no work-item hash.

**Acceptance Criteria**

- AC-1.5.a: each handover produces the documented argument vector.
- AC-1.5.b: integrate on a hashless row is refused with no dispatch.
- AC-1.5.c: the panel is recorded as hidden before any handover dispatch.

### 1.6: Conventions, localization, accessibility, and the axiom

**Dependencies:** 1.3, 1.5

**Implementation Details**

- Place any new setting under `GdockCatalogSection` with a `gdock.` id and UserDefaults key; palette
  ids are `palette.gdock.*`.
- Declare every user-facing string with `String(localized:)` and add English and Japanese entries to
  `Resources/Localizable.xcstrings`.
- Compose accessibility labels for rows (worktree, state, land status), lander lines, and the action
  line; confirm every operation is keyboard-reachable through the key map.
- Record `AX-GDOCK-WORKTREE-PANEL` in `docs/gdock-agent-conventions.md`: hold semantics and the pin
  exception, one snapshot source, the unknown-not-invented rule, and the oracle-transcription rule
  for parity tests.

**Acceptance Criteria**

- AC-1.6.a: every new setting id and UserDefaults key begins with `gdock.`, and every new palette id
- with `palette.gdock.`.
- AC-1.6.b: every panel localization key has English and Japanese entries.
- AC-1.6.c: representative rows compose the documented accessibility label.
- AC-1.6.d: `docs/gdock-agent-conventions.md` contains an `AX-GDOCK-WORKTREE-PANEL` section with
- Why, How, and Acceptance Checks.

