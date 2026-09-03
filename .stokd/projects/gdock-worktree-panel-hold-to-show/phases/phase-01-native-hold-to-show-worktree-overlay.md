# Phase 1: Native hold-to-show worktree overlay

**Project:** Gdock Worktree Panel (hold-to-show...
**Slug:** gdock-worktree-panel-hold-to-show
**Review Mode:** complete

## Work Items

### 1.1: Overlay host, hold chord, pin, and shortcut catalog

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
- it when unpinned.
- AC-1.1.b: Each pinning mode survives modifier release; ending the mode
- restores hold-to-hide.
- AC-1.1.c: App resign hides an unpinned overlay.
- AC-1.1.d: The controller is a floating panel, not a rail kind.
- AC-1.1.e: Shortcut id is `gdock.`-prefixed and remappable.
- AC-1.1.f: `./scripts/test-unit.sh -only-testing:cmuxTests/GdockWorktreePanelHoldTests CMUX_SKIP_ZIG_BUILD=1 test` exits 0.
- AC-1.1.g: `./scripts/lint-pbxproj-test-wiring.sh` exits 0.

### 1.2: Snapshot data plane and honest lander degradation

**Dependencies:** 1.1

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
- documented fields.
- AC-1.2.b: Missing `stokd` yields structured code 127, not `fatalError`.
- AC-1.2.c: Fixture JSON without lander fields never produces a pid or
- queue total.
- AC-1.2.d: `rg` over the new sources finds no `land explain` JSON parse.
- AC-1.2.e: `./scripts/test-unit.sh -only-testing:cmuxTests/GdockWorktreePanelSnapshotTests CMUX_SKIP_ZIG_BUILD=1 test` exits 0.

### 1.3: Native table, detail, commits, panes, and ACTION chrome

**Dependencies:** 1.2

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

### 1.4: Navigation, marks, filter, and help

**Dependencies:** 1.1, 1.3

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

### 1.5: Mutating verbs: enqueue, shove, kill, disposition, handover

**Dependencies:** 1.2, 1.4

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
- covered; checked-out is refused.
- AC-1.5.c: Each disposition kind builds the required flags; cancel does
- not invoke `stokd`.
- AC-1.5.d: `g`/`L`/`v` argv tests pass; source scan finds no `git merge`
- / `git push` in the overlay module.
- AC-1.5.e: In-flight OPERATION clears after process exit.
- AC-1.5.f: Focused action test suite exits 0.

### 1.6: Localization, parity checklist, and tagged dogfood

**Dependencies:** 1.3, 1.4, 1.5

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

