# PRD: Gdock Worktree Panel (hold-to-show native port of `stokd worktree`)

## 0. Source Context

**Derived From:** Operator `/prd-forge` request on 2026-08-31 in Claude session
  `c707181a` — screenshot of the live `stokd worktree` TUI plus the instruction
  to port it as a native (non-terminal) gdock UI.
**Feature Name:** Gdock Worktree Panel
**PRD Owner:** Brian Stoker
**Last Updated:** 2026-08-31
**Repository:** `stokd-cloud/gdock` (fork of `manaflow-ai/cmux`)
**Landing:** fork-only on `main`
**This task:** author this document only. It does not implement the feature,
  does not run `stokd project create`, and does not touch Swift.

### Summary

Port the entire `stokd worktree` TUI (`stokd-cloud/mono` →
`apps/cli/src/commands/worktree_list.rs`) into gdock as a **native centered
modal**, visible **only while the operator holds Opt+Shift+W** (Cmd+Tab
grammar: show on chord keyDown, hide when the held modifiers are released).
The panel is not a rail tab, not a terminal, and not a persistent window.

Feature parity with the TUI is the floor, except for two honestly named gaps
that a non-Rust client cannot close from gdock alone: in-process lander
status (`RepoLanderStatus`) and `queue_position` / `land_detail`. Those stay
visible as degraded rows plus a documented mono follow-up
(`stokd worktree snapshot --json`), not as invented JSON.

### Charter

Give the operator, inside gdock, the same worktree operations they already
drive from `stokd worktree` — browse, mark, filter, enqueue, shove, kill,
disposition, and hand over to land/integrate/review — without dropping into a
terminal, and without leaving a panel on screen after they release the chord.
The overlay must be fast enough to use as a glanceable hold overlay and
complete enough that typed/confirm flows (filter, kill confirm, disposition
reason) remain reachable via an explicit pin, because two modifiers cannot
stay held while typing.

### Investigation Summary

Read-only investigation completed in Claude session `c707181a` (five sequential
lanes) against:

- `stokd-cloud/mono/main/apps/cli/src/commands/worktree_list.rs` (5668 lines)
- `stokd worktree list --json` field set
- gdock `GdockSessionCyclerWindowController`,
  `WindowScopedShortcutHintModifierMonitor`, `StokdCLIRunner` /
  `StokdExecutableResolver`, `StokdWorkAPIClient`, `CmuxGit`
- Keyboard catalog: Opt+Shift+W is unbound; existing W chords are Cmd+W,
  Cmd+Shift+W, Ctrl+Cmd+W

TUI surface enumerated:

- Nine columns: WORKTREE, STATE, SYNC, AGENTS, CHANGED, LAND, STATUS,
  DISPOSITION, OPERATION
- Two focus panes: Worktrees, DirtyFiles
- Modes: Browse, Help, Filter, ConfirmKill, ConfirmDeleteDirty,
  DispositionPick, DispositionReason
- Keys: ↑↓ / j k / PageUp PageDown / Home End, Tab, Space mark, l enqueue,
  s shove, x kill, d disposition, g / L / v handovers, / filter, r refresh,
  ? help, q / Esc
- Selection detail block, commits + files pane, two LANDER status lines,
  ACTION line, RowOp in-flight states, marked multi-select
- Action verbs shell out to `stokd shove`, `stokd disposition <kind>`, git
  worktree remove + branch -D (checked-out guard), and three handovers that
  exit the TUI into `stokd integrate` | `stokd worktree land` |
  `stokd worktree review`

JSON available to a non-Rust client from `stokd worktree list --json`:
branch, path, rel_path, dirty, merged, ahead, behind, active_agents,
last_change_secs_ago, hash, title, status, land_state, disposition, primary.

JSON **not** available: queue_position, land_detail, RepoLanderStatus
(lander presence/pid, queue_total, queue_eligible, current, next).
`stokd land explain` has no `--json`.

### Source inventory (read-only)

| Source | Role |
|---|---|
| `stokd-cloud/mono` `apps/cli/src/commands/worktree_list.rs` | Parity oracle for columns, modes, keys, actions |
| Live `stokd worktree` TUI screenshot 2026-08-31 | Operator visual target |
| `GdockSessionCyclerWindowController` | Floating overlay precedent |
| `WindowScopedShortcutHintModifierMonitor` | Hold-to-show flagsChanged monitor |
| `StokdCLIRunner` / `StokdExecutableResolver` | Process boundary for `stokd` |
| `docs/stokd-worktrees-panel.prd.md` | **Different** product: left-rail read+open list. Not this modal. |
| `docs/stokd-work-panel.prd.md` | Shared CLI runner / localization / test-wiring conventions |

## 1. Objectives & Constraints

### Objectives

- Show a native centered worktree overlay on Opt+Shift+W keyDown and hide it
  when Opt or Shift is released, unless the overlay is pinned.
- Render every TUI column, pane, mode, keybinding, action verb, in-flight
  state, and failure path listed in the investigation, using native AppKit /
  SwiftUI chrome rather than a terminal.
- Drive mutating verbs through `stokd` / git process results, never by
  editing git or stokd files from the app.
