# PRD: Gdock Worktree Panel (hold-to-show native port of `stokd worktree`)

## 0. Source Context

**Derived From:** Operator request (2026-08-31, with a screenshot of the live `stokd worktree` TUI):
build the worktree TUI "in non terminal form", displayed "over the center of the screen like a modal
but only while you are holding down the workspace view command which I want to be opt + shft + w",
where "it doesn't stay up when you let go of the key", with "all the features that worktree tui has
except built like an actual UI" — "feature parity", "port the entire thing". Source named by the
operator: `stokd-cloud/mono/main/apps/cli`, command `stokd worktree`.
**Feature Name:** Gdock Worktree Panel
**PRD Owner:** Brian Stoker (brian@stokd.cloud)
**Last Updated:** 2026-08-31
**Repository:** `stokd-cloud/gdock` (fork of `manaflow-ai/cmux`)
**Landing:** fork-only on `main`
**This task:** author this document only. It does not implement the feature, does not run
  `stokd project create`, and does not touch Swift.
**Authoring history:** this document is the merge of two independently authored PRDs for the same
  objective — task `7b7422a` and task `5cdf921` (see `## 6. Open Questions`, item 7).

### Summary

`stokd worktree` opens a crossterm panel over the repository: one row per linked worktree across
nine columns, a five-line detail block for the selection, a files pane that shows dirty paths for a
dirty tree and commits-ahead-with-files for a clean one, two permanently reserved repository lander
rows, an ACTION line, and a footer of single-key operations — mark, enqueue, shove, kill,
disposition, filter, refresh, help, and three handovers that exit the TUI into another `stokd`
command. It is 5,668 lines in `apps/cli/src/commands/worktree_list.rs`.

This project ports that surface into gdock as a native macOS panel, summoned by holding a new
`⌥⇧W` chord and dismissed when the chord's modifiers are released. Nothing about the port invents a
second source of truth: rows come from `stokd worktree list --json`, per-worktree file and commit
detail comes from `git` in the worktree, and every mutation runs the same `stokd` verb the TUI runs.

### Charter

**Problem.** The operator's worktree control surface only exists inside a terminal session. Using it
means finding or opening a shell, running a command, and losing the pane to a full-screen TUI. The
information it shows — which worktrees are dirty, which are queued to land, which have live agents,
what each one last did — is exactly the information wanted *while* working in gdock, at a glance,
without displacing anything.

**Intended change.** A press-and-hold heads-up panel: hold `⌥⇧W`, the panel appears centered over
the key window; act on it while held; release and it is gone with focus back where it was. Feature
parity with the TUI is the requirement, not a stretch goal — every column, pane, mode, key, and
guard is ported or explicitly named as a gap.

**Why now.** gdock already owns every dependency: `StokdCLIRunner` and `StokdExecutableResolver`
invoke `stokd`, `CmuxGit` reads repository state, `WindowScopedShortcutHintModifierMonitor` is a
working modifier-hold monitor with app-resign safety, and `GdockSessionCyclerWindowController`
(landed 2026-08-31) is a floating panel overlay with a key monitor, activation, and focus restore.
The port is assembly plus a faithful reading of the Rust, not new infrastructure.

**Success.** The operator stops opening a terminal to answer "what is the state of my worktrees",
and every operation they previously ran from the TUI footer is one held chord away.

**Explicitly accepted risk.** Three fields the TUI renders are computed in-process by the Rust and
have no machine-readable surface for any non-Rust client: `queue_position`, `land_detail`, and the
whole `RepoLanderStatus` block (lander presence/pid, queue totals, current, next). This project
renders them as explicitly unknown rather than fabricating them or re-implementing the CLI's
internals in Swift, and proposes the CLI-side follow-up in `## 6. Open Questions`.

### Investigation Summary

Six read-only lanes, all against primary sources in this session.

**Lane 1 — TUI surface (`apps/cli/src/commands/worktree_list.rs`).** Nine columns
(`WORKTREE`, `STATE`, `SYNC`, `AGENTS`, `CHANGED`, `LAND`, `STATUS`, `DISPOSITION`, `OPERATION`,
`render_tui_header`). Two focus panes (`FocusPane::{Worktrees, DirtyFiles}`). Six UI modes
(`UiMode::{Browse, Help, Filter, ConfirmKill, ConfirmDeleteDirty, DispositionPick,
DispositionReason}`). Row model `WorktreeRow` carries branch, path, rel_path, is_primary,
is_bare_hub, dirty, merged, ahead, behind, hash, title, status, land_state, land_detail,
disposition, active_agents, last_change_secs_ago, queue_position, and a live `RowOp`
(`Idle | Shoving | Killing | Disposing | Message`). Constants: `MAX_VISIBLE_WORKTREE_ROWS = 10`,
`MAX_DIRTY_FILES = 200`, `MAX_COMMIT_FILE_LINES = 200`, `MAX_COMMITS_IN_PANE = 30`,
`SELECTION_DETAIL_LINES = 5`, `POLL_INTERVAL = 2500ms`.

**Lane 2 — keys and modes.** `↑/k`, `↓/j`, `PageUp`, `PageDown`, `Home`, `End`
(`apply_browse_nav_key`); `Tab` switches focus pane; `Space` marks; `l` enqueues; `s` shoves;
`x` kills behind a `[y/N]` confirm; `d` opens the disposition picker (`1` dev_complete, `2` blocked,
`3` abandon, `4` needs-input, then optional reason/blocker/question entry); `d` in the files pane
discards one dirty file behind a confirm; `/` filters; `r` refreshes; `?` toggles help; `Enter`
shows detail; `g`/`L`/`v` hand over to `integrate` / `worktree land` / `worktree review`;
`q`/`Esc` exits.

**Lane 3 — mutation verbs.** Every mutation shells out: `stokd shove` with `current_dir(path)`;
`stokd disposition <kind> [--hash --reason --blocker --question]` with `current_dir(path)`; kill is
raw git (`remove_worktree` then `git branch -D`, refusing when
`branch_checked_out_in_any_worktree`, and refusing outright for primary, detached, empty, or
protected branches per `kill_eligible`); enqueue is *not* a land — `plan_enqueue` stages
`disposition dev_complete` per target and `debug_assert!(!enqueue_would_spawn_land(&plan))`;
handovers exit the TUI and exec another `stokd` invocation. Child output is passed through
`run_tui_action_guarded` and `sanitize_action_text` before it can reach the frame.

**Lane 4 — data surfaces available to a non-Rust client.** `stokd worktree list --json` emits
branch, path, rel_path, dirty, merged, ahead, behind, active_agents, last_change_secs_ago,
last_change, hash, title, status, land_state, disposition, primary (`render_json_array`). It does
**not** emit queue_position, land_detail, or is_bare_hub, and there is no JSON verb for
`RepoLanderStatus` — `collect_repo_lander_status` reads config, resolves a local repo id, checks a
lander pidfile, and calls `ApiClient::get_landing_queue`. `stokd land explain` has no `--json`.
Dirty files, commits ahead of base, and commit file lists are plain `git` in the worktree.

**Lane 5 — gdock reuse.** `WindowScopedShortcutHintModifierMonitor` (flagsChanged monitor, hold
delay timer, `NSApplication.didResignActiveNotification` reset) is the hold-to-show pattern.
`GdockSessionCyclerWindowController` is the floating-panel pattern: local key monitor, dismiss on
resign-key, activation that focuses a target window/workspace/panel, and focus restore.
`StokdCLIRunner.run(directory:arguments:timeout:)` is the subprocess seam. `CmuxGit` is the git
seam. The `Gdock*` naming and the `gdock.*` / `palette.gdock.*` id conventions are established in
`docs/gdock-agent-conventions.md`.

