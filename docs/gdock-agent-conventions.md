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

## AX-GDOCK-REPO-COMMAND-SURFACE

A gdock workspace group that names a repository is a command surface for that
repository. A group that does not name one is inert.

Repo-only affordances — accordion focus behavior, the GitHub and stokd
repo-detail launchers, the stokd quad launch, and repo-scoped work metadata —
attach to a workspace group **if and only if** that group's name resolves to a
GitHub `owner/repo` slug through the single shared identity resolver
(`GdockRepoWorkspaceGroupIdentity`). Hand-named groups keep exactly the upstream
cmux behavior they have today.

The user's focus is never relocated by an automatic re-grouping unless the
surface being relocated is the one the user is currently working in.

### Why

- A group named `Scratch` is a user's filing choice, not a repository. Giving it
  a "open on GitHub" button or silently collapsing it is a guess about intent.
- Parsing `owner/repo` in each surface that wants it drifts: one surface accepts
  `owner/repo/extra`, the next does not, and the affordances disagree about what
  a repo is.
- Auto-grouping runs off a debounced cwd notification. Moving a workspace the
  user is not looking at is housekeeping; moving the one they are typing in and
  leaving their focus behind is data loss of attention.

### Acceptance checks

- **AC-A (single resolver).** Exactly one code path decides repo-group identity,
  and every repo-only affordance consumes it. A second inline `owner/repo` parse
  in a sidebar, quad, or stokd surface is a violation.
- **AC-B (inert by default).** For a group whose name does not resolve to a slug,
  every repo-only affordance is absent — zero trailing repo buttons, zero
  accordion mutations, zero quad plans. Each affordance carries a negative test
  proving this.
- **AC-C (focus follows intent).** An automatic workspace/panel relocation moves
  user focus only when the relocated surface is the focused one. Every other
  relocation is focus-neutral and window-activation-neutral, and both directions
  are tested.
- **AC-D (one shared action path).** Each repo-only affordance is implemented
  once and reached identically from the AppKit sidebar list, the SwiftUI sidebar
  fallback, and the command palette, per `skills/cmux-shared-behavior`. No
  per-surface duplicate of the behavior.

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