- Pin automatically (or via an explicit pin control) for Filter, ConfirmKill,
  ConfirmDeleteDirty, DispositionPick, and DispositionReason so those flows
  remain usable.
- Degrade lander / queue fields the JSON snapshot cannot supply, and name the
  mono follow-up instead of inventing a client-side lander.
- Register the chord in `KeyboardShortcutSettings` under a `gdock.` id.

### Constraints

- **Fork-only** on `stokd-cloud/gdock` `main`.
- **Single-repo (gdock).** Do not smuggle `stokd-cloud/mono` CLI work items
  into this gdock project. The missing snapshot verb is a named gap plus a
  proposed follow-up, not a work item here.
- **Not the left-rail Worktrees section** specified in
  `docs/stokd-worktrees-panel.prd.md`. That PRD stays read+open. This PRD is
  the hold-to-show operator console.
- New settings and palette ids use the `gdock.` / `palette.gdock.` prefix.
- Process execution off the main actor; no SwiftUI `body` writes.
- Snapshot-boundary rule: no observable store below a Lazy stack.
- User-facing strings localized en+ja.
- Tests wired into `cmux.xcodeproj`; `./scripts/lint-pbxproj-test-wiring.sh`
  green.
- Bonsplit submodule SHA unchanged.

### Scope Inventory

- Hold-to-show overlay lifecycle (chord, pin, resign, hide).
- Native table + detail + commits/files + lander/ACTION chrome.
- Snapshot assembly from `stokd worktree list --json` plus git for dirty
  files, commits, and file lists.
- Browse / Help / Filter / ConfirmKill / ConfirmDeleteDirty /
  DispositionPick / DispositionReason.
- Marked multi-select and every enumerated keybinding / action verb.
- Shortcut catalog entry, localization, focused tests, tagged dogfood.
- Honest degradation of lander/queue fields that have no JSON verb.

### Non-Goals

- Implementing `stokd worktree snapshot --json` inside `stokd-cloud/mono`.
- Replacing or extending the left-rail Worktrees section from
  `docs/stokd-worktrees-panel.prd.md`.
- A persistent window, rail tab, or terminal host for this UI.
- Cross-repo worktree lists (this overlay is the focused gdock repo).
- Canvas / dock-anywhere placement.
- Upstream cmux PRs.

---

## 1.5 Required Toolchain

| Tool | Min Version | Install Command | Verify Command |
|------|-------------|-----------------|----------------|
| macOS | 14.0 | (OS) | `sw_vers -productVersion` |
| Xcode | 15.0 | App Store | `xcodebuild -version` |
| Swift | 6.0 | (bundled with Xcode) | `swift --version` |
| stokd CLI | current | `curl -fsSL https://stokd.cloud/install \| sh` | `stokd --version` |
| Python 3 | 3.9 | Xcode CLT | `python3 --version` |
| git | 2.40 | Xcode CLT | `git --version` |

Working directory for all Verification Commands: gdock repo root.

```bash
./scripts/setup.sh   # once per machine if GhosttyKit missing
```

Prefer `CMUX_SKIP_ZIG_BUILD=1` on tagged reloads when host zig is not 0.15.2.

---

## 2. Contract

**VAL-HOLD-001** — The overlay appears only while Opt+Shift+W is held.
Surface: artifact
Needs: none
Behavior: Pressing the registered Opt+Shift+W chord shows the centered
  worktree overlay; releasing Option or Shift hides an unpinned overlay
  without requiring q or Esc. Navigation and single-key TUI actions remain
  dispatchable while the modifiers stay held.
Evidence: Persist RED → GREEN results from `GdockWorktreePanelHoldTests` plus
  tagged dogfood notes that the overlay is gone after modifier release.
Rigor: R3
Why: Hold-to-show is a global key-monitor path; a missed hide leaves a
  blocking modal on screen, so the suite is a hard gate.
Fail: An unpinned overlay remaining visible after Option or Shift is
  released, or failing to appear on chord keyDown while gdock is focused.

**VAL-HOLD-002** — Typed and confirm flows pin the overlay.
Surface: library
Needs: VAL-HOLD-001
Behavior: Entering Filter, ConfirmKill, ConfirmDeleteDirty, DispositionPick,
  or DispositionReason pins the overlay so it survives modifier release;
  unpinning or completing/cancelling the mode restores hold-to-hide.
Evidence: Persist RED → GREEN `GdockWorktreePanelPinTests` covering each
  pinning mode, cancel, confirm, and modifier-release-while-pinned.
Rigor: R2
Why: Pin is a deterministic mode machine and is fully covered by unit tests.
Fail: Filter or a confirm sheet dismissing because the operator released
  Option/Shift, or remaining pinned after the mode ends.

**VAL-HOLD-003** — App resign hides an unpinned overlay.
Surface: library
Needs: VAL-HOLD-001
Behavior: When gdock resigns active status, an unpinned overlay hides; a
  pinned overlay stays until the operator cancels or completes the pinned
  mode.
Evidence: Persist RED → GREEN `GdockWorktreePanelHoldTests` resign fixture.
Rigor: R2
Why: Resign is a single notification path with a unit-testable fixture.
Fail: An unpinned overlay remaining after gdock is no longer active.

