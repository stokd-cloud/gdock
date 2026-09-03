# ghostty-dock (gdock) — agent conventions

**Product:** ghostty-dock (short: **gdock**) — cmux fork.

## New settings and command-palette IDs

**Every new setting and palette command added for this fork must be prefixed with `gdock`.**

| Surface | Prefix | Example |
|---------|--------|---------|
| Setting dotted-id + UserDefaults key | `gdock.` | `gdock.autoWorkspaceGroupMode` |
| Palette one-shot `commandId` | `palette.gdock.` | `palette.gdock.someAction` |
| Palette settings toggle `commandId` | `palette.toggleSetting.gdock.` | `palette.toggleSetting.gdock.autoWorkspaceGroupMode` |

### Why

- Avoids collisions with upstream cmux IDs when merging or cherry-picking.
- Makes fork-owned surface area greppable (`rg 'gdock\\.'`).
- Keeps Settings search, schema, and palette contribution ownership obvious.

### How to add a setting

1. Add a `DefaultsKey` on `GdockCatalogSection` (or a new section that only uses `gdock.*` ids).
2. Wire a command-palette toggle via `CommandPaletteSettingToggleDescriptor` with `commandId` starting `palette.toggleSetting.gdock.`.
3. Localize titles with `String(localized:defaultValue:)` and update `Resources/Localizable.xcstrings` (en + ja minimum).
4. Do not place fork-only flags under `app.*` / `sidebar.*` / `rightSidebar.beta.*` unless you are extending an existing upstream beta.

### Feature: Auto Workspace Group Mode

- Setting: `gdock.autoWorkspaceGroupMode` (default off).
- Palette: Enable/Disable **Auto Workspace Group Mode** (`palette.toggleSetting.gdock.autoWorkspaceGroupMode`).
- When on: non-anchor workspaces whose cwd is inside a GitHub-remote repo are placed in a workspace group named `owner/repo` (primary remote: origin → upstream → others). A group anchor is the group's header and is never moved into another group, but it is not exempt: an anchor that owns nothing else renames its group to the repo it moved to, and an anchor with siblings sheds the panels that diverged (always keeping one, so the header survives). Focus follows an extracted panel only when it is the panel the user is working in.

Also listed in `Agents.md` so every agent session loads it.

### Feature: Grid Mode

- Settings: `gdock.gridMode` (default off) and `gdock.gridModeShape`
  (`"<rows>x<cols>"`, default `"2x2"`, clamped to 4×4; remembered across
  restarts).
- Palette: Enable/Disable **Grid Mode**
  (`palette.toggleSetting.gdock.gridMode`).
- Shortcuts: **Create Next Quad Pane** (`gdock.nextQuadPane`, default
  `Cmd+Y`) and **Create Quad Pane Workspaces**
  (`gdock.quadPaneWorkspaces`, default `Cmd+Shift+Y`).
- Titlebar: a grid-shape picker button (trailing edge of the workspace
  titlebar) renders while the mode is on; picking a shape re-shapes every
  workspace (`GdockGridSplitAction` + `TabManager+GdockGridMode`).
- When on: every workspace is kept in the enforced grid. Cells with no
  surface hold **unactivated placeholder terminals**
  (`heldForStartupRestoreAdmission` — no PTY until the cell is focused).
  Cmd+T fills the next unactivated cell; when every cell is occupied it
  creates a new shaped workspace (in the same workspace group, when any)
  and navigates there. Shrinking the shape spills surplus surfaces into a
  new workspace — Grid Mode never hides a surface behind another.

### Feature: Stokd Work panel (right sidebar)

- Data: every read and mutation goes through the resolved `stokd`
  executable (`StokdExecutableResolver` → `StokdCLIRunner` →
  `StokdWorkCLILoader`). No HTTP client, no hardcoded host: the CLI alone
  resolves the environment, org, and credentials. Argument vectors live in
  `StokdWorkCLIArguments`; `scripts/lint-stokd-work-dock-independence.sh`
  fails on any `SidebarDock`, `sidebar.beta.dock.enabled`, `localhost`,
  `8167`, `http://`, or `URLSession` under `Sources/Stokd/`.