**Lane 6 — chord availability.** `⌥⇧W` is unbound in `KeyboardShortcutSettings`; the existing `W`
chords are `⌘W` (closeTab), `⌘⇧W` (closeWorkspace), and `⌃⌘W` (closeWindow). No default collision.

**Decision recorded during investigation.** A press-and-hold panel and a twelve-key interactive
surface are in tension: an operator cannot type a filter string or a blocker reason while holding
two modifiers. The resolution adopted here is the Cmd-Tab grammar — the panel is summoned by the
full chord and stays up while `⌥⇧` remain held, so navigation and single-key actions work under the
hold; flows that need typing or a destructive confirmation require an explicit pin, and an unpinned
panel always vanishes on modifier release exactly as the operator asked. Alternatives are recorded
in `## 6. Open Questions`.

### Source inventory (read-only)

| Source | Role |
|---|---|
| `stokd-cloud/mono` `apps/cli/src/commands/worktree_list.rs` | Parity oracle for columns, modes, keys, actions |
| Live `stokd worktree` TUI screenshot 2026-08-31 | Operator visual target |
| `GdockSessionCyclerWindowController` | Floating overlay precedent |
| `WindowScopedShortcutHintModifierMonitor` | Hold-to-show flagsChanged monitor |
| `StokdCLIRunner` / `StokdExecutableResolver` | Process boundary for `stokd` |
| `CmuxGit` | Git seam for dirty paths, commits, and commit file lists |
| `docs/stokd-worktrees-panel.prd.md` | **Different** product: the left-rail read+open worktree list. Not this panel. |
| `docs/stokd-work-panel.prd.md` | Shared CLI runner / localization / test-wiring conventions |

## 1. Objectives & Constraints

### Objectives

- Hold `⌥⇧W` and see the worktree surface centered over the key window; release and it is gone.
- Reach every operation the TUI footer offers, from the panel, without a terminal.
- Show exactly what the TUI shows, derived from the same data the CLI derives it from.
- Name every parity gap in the UI itself rather than rendering a confident wrong value.
- Leave gdock's typing latency, list-boundary, localization, and shortcut policies intact.

### Constraints

- Fork conventions: new settings are `gdock.*`, one-shot palette ids are `palette.gdock.*`, toggles
  are `palette.toggleSetting.gdock.*`, and new settings live in `GdockCatalogSection`
  (`CLAUDE.md`, `docs/gdock-agent-conventions.md`).
- gdock is a strict consumer of stokd state: it never writes under `~/.stokd`, and it never
  re-derives stokd's on-disk layout outside `StokdWorkspaceStatePaths`
  (AX-GDOCK-PANEL-CARD-SESSION-SUMMARY).
- No view below a lazy container may hold an observable store reference, and no function called from
  `body` may write state (`CLAUDE.md`; cmux issue 2586).
- No subprocess, git invocation, or network call may run on the main thread.
- Every user-facing string is `String(localized:)` with English and Japanese entries in
  `Resources/Localizable.xcstrings`.
- Swift test files must be wired into `cmux.xcodeproj` or they are silently skipped
  (`scripts/lint-pbxproj-test-wiring.sh`).
- Stokd projects bind to one repository. This project is scoped to `stokd-cloud/gdock`; no work item
  edits `stokd-cloud/mono`.
- Fork-only. Every work item lands on `stokd-cloud/gdock` `main`; nothing here is an upstream cmux
  change.
- This is **not** the left-rail Worktrees section specified in `docs/stokd-worktrees-panel.prd.md`.
  That surface stays a read+open list; this PRD is the hold-to-show operator console.
- The Bonsplit submodule SHA is unchanged by this project.

### Scope Inventory

| # | Surface | In scope |
|---|---------|----------|
| 1 | Chord lifecycle | `⌥⇧W` keyDown shows; `⌥⇧` release hides; autorepeat, missed key-up, app deactivation, window close |
| 2 | Panel chrome | Centered floating panel over the key window, above terminal portals; focus restore on dismiss |
| 3 | Pin | Explicit pin for flows that need typing or confirmation; unpinned release always dismisses |
| 3.5 | Row population | The TUI's operator view: primary, bare hub, and lander scratch worktrees excluded |
| 4 | Table | Nine columns, per-column formatting, selection chevron, mark glyph, ≥10-row scroll window with a range indicator |
| 5 | Sort | Projects → tasks → other; then operator status rank; then recency; then branch |
| 6 | Filter | Case-insensitive substring over branch, rel_path, title, status, land_state, disposition |
| 7 | Detail block | Five lines: BRANCH, PATH, ID, HASH, STATE (with the LANDER swap on land failure) |
| 8 | Files pane | Dirty paths when dirty; commits + files when clean; loading state; overflow counts; caps |
| 9 | Focus panes | Tab between worktrees and files; pane-local navigation and pane-local `d` |
| 10 | Lander block | Two lander rows plus the ACTION line, with explicit unknown states |
| 11 | Mark + enqueue | Space marks; `l` stages `disposition dev_complete` per target; never spawns a parallel land; reports staged/already/skipped |
| 12 | Shove | `stokd shove` in the worktree directory with an in-flight row state |
| 13 | Kill | Eligibility guard, confirmation, worktree removal, branch delete with checked-out guard |
| 14 | Disposition | Picker (1–4) plus reason / blocker / question entry, then `stokd disposition` |
| 15 | Discard file | Per-file discard from the dirty pane behind a confirmation |
| 16 | Handovers | `g` integrate, `L` worktree land, `v` worktree review |
| 17 | Busy guard | A row with an operation in flight refuses a second operation |
| 18 | Refresh | 2.5s background poll, manual `r`, last-good snapshot, in-flight op preservation |
| 19 | Help | The TUI's help content, reachable from the panel |
| 20 | Settings + palette | Editable `gdock.*` shortcut action and `palette.gdock.*` commands |
| 21 | Localization | English and Japanese for every new string |
| 21.5 | Degraded states | No worktrees, missing `stokd`, not a repository, failed snapshot — each distinct |
| 22 | Accessibility | Labels for rows and status lines; keyboard-only operation |

### Non-Goals

- Editing `stokd-cloud/mono`. The missing CLI JSON surface is proposed, not built, here.
- Replacing or deprecating the `stokd worktree` TUI, which remains the terminal-side surface.
- Cross-repository worktree browsing. The panel shows the repository of the key window's workspace,
  exactly as the TUI shows the repository it was run in.
- Mouse-driven layout customization: column resizing, reordering, or hiding.
- A persistent, always-on worktree sidebar panel. This surface is summoned and dismissed.
- Replacing or extending the left-rail Worktrees section from `docs/stokd-worktrees-panel.prd.md`.
  That PRD's behavior must be unchanged when this one ships.
- Canvas placement or dock-anywhere positioning for this panel.
- Upstream cmux pull requests. This is fork-only work.
- Any new landing, merging, or branch-protection behavior. The panel triggers existing verbs only.

## 1.5 Required Toolchain

| Tool | Min Version | Install Command | Verify Command |
|------|-------------|-----------------|----------------|
| macOS | 14.0 | (OS) | `sw_vers -productVersion` |
| Xcode | 26.0 | Apple Developer downloads | `xcodebuild -version` |
| Swift | 6.0 | (bundled with Xcode) | `swift --version` |
| stokd CLI | 0.2.221 | `curl -fsSL https://stokd.cloud/install.sh \| sh` | `stokd --version` |
| Python 3 | 3.9 | `xcode-select --install` | `python3 --version` |
| git | 2.40 | `xcode-select --install` | `git --version` |

Working directory for all Verification Commands: the gdock repository root.

```bash
./scripts/setup.sh   # once per machine if GhosttyKit is missing
```

Prefer `CMUX_SKIP_ZIG_BUILD=1` on tagged reloads when the host zig is not 0.15.2.

## 2. Contract