**VAL-OVERLAY-001** — The panel is a centered native overlay, not a rail.
Surface: artifact
Needs: VAL-HOLD-001
Behavior: The worktree UI mounts as a floating centered panel over the
  focused gdock window, reusing the session-cycler overlay host pattern, and
  does not add a rail tab, terminal surface, or persistent window.
Evidence: Source scan that the controller subclasses the floating-panel
  host (not `SidebarDockStore` kinds) plus tagged dogfood screenshot of the
  centered overlay.
Rigor: R2
Why: Placement is structural and confirmed by source plus one dogfood still.
Fail: The UI appearing as a left-rail Worktrees section, a right-rail tool,
  or an embedded terminal.

**VAL-DATA-001** — Rows come from `stokd worktree list --json` plus git.
Surface: cli
Needs: the existing `StokdCLIRunner` / `CmuxGit` process boundary
Behavior: Given a reachable `stokd` and a git checkout, the overlay lists
  one row per JSON worktree (branch, path, dirty, ahead/behind, agents,
  hash, title, status, land_state, disposition, primary) and loads the
  selected row's dirty files, commits, and file list from git. A missing
  binary or non-zero `stokd` exit yields an empty table plus a structured
  error, never a crash.
Evidence: Persist RED → GREEN `GdockWorktreePanelSnapshotTests` against
  fixture JSON and git fixtures, including missing-binary code 127.
Rigor: R2
Why: Decoding and process errors are independently fixture-testable.
Fail: Inventing rows from the VS Code worktrees panel, or crashing when
  `stokd` is missing.

**VAL-LANDER-001** — Lander chrome degrades instead of inventing JSON.
Surface: parity
Needs: VAL-DATA-001
Behavior: LANDER / CURRENT / ACTION lines render only fields present in
  `stokd worktree list --json` plus in-overlay operation state. Fields the
  TUI computes in-process (`RepoLanderStatus`, `queue_position`,
  `land_detail`) display an explicit unavailable/degraded marker and are
  listed as a mono follow-up (`stokd worktree snapshot --json`), not filled
  from guesswork.
Evidence: Persist RED → GREEN snapshot tests that fixture JSON without
  lander fields never fabricates pid/queue numbers, plus a source scan that
  gdock does not parse `stokd land explain` as JSON.
Rigor: R2
Why: The TUI is the oracle; independent tests must prove the client does
  not fake the missing block.
Fail: Showing a lander pid, queue total, or current worker that did not
  come from a documented JSON field.

**VAL-TABLE-001** — The table shows the nine TUI columns.
Surface: artifact
Needs: VAL-DATA-001
Behavior: The overlay table exposes WORKTREE, STATE, SYNC, AGENTS, CHANGED,
  LAND, STATUS, DISPOSITION, and OPERATION for every listed row, using the
  TUI's dirty/clean, ahead/behind, and status color language, and marks the
  JSON `primary` row the way the TUI marks the current worktree.
Evidence: Persist RED → GREEN `GdockWorktreePanelTableTests` asserting all
  nine column identifiers and fixture cell values.
Rigor: R2
Why: Column presence is a straightforward table-model test.
Fail: Shipping fewer than the nine enumerated columns, or renaming them so
  the TUI screenshot is no longer recognizable.

**VAL-DETAIL-001** — Selecting a row fills the TUI detail block.
Surface: artifact
Needs: VAL-TABLE-001
Behavior: The selected row shows BRANCH, PATH, ID, HASH, and a STATE line
  (clean/dirty, ahead/behind, STATUS, LAND, DISP) matching the TUI detail
  block for that row.
Evidence: Persist RED → GREEN detail-block tests against one dirty and one
  clean fixture row.
Rigor: R2
Why: Detail mapping is a pure projection of the snapshot row.
Fail: A selected row with an empty detail block while snapshot data exists.

**VAL-COMMITS-001** — The lower pane lists commits and files.
Surface: artifact
Needs: VAL-DATA-001
Behavior: The overlay shows the selected worktree's commit count, file
  count, recent commits (hash + subject), and file paths from git, matching
  the TUI "commits / files" pane.
Evidence: Persist RED → GREEN git-fixture tests for a 3-commit / 35-file
  row and an empty-history row.
Rigor: R2
Why: Git porcelain parsing is independently fixture-testable.
Fail: Omitting the commits/files pane, or showing another worktree's files
  for the selection.

**VAL-PANE-001** — Focus moves between Worktrees and DirtyFiles.
Surface: library
Needs: VAL-TABLE-001
Behavior: Tab (and the TUI equivalent) moves focus between the worktree
  table and the dirty-files list; each pane keeps its own selection index.
Evidence: Persist RED → GREEN `GdockWorktreePanelFocusTests` for Tab both
  directions and independent selection.
Rigor: R2
Why: Focus is a two-state machine covered by unit tests.
Fail: Only one focus target, or Tab doing nothing while the overlay is
  shown.