- Kinds: tasks, projects, and **todos** are rows in this one panel (kind
  filter All / Tasks / Projects / Todos). A todo belongs to a repository
  when the todo or any checklist item names it.
- Settings (preferences, not gates): `gdock.workPanel.kindFilter`
  (`all`), `gdock.workPanel.showCompleted` (default **off**: completed,
  cancelled, and failed items are hidden), `gdock.workPanel.sortField`
  (`updated_at` | `created_at`), `gdock.workPanel.sortAscending` (default
  off: newest first). Palette: **Work: Show Completed Items**
  (`palette.toggleSetting.gdock.workPanel.showCompleted`).
- Search is two-tier: tier 1 matches title / hash / status / repo on the
  loaded set instantly; tier 2 fetches item bodies (`task get`,
  `project get`, `todo view --json`) through a debounced queue with at most
  two `stokd` subprocesses in flight, cached per hash, and appends body-only
  matches marked "matched in body". Nothing shells out from `body` or per
  keystroke.
- Paging is infinite scroll: the first page is 100 rows per kind, cut
  server-side by the panel sort (`--sort-by`, `--desc`); when a row past the
  midpoint appears and a kind came back full, the cap grows by another page
  and the list reloads in place (never a spinner over the list). A sort
  change restarts from the first page.
- Detail: selecting a row opens a resizable split pane under the list
  (height persisted as `gdock.workPanel.detailHeight`); the list stays live,
  selecting another row swaps the detail, selecting the open row closes it.
  `StokdWorkDetailParser` parses the CLI text/JSON defensively and falls
  back to the raw output; a non-zero exit shows stderr plus Retry.
- Actions: `StokdWorkActionTable` is the single (kind, status) → verbs table
  shared by the row context menu and the detail menu. Interactive verbs
  (start, resume, integrate, review, advance, report, open in terminal)
  open a terminal surface born with the command via
  `StokdWorkTerminalLauncher`; note / priority / complete / delete run
  through the CLI runner, with confirmation for complete and delete.

## AX-GDOCK-INSTALLED-CLI-RESOLUTION

Installed gdock app restore startup input must invoke the bundled CLI from the
running app bundle, not an ambient `cmux` command resolved through the user's
login shell.

### Why

- `/Applications/gdock.app/Contents/Resources/bin/gdock` is the installed
  app's matching restore CLI.
- User shell startup files can resolve stale or development `cmux` shims before
  gdock's managed terminal environment is applied.
- Agent session auto-resume must survive app close/reopen without depending on
  the user's current `PATH` state.

### Acceptance checks

- Restored local agent startup input uses a shell-quoted bundled gdock CLI path
  when the bundle contains one.
- Startup input falls back to `cmux` only when no bundled CLI can be resolved.
- The restore token behavior is covered in `CMUXAgentLaunchTests` and the app
  auto-resume integration path is covered in `cmuxTests`.

## The gdock launcher and the installed main app

`scripts/gdock-run` is the **source of truth** for the `gdock-build` launcher. The
host copy at `~/.local/bin/gdock-build` is generated — install it with
`scripts/install-gdock-build.sh` and never hand-edit it. `--check` reports drift.

### Installed app location

Untagged Release builds ("main app" mode) are installed to
`$GDOCK_INSTALL_DIR/gdock.app`, default `/Applications/gdock.app`, by a
same-filesystem staged rename. That stable path is what `gdock-build` launches, so
the installed app keeps working while a new build compiles in DerivedData.

**Tagged builds (`--tag`) and `--debug` builds never write to the install
directory.** They stay in DerivedData exactly as before. Agent dogfood builds are
always tagged, so agents never touch `/Applications`.

### Unchanged Release artifact reuse

On the first `gdock-build --tag <tag>` run, the tag has no cache record of its
own. If the same worktree's successful `release:main` record has the exact
current source fingerprint and Zig-helper build profile, `gdock-build` packages
that Release artifact into the tag's isolated DerivedData instead of invoking
xcodebuild again. The atomic build record binds that fingerprint to the signed
artifact identity and canonical worktree root, and main publication/reuse is
serialized while it is cloned. Legacy records without that manifest are not donors.
Packaging rewrites and audits the host, nested bundle, URL/auth, socket, and sidebar
extension-point identities, then signs the result before it can replace the
tagged output. The donor is never modified and the installed app is never used
as a donor.