**VAL-CHORD-001** — Holding the chord shows the panel; releasing it hides the panel.
Surface: tui
Needs: none
Behavior: pressing `W` while `⌥` and `⇧` are held presents the worktree panel centered over the key
  window, and releasing either modifier dismisses it, with no dismissal required from the operator.
Evidence: a UI test that synthesizes the chord key-down, asserts the panel controller reports
  visible, synthesizes a flags-changed event dropping `⌥`, and asserts it reports not visible.
Rigor: R3
Why: the whole feature is reachable only through this lifecycle, and a wrong edge leaves the panel
  either unreachable or stuck over the operator's work.
Fail: the panel stays on screen after the modifiers are released, or never appears while they are
  held.

**VAL-CHORD-002** — The panel is never stranded on screen.
Surface: tui
Needs: VAL-CHORD-001
Behavior: the panel hides on every path that can end a hold — modifier release, key-up of `W` while
  unpinned, application deactivation, key-window change, and screen lock — and key auto-repeat while
  the chord is held neither re-presents nor flickers it.
Evidence: one test per termination path driving the controller's event entry points and asserting a
  single hide, plus an auto-repeat test asserting the presentation count stays at one.
Rigor: R3
Why: a missed key-up is the classic hold-to-show defect and leaves a floating panel covering the
  operator's terminal with no obvious way to remove it.
Fail: an unpinned panel outlives its hold after focus moves to another application.

**VAL-CHORD-003** — The chord is a first-class, editable gdock shortcut.
Surface: tui
Needs: none
Behavior: `gdock.worktreePanel` exists in both `ShortcutAction` and the `KeyboardShortcutSettings`
  mirror with a default of `⌥⇧W`, is editable in Settings and `cmux.json`, is listed in
  `web/data/cmux-shortcuts.ts` and the config schema, and no other action's default binds `⌥⇧W`.
Evidence: a Swift test asserting the default stroke on both types and asserting no other
  `Action.allCases` default equals it, plus a grep for the id in the web catalog and schema.
Rigor: R2
Why: shortcut policy is repo-wide and mechanically checkable, but a silent collision would make one
  of two actions unreachable.
Fail: two actions ship with the same default chord.

**VAL-CHORD-004** — A pinned panel survives the release; an unpinned one never does.
Surface: tui
Needs: VAL-CHORD-001
Behavior: an explicit pin action keeps the panel open after the modifiers are released so filter
  text and disposition reasons can be typed, and a pinned panel dismisses only on `Esc`, on
  activation, or on an explicit unpin; a panel that was never pinned always dismisses on release.
Evidence: a test that pins, releases the modifiers, asserts still visible, then dismisses with
  `Esc`; and a paired test that never pins and asserts hidden on release.
Rigor: R3
Why: this is the only mechanism that reconciles "gone when you let go" with a surface whose flows
  require typing, so both halves must be provably true.
Fail: an unpinned panel persists after release, or a pinned panel vanishes mid-typing.

**VAL-PANEL-001** — The panel presents centered, above terminal content, and returns focus.
Surface: tui
Needs: VAL-CHORD-001
Behavior: the panel is centered over the key window's frame, draws above portal-hosted terminal and
  browser views, takes key focus while shown, and on dismissal returns key focus to the window that
  held it when the panel appeared.
Evidence: a test asserting the computed frame is centered on an injected reference frame; a focus
  test asserting the recorded restore target is made key on dismiss; and an assertion that the
  panel's window level is above the main window's level, which is the property that keeps
  portal-hosted terminal views from covering it.
Rigor: R3
Why: portal-hosted terminal views sit above SwiftUI during split and workspace churn, so "on top" is
  a real property to prove, not an assumption.
Fail: the panel renders behind a terminal surface, or focus lands somewhere other than where the
  operator was.

**VAL-PANEL-002** — The panel costs nothing when it is closed and does not regress typing.
Surface: tui
Needs: VAL-PANEL-001
Behavior: with the panel closed no polling, subprocess, or git work runs for it, and no view inside
  the panel holds a reference to an observable store.
Evidence: a test asserting the refresh scheduler performs zero work while not presented, and a test
  that constructs every panel row view from value inputs alone with no store in scope and asserts
  the view is `Equatable` — a view holding a store reference cannot satisfy either half.
Rigor: R3
Why: an always-on 2.5s poll of every worktree would tax the machine for a surface that is usually
  not visible, and a store reference below a lazy container reintroduces a known 100%-CPU spin.
Fail: closing the panel leaves a repeating timer or subprocess cadence running.

**VAL-PANEL-003** — The panel is a floating centered surface, not a rail, tab, or terminal.
Surface: tui
Needs: VAL-PANEL-001
Behavior: the worktree surface mounts as a floating panel controller following the session-cycler
  precedent; it registers no `SidebarDockStore` kind, adds no rail tab, hosts no terminal surface,
  and creates no persistent window, so the existing left-rail Worktrees section is untouched.
Evidence: a source-level check that the controller is the floating-panel host and that the panel
  module registers no sidebar dock kind and instantiates no terminal surface, plus a tagged dogfood
  screenshot showing the centered panel.
Rigor: R2
Why: placement is structural, and the fork already ships a left-rail worktree list, so a port that
  lands as a rail section would silently duplicate a different product.
Fail: the surface appears as a left-rail Worktrees section, a right-rail tool, an embedded terminal,
  or a window that outlives the hold.

**VAL-TABLE-001** — The table renders the TUI's nine columns with the TUI's values.
Surface: parity
Needs: VAL-DATA-001
Behavior: each row shows identity (with the `PRJ:` / `TSK:` prefix), dirty state, `↑ahead ↓behind`,
  agent count, relative change age, land state, status, disposition, and the operation cell, with
  the operation cell resolving in the TUI's order: in-flight op, then land-failure detail, then
  queue chip, then `·`.
Evidence: a table-driven test whose expected cells are transcribed from `render_tui_row`,
  `row_operation_display`, `format_land_state`, `format_dirty`, and `format_relative_age`, covering
  idle, shoving, killing, disposing, land-failed, and queued rows.
Rigor: R5
Why: this is the operator's stated bar — feature parity — and the only way to hold it is to
  adjudicate against the Rust that defines each cell.
Fail: a column silently drops a state the TUI renders, so the panel disagrees with the terminal.
Oracle: `apps/cli/src/commands/worktree_list.rs` cell renderers in `stokd-cloud/mono`, transcribed
  into the test fixture with the function name and value recorded per case.

**VAL-TABLE-002** — Rows sort exactly as the TUI sorts them.
Surface: parity
Needs: VAL-DATA-001
Behavior: rows order by identity family (projects, then tasks, then other), then by operator status
  rank, then by most recent change with unknown ages last, then by branch name.
Evidence: a test over a fixture exercising every tie-break level in turn, asserting the full ordering
  against the order `sort_operator_rows` produces for the same input.
Rigor: R5
Why: order is what makes the panel scannable, and a subtly different comparator produces a list that
  looks right and is not.
Fail: two rows that the TUI orders deterministically appear in the opposite order.
Oracle: `sort_operator_rows` and `operator_status_rank` in `worktree_list.rs`.

**VAL-TABLE-003** — Selection, marking, and the scroll window behave as the TUI's do.
Surface: tui
Needs: VAL-TABLE-001
Behavior: navigation keys move the selection with the TUI's semantics, `Space` toggles a mark on the
  selected row, marked rows render a mark glyph independent of selection, and with more than ten
  rows the visible window follows the selection and a `rows N–M of T` indicator appears.
Evidence: tests for each navigation key, for mark toggling and multi-mark accumulation, and for the
  window range and indicator text at boundary selections.
Rigor: R2
Why: pure list-state logic, fully determined by unit tests over value inputs.
Fail: marking a row clears another row's mark, or the selection scrolls out of view.