**VAL-STATUS-001** — ACTION and OPERATION reflect in-flight work.
Surface: library
Needs: VAL-DATA-001
Behavior: The ACTION line shows idle or the in-flight verb and the TUI
  footer key hints (select, mark, enqueue, handover, shove, kill,
  disposition, refresh, filter, help). The OPERATION column shows per-row
  RowOp state (enqueue, shove, kill, disposition) until the process
  completes or fails, then clears or shows the failure.
Evidence: Persist RED → GREEN in-flight fixtures for success and non-zero
  exit.
Rigor: R2
Why: RowOp is a deterministic state machine.
Fail: A running shove with ACTION idle and OPERATION empty, or a stuck
  OPERATION after the process exits.

**VAL-NAV-001** — Movement keys match the TUI.
Surface: library
Needs: VAL-PANE-001
Behavior: While the overlay is visible, ↑ ↓ j k PageUp PageDown Home End
  move the focused pane's selection; r refreshes the snapshot; q and Esc
  dismiss a pinned overlay (unpinned already hides on modifier release).
Evidence: Persist RED → GREEN key-dispatch tests for each listed key.
Rigor: R2
Why: Key routing is unit-testable without a live window.
Fail: j/k doing nothing, or Esc killing gdock instead of dismissing the
  overlay.

**VAL-MARK-001** — Space marks rows for multi-select actions.
Surface: library
Needs: VAL-NAV-001
Behavior: Space toggles a mark on the focused worktree row; marked rows
  form the target set for enqueue, shove, kill, and disposition when any
  marks exist, otherwise the action uses the focused row.
Evidence: Persist RED → GREEN mark-set tests for toggle, empty set, and
  multi-row action targeting.
Rigor: R2
Why: Mark set is a pure model concern.
Fail: Actions ignoring marks, or Space activating the focused row as if it
  were Return.

**VAL-FILTER-001** — Slash filters the cycling/listed set.
Surface: library
Needs: VAL-HOLD-002 and VAL-TABLE-001
Behavior: `/` enters Filter (pinned), a text field filters rows by
  worktree/title/branch, and Enter returns to Browse on the filtered set;
  Esc cancels filter and restores the unfiltered list.
Evidence: Persist RED → GREEN filter tests for substring match, empty
  match, Enter, and Esc.
Rigor: R2
Why: Filter is a string-match over fixture rows.
Fail: `/` doing nothing, or filter remaining applied after Esc.

**VAL-HELP-001** — Question mark shows the TUI help overlay.
Surface: artifact
Needs: VAL-HOLD-002
Behavior: `?` pins and shows a help sheet listing the same action keys as
  the TUI ACTION/help line; Esc or `?` again closes it.
Evidence: Persist RED → GREEN help-mode tests plus a localized string scan
  for each documented key.
Rigor: R2
Why: Help is a mode plus a string catalog check.
Fail: `?` unbound, or help omitting kill/disposition/handover keys.

**VAL-ENQUEUE-001** — `l` stages `dev_complete` and never spawns a land.
Surface: cli
Needs: VAL-MARK-001
Behavior: `l` on the marked set — or the focused row when nothing is marked
  — stages each eligible target by running `stokd disposition dev_complete`
  in that worktree, off the main actor, with OPERATION in-flight per row. A
  row already queued or landable is reported as already-queued and a row
  whose own land is in flight is skipped; neither is re-staged. The action
  reports the staged / already / skipped counts and clears the marks. The
  overlay never invokes `stokd land` or any other land process directly.
Evidence: Persist RED → GREEN planner tests over rows in each state
  (unqueued, `queue_position` set, `land_state` in {dev_complete, pending,
  landing, landed}, land in flight) asserting the per-row action and the
  reported counts, plus a recording-runner test asserting that no land argv
  is ever issued.
Rigor: R4
Why: Enqueue writes the serialized lander's queue. A second land process,
  or a double-staged item, corrupts the queue for every other worktree in
  the repository, so two independent lanes must agree before it ships.
Fail: Treating `l` as a shove, invoking `stokd land`, or re-staging a row
  that is already queued — any of which breaks land serialization.

**VAL-SHOVE-001** — `s` shoves the targeted worktrees.
Surface: cli
Needs: VAL-MARK-001
Behavior: `s` runs `stokd shove` for the focused or marked set, off the
  main actor, with OPERATION in-flight and a structured error on failure.
Evidence: Persist RED → GREEN `stokd shove` argv + exit-code fixtures.
Rigor: R2
Why: Same process-boundary tests as enqueue.
Fail: `s` calling `git push` instead of `stokd shove`.

**VAL-KILL-001** — `x` kills with the TUI confirmations.
Surface: cli
Needs: VAL-HOLD-002 and VAL-MARK-001
Behavior: `x` pins ConfirmKill; confirming runs git worktree remove and
  deletes the branch with the TUI's checked-out guard. A dirty tree extra
  confirm (ConfirmDeleteDirty) is required before data loss. Cancel leaves
  the worktree untouched.
Evidence: Persist RED → GREEN tests for cancel, checked-out refusal, dirty
  confirm, and successful remove argv.
Rigor: R3
Why: Destructive git is a hard-gated path; independent tests must see both
  confirms and the checked-out refusal.
Fail: `x` removing a checked-out or dirty worktree without the matching
  confirm, or skipping the checked-out guard.

