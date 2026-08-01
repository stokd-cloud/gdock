# PRD: Stokd Rail Panels — First Slice

## 0. Source Context

**Feature Name:** Stokd Rail Panels (first slice)
**PRD Owner:** Brian Stoker
**Last Updated:** 2026-08-01
**Repository:** `stokd-cloud/ghostty-dock` (fork of `manaflow-ai/cmux`), branch `main`
**Landing:** fork-only on `main`

### What this is

Ship four Stokd surfaces into the **current** left/right rail system (N collapsible, resizable sections), with a fixed default layout the user asked for. This is a new PRD for the current implementation — not a rewrite of the old full-port PRD.

### Source inventory (read only; do not import architecture)

| Source | Role here |
|---|---|
| `stokd-cloud/mono` → `docs/port-stokd-panels-to-ghostty-dock.prd.md` | Feature inventory for Work + Worktrees behavior. **Not** the docking model. |
| `.stokd/projects/stokd-widgets-global-config-per-model-token-usage/prd.md` | Feature inventory for Global Config + Token Usage. Prefer its data-plane ideas where still accurate. |
| `.stokd/projects/dockable-sidebar-spaces-and-quad-split/prd.md` | **Authoritative layout substrate** (rails, sections, collapse, resize, beta flag, persistence rules). |
| Live code on `main` | `Sources/Sidebar/SidebarDock*` — seeding, store, commands, placement matrix, right modes. |

### Architecture correction vs old panel PRD

The old port PRD assumes the canvas **Dockable** refactor (`DockableKind` everywhere, freeform dock-anywhere). That is **not** how this slice lands.

- Rails already exist on `main` behind `sidebar.beta.dock.enabled` (default off).
- Left/right stay segregated rails; tools live **in rails only** (not freeform canvas).
- Old prerequisite "wait for full canvas dockable refactor" is **superseded** for this slice.
- Old eight-panel mega-port is **not** this PRD. Only the four panels below.

### Request (paraphrased)

> Take Work, Worktrees, Usage, and Global Config from the stokd extension / old PRDs. Work becomes a tab on the right. Usage, Worktrees, and Global Config live on the bottom half of the left: Usage on the bottom; Worktrees and Global Config above it. Top half of the left stays the existing normal left content.

### Default layout (load-bearing)

```
LEFT RAIL                          RIGHT RAIL
┌─────────────────────────┐        ┌─────────────────────────┐
│ Section: Workspaces     │        │ Section: Tools          │
│ (existing selector)     │        │ tabs: Files | Find |    │
│  — top half —           │        │       Vault | Work      │
├─────────────────────────┤        │                         │
│ Section: Global Config  │        │  (active tool content)  │
├─────────────────────────┤        │                         │
│ Section: Worktrees      │        │                         │
├─────────────────────────┤        │                         │
│ Section: Usage          │        │                         │
│  — bottom —             │        │                         │
└─────────────────────────┘        └─────────────────────────┘
```

Notes:

- Left stokd stack (Global Config → Worktrees → Usage) is the **bottom half** of the left rail; Workspaces keeps the top.
- Right: **Work is a tab** in the existing tool tab strip (alongside Files / Find / Vault), not a separate stacked section by default.
- Users can later reorder / collapse / resize via the rail system; defaults above are the first-boot seed when the feature is enabled.

---

## 1. Objectives & Constraints

### Objectives

1. Register four rail-hosted panel kinds: **Work**, **Worktrees**, **Global Config**, **Usage**.
2. Seed the default layout above when the rail dock beta is on and the stokd-panels seed has not been applied yet.
3. Reuse rail primitives already on `main` (sections, collapse, dividers, move between rails, actor wiring via `SidebarDockCommand` / invoker). Do not invent a second docking system.
4. Give each panel a real data path (CLI / local API / local files as appropriate) so the UI is usable, not placeholder chrome.
5. Persist section membership, order, collapse, and extents with the same rules as the rail PRD (additive snapshot fields; no `SessionSnapshotSchema.currentVersion` bump).

### Constraints

- **Fork-only.** Lands on `stokd-cloud/ghostty-dock` `main`. No `vendor/bonsplit` changes.
- **Rail host only.** No freeform canvas "dock anywhere."
- **Beta-gated.** Ship behind a flag (prefer reusing / extending `sidebar.beta.dock.enabled`, or a dedicated `sidebar.beta.stokdPanels.enabled` if product wants independent control — decide once in implementation; default off either way). Flag off → rails and panels behave as today (no stokd sections/tabs).
- **Config writes only through `stokd config set …`.** Never write `~/.stokd/config.yaml` or workspace YAML from the app directly.
- **Localization.** All user-facing strings `String(localized:)` with en+ja in `Resources/Localizable.xcstrings`.
- **Tests.** New `cmuxTests` files wired into `cmux.xcodeproj`; two-commit red/green for behavior fixes.
- **Snapshot boundary / no body mutations.** Existing cmux UI rules still apply.

### Non-goals (explicit)

- Agents dashboard, Agent chat (ACP), Reviews, Current Activity, Model Configuration, Workload Configuration from the old eight-panel PRD.
- Porting every behavior of the VS Code extension 1:1 in this slice.
- Widget-tile chrome / Notification Center styling from the widgets PRD (panels are full rail sections/tabs, not glanceable tiles).
- Realtime Socket.IO as a hard requirement (optional later; poll / file-watch is enough for v1).
- Upstream cmux PRs.
- Using prd-forge or expanding this into a mega-PRD.

