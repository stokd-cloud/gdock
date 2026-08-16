# ghostty-dock (gdock) — Iteration 1: side controls on canvas

**Date:** 2026-07-28
**Status:** Implemented (uncommitted at draft time; ship with this branch)
**Product:** **ghostty-dock** (short: **gdock**) — the cmux fork.
**Builds on:** existing **canvas mode** + canvas Dockable plumbing. Do **not** re-build canvas mode or re-do `CmuxDockable`.

## Naming (do not reintroduce)

| Call it | Do **not** call it |
|---------|-------------------|
| ghostty-dock / **gdock** | "chrome-*" product brands, chrome-flavored product brands |
| side controls / side rails / fixed hosts | product names that make docking sound "chrome-only" |

"Chrome" in upstream cmux docs sometimes means **window chrome** (sidebars, rails). That is *not* the product name for this fork, and it is **not** the framing for how docking should work in gdock. Docking is about **placeable surfaces** — not a chrome subsystem.

## The actual problem

Canvas mode is **already built in** and useful. You can hide the left/right rails and work on a freeform canvas.

When you do that, **you lose the controls** that only lived in those sides: workspace selector, Files, Find, Vault, etc.

**What you want:** those controls available **as panes on the canvas** (and movable anywhere) — so canvas mode is complete, not “pretty empty board, tools stuck off-screen in hidden rails.”

## One line

**Put the real side controls into the canvas as dockable panes** (singleton each this pass). Fixed rails optional/hidden — not the only home for Files / Find / Vault / left selector.

## This pass

| Control | Ship |
|---------|------|
| Files | One real pane you can put on canvas (or dock right) |
| Find | One real pane on canvas |
| Vault | One real pane on canvas |
| Left selector (real workspace/session UI) | One real pane on canvas / dockable — **not** a fake tab |

- Default can still *look* normal (selector left, Files right) **or** start canvas-first — either way tools are panes.
- Hide fixed side hosts by default is fine if panes replace them.
- **Singleton:** one of each kind; shortcut = focus or create that one.
- Empty fixed columns collapse / stay gone.

## Next pass (not now)

Multiple Files trees, multiple selectors, multi-target shortcuts. Crazy later.

## Non-goals

- Inventing canvas mode (exists)
- Re-doing Dockable package from scratch
- Restyle
- Multi-instance

## Done when

- [ ] In canvas mode with sides hidden, I can still open/use Files, Find, Vault, and the real left selector **as canvas panes**
- [ ] Those are the real UIs, not impostor stubs
- [ ] Move them around like other panes
- [ ] One of each; quit/relaunch restore OK or gap noted
- [ ] Fixed rails not required to access those tools

## Explicit fail

- “Use canvas mode and hide sides” without bringing tools onto the canvas
- Fake canvas tabs while real controls only live in fixed hosts
- Claiming multi-instance done

## Dogfood (this branch)

From any shell (helper on PATH):

```bash
gdock --build          # rebuild tag gdock from mission worktree, then launch
gdock                  # open existing DEV build (rebuild once if missing)
gdock --build-only     # rebuild only
gdock --path           # print .app path
gdock --last-run       # print the saved transcript of the previous gdock invocation
```

Source of truth for the helper: `scripts/gdock` (install with `cp scripts/gdock ~/.local/bin/gdock && chmod +x ~/.local/bin/gdock`).

Every run (except `--help` / `--last-run`) is archived under `~/.cache/gdock/`:

- `last-run.log` / `last-run.meta` — console transcript + exit code / branch / tag
- `last-run.log.prev` / `last-run.meta.prev` — previous run
- `last-reload.log` — full `reload.sh` / xcodebuild log when a rebuild ran

You do **not** need to re-run gdock to inspect a failure; open the last-run files.

Defaults:

- Tag: `gdock` (`GDOCK_TAG`)
- Worktree: `/opt/worktrees/stokd-cloud/ghostty-dock/canvas-dockable-mission-20260725-170934` (`GDOCK_WORKTREE`)
- App name: `cmux DEV gdock.app` under DerivedData `cmux-gdock`

Manual equivalent:

```bash
cd /opt/worktrees/stokd-cloud/ghostty-dock/canvas-dockable-mission-20260725-170934
CMUX_SKIP_ZIG_BUILD=1 ./scripts/reload.sh --tag gdock --launch
```

CLI against this build only:

```bash
CMUX_TAG=gdock scripts/cmux-debug-cli.sh …
```

Look for: **cmux DEV gdock** + red **THIS IS A DEV BUILD** banner (not production cmux).

---

**One line again:** Canvas mode is done. **Controls in the canvas** is the job. Product name is **ghostty-dock / gdock**.