**VAL-DISP-001** — `d` runs `stokd disposition` with kind and reason.
Surface: cli
Needs: VAL-HOLD-002 and VAL-MARK-001
Behavior: `d` pins DispositionPick (dev_complete, blocked, abandon,
  needs-input); kinds that require `--reason` / `--blocker` / `--question`
  pin DispositionReason; confirming runs
  `stokd disposition <kind> [--hash --reason --blocker --question]` off the
  main actor.
Evidence: Persist RED → GREEN argv fixtures for each kind, including the
  required-flag matrix and cancel.
Rigor: R2
Why: Kind/flag matrix is fully fixture-testable.
Fail: `d` posting a disposition without the flags the CLI requires, or
  writing a disposition record without invoking `stokd`.

**VAL-HAND-001** — `g` / `L` / `v` hand over to the TUI's exit commands.
Surface: cli
Needs: VAL-MARK-001
Behavior: `g` starts `stokd integrate`, `L` starts `stokd worktree land`,
  and `v` starts `stokd worktree review` for the targeted worktree, then
  dismisses the overlay. The overlay does not itself land, merge, or
  integrate.
Evidence: Persist RED → GREEN argv tests for the three handovers plus a
  source scan that the overlay never calls `git merge` / `git push` itself.
Rigor: R2
Why: Handover is argv + an explicit non-goal scan.
Fail: The overlay merging or force-pushing, or the three keys being unbound.

**VAL-PARITY-001** — Every enumerated TUI control has a native counterpart.
Surface: parity
Needs: VAL-TABLE-001, VAL-NAV-001, VAL-MARK-001, VAL-FILTER-001,
  VAL-HELP-001, VAL-ENQUEUE-001, VAL-SHOVE-001, VAL-KILL-001, VAL-DISP-001,
  VAL-HAND-001, VAL-LANDER-001
Behavior: Against `worktree_list.rs` as oracle, the overlay provides the
  nine columns, two panes, six modes, and every listed keybinding/action.
  The only permitted omissions are RepoLanderStatus / queue_position /
  land_detail, which VAL-LANDER-001 already degrades.
Evidence: Persist a checklist test `GdockWorktreePanelParityTests` that
  walks the oracle list and fails on any unmapped column, mode, or key
  other than the named gap.
Rigor: R3
Why: Full-port claims need a hard-gated oracle checklist, not prose.
Fail: Shipping a glanceable subset (table-only) while this PRD is marked
  complete.

**VAL-SHORT-001** — The chord is a documented, remappable gdock shortcut.
Surface: library
Needs: VAL-HOLD-001
Behavior: Opt+Shift+W is registered in `KeyboardShortcutSettings` with a
  `gdock.`-prefixed id, is editable in Settings and `cmux.json`, and is
  documented. Default remains unbound for any conflicting catalog entry.
Evidence: Persist RED → GREEN shortcut-catalog tests plus a localization
  audit line for the shortcut title.
Rigor: R2
Why: Catalog membership is a unit-level registry test.
Fail: A hard-coded keyDown path that Settings cannot rebind.

**VAL-LOC-001** — Every user-facing string is localized en+ja.
Surface: artifact
Needs: VAL-OVERLAY-001
Behavior: Overlay titles, columns, help, confirms, and errors go through
  `String(localized:)` and exist in `Resources/Localizable.xcstrings` for
  en and ja.
Evidence: Persist the localization-audit command output from the work item
  and a string-catalog grep for the new keys.
Rigor: R2
Why: Localization is a repo-required audit, independently greppable.
Fail: Raw English literals in the overlay source.

**VAL-FAIL-001** — Missing CLI and failed verbs stay on the overlay.
Surface: artifact
Needs: VAL-DATA-001
Behavior: A missing `stokd` binary, a non-zero action exit, or a non-git
  cwd leaves the overlay visible (pinned if an action was in flight) with a
  structured error on the ACTION line and does not crash gdock.
Evidence: Persist RED → GREEN failure fixtures in snapshot and action
  tests.
Rigor: R2
Why: Failure chrome is user-visible and fixture-testable.
Fail: A missing `stokd` crashing the app, or a failed shove with no ACTION
  error.

### Oracle

The parity oracle is `stokd-cloud/mono` `apps/cli/src/commands/worktree_list.rs`
plus a live `stokd worktree` run in the same repo. VAL-PARITY-001 and
VAL-LANDER-001 are adjudicated against that file's columns, modes, keys, and
in-process lander block — not against the left-rail Worktrees PRD and not
against a screenshot alone.

---

## 3. Execution Topology

## Phase 1: Native hold-to-show worktree overlay
**Purpose:** One unattended pass delivers the overlay lifecycle, snapshot,
  native chrome, TUI-parity interactions, and mutating verbs. No operator
  decision depends on a partial ship, so there is no `**Stop:**`.

### 1.1 Overlay host, hold chord, pin, and shortcut catalog

**Targets:** VAL-HOLD-001, VAL-HOLD-002, VAL-HOLD-003, VAL-OVERLAY-001, VAL-SHORT-001
**Dependencies:** []

**Landing:** fork-only

