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