Debug, `--build`, changed sources, a DerivedData override, or any missing,
malformed, incompatible, or invalidly signed donor uses the normal full-build
path. A second unchanged run uses the tag's own cache record and does not
repackage.

### The swap gate

Replacing the installed app is gated on whether it is running:

| Installed app | Result |
|---------------|--------|
| Not running | Replaced silently, then launched. |
| Running, interactive terminal | Prompted (`[y/N]`, `GDOCK_PROMPT_TIMEOUT`, default 60s). |
| Running, answer yes / `--force-install` / `GDOCK_INSTALL=auto` | Spawn a session-detached helper, then quit. The helper waits for the installed pids to exit, replaces the bundle, and launches. This survives SIGHUP when `gdock-build` was a child of that app. |
| Running, declined / timed out / no tty / `--no-install` / `GDOCK_INSTALL=never` | Left untouched; the build is recorded as a **pending install**. |

A pending install is retried on the next run in that mode with **no rebuild**: once
the app is closed it installs and launches; while it is still running you are asked
again. A pending record is dropped only when its bundle is gone or a newer
successful build supersedes it.

The quit must precede the launch. The installed bundle and the DerivedData bundle
share bundle id `cloud.stokd.ghostty-dock`, so `open -a` against a running
instance foregrounds the **old** process — "launched the new build" would be a lie.

Do not run that quit/replace/launch sequence in the `gdock-build` process that
issued the prompt. That process is often a descendant of `/Applications/gdock.app`;
AppleScript `quit` closes its PTY and SIGHUPs the builder, so an in-process
`ditto`/`open` never runs. The helper must `setsid` (or equivalent) **before**
the quit is sent. `tests/test_gdock_install_applications.sh` case 5b sends
SIGHUP to the builder from the osascript seam and still requires install+launch.

### Never match processes by command line

Running-app detection resolves pids whose process executable is exactly
`$GDOCK_INSTALL_DIR/gdock.app/Contents/MacOS/gdock` (via `ps -axo pid=,comm=`), and
termination signals those pids individually. Do not reintroduce `pkill`/`pgrep`
command-line matching here: it signals every process whose argv merely mentions
the path, which has killed live sibling agent sessions.

### Flags and environment

| Flag | Effect |
|------|--------|
| `--force-install` | Quit the running installed app and replace it without asking. |
| `--no-install` | Leave the installed app alone; record a pending install. |
| `--run-installed` | Launch the installed app now. No build, no install. |
| `--installed-path` | Print the installed app path. |

`GDOCK_INSTALL_DIR` (default `/Applications`), `GDOCK_INSTALL` (`auto`/`ask`/`never`,
default `ask`), and `GDOCK_PROMPT_TIMEOUT` configure the gate. `GDOCK_OPEN`,
`GDOCK_OSASCRIPT`, `GDOCK_PS`, `GDOCK_KILL`, and `GDOCK_ASSUME_TTY` are test seams
used by `tests/test_gdock_install_applications.sh`, which covers the whole gate
without Xcode, a real `/Applications` write, or real signalling.

`--path` still prints the DerivedData build path; use `--installed-path` for the
installed one.

Contract: `AX-GDOCK-INSTALLED-APP-SWAP-GATE`.

## AX-GDOCK-QUAD-SHORTCUT-WORKSPACE-VISIBILITY

Gdock quad shortcut actions preserve workspace visibility by filling visible
quad panes before creating hidden pane-local tabs, then rolling over to a
same-directory workspace once a true 2x2 quad is complete.

### Why

- The workflow is meant to keep active work visible in panes and workspaces,
  instead of hiding extra sessions behind tabs inside a quad pane.
- `gdock.*` shortcut IDs keep fork-owned behavior separate from upstream cmux
  actions and make the Settings/config/docs surface auditable.
- A shared action path prevents shortcut, Settings, and command-surface behavior
  from drifting apart.

### How to apply

1. Use `gdock.`-prefixed shortcut action IDs for fork-owned quad workflow
   shortcuts.