**Implementation Details**
- **Landing:** fork-only.
- Add `GdockWorktreePanelWindowController` as a floating centered panel,
  following `GdockSessionCyclerWindowController` (not a `SidebarDock` kind).
- Monitor Opt+Shift+W via `WindowScopedShortcutHintModifierMonitor` /
  flagsChanged: show on chord keyDown, hide unpinned overlay when Option or
  Shift drops, hide unpinned overlay on app resign.
- Pin on Filter / confirm / disposition modes; unpin when those modes end.
- Register `gdock.worktreePanelHold` (name TBD to match catalog style) in
  `KeyboardShortcutSettings` with default Opt+Shift+W; document it.
- Failure modes: missing shortcut binding → overlay never shows (not a
  crash); duplicate chord with an existing W shortcut is forbidden by
  catalog uniqueness tests.

**Acceptance Criteria**
- AC-1.1.a: Chord keyDown shows the overlay; Option or Shift release hides
  it when unpinned.
- AC-1.1.b: Each pinning mode survives modifier release; ending the mode
  restores hold-to-hide.
- AC-1.1.c: App resign hides an unpinned overlay.
- AC-1.1.d: The controller is a floating panel, not a rail kind.
- AC-1.1.e: Shortcut id is `gdock.`-prefixed and remappable.
- AC-1.1.f: `./scripts/test-unit.sh -only-testing:cmuxTests/GdockWorktreePanelHoldTests CMUX_SKIP_ZIG_BUILD=1 test` exits 0.
- AC-1.1.g: `./scripts/lint-pbxproj-test-wiring.sh` exits 0.

**Acceptance Tests**
- Test-1.1.a: Unit — show/hide on flagsChanged.
- Test-1.1.b: Unit — pin matrix for the five pinning modes.
- Test-1.1.c: Unit — resign notification.
- Test-1.1.d: Source — floating panel host, no `stokdWorktrees` kind reuse.
- Test-1.1.e: Unit — catalog id + default chord.
- Test-1.1.f: Suite gate.
- Test-1.1.g: Test-wiring lint.

**Verification Commands**
```bash
set -euo pipefail
rg -n 'GdockWorktreePanelWindowController|gdock\.worktreePanel' Sources/ Packages/macOS/
./scripts/lint-pbxproj-test-wiring.sh
./scripts/test-unit.sh -only-testing:cmuxTests/GdockWorktreePanelHoldTests CMUX_SKIP_ZIG_BUILD=1 test
./scripts/test-unit.sh -only-testing:cmuxTests/GdockWorktreePanelPinTests CMUX_SKIP_ZIG_BUILD=1 test
```

### 1.2 Snapshot data plane and honest lander degradation

**Targets:** VAL-DATA-001, VAL-LANDER-001
**Dependencies:** ["1.1"]

**Landing:** fork-only

**Implementation Details**
- **Landing:** fork-only.
- Resolve `stokd` via `StokdExecutableResolver`; run
  `stokd worktree list --json` off the main actor in the focused workspace
  repo root.
- Decode the documented JSON fields into immutable row value types.
- Load dirty files, commits, and file lists through `CmuxGit` (or the
  existing git process boundary), never by shelling out from `body`.
- Lander/queue fields absent from JSON render as an explicit degraded
  marker. Do not parse `stokd land explain`. Record the mono follow-up
  `stokd worktree snapshot --json` in this PRD's Open Questions only.
- Failure modes: missing binary → code 127 empty table + error; non-zero
  `stokd` → empty table + stderr banner; non-git cwd → empty + reason.

**Acceptance Criteria**
- AC-1.2.a: Fixture JSON decodes into one row per worktree with the
  documented fields.
- AC-1.2.b: Missing `stokd` yields structured code 127, not `fatalError`.
- AC-1.2.c: Fixture JSON without lander fields never produces a pid or
  queue total.
- AC-1.2.d: `rg` over the new sources finds no `land explain` JSON parse.
- AC-1.2.e: `./scripts/test-unit.sh -only-testing:cmuxTests/GdockWorktreePanelSnapshotTests CMUX_SKIP_ZIG_BUILD=1 test` exits 0.

**Acceptance Tests**
- Test-1.2.a: Unit — JSON decode fixture.
- Test-1.2.b: Unit — missing binary / non-zero exit.
- Test-1.2.c: Unit — lander degradation.
- Test-1.2.d: Regression scan.
- Test-1.2.e: Suite gate.

**Verification Commands**
```bash
set -euo pipefail
rg -n 'worktree list --json' Sources/
if rg -n 'land explain' Sources/GdockWorktreePanel* Sources/Stokd/WorktreePanel* 2>/dev/null; then
  echo 'VAL-LANDER-001: do not parse stokd land explain' >&2
  exit 1
fi
./scripts/lint-pbxproj-test-wiring.sh
./scripts/test-unit.sh -only-testing:cmuxTests/GdockWorktreePanelSnapshotTests CMUX_SKIP_ZIG_BUILD=1 test
```

### 1.3 Native table, detail, commits, panes, and ACTION chrome