**VAL-TABLE-005** — The panel lists the rows the TUI lists, not the rows the JSON returns.
Surface: parity
Needs: VAL-DATA-001
Behavior: the panel excludes the primary worktree, the bare hub, and lander scratch worktrees from
  its list, matching the TUI's operator view rather than the unfiltered `--json` document, which
  deliberately keeps them.
Evidence: a test over a fixture containing a primary, a bare hub, a lander scratch, and two ordinary
  worktrees, asserting exactly the two ordinary rows survive; and a test asserting the same document
  decodes to five rows before the view filter, so the exclusion is the panel's and not the decoder's.
Rigor: R5
Why: `--json` and the TUI view are deliberately different populations, so a port that renders the
  JSON verbatim disagrees with the terminal on its very first row while looking entirely plausible.
Fail: the primary worktree appears in the panel and can be selected for kill.
Oracle: the TUI-only row exclusion in `worktree_list.rs` (documented in-source as dropping primary,
  bare hub, and lander scratch, with `--json` / `--plain` keeping the full topology).

**VAL-TABLE-004** — Filtering narrows over the TUI's six fields.
Surface: parity
Needs: VAL-TABLE-001
Behavior: a filter string case-insensitively substring-matches branch, relative path, title, status,
  land state, and disposition; an empty filter restores every row; and filtering derives from the
  last-good snapshot so a failed refresh cannot empty the list.
Evidence: one test per matched field, a clearing test, and a test that changes the filter after an
  injected refresh failure and still gets rows.
Rigor: R3
Why: the field set is a parity claim, and the last-good derivation is the property that keeps the
  panel usable exactly when the repository is misbehaving.
Fail: filtering against a failed refresh yields an empty panel.

**VAL-DETAIL-001** — The selection detail block matches the TUI's five lines.
Surface: parity
Needs: VAL-TABLE-001
Behavior: the detail block always renders five lines — BRANCH, PATH, ID, HASH, and the composite
  STATE line — and when the selection's land state is a failure the last line is replaced by a
  LANDER line carrying the failure reason.
Evidence: tests asserting exactly five lines for a normal row, for no selection, and for a
  land-failed row where the LANDER line replaces the fifth.
Rigor: R3
Why: the line count is contractual in the source (`SELECTION_DETAIL_LINES`) and the failure swap is
  the operator's only in-panel view of why a land failed.
Fail: a land failure reason is shown nowhere in the panel.

**VAL-FILES-001** — The files pane shows dirty paths, or commits and their files.
Surface: parity
Needs: VAL-DATA-001
Behavior: a dirty worktree lists its dirty paths capped at 200 with an overflow count; a clean one
  lists up to 30 commits ahead of base with their files capped at 200 lines and its own overflow
  count; a worktree with neither reports no commits ahead of base; and a pending load reports
  loading rather than emptiness.
Evidence: tests for each of the four pane states, including the exact cap and overflow arithmetic at
  201 dirty paths and at 31 commits.
Rigor: R3
Why: the caps exist so a huge worktree cannot wedge the surface, and an uncapped port would hang the
  panel on precisely the repositories that most need triage.
Fail: a loading pane is indistinguishable from an empty one.

**VAL-FILES-002** — The files pane is a focus target and can discard a single file.
Surface: tui
Needs: VAL-FILES-001
Behavior: `Tab` moves focus between the worktree list and the files pane, navigation keys apply to
  the focused pane, and `d` on a dirty file discards that file's changes only after an explicit
  confirmation naming the path.
Evidence: a focus-switch test, a pane-local navigation test, and a discard test asserting no git
  mutation runs until the confirmation is accepted and that the invoked command targets exactly the
  selected path.
Rigor: R3
Why: this is destructive and irreversible, so the confirmation gate is the assertion, not the
  discard itself.
Fail: a keystroke discards a file without a confirmation, or discards the wrong path.

**VAL-LANDER-001** — The lander block reports what is known and admits what is not.
Surface: tui
Needs: VAL-DATA-001
Behavior: the panel reserves the TUI's two lander rows and its ACTION line; the ACTION line reads
  idle when nothing is running and names the in-flight verb while an operation is running; when
  lander presence or queue data cannot be obtained the rows say so explicitly, and an unavailable
  queue never renders as an empty queue.
Evidence: tests over the available, unavailable, and error states asserting the rendered text differs
  in each and that the unavailable case contains an explicit unknown marker rather than a zero, plus
  a test asserting the ACTION line moves from idle to the named verb and back across an operation.
Rigor: R2
Why: string-level rendering over injected values, but the honesty property has to be pinned because
  the failure is silent and misleading.
Fail: "queue 0" is shown when the queue could not be read.

**VAL-ACT-001** — Shove runs the CLI's shove in the selected worktree.
Surface: tui
Needs: VAL-TABLE-003
Behavior: `s` runs `stokd shove` with the selected worktree as the working directory, marks the row
  as shoving while it runs, and reports success or a sanitized failure when it finishes.
Evidence: a test with an injected command runner asserting the executable, argument vector, and
  working directory, plus the row-state transition into and out of the in-flight state.
Rigor: R3
Why: a wrong working directory would shove the wrong branch, which is a remote-visible mistake.
Fail: shove runs against the primary worktree instead of the selected one.

**VAL-ACT-002** — Kill refuses protected worktrees and confirms before removing anything.
Surface: tui
Needs: VAL-TABLE-003
Behavior: `x` is refused for the primary worktree, a detached or empty branch, and any protected
  branch; for an eligible row it requires an explicit confirmation naming the worktree, then removes
  the worktree and deletes its branch, refusing the branch delete when that branch is still checked
  out in another worktree.
Evidence: one test per refusal reason asserting no command runs, a confirmation test asserting no
  mutation before acceptance, and a checked-out-elsewhere test asserting the branch survives with a
  reported reason.
Rigor: R4
Why: this destroys a worktree and a branch; a defect here loses uncommitted operator work, so one
  validation lane is not enough.
Fail: the primary worktree, or a branch checked out elsewhere, is removed.

**VAL-ACT-003** — Disposition offers the TUI's four kinds and their reason fields.
Surface: tui
Needs: VAL-TABLE-003
Behavior: `d` offers dev_complete, blocked, abandon, and needs-input; the kinds that take free text
  collect reason, blocker, or question first; and the panel then runs `stokd disposition <kind>` in
  the worktree with the collected values and the row's hash when it has one.
Evidence: a mapping test from each picker key to its kind spelling, and command tests asserting the
  argument vector for a bare disposition and for one carrying every optional field.
Rigor: R3
Why: disposition drives the lander, so a wrong kind or a dropped reason changes what happens to the
  operator's branch.
Fail: a typed blocker reason is dropped and a blocked item is recorded with no cause.

**VAL-ACT-004** — Enqueue stages dispositions and never starts a parallel land.
Surface: tui
Needs: VAL-ACT-003
Behavior: `l` targets the marked rows, or the selection when nothing is marked, stages
  `disposition dev_complete` for each target that is not already queued or landing, skips rows that
  are in flight, clears the marks, and reports staged, already-queued, and skipped counts; it never
  invokes a land command.
Evidence: a planner test over a mixed fixture asserting the per-row action, an assertion that no
  planned action maps to a land invocation, and a reporting test asserting the three counts.
Rigor: R4
Why: the CLI carries a debug assertion against exactly this mistake because parallel lands corrupt
  the serialized landing queue; the port must carry the same guarantee.
Fail: enqueue spawns a land process alongside the lander.

**VAL-ACT-005** — A row with work in flight refuses further operations.
Surface: tui
Needs: VAL-ACT-001
Behavior: while a row is shoving, killing, or disposing, shove, kill, and disposition on that row are
  refused with a busy message, and other rows remain operable.
Evidence: a test per operation asserting refusal and no command dispatch for the busy row, plus one
  asserting a different row still dispatches.