2. Route keyboard dispatch through one shared `TabManager`-backed action path.
3. Make `Cmd-Y` fill one-, two-, and three-pane workspaces toward a true
   `H(V,V)` 2x2 topology; when the current workspace is already a true quad,
   create a same-directory workspace instead of a pane-local tab.
4. Keep Shortcut Settings, `cmux.json` schema, docs, and localization in sync
   for every new shortcut.

### Acceptance Checks

- Runnable:
  `xcodebuild -project cmux.xcodeproj -scheme cmux-unit -configuration Debug -destination 'platform=macOS' -derivedDataPath /tmp/cmux-quad-tab test -only-testing:cmuxTests/QuadSplitActionTests -only-testing:cmuxTests/QuadSplitButtonTests`
  exits 0 and covers fill, rollover, batching, and shortcut metadata.
- `web/data/cmux.schema.json` includes `gdock.nextQuadPane` and
  `gdock.quadPaneWorkspaces`.
- `Resources/Localizable.xcstrings` has English and Japanese entries for both
  shortcut labels.

## AX-GDOCK-PANEL-CARD-SESSION-SUMMARY

Gdock consumes stokd's per-session outcome log read-only, binds each pane to a
session by process identity before recency, and delivers the result to the
sidebar as an immutable value reduced above the lazy-list boundary.

### Why

- The summaries are written by the stokd CLI, not by gdock. Writing, locking,
  truncating, or migrating anything under `~/.stokd` would corrupt state whose
  only owner is another process.
- The state directory is named by a hash of the canonical workspace root, so two
  worktrees of one repository do not collide. That name cannot be reconstructed
  by convention — it has to be derived, in one place, from the same algorithm
  the CLI uses (`apps/cli/src/state_paths.rs` in stokd-cloud/mono).
- A workspace usually holds several sessions, most of them finished. "Newest
  file wins" alone would show one pane's work on another pane's card, which is
  worse than showing nothing.
- The sidebar list path is the one place in this app where holding an observable
  reference below a lazy container reintroduces a 100%-CPU relayout loop
  (`CLAUDE.md`; issue 2586). Cards are decoration on that path, so they get the
  value-snapshot treatment, not a live store.

### How to apply

1. Derive every path through `StokdWorkspaceStatePaths`. Never string-build a
   workspace directory name, and never write to one.
2. Read the log tolerantly. The writer appends and fsyncs per entry, so a
   blank, malformed, or half-written trailing line is expected: skip it and keep
   the records around it.
3. Enumerate the **union** of `runtime/sessions/*.runtime.json` and
   `runtime/*.outcomes.jsonl`. The two do not track each other: stokd prunes a
   session's runtime record when the session ends but keeps its log, so a
   record-driven scan hides every finished session — the completed work most
   worth showing. A freshly started session is the mirror case: record, no log
   yet. A session missing its record contributes no process identity (pid and
   pgid stay 0, which never matches) and competes only on recency.
4. Do all filesystem work off the main thread, behind a per-directory minimum
   interval and a per-session (mtime, size) short-circuit — a directory mtime
   does not change when a session appends to an existing log. The render path
   reads only the last published snapshot: no IO, no subprocess.
5. Bind a pane to a session in this order and no other: exact pid match against
   the pane's own agent pids; then process-group match; then the most recently
   active running session in that workspace; then the most recently active
   session. Keep the selection a pure function over injected descriptors so the
   precedence is testable without a filesystem or live processes. Return nil
   rather than inventing a session.
6. Reduce to `GdockWorkspacePanelCard` above the lazy-list boundary. A card view
   holds no store reference and reads no observable state.
7. Emit a card only for a pane actually running an agent — one with a non-empty
   `agentPIDKeysByPanelId` entry. A plain shell pane gets no card, so a
   four-pane workspace with one agent shows one card rather than four rows of
   nothing.
8. Render the cards as ONE selection-ringed stack that stands in for the focused
   workspace's own row, not as sibling rows beneath it. Drawing both would show
   that workspace twice. Because the stack *is* that row it stays in the
   reorderable-row set and keeps its workspace's number — excluding it silently
   renumbers every workspace after it and shifts the Cmd-N shortcuts.