**Targets:** VAL-TABLE-001, VAL-DETAIL-001, VAL-COMMITS-001, VAL-PANE-001
**Dependencies:** ["1.2"]

**Landing:** fork-only

**Implementation Details**
- **Landing:** fork-only.
- Native table with the nine TUI columns; selection drives the detail block
  (BRANCH/PATH/ID/HASH/STATE line) and the commits/files pane.
- Two focus panes (Worktrees, DirtyFiles) with independent selection.
- ACTION line + OPERATION column bind to RowOp in-flight state from 1.5.
- SwiftUI snapshot-boundary: rows are value snapshots; no store below a
  Lazy stack. The oracle checklist itself is work item 1.6.

**Acceptance Criteria**
- AC-1.3.a: All nine column ids exist and render fixture cells.
- AC-1.3.b: Selected dirty and clean fixtures fill the detail block.
- AC-1.3.c: Git fixture with 3 commits / 35 files renders both lists.
- AC-1.3.d: Tab moves focus between the two panes.
- AC-1.3.e: `./scripts/test-unit.sh -only-testing:cmuxTests/GdockWorktreePanelTableTests CMUX_SKIP_ZIG_BUILD=1 test` exits 0.

**Acceptance Tests**
- Test-1.3.a: Unit — columns.
- Test-1.3.b: Unit — detail projection.
- Test-1.3.c: Unit — commits/files.
- Test-1.3.d: Unit — pane focus.
- Test-1.3.e: Suite gate.

**Verification Commands**
```bash
set -euo pipefail
./scripts/lint-pbxproj-test-wiring.sh
./scripts/test-unit.sh -only-testing:cmuxTests/GdockWorktreePanelTableTests CMUX_SKIP_ZIG_BUILD=1 test
./scripts/test-unit.sh -only-testing:cmuxTests/GdockWorktreePanelFocusTests CMUX_SKIP_ZIG_BUILD=1 test
```

### 1.4 Navigation, marks, filter, and help

**Targets:** VAL-NAV-001, VAL-MARK-001, VAL-FILTER-001, VAL-HELP-001
**Dependencies:** ["1.1", "1.3"]

**Landing:** fork-only

**Implementation Details**
- **Landing:** fork-only.
- Dispatch ↑↓jk, PageUp/PageDown, Home/End, r, q, Esc, Space, `/`, `?`
  through one overlay key router (shared with 1.5).
- Space toggles marks; marked set is the action target when non-empty.
- `/` pins Filter; Enter commits; Esc restores.
- `?` pins Help listing every action key.
- Unpinned q/Esc is unnecessary for hide (modifiers already hide) but must
  dismiss a pinned overlay.

**Acceptance Criteria**
- AC-1.4.a: Each movement key changes selection as in the TUI.
- AC-1.4.b: Space toggles marks; actions use the mark set when present.
- AC-1.4.c: `/` filters; Esc restores the full list.
- AC-1.4.d: `?` shows help containing kill/disposition/handover keys.
- AC-1.4.e: Focused unit suites for nav/mark/filter/help exit 0.

**Acceptance Tests**
- Test-1.4.a: Unit — movement keys.
- Test-1.4.b: Unit — mark set.
- Test-1.4.c: Unit — filter.
- Test-1.4.d: Unit — help catalog.
- Test-1.4.e: Suite gates.

**Verification Commands**
```bash
set -euo pipefail
./scripts/lint-pbxproj-test-wiring.sh
./scripts/test-unit.sh -only-testing:cmuxTests/GdockWorktreePanelNavTests CMUX_SKIP_ZIG_BUILD=1 test
```

### 1.5 Mutating verbs: enqueue, shove, kill, disposition, handover

**Targets:** VAL-ENQUEUE-001, VAL-SHOVE-001, VAL-KILL-001, VAL-DISP-001, VAL-HAND-001, VAL-STATUS-001, VAL-FAIL-001
**Dependencies:** ["1.2", "1.4"]

**Landing:** fork-only

**Implementation Details**
- **Landing:** fork-only.
- `l` / `s` invoke the exact argv `worktree_list.rs` uses for enqueue vs
  shove (do not invent a third verb or flags). OPERATION/ACTION track RowOp
  until exit. Open Question 2 is only about confirming those flags at
  implementation time against the oracle file, not about adding a new verb.
- `x` pins ConfirmKill; dirty trees also pin ConfirmDeleteDirty; refuse
  checked-out worktrees; on confirm, `git worktree remove` + `git branch -D`
  with the TUI guard.
- `d` pins DispositionPick then DispositionReason as required; runs
  `stokd disposition <kind> [--hash --reason --blocker --question]`.
- `g` / `L` / `v` spawn `stokd integrate` / `stokd worktree land` /
  `stokd worktree review` and dismiss. The overlay never merges or pushes.
- Failure modes: non-zero exit → ACTION error + OPERATION failure; never
  leave a silent no-op.

**Acceptance Criteria**
- AC-1.5.a: `l` and `s` argv match fixtures; non-zero maps to ACTION error.
- AC-1.5.b: `x` cancel / checked-out / dirty-confirm / success paths all
  covered; checked-out is refused.
- AC-1.5.c: Each disposition kind builds the required flags; cancel does
  not invoke `stokd`.
