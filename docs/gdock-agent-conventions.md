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
- When on: non-anchor workspaces whose cwd is inside a GitHub-remote repo are placed in a workspace group named `owner/repo` (primary remote: upstream → origin → others). Group anchors are not auto-moved.

Also listed in `Agents.md` so every agent session loads it.

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

### The swap gate

Replacing the installed app is gated on whether it is running:

| Installed app | Result |
|---------------|--------|
| Not running | Replaced silently, then launched. |
| Running, interactive terminal | Prompted (`[y/N]`, `GDOCK_PROMPT_TIMEOUT`, default 60s). |
| Running, answer yes / `--force-install` / `GDOCK_INSTALL=auto` | Quit first, then replace, then launch the new app. |
| Running, declined / timed out / no tty / `--no-install` / `GDOCK_INSTALL=never` | Left untouched; the build is recorded as a **pending install**. |

A pending install is retried on the next run in that mode with **no rebuild**: once
the app is closed it installs and launches; while it is still running you are asked
again. A pending record is dropped only when its bundle is gone or a newer
successful build supersedes it.

The quit must precede the launch. The installed bundle and the DerivedData bundle
share bundle id `cloud.stokd.ghostty-dock`, so `open -a` against a running
instance foregrounds the **old** process — "launched the new build" would be a lie.

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
7. Derive the displayed line; never render raw entry text. First sentence,
   whitespace-collapsed, capped with an ellipsis, trailing period stripped.
   Counts and disposition are voiced in the accessibility label rather than
   drawn, so a card stays one line.
8. Preserve unknown kinds. gdock ships on its own cadence; a kind the CLI adds
   later must still display, not vanish.
9. Gate the surface on `gdock.panelCardSessionSummaries`. With it off the
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
- Display model: `GdockWorkspacePanelCardBuilder.cards` called without
  `summariesByPaneId` is byte-identical to its pre-summary output, and no view
  under the sidebar's lazy container references
  `StokdSessionOutcomesStore`.
- `Resources/Localizable.xcstrings` has English and Japanese entries for every
  summary string.