Rigor: R2
Why: pure guard logic over row state, but without it the operator can double-fire a mutation.
Fail: two dispositions run against one worktree at once.

**VAL-HAND-001** — The three handovers dismiss the panel and run the CLI's handover commands.
Surface: tui
Needs: VAL-TABLE-003
Behavior: `g` hands over to `stokd integrate <hash>` and is refused with a message when the row has
  no hash, `L` to `stokd worktree land --cwd <path>`, and `v` to `stokd worktree review --worktree
  <path>`; each dismisses the panel first and surfaces the command's outcome to the operator.
Evidence: command tests asserting each argument vector, a no-hash refusal test, a test asserting
  the panel is hidden before the command is dispatched, and a source-level check that the panel
  module never invokes `git merge` or `git push` itself.
Rigor: R3
Why: these are long-running foreground operations in the TUI; leaving a modal panel over them would
  hide their output entirely.
Fail: a handover runs behind a panel the operator cannot see past, or the panel lands, merges, or
  pushes on its own instead of handing over.

**VAL-DATA-001** — One snapshot source feeds the whole panel.
Surface: data
Needs: none
Behavior: rows come from `stokd worktree list --json` and per-worktree file and commit detail comes
  from git in that worktree; the panel derives no stokd state path itself and writes nothing under
  `~/.stokd`.
Evidence: a decoding test over a captured `--json` document covering every documented field, and a
  source-level check that the panel opens no path under `~/.stokd` for writing and derives none
  outside `StokdWorkspaceStatePaths`.
Rigor: R4
Why: a second derivation of stokd state drifts silently the moment the CLI changes, which is the
  exact failure the panel-card axiom already exists to prevent.
Fail: the panel shows a state the CLI does not agree with.

**VAL-DATA-002** — Refreshing is background work with a last-good snapshot.
Surface: tui
Needs: VAL-DATA-001
Behavior: while presented the panel refreshes on a 2.5-second cadence and on demand, collapses
  overlapping refreshes, performs every subprocess and git call off the main thread, keeps the last
  good snapshot when a refresh fails, and preserves in-flight row operations across a refresh.
Evidence: a scheduler test asserting no overlapping request, a failure test asserting rows survive,
  an op-preservation test across a merged refresh, and a threading assertion that the collector never
  runs on the main queue.
Rigor: R3
Why: a main-thread subprocess in a panel that polls every 2.5 seconds is a visible stall in a
  typing-latency-sensitive application.
Fail: a failed refresh blanks the panel, or an in-flight shove loses its row state.

**VAL-DATA-003** — Child process output is sanitized before it reaches the panel.
Surface: tui
Needs: VAL-DATA-001
Behavior: any text taken from a child process — git errors, `stokd` output, failure reasons — is
  stripped of control and escape sequences and bounded in length before being displayed.
Evidence: a test feeding output containing ANSI escapes, carriage returns, and an oversized line, and
  asserting the displayed string is plain and bounded.
Rigor: R3
Why: the TUI sanitizes for exactly this reason, and unsanitized child output rendered into a live
  surface is both a corruption and an injection vector.
Fail: a git error containing escape sequences corrupts the panel's rendering.

**VAL-DATA-004** — Empty, unavailable, and broken states are distinguishable from each other.
Surface: tui
Needs: VAL-DATA-001
Behavior: a repository with no non-primary worktrees, a missing or non-executable `stokd`, a
  directory that is not a git repository, and a snapshot command that failed each produce a distinct
  explanatory panel state naming what happened and what to do about it. None of them terminates the
  process, and a failure raised while an operation is in flight leaves the panel presented and
  pinned with the error on the ACTION line rather than dismissing it under the operator.
Evidence: one test per state asserting a distinct rendered message, an assertion that none of the
  four renders as a bare empty table, an assertion that a missing binary surfaces as a structured
  exit-127 result rather than a trap, and a test asserting an in-flight failure leaves the panel
  presented and pinned.
Rigor: R3
Why: these states are common on a fresh machine and in a non-repository window, and an unexplained
  empty panel reads as "you have no worktrees", which is a lie in three of the four cases.
Fail: a missing `stokd` binary is indistinguishable from a repository with no worktrees.

**VAL-PARITY-001** — Every TUI key has a panel affordance.
Surface: parity
Needs: VAL-CHORD-004
Behavior: each operation in the TUI's help footer — navigate, Tab, Enter, Space, `l`, `s`, `x`, `d`,
  `g`, `L`, `v`, `/`, `r`, `?`, and dismiss — is reachable from the panel, and the panel's own help
  lists them.
Evidence: a test that enumerates the panel's key map and asserts, per key, that it dispatches to a
  named operation drawn from a closed enumeration of panel operations — presence of a handler is not
  sufficient, and a handler that dispatches to no operation fails the test. The expected key set is
  transcribed from `render_worktree_help_frame`, so the test fails if the TUI gains a key the panel
  lacks.
Rigor: R5
Why: "feature parity" is the operator's explicit acceptance bar, so the key set must be adjudicated
  against the source rather than reviewed by eye.
Fail: an operation exists in the terminal and has no equivalent in the panel.
Oracle: the help lines in `render_worktree_help_frame` and the `UiMode::Browse` key handler in
  `worktree_list.rs`.

**VAL-PARITY-002** — Unavailable fields render as unknown, never as invented values.
Surface: parity
Needs: VAL-DATA-001
Behavior: queue position, land failure detail, and lander presence are rendered as explicitly unknown
  whenever the data is not available to the panel, and the panel's help or an inline note names them
  as known gaps against the TUI.
Evidence: tests asserting the unknown rendering for each of the three fields when absent, and a check
  that the gap note names all three.
Rigor: R4
Why: the honest failure of a port is a missing field; the dishonest one is a plausible wrong value,
  and only the second can make an operator land the wrong branch.
Fail: the panel shows queue position 0 for a worktree whose queue position it cannot read.

**VAL-SET-001** — The panel follows the fork's setting and palette conventions.
Surface: tui
Needs: VAL-CHORD-003
Behavior: every new setting id and UserDefaults key is prefixed `gdock.` and lives in
  `GdockCatalogSection`, one-shot palette commands are prefixed `palette.gdock.`, and the panel is
  reachable from the command palette as well as the chord.
Evidence: a test asserting the palette command ids and the setting id prefixes, plus a grep asserting
  no new key lands under an upstream prefix.
Rigor: R2
Why: mechanically checkable, and violations only surface later as merge collisions with upstream.
Fail: a fork-only key ships under `app.*` or `sidebar.*`.

**VAL-L10N-001** — Every new string is localized in English and Japanese.
Surface: artifact
Needs: none
Behavior: each user-facing string the panel introduces is declared with `String(localized:)` and has
  English and Japanese entries in `Resources/Localizable.xcstrings`.
Evidence: a script that extracts the panel's localization keys from source and asserts each has both
  localizations in the catalog.
Rigor: R1
Why: decided by extraction and lookup, with the evidence persisted as the script's output.
Fail: a panel string ships English-only.

**VAL-A11Y-001** — The panel is operable and legible without a mouse.
Surface: tui
Needs: VAL-TABLE-003
Behavior: every row exposes an accessibility label naming its worktree, state, and land status; the
  lander and action lines are exposed; and every operation is reachable from the keyboard alone.
Evidence: tests asserting the composed accessibility label for representative rows, and a keyboard
  reachability test over the registered handlers.
Rigor: R2
Why: composed-label logic is unit-testable, and this surface is keyboard-summoned so keyboard-only
  operation is its normal mode rather than an accommodation.
Fail: a row's state is conveyed only by color.

### Oracle

The adjudicating implementation is `stokd-cloud/mono`, file
`apps/cli/src/commands/worktree_list.rs`, at the revision recorded in the evidence for each parity
assertion. It adjudicates all eight `parity`-surface assertions:

| Assertion | Oracle symbols |
|-----------|----------------|
| VAL-TABLE-001 | `render_tui_row`, `render_tui_header`, `row_operation_display`, `format_land_state`, `format_dirty`, `format_relative_age`, `styled_identity_cell`, `styled_agents_cell` |
| VAL-TABLE-002 | `sort_operator_rows`, `operator_status_rank`, `identity_kind` |
| VAL-TABLE-004 | `filter_rows`, `visible_rows` |
| VAL-TABLE-005 | the TUI-only row exclusion of primary, bare hub, and lander scratch worktrees |
| VAL-DETAIL-001 | `format_selection_detail_lines`, `SELECTION_DETAIL_LINES`, `format_land_failure_detail` |
| VAL-FILES-001 | `MAX_DIRTY_FILES`, `MAX_COMMIT_FILE_LINES`, `MAX_COMMITS_IN_PANE`, pane header construction |
| VAL-PARITY-001 | `render_worktree_help_frame`, the `UiMode::Browse` key handler |
| VAL-PARITY-002 | `render_json_array` (the fields `--json` does and does not emit) and `collect_repo_lander_status` (the block it has no JSON verb for) |

Oracle use is transcription, not linkage: gdock does not build, vendor, or execute the Rust. Each
parity test records, per case, the oracle symbol and the exact expected value transcribed from it, so
a reviewer can re-derive the fixture from the named source without reading the port.

## 3. Execution Topology

## Phase 1: Port the worktree surface into gdock

**Purpose:** the panel is one coherent surface — data, view model, chord, actions, and handovers all
have to exist before any of it is usable, and no intermediate result changes a decision the operator
has not already made. Ordering lives in `**Dependencies:**`.

### 1.1 Snapshot source and background refresh

**Targets:** VAL-DATA-001, VAL-DATA-002, VAL-DATA-003, VAL-DATA-004, VAL-PARITY-002
**Dependencies:** []
**Landing:** fork-only

**Implementation Details**
- Add `GdockWorktreeSnapshot` value types mirroring the documented `stokd worktree list --json`
  fields: branch, path, rel_path, dirty, merged, ahead, behind, active_agents,
  last_change_secs_ago, last_change, hash, title, status, land_state, disposition, primary.
  Decoding is tolerant of unknown keys so a CLI addition does not break the panel.
- Add `GdockWorktreeSnapshotLoader` over `StokdCLIRunner` (`worktree list --json`) plus a git seam
  for per-worktree dirty paths, commits ahead of base, and commit file lists. All work runs off the
  main thread; results are published as immutable value snapshots.
- Fields the JSON cannot supply — `queue_position`, `land_detail`, lander presence and queue — are
  modeled as an explicit `.unknown` case, never as a default zero or empty string.
- Add a refresh scheduler with a 2.5-second cadence while presented, an in-flight guard that
  collapses overlapping requests, a manual refresh entry point, last-good snapshot retention on
  failure, and in-flight row-operation preservation across merges.
- Route every child-derived string through a `GdockWorktreeText.sanitize` helper that strips control
  and escape sequences and bounds length.

**Acceptance Criteria**
- AC-1.1.a: decoding a captured `--json` document yields one row per entry with every documented
  field populated.
- AC-1.1.b: a document containing an unknown key still decodes.
- AC-1.1.c: with the panel not presented, the scheduler performs zero refreshes.
- AC-1.1.d: a failed refresh leaves the previous rows intact and surfaces an error string.
- AC-1.1.e: a row marked in-flight keeps that state after a refresh merges new data.
- AC-1.1.f: sanitizing text containing ANSI escapes, `\r`, and 10,000 characters yields plain,
  bounded text.
- AC-1.1.g: absent queue position, land detail, and lander presence each decode to the unknown case.
- AC-1.1.h: no worktrees, missing `stokd`, not-a-repository, and command-failed each produce a
  distinct explanatory state, and none of them renders as a bare empty table.

**Acceptance Tests**
- Test-1.1.a: `GdockWorktreeSnapshotDecodingTests` — full-field and unknown-key documents.
- Test-1.1.b: `GdockWorktreeRefreshSchedulerTests` — idle, cadence, collapse, failure, preservation.
- Test-1.1.c: `GdockWorktreeTextSanitizeTests` — escapes, control characters, length bound.
- Test-1.1.d: `GdockWorktreeUnavailableStateTests` — the four empty/unavailable/broken states.

**Verification Commands**
```bash
./scripts/lint-pbxproj-test-wiring.sh
./scripts/test-unit.sh test \
  -only-testing:cmuxTests/GdockWorktreeSnapshotDecodingTests \
  -only-testing:cmuxTests/GdockWorktreeRefreshSchedulerTests \
  -only-testing:cmuxTests/GdockWorktreeTextSanitizeTests \
  -only-testing:cmuxTests/GdockWorktreeUnavailableStateTests
```

### 1.2 Rows, sorting, filtering, detail, and panes

**Targets:** VAL-TABLE-001, VAL-TABLE-002, VAL-TABLE-003, VAL-TABLE-004, VAL-TABLE-005, VAL-DETAIL-001, VAL-FILES-001, VAL-LANDER-001, VAL-PARITY-001
**Dependencies:** ["1.1"]
**Landing:** fork-only

**Implementation Details**
- Add `GdockWorktreeRowPresentation` producing the nine cells per row, transcribing the oracle
  renderers listed in `### Oracle`, including the operation cell's four-way precedence and the
  `PRJ:` / `TSK:` identity prefixes.
- Add `GdockWorktreeVisibleRows` applying the TUI's operator-view exclusion — primary, bare hub, and
  lander scratch worktrees are dropped — before any sorting or filtering. `--json` deliberately keeps
  those rows, so this exclusion is the panel's own and must not be pushed into the decoder.
- Add `GdockWorktreeSort` implementing the four-level comparator, and `GdockWorktreeFilter` matching
  case-insensitively over the six documented fields and deriving from the last-good snapshot.
- Add `GdockWorktreeDetail` producing exactly five lines with the land-failure swap, and
  `GdockWorktreeFilesPane` producing the dirty, commits, empty, and loading states with the 200 /
  200 / 30 caps and overflow counts.
- Add `GdockWorktreeLanderLines` producing the two lander rows and the ACTION line, with explicit
  unknown text for unavailable presence or queue data.
- Add `GdockWorktreeKeyMap` as the single registry of panel operations, so the parity test can
  enumerate it.
- All of these are pure functions over value inputs; no view holds a store reference.

**Acceptance Criteria**
- AC-1.2.a: each of the nine columns renders the oracle's value for idle, shoving, killing,
  disposing, land-failed, and queued fixtures.
- AC-1.2.b: sorting a fixture that exercises all four tie-break levels produces the oracle order.
- AC-1.2.c: each of the six filter fields matches case-insensitively, and clearing restores rows.
- AC-1.2.d: the detail block is five lines for a normal row, no selection, and a land-failed row.
- AC-1.2.e: the files pane produces distinct output for dirty, commits, empty, and loading, with
  correct overflow counts at 201 dirty paths and 31 commits.
- AC-1.2.f: lander lines differ across available, unavailable, and error states, and the unavailable
  state contains no numeric queue total.
- AC-1.2.g: the key map covers every key transcribed from the oracle help frame, and every mapped key
  dispatches to a named operation.
- AC-1.2.h: a fixture containing a primary, a bare hub, a lander scratch, and two ordinary worktrees
  yields exactly the two ordinary rows, while the same document decodes to five rows.