- AC-1.5.d: `g`/`L`/`v` argv tests pass; source scan finds no `git merge`
  / `git push` in the overlay module.
- AC-1.5.e: In-flight OPERATION clears after process exit.
- AC-1.5.f: Focused action test suite exits 0.

**Acceptance Tests**
- Test-1.5.a: Unit — shove/enqueue argv + failure.
- Test-1.5.b: Unit — kill confirm matrix.
- Test-1.5.c: Unit — disposition flag matrix.
- Test-1.5.d: Unit — handover argv + source scan.
- Test-1.5.e: Unit — RowOp lifecycle.
- Test-1.5.f: Suite gate.

**Verification Commands**
```bash
set -euo pipefail
if rg -n 'git merge|git push' Sources/GdockWorktreePanel* 2>/dev/null; then
  echo 'VAL-HAND-001: overlay must not merge or push' >&2
  exit 1
fi
./scripts/lint-pbxproj-test-wiring.sh
./scripts/test-unit.sh -only-testing:cmuxTests/GdockWorktreePanelActionTests CMUX_SKIP_ZIG_BUILD=1 test
```

### 1.6 Localization, parity checklist, and tagged dogfood

**Targets:** VAL-LOC-001, VAL-PARITY-001
**Dependencies:** ["1.3", "1.4", "1.5"]

**Landing:** fork-only

**Implementation Details**
- **Landing:** fork-only.
- Every overlay string uses `String(localized:)` with keys in
  `Resources/Localizable.xcstrings` (en+ja), including shortcut titles.
- `GdockWorktreePanelParityTests` walks the `worktree_list.rs` oracle list
  (nine columns, two panes, six modes, every listed key) and fails on any
  unmapped item other than VAL-LANDER-001's named gap.
- Tagged Release reload (`./scripts/reload.sh --tag worktree-panel`) for
  hold/pin/table dogfood; do not launch an untagged app.
- Document the chord in the keyboard-shortcut docs the catalog already uses.

**Acceptance Criteria**
- AC-1.6.a: Localization audit lists the new keys in en and ja.
- AC-1.6.b: No raw user-facing literals in the overlay sources.
- AC-1.6.c: Parity checklist is green against the oracle list.
- AC-1.6.d: Tagged dogfood notes confirm hold-to-show and the nine columns.

**Acceptance Tests**
- Test-1.6.a: Localization audit.
- Test-1.6.b: Source scan for literals.
- Test-1.6.c: Unit — `GdockWorktreePanelParityTests`.
- Test-1.6.d: Dogfood evidence artifact.

**Verification Commands**
```bash
set -euo pipefail
rg -n 'String\(localized:' Sources/GdockWorktree* Packages/macOS/CmuxSettings/
./scripts/test-unit.sh -only-testing:cmuxTests/GdockWorktreePanelParityTests CMUX_SKIP_ZIG_BUILD=1 test
./scripts/reload.sh --tag worktree-panel
```

---

## 4. Completion Criteria

- Every VAL-* id in §2 appears in exactly one §3 `**Targets:**` line.
- `stokd project lint .stokd/projects/gdock-worktree-panel/prd.md` exits 0.
- Hold-to-show, pin, nine columns, two panes, six modes, and every listed
  action key are implemented and gated by the named test suites.
- Lander/queue fields are degraded, not faked.
- Tagged dogfood of `gdock worktree-panel` shows the overlay on
  Opt+Shift+W and hides it on modifier release.
- Left-rail Worktrees PRD behavior is unchanged.

## 5. Rollout & Validation

### Rollout Strategy

Fork-only. Land the overlay behind the new remappable shortcut (default
Opt+Shift+W). No beta flag. Do not seed a rail tab. Do not create the
project record from this authoring task; operators run
`stokd project create -f .stokd/projects/gdock-worktree-panel/prd.md`
separately.

### Post-Launch Validation

- Dogfood hold/release, pin/filter, kill confirm, and one shove against a
  disposable worktree.
- Confirm the left-rail Worktrees section still matches
  `docs/stokd-worktrees-panel.prd.md`.
- If lander pid/queue is still required at a glance, open the mono follow-up
  for `stokd worktree snapshot --json` rather than patching gdock.

## 6. Open Questions

1. **Pin affordance.** Auto-pin on Filter/confirm/disposition is specified.
   Should there also be an explicit pin key (e.g. Space-hold or `p`) so the
   operator can keep the overlay up for browsing without holding Opt+Shift?
   Default in this PRD: no extra pin key; browsing stays hold-to-show.
2. **Enqueue vs shove.** The TUI uses `l` enqueue and `s` shove. Confirm
   the exact `stokd shove` flags each key must pass (the overlay must not
   invent a third verb).
3. **Mono follow-up (out of this repo):** `stokd worktree snapshot --json`
   exposing RepoLanderStatus, queue_position, and land_detail so VAL-LANDER-001
   can be upgraded later without a gdock-side parser for `stokd land explain`.
4. **Duplicate in-progress task.** Task `5cdf921` was created with the same
   objective as `7b7422a`. Operators should abandon one before starting the
   project so two PRDs do not diverge.