9. Resolve per-pane title and directory through the workspace's own accessors
   (`resolvedPanelTitle`, `effectivePanelDirectory` with `currentDirectory` as
   the local fallback), never the raw `panelTitles` / `panelDirectories` maps.
   Those are populated only by shell-integration reporting, so reading them
   directly renders a blank card and — because an empty directory
   short-circuits the store lookup — silently suppresses every summary.
10. Derive the displayed line; never render raw entry text. First sentence,
   whitespace-collapsed, capped with an ellipsis, trailing period stripped. A
   card carries the agent's glyph, the latest outcome kind as a badge, that
   headline, the session's short id, and one metadata line.
11. The metadata line carries only recorded values: elapsed since the session's
   `started_at`, counts by kind, and the age of the newest entry. Progress
   percentages and time-remaining estimates are NOT recorded anywhere gdock
   reads; omit them rather than inventing them.
12. Preserve unknown kinds. gdock ships on its own cadence; a kind the CLI adds
   later must still display, not vanish.
13. Gate the surface on `gdock.panelCardSessionSummaries`. With it off the
   reduce attaches nothing at all, rather than computing a value it then hides.

### Acceptance Checks

- Runnable:
  `xcodebuild test -project cmux.xcodeproj -scheme cmux -destination 'platform=macOS' -only-testing:cmuxTests/StokdWorkspaceStatePathsTests -only-testing:cmuxTests/StokdSessionOutcomeSummarizerTests -only-testing:cmuxTests/StokdSessionOutcomesScannerTests -only-testing:cmuxTests/StokdSessionOutcomesLocatorTests -only-testing:cmuxTests/GdockWorkspacePanelCardBuilderTests`
  exits 0 and covers key derivation, tolerant decoding, the record/log union,
  headline derivation, pane-to-session precedence, and card attachment.
- Storage design: `StokdWorkspaceStatePaths.workspaceKey` reproduces the CLI's
  key for known roots, and no gdock code path opens a file under `~/.stokd` for
  writing.
- Pane-to-session selection: each of the four precedence tiers has a test that
  fails if the tier above it is removed, and an empty descriptor list yields
  nil.
- Population: a workspace of four panes where one runs an agent yields exactly
  one card; a workspace with no agent panes yields none.
- Structure: when a stack is emitted the focused workspace contributes no
  ordinary row, and `numberedWorkspaceIndexById` is identical to the all-rows
  arrangement.
- Display model: no view under the sidebar's lazy container references
  `StokdSessionOutcomesStore`, and the metadata line contains no percent or ETA
  text.
- `Resources/Localizable.xcstrings` has English and Japanese entries for every
  summary string.

## AX-GDOCK-SESSION-CYCLER

Session cycling is one ring, one model, one summary source.

gdock cycles agent sessions through a single scope ring and a single pure
selection model. The ring is modular over N scopes — today `currentRepo` and
`allSessions` — and is never a two-way boolean toggle. The overlay renders the
stokd outcome summary for exactly the highlighted session and a provider mark
plus title for every other row, and it reads that summary only through the
existing read-only consumer described in AX-GDOCK-PANEL-CARD-SESSION-SUMMARY.

### Why

- A boolean "current repo vs all" has to be rewritten the day a third scope
  (current window, current machine, cloud) arrives, and every call site that
  assumed two states becomes a bug. Modular `next`/`previous` over `allCases`
  makes a third scope a new case and nothing else.
- Selection, filtering, and scope must be pure value functions: the overlay
  renders rows below a lazy container, where holding an observable store
  reference is what reintroduced the 100%-CPU spin loop (`CLAUDE.md`; cmux issue
  2586).
- Re-deriving stokd's on-disk layout in a second place is how two readers
  silently disagree after a CLI change. AX-GDOCK-PANEL-CARD-SESSION-SUMMARY
  already fixed one derivation site; this keeps it at one.
- Rendering a full summary on every row turns a fast cycler into a wall of
  paragraphs. The summary earns its space only on the row the operator is on.

### How

1. `GdockCycleRing` steps modularly over any `CaseIterable & Equatable`;
   `GdockSessionCycleScope.next()/previous()` are thin wrappers. No call site
   branches on how many scopes exist.
2. `GdockSessionCyclerModel.listing(...)` is pure over values and owns scope
   filtering, case-insensitive query filtering, selection preservation across a
   scope change, and clamping. `selection(movedBy:from:in:)` owns wrap-around.