**Acceptance Tests**
- Test-1.2.a: `GdockWorktreeRowPresentationTests` — per-column parity table.
- Test-1.2.h: `GdockWorktreeVisibleRowsTests` — operator-view exclusion against the decoded set.
- Test-1.2.b: `GdockWorktreeSortTests` — tie-break ladder.
- Test-1.2.c: `GdockWorktreeFilterTests` — six fields, clearing, last-good derivation.
- Test-1.2.d: `GdockWorktreeDetailTests` — five-line invariant and failure swap.
- Test-1.2.e: `GdockWorktreeFilesPaneTests` — four states and caps.
- Test-1.2.f: `GdockWorktreeLanderLinesTests` — availability states.
- Test-1.2.g: `GdockWorktreeParityTests` — key-map coverage against the transcribed help set.

**Verification Commands**
```bash
./scripts/test-unit.sh test \
  -only-testing:cmuxTests/GdockWorktreeRowPresentationTests \
  -only-testing:cmuxTests/GdockWorktreeSortTests \
  -only-testing:cmuxTests/GdockWorktreeFilterTests \
  -only-testing:cmuxTests/GdockWorktreeDetailTests \
  -only-testing:cmuxTests/GdockWorktreeFilesPaneTests \
  -only-testing:cmuxTests/GdockWorktreeLanderLinesTests \
  -only-testing:cmuxTests/GdockWorktreeVisibleRowsTests \
  -only-testing:cmuxTests/GdockWorktreeParityTests
```

### 1.3 Chord lifecycle, panel presentation, and pin

**Targets:** VAL-CHORD-001, VAL-CHORD-002, VAL-CHORD-003, VAL-CHORD-004, VAL-PANEL-001, VAL-PANEL-002, VAL-PANEL-003
**Dependencies:** ["1.2"]
**Landing:** fork-only

**Implementation Details**
- Add `gdock.worktreePanel` to `ShortcutAction` and the `KeyboardShortcutSettings` mirror with the
  `⌥⇧W` default, a display name, a group, dock-routing disposition, and entries in
  `web/data/cmux-shortcuts.ts` and `web/data/cmux.schema.json`.
- Add `GdockWorktreePanelHoldMonitor` modeled on `WindowScopedShortcutHintModifierMonitor`: a
  flags-changed monitor for modifier release, a key-down entry point that ignores auto-repeat, and
  `NSApplication.didResignActiveNotification`, key-window-change, and screen-sleep observers that
  force a hide. Every one of those is an injectable entry point on the monitor, so each termination
  path named in VAL-CHORD-002 is drivable from a unit test without the real notification.
- Add `GdockWorktreePanelWindowController` modeled on `GdockSessionCyclerWindowController`: a
  floating panel centered on the key window's frame, a local key monitor while presented, recorded
  restore-focus target, and dismissal paths for release, `Esc`, activation, and unpin.
- Pin model: an explicit pin action (and any mode that requires typing) sets pinned; released
  modifiers dismiss only when not pinned.
- Wire the SwiftUI panel view over the 1.2 value types; row views are `Equatable` value views.
- Register `palette.gdock.worktreePanel` so the surface is reachable without the chord.
- The panel registers no `SidebarDockStore` kind, adds no rail tab, and hosts no terminal surface;
  the left-rail Worktrees section from `docs/stokd-worktrees-panel.prd.md` is not touched.

**Acceptance Criteria**
- AC-1.3.a: chord key-down presents; dropping either modifier hides.
- AC-1.3.b: auto-repeat while held leaves the presentation count at one.
- AC-1.3.c: app deactivation, key-window change, screen sleep, and `W` key-up while unpinned each
  hide exactly once.
- AC-1.3.d: pinning then releasing the modifiers leaves it visible; `Esc` then hides it.
- AC-1.3.e: the computed frame is centered on an injected reference frame.
- AC-1.3.f: dismissal makes the recorded restore target key.
- AC-1.3.g: `gdock.worktreePanel` defaults to `⌥⇧W` on both types and no other action's default
  matches it.
- AC-1.3.h: with the panel hidden the refresh scheduler reports zero work.
- AC-1.3.i: the panel module registers no sidebar dock kind and instantiates no terminal surface.

**Acceptance Tests**
- Test-1.3.a: `GdockWorktreePanelHoldMonitorTests` — present, release, repeat, deactivate, key-window
  change.
- Test-1.3.b: `GdockWorktreePanelPinTests` — pinned and unpinned release paths.
- Test-1.3.c: `GdockWorktreePanelPresentationTests` — centering, focus restore, idle cost.
- Test-1.3.d: `GdockWorktreePanelShortcutTests` — defaults, collision, palette id.
- Test-1.3.e: Source — floating-panel host, no sidebar dock kind, no terminal surface.

**Verification Commands**
```bash
./scripts/test-unit.sh test \
  -only-testing:cmuxTests/GdockWorktreePanelHoldMonitorTests \
  -only-testing:cmuxTests/GdockWorktreePanelPinTests \
  -only-testing:cmuxTests/GdockWorktreePanelPresentationTests \
  -only-testing:cmuxTests/GdockWorktreePanelShortcutTests
grep -q 'gdock.worktreePanel' web/data/cmux-shortcuts.ts web/data/cmux.schema.json
if rg -n 'SidebarDockStore|TerminalPanelView' Sources/GdockWorktreePanel* 2>/dev/null; then
  echo 'VAL-PANEL-003: the worktree panel must not be a rail kind or host a terminal' >&2
  exit 1
fi
```

### 1.4 Operations: shove, kill, disposition, enqueue, discard

**Targets:** VAL-ACT-001, VAL-ACT-002, VAL-ACT-003, VAL-ACT-004, VAL-ACT-005, VAL-FILES-002
**Dependencies:** ["1.3"]
**Landing:** fork-only

**Implementation Details**
- Add `GdockWorktreeOperations` as the single dispatch path for every mutation, over an injected
  command seam so every argument vector is testable without running anything.
- Shove: `stokd shove` with the row's path as working directory; row enters the shoving state.
- Kill: `GdockWorktreeKillEligibility` refuses primary, detached, empty, and protected branches;
  eligible rows require a confirmation naming the worktree; removal is followed by a branch delete
  that refuses when the branch is checked out in another worktree, reporting the reason.
- Disposition: picker for the four kinds, free-text collection for reason, blocker, and question,
  then `stokd disposition <kind> [--hash --reason --blocker --question]` in the worktree.
- Enqueue: `GdockWorktreeEnqueuePlanner` maps each target to stage / already-queued / skip-in-flight,
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

**Acceptance Tests**
- Test-1.4.a: `GdockWorktreeOperationCommandTests` — argument vectors for shove and disposition.
- Test-1.4.b: `GdockWorktreeKillGuardTests` — eligibility, confirmation, checked-out guard.
- Test-1.4.c: `GdockWorktreeEnqueuePlannerTests` — plan mapping, no-land assertion, counts.
- Test-1.4.d: `GdockWorktreeBusyGuardTests` — refusal matrix.
- Test-1.4.e: `GdockWorktreeDiscardFileTests` — confirmation gate and exact target path.

**Verification Commands**
```bash
./scripts/test-unit.sh test \
  -only-testing:cmuxTests/GdockWorktreeOperationCommandTests \
  -only-testing:cmuxTests/GdockWorktreeKillGuardTests \
  -only-testing:cmuxTests/GdockWorktreeEnqueuePlannerTests \
  -only-testing:cmuxTests/GdockWorktreeBusyGuardTests \
  -only-testing:cmuxTests/GdockWorktreeDiscardFileTests
```

### 1.5 Handovers

**Targets:** VAL-HAND-001
**Dependencies:** ["1.4"]
**Landing:** fork-only

**Implementation Details**
- Add `GdockWorktreeHandover` with the three cases and their argument vectors: integrate by hash,
  land by `--cwd`, review by `--worktree`.
- Each handover dismisses the panel before dispatching, and the command's outcome is surfaced to the
  operator rather than discarded.