---

## 2. Panels (behavior minimum)

### 2.1 Work (right rail tab)

- Source: extension work items UI / old PRD §3.2 inventory.
- Shows tasks + projects for the active workspace context.
- List/filter/sort must match current stokd API shapes (paged Tasks/Projects), not obsolete single-list assumptions from old drafts.
- Actions that already exist in the extension (open, mark done, copy hash, etc.) should be ported only where they have a clear native affordance; deep "agents window" flows stay out of scope.

### 2.2 Worktrees (left section)

- Source: old PRD §3.1 inventory, corrected for current reality.
- Inventory derives from **Git / local worktree discovery** for the active repo (not a hard dependency on `stokd worktree list` alone if that path is incomplete — prefer the same source of truth the extension effectively uses today, documented in code comments).
- Rows: path, branch, dirty state; land / open when those commands exist and are safe.
- No requirement to ship every review-chip from the old PRD in this slice.

### 2.3 Global Config (left section)

- Source: widgets PRD Global Config inventory.
- Schema-driven fields from `stokd config schema --json` (or current CLI equivalent).
- Scope context from the **active window's focused workspace cwd**.
- Display layered provenance (default / global / workspace / effective) where cheap; writes only via CLI writer with explicit scope.

### 2.4 Usage (left section, bottom)

- Source: widgets PRD Token Usage inventory.
- Per provider → per model token/cost breakdown for useful timespans (`24h` / `week` / `month` / `total` or whatever the current data plane already supports).
- Prefer file-watch / incremental ingest over dumb 60s full poll when practical.
- Include reasoning tokens and restart-safe provider dedupe if those are already in the current data model; do not invent fake zeros for providers that cannot report cache columns.

---

## 3. Implementation shape (high level)

Order is intentional.

1. **Panel kinds + rail registration**  
   New rail panel types (or extended `RightSidebarMode` / left panel registry — match existing rail patterns; do not force old `DockableKind` canvas path). Placement matrix allows the four kinds on the intended edges.

2. **Seeding**  
   Extend `SidebarDockSeeding` (or sibling) so first enable produces the default layout diagram. Idempotent: do not thrash user rearrangements after first seed (use a seed generation / "stokd panels seed applied" marker consistent with rail persistence design).

3. **Data plane (minimal)**  
   Small shared helpers for CLI invoke + API client (may start as app-local code under `Sources/Stokd/` rather than a full `StokdKit` mega-package if that ships faster; extract package only if it pays for itself). No direct config file mutation.

4. **Panel UIs**  
   One SwiftUI host per panel, mounted through the same section content path as Files/Find/Vault / left selector.

5. **Persistence**  
   Section list + selected tab + collapse/extents ride existing rail snapshot fields. Additive optionals only.

6. **Tests**  
   - Unit: seed layout matches the default diagram.  
   - Unit: placement matrix allows / refuses the right edges.  
   - Unit: data mappers for Work / Worktrees / Config / Usage with fixtures.  
   - Actor/wiring: palette or debug surface can open/focus each panel the same way other rail tools do (no store-only fake-pass).

7. **Dogfood**  
   Tagged build `stokd-rail-panels`, flag on, confirm left stack + right Work tab visually and via debug/socket where available.

---

## 4. Acceptance (done when)

- [ ] With flag on, cold window seeds exactly the default layout in §0.
- [ ] Right rail tab strip includes **Work** with Files / Find / Vault.
- [ ] Left rail top remains existing workspaces section; below it Global Config, Worktrees, Usage (Usage bottom).
- [ ] Each panel loads real data for a normal local stokd workspace (or shows a clear empty/error state if CLI/API missing — never blank crash).
- [ ] Flag off: no stokd sections/tabs appear; existing rails unchanged.
- [ ] en+ja strings present; pbx test wiring clean; bonsplit submodule SHA unchanged.
- [ ] No canvas freeform docking; no other old-PRD panels shipped.

---

## 5. Decisions

| ID | Decision |
|---|---|
| D1 | **Rail substrate wins.** Old canvas-Dockable-first plan is not used for this slice. |
| D2 | **Four panels only.** Everything else from the old port PRD is a later PRD. |
| D3 | **Default placement is product, not suggestion.** Seed must match §0; user can rearrange after. |
| D4 | **Work is a right-rail tab**, not a left-rail section, in the default seed. |
| D5 | **Usage is its own bottom left section**, not a tab inside Worktrees. |
| D6 | **No prd-forge.** This document stays short; implementers expand tasks from here. |

### Superseded ideas (from older docs)

- Hard gate on full canvas dockable refactor before any stokd panel work.
- Eight panels in one project.
- Widget-tile-only presentation for Config/Usage.
- Cap of two sections per rail (already removed by the rail PRD).

---

## 6. Open questions (do not block drafting UI chrome)

1. Single beta flag vs dedicated `stokdPanels` flag.
2. Whether Global Config + Worktrees should ever share one section as tabs instead of two sections (default is two sections per §0).
3. How much of Worktrees "land / review" action surface ships in v1 vs list+open only.

If unanswered at implement time: pick the default already stated in this PRD (shared dock flag ok; two sections; list+open first) and record the choice in the project notes.