3. When grouped workspace-repo mode is off, or no `owner/repo` group resolves,
   `currentRepo` falls back to every session rather than narrowing to nothing.
4. A row's identity is the panel running the agent, not the workspace: two panes
   in one directory routinely run different sessions.
5. Provider marks resolve through `GdockSessionAgentBadge`, which joins the
   workspace's existing agent status keys to `SessionAgent`. An unrecognized key
   still yields a row — with no art and the key as its name — because a running
   agent gdock cannot name is still a session worth cycling to.
6. The keyboard chord, the command palette, and any future socket verb all call
   `GdockSessionCyclerPresenter`; none of them re-implements cycling.
7. Shortcut ids are `gdock.cycleSessionsNext` / `gdock.cycleSessionsPrev` and
   palette ids are `palette.gdock.cycleSessionsNext` / `...Prev`, per the fork
   prefix convention above.
8. The cycler owns Cmd+Shift+] and Cmd+Shift+[. Upstream's `nextSurface` /
   `prevSurface` ship unbound-by-default in this fork rather than sharing the
   chord; both remain bindable in Settings and reachable from the palette.

### Acceptance Checks

- Runnable:
  `./scripts/test-unit.sh test -only-testing:cmuxTests/GdockSessionCycleScopeTests -only-testing:cmuxTests/GdockSessionCyclerModelTests -only-testing:cmuxTests/GdockSessionAgentBadgeTests -only-testing:cmuxTests/GdockSessionCyclerShortcutTests`
  exits 0 and covers modular ring stepping over a three-member fixture, scope and
  query filtering, wrap-around selection, selection preservation across a scope
  change, summary-on-the-highlighted-row-only, provider-mark resolution, and the
  chord handover.
- Ring generality: the ring tests use a three-member fixture, so an
  implementation that flips between two states fails.
- Single summary source: no path derivation under `~/.stokd` outside
  `StokdWorkspaceStatePaths`, and no gdock code path opens a file there for
  writing.
- Chord ownership: no action other than the two cycler actions has Cmd+Shift+]
  or Cmd+Shift+[ as its default binding.
- `Resources/Localizable.xcstrings` has English and Japanese entries for every
  cycler string.

## AX-GDOCK-ICONS-SOURCE

Gdock raster app icons are generated from `design/gdock-light.png` and
`design/gdock-dark.png`. Those two 1024x1024 files are the canonical light and
dark sources. Every `AppIcon.appiconset` size, the `AppIconLight` /
`AppIconDark` imagesets, the iOS `AppIcon` / `AppIconDark` files, and the
Debug / Nightly banner variants are a resize or overlay of those sources. Do
not synthesize a glow, recolor the cube from the old cmux chevron, or
hand-edit a single size.

### Why

- The light and dark mockups are the product icon. The previous generator
  rebuilt dark from a Figma chevron plus glow and drifted from the mockups.
- One pair of sources keeps Dock, Finder, Settings picker, iOS, and
  Debug / Nightly icons the same mark.

### How to apply

1. Put new mockups at `design/gdock-light.png` and `design/gdock-dark.png`
   (1024x1024 RGBA).
2. Run `python3 scripts/generate_app_icons.py` to resize into
   `AppIcon.appiconset` (light + dark), the `AppIconLight` / `AppIconDark`
   imagesets, the iOS AppIcon sets, and Debug / Nightly banner variants.
3. Do not edit individual size PNGs by hand. Do not call the old
   glow-from-chevron path in `generate_dark_icon.py`.
4. Icon Composer (`AppIcon.icon`) keeps the cube glyph only (no baked
   squircle); raster sets use the full mockups.

### Acceptance Checks

- Runnable: `python3 tests/test_gdock_app_icons.py` exits 0.
- `AppIconLight.png` equals `design/gdock-light.png` and `AppIconDark.png`
  equals `design/gdock-dark.png`.
- Light center is ~ `(224,224,224)` and dark center is ~ `(31,31,31)`;
  neither center is cyan-glow.
- `scripts/generate_dark_icon.py` does not composite
  `design/cmux-icon-chevron.png`.