- Integrate is refused with a message when the selected row carries no work-item hash.
- The panel itself never merges, pushes, or lands; the handover command owns that entirely.

**Acceptance Criteria**
- AC-1.5.a: each handover produces the documented argument vector.
- AC-1.5.b: integrate on a hashless row is refused with no dispatch.
- AC-1.5.c: the panel is recorded as hidden before any handover dispatch.
- AC-1.5.d: no `git merge` or `git push` invocation exists in the panel module.

**Acceptance Tests**
- Test-1.5.a: `GdockWorktreeHandoverTests` — vectors, refusal, dismissal ordering.
- Test-1.5.b: Source — the panel module never invokes `git merge` or `git push`.

**Verification Commands**
```bash
./scripts/test-unit.sh test -only-testing:cmuxTests/GdockWorktreeHandoverTests
if rg -n 'git merge|git push' Sources/GdockWorktreePanel* 2>/dev/null; then
  echo 'VAL-HAND-001: the panel hands over, it does not merge or push' >&2
  exit 1
fi
```

### 1.6 Conventions, localization, accessibility, and the axiom

**Targets:** VAL-SET-001, VAL-L10N-001, VAL-A11Y-001
**Dependencies:** ["1.3", "1.5"]
**Landing:** fork-only

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
  with `palette.gdock.`.
- AC-1.6.b: every panel localization key has English and Japanese entries.
- AC-1.6.c: representative rows compose the documented accessibility label.
- AC-1.6.d: `docs/gdock-agent-conventions.md` contains an `AX-GDOCK-WORKTREE-PANEL` section with
  Why, How, and Acceptance Checks.

**Acceptance Tests**
- Test-1.6.a: `GdockWorktreePanelConventionTests` — id prefixes.
- Test-1.6.b: `GdockWorktreePanelAccessibilityTests` — composed labels.
- Test-1.6.c: Structural — the axiom section exists.

**Verification Commands**
```bash
./scripts/test-unit.sh test \
  -only-testing:cmuxTests/GdockWorktreePanelConventionTests \
  -only-testing:cmuxTests/GdockWorktreePanelAccessibilityTests
grep -q '^## AX-GDOCK-WORKTREE-PANEL' docs/gdock-agent-conventions.md
./scripts/reload.sh --tag worktree-panel
```

## 4. Completion Criteria

- Every assertion in `## 2. Contract` has its evidence collected and persisted, at the rigor it
  carries. The eight `R4`-and-above assertions — VAL-ACT-002, VAL-ACT-004, VAL-DATA-001,
  VAL-PARITY-002, VAL-TABLE-001, VAL-TABLE-002, VAL-TABLE-005, VAL-PARITY-001 — additionally carry
  dual-lane agreement, and the four `R5` assertions (VAL-TABLE-001, VAL-TABLE-002, VAL-TABLE-005,
  VAL-PARITY-001) carry their oracle transcription per case.
- Every work item's Verification Commands exit 0, by execution rather than inspection.
- `./scripts/lint-pbxproj-test-wiring.sh` exits 0, so no test suite is silently skipped.
- `./scripts/reload.sh --tag worktree-panel` produces a Release build.
- The ceremony obligations this document derives (`C3`) are met: the charter and investigation
  summary are recorded above, two contract-review passes are recorded, the operator has confirmed the
  investigation and the plan, and a terminal review is recorded before the project closes.
- Dogfood: holding `⌥⇧W` in a repository with several worktrees shows the panel; the row set, order,
  and cells agree with `stokd worktree` run in a terminal against the same repository at the same
  moment; releasing the modifiers removes it. The dogfood build is tagged
  (`./scripts/reload.sh --tag worktree-panel`); an untagged app is never used.
- Every `VAL-*` id in `## 2. Contract` appears in exactly one `**Targets:**` line in
  `## 3. Execution Topology`.
- `stokd project lint .stokd/projects/gdock-worktree-panel/prd.md` exits 0.
- Lander and queue fields are degraded, never faked (VAL-PARITY-002).
- The left-rail Worktrees section from `docs/stokd-worktrees-panel.prd.md` behaves exactly as it did
  before this project landed.
- The Bonsplit submodule SHA is unchanged.

## 5. Rollout & Validation

### Rollout Strategy

- The panel ships behind its shortcut only: with no chord pressed and no palette command invoked,
  gdock behaves exactly as before, and the refresh scheduler does no work.
- The chord default is `⌥⇧W`, which is unbound today, so no existing binding changes and no upstream
  action is displaced. An operator who dislikes the chord rebinds it in Settings.
- Land the work items in dependency order behind one branch; the surface is not useful until 1.3
  presents it, so there is no partial-surface release to manage.
- Parity gaps are visible in the panel from the first build rather than discovered later.
- Fork-only, with no beta flag and no seeded rail tab.
- This authoring task does not create the project record. An operator runs
  `stokd project create -f .stokd/projects/gdock-worktree-panel/prd.md` separately.

### Post-Launch Validation

- Side-by-side check on a repository with at least eight worktrees including one dirty, one queued,
  one landing-failed, and one with live agents: panel cells match the TUI's cells.
- Destructive-path rehearsal on a scratch worktree: kill refuses the primary, refuses a branch
  checked out elsewhere, and requires confirmation before removing an eligible one.
- Enqueue rehearsal with two marked rows: two dispositions are staged, no land process starts, and
  the reported counts match the queue.
- Latency check: hold the chord repeatedly while typing in a terminal pane and confirm no typing
  stall, per the typing-latency rules in `CLAUDE.md`.
- Pin rehearsal: enter filter and a disposition reason, release the modifiers mid-typing, and confirm
  the panel survives and then dismisses on `Esc`.
- Regression check: confirm the left-rail Worktrees section still matches
  `docs/stokd-worktrees-panel.prd.md`.
- If lander pid and queue position are still wanted at a glance after launch, open the mono
  follow-up for `stokd worktree snapshot --json` (Open Question 3) rather than adding a gdock-side
  parser for `stokd land explain`.

## 6. Open Questions

1. **Interaction model under the hold.** This document adopts the Cmd-Tab grammar: the panel stays
   while `⌥⇧` remain held so single-key operations work, and typing flows require an explicit pin.
   The alternatives are (a) read-only while held with all operations behind a pin, and (b) a tap /
   hold split where a tap pins and a hold peeks. Confirm the adopted model or name a replacement
   before 1.3 begins.
2. **What pins.** The pin action is unassigned. Candidates: `Enter`, a second tap of the chord, or
   releasing `W` while keeping `⌥⇧`. This is a one-line change inside 1.3 once chosen.
3. **The CLI gap.** `queue_position`, `land_detail`, and the whole lander block have no
   machine-readable surface. The clean fix is a `stokd worktree snapshot --json` in
   `stokd-cloud/mono` emitting rows plus lander status in one document, which would let this panel
   drop three unknown states and would serve any future non-Rust client. That work is out of scope
   here (single-repo project) and is proposed as a separate mono task.
4. **Surface taxonomy.** The PRD specification's `Surface:` vocabulary has no native-GUI value; this
   document uses `tui` for interactive-surface assertions and `parity` where the Rust adjudicates.
   Confirm that reading, or extend the vocabulary.
5. **Repository scope of the panel.** The panel shows the key window's repository. Whether a
   multi-repository view is wanted later is deliberately unanswered here and listed as a non-goal.
6. **Exact enqueue and shove argument vectors.** The TUI binds `l` to enqueue and `s` to shove. The
   precise flags each key passes must be confirmed against `worktree_list.rs` at implementation
   time in 1.4. This is a transcription question, not licence to invent a third verb.
7. **Duplicate authoring tasks.** Task `5cdf921` and task `7b7422a` were both created with this same
   objective and each produced a PRD. This document is their merge; the surviving artifact is this
   file. Operators should close the redundant task rather than leave two PRDs to diverge.
