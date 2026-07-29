# ghostty-dock (gdock) — All-UI Dockable

## 0. Source Context

**Derived From:** User dogfood of `docs/cmux-canvas-dockable-refactor.prd.md` (mission closed 2026-07-28). Reaction: canvas panel kinds became Dockable, but fixed chrome (left sidebar, right sidebar / Files rail) still cannot be placed arbitrarily. Explicit ask: *not* a half-version of existing UI made dockable — **all UI dockable**; put left and right chrome wherever the user wants.

**Feature Name:** ghostty-dock all-UI dockable (gdock)
**Naming:** Prefer ghostty-dock / gdock. Do not brand this as "chrome-*" product brands — docking is placeable surfaces, not a chrome-only subsystem.  
**PRD Owner:** user (stokd)  
**Last Updated:** 2026-07-28  
**Repository:** `apps/ghostty-dock` / fork `stokd-cloud/ghostty-dock` (same isolation model as prior mission).

### Relationship to prior mission (do not re-run)

| Prior mission (`cmux-canvas-dockable-refactor`) | This mission |
|------------------------------------------------|--------------|
| Common `Dockable` for **canvas panel content kinds** | Make **app chrome surfaces** the same class of placeable objects |
| Collapse `CanvasPaneContent` enum | Collapse **fixed left/right chrome hosts** as the only home for tools |
| Fork-only canvas mount + snapshot | May touch more app shell; still prefer rebasable boundaries |
| **Done** — do not restart that project | **New** project, **one** worktree, resume-only |

Foundation already shipped and must be **reused**: `Packages/macOS/CmuxDockable`, panel `Dockable` conformances, generic canvas mount, `DockableSnapshot`, registry. This PRD is **not** “re-implement canvas Dockable.”

### Summary

**Product:** ghostty-dock (**gdock**). cmux still has two worlds:

1. **Placeable panes** — terminals, browsers, markdown, and other `Dockable` kinds on canvas / splits.
2. **Fixed chrome** — workspace/left sidebar stack and right sidebar rail (Files / Find / vault / sessions / feed / dock, etc.) that only toggle in place.

Users can open a Files-like *panel kind* on canvas in some paths, but the **chrome hosts** remain undockable. This feature eliminates that split: **every primary interactive UI surface is a dockable pane** (or a pure non-interactive decoration). The left sidebar(s) and right sidebar are not special snowflake columns — they are panes (or stacks of panes) the user can move to any split, canvas freeform pane, window, or float, and restore.

**Success slogan (acceptance voice):** *I can put that shit wherever I want* — left chrome, right chrome, tools, not only terminal/browser canvas content.

---

## 1. Objectives & Constraints

### Objectives

1. **Unified placeable model** — Every primary surface the user interacts with is either:
   - a `Dockable` (or thin adapter over `Dockable`), or
   - explicitly non-placeable decoration (titlebar, traffic lights, pure status glyphs) listed in Non-Goals.
2. **Left chrome is placeable** — The left/workspace sidebar stack (workspace list, session index, feed strip, PR chrome, etc. — inventory in §2) can leave its fixed column: dock into splits, freeform canvas, other windows, multi-column layouts.
3. **Right chrome is placeable** — The right rail (Files / file explorer, Find, vault, sessions, feed, dock tools, etc.) is not a permanent `⌘⌥B` column only; same placement powers as left.
4. **No “kind on canvas but host fixed” trap** — Shipping `rightSidebarTool` as a canvas kind while keeping a mandatory fixed Files rail is **not** done for this PRD.
5. **One placement vocabulary** — Same verbs for all placeables: dock, undock, split, tab, float (if product already floats), move to window/workspace, close, restore.
6. **Persistence** — Layout of chrome-origin panes survives quit/relaunch with the same snapshot story as other Dockables (extend `DockableSnapshot` / workspace snapshot, not a parallel chrome-only format long-term).
7. **Preserve behavior** — File explorer, git status, search, session list, etc. keep capabilities; only **host geometry** changes.
8. **Entry points stay coherent** — Keyboard shortcuts, command palette, menus, CLI/socket share one action path per placement verb (cmux shared-behavior policy).

### Constraints

- **One mission / one worktree / resume-only.** No second parallel Zenith project for the same PRD. Abort dupes immediately.
- **Build on `CmuxDockable`** — Do not invent a second protocol for chrome. Extend registry/kinds/capabilities as needed.
- **Swift 6 / @MainActor** for mount lifecycle, matching existing dockable rules.
- **No silent scope cut** of left or right primary tools without a recorded decision.
- **Localization** — All new user-facing strings EN+JA.
- **Shortcuts** — New shortcuts go through `KeyboardShortcutSettings` + config + docs.
- **Tests + pbxproj wiring** for new coverage; two-commit red/green for bug regressions.
- **Tagged dogfood** — `./scripts/reload.sh --tag <slug>` / user helper `gdock` for the prior tree; new mission gets its own tag (e.g. `all-ui-dockable`).

### Non-Goals (explicit)

- Re-doing the already-closed canvas content Dockable package from scratch.
- Making **every** ephemeral sheet/popover/menu a freeform pane (menus stay menus).
- Redesigning visual style of Files/workspace lists (placement first).
- iOS parity in v1 unless inventory proves shared package already covers it (macOS primary).
- Multi-monitor edge-case perfection in v1 (document; cover after core placeability).
- Replacing Bonsplit or CmuxCanvas geometry engines unless required — prefer **hosting chrome content in existing pane/canvas slots**.

---

## 1.5 Required Toolchain

Same as ghostty-dock: macOS 14+, Xcode 15+, Swift 6, `./scripts/setup.sh` once, tagged reload for app builds.

Dogfood helper (machine-local): `~/.local/bin/gdock` opens the prior canvas-dockable DEV app; this mission should add `gdock` env or a sibling tag, not hardcode only the old mission forever.

---

## 2. Surface Inventory (must complete in Phase 0)

Phase 0 produces a checked-in inventory table. **No implementation of placement until the table is complete and accepted.**

For each surface:

| Field | Meaning |
|-------|---------|
| `id` | Stable id (e.g. `chrome.left.workspaceList`) |
| `today` | `fixed-left` / `fixed-right` / `canvas-dockable` / `split-pane` / `window` / `overlay` |
| `target` | `dockable-pane` / `dockable-stack` / `decoration` / `out-of-scope` |
| `actor` | What user does (browse files, pick workspace, …) |
| `state` | What must persist |
| `entrypoints` | shortcut, palette, menu, CLI, socket |
| `risk` | focus, performance, portal/webview, snapshot |

### 2.1 Known starting set (expand/correct in Phase 0)

**Left / workspace chrome (non-exhaustive seed):**

- Workspace / tab list and selection chrome  
- Session index / sessions panel surfaces in the left stack  
- Feed / notifications strip if fixed left  
- Git / PR sidebar chrome if fixed left  
- Any secondary left column (e.g. nested tool lists)

**Right chrome (non-exhaustive seed):**

- File explorer (Files mode) — **primary pain**  
- Find in directory  
- Vault  
- Sessions (if right)  
- Feed (if right)  
- Dock tools / extension browser chrome  
- Mode switcher for the right rail itself  

**Already placeable (must remain placeable; may become the *only* home for tools):**

- Terminal, browser, markdown, file preview, agent session, project, workspace todo, custom sidebar, rightSidebarTool panel kind, etc. (post canvas-dockable)

**Decoration candidates (default non-placeable unless inventory disagrees):**

- Window titlebar / traffic lights  
- Pure resize handles  
- Toast/banner “THIS IS A DEV BUILD”  
- Modal alerts  

Phase 0 **fails** if left or right primary tools are omitted or marked `out-of-scope` without user decision.

---

## 3. Product Principles

1. **Chrome is content** — A file tree is not “the right bar”; it is a Files pane that *often* starts docked right.
2. **Default layout can look familiar** — First launch may still show left list + center terminals + right Files. Difference: user can tear any of those off.
3. **Empty chrome columns collapse** — If all tools leave a column, the column goes away (or becomes a drop target), not a permanent empty strip.
4. **Focus and keyboard** — Moving a pane does not break file explorer shortcuts, list navigation, or terminal typing isolation.
5. **One open path** — “Show Files” focuses or creates a Files pane in the last preferred placement (right column if still present, else last frame, else new split/canvas).

---

## 4. Execution Phases

### Phase 0 — Inventory + acceptance criteria freeze

**Purpose:** Stop another “half dockable” delivery.

**Work**

- Produce `docs/cmux-all-ui-dockable.inventory.md` (or table in this PRD) with every surface.
- Map each surface → Dockable kind or new kind, snapshot needs, entrypoints.
- Record decisions for any `decoration` / deferred item.
- Define dogfood matrix: for each `dockable-*` target, place left, right, center split, canvas freeform, second window (if supported).

**Acceptance**

- AC-0.1: Inventory lists **all** left and right primary tools; none silently dropped.  
- AC-0.2: User/owner sign-off recorded (decision file) on inventory + non-goals.  
- AC-0.3: Mission plan maps VAL-* 1:1 to inventory placeable rows (or explicit groups).

**No code placement changes in Phase 0.**

---

### Phase 1 — Placement substrate for chrome hosts

**Purpose:** Chrome tools can mount as Dockables without the fixed rail.

**Work**

- For each right-tool and left-tool marked `dockable-pane` / `dockable-stack`, ensure a Dockable kind + factory + payload codec (reuse `rightSidebarTool` / existing panels where possible; split kinds if fidelity requires).
- Generic mount already exists; ensure chrome tools use it with real content (not empty stubs).
- “Preferred placement” store: last frame / side / window for “Show Files”, “Show Workspaces”, etc.

**Acceptance**

- AC-1.1: Files pane can exist **without** the fixed right rail visible.  
- AC-1.2: At least one left primary list (workspace or sessions — per inventory) can exist **without** the fixed left column.  
- AC-1.3: Registry/matrix tests cover new kinds; no dummy factories.  
- AC-1.4: Focused unit/integration tests for mount/focus/unmount of Files + one left tool.

---

### Phase 2 — Tear-off / dock gestures and commands

**Purpose:** User can move chrome tools with real product verbs.

**Work**

- Undock: from default left/right chrome → split or canvas pane (drag and/or command).  
- Dock: from free pane → left/right edge drop zones **optional**; if edge docks remain, they are conveniences, not prisons.  
- Commands/shortcuts/palette/CLI: Show/Toggle Files, Show Workspaces, etc. route through shared actions that operate on panes, not “toggle fixed column only.”  
- Multi-entrypoint policy: one code path.

**Acceptance**

- AC-2.1: From default layout, user undocks Files to center split; app usable; fixed right column gone or empty-collapsed.  
- AC-2.2: User undocks left workspace list to canvas freeform; can focus and select workspaces.  
- AC-2.3: “Toggle right sidebar” either: (a) toggles visibility of a **Files pane** in preferred placement, or (b) is renamed/replaced with clear pane-oriented commands — no forever-fixed-only behavior.  
- AC-2.4: Shared-behavior tests or harness for shortcut + palette + socket for Show Files.

---

### Phase 3 — Default layout as composition of panes

**Purpose:** Familiar layout is a **saved arrangement of dockables**, not special chrome hosts.

**Work**

- Bootstrap default workspace = left list pane(s) + terminal + optional Files pane, all Dockable.  
- Migrate existing users: fixed chrome open → equivalent panes + frames.  
- Remove or gut dead code paths that only support fixed-host embedding once migration is proven.

**Acceptance**

- AC-3.1: Fresh profile default layout works with **no** mandatory fixed-only host types in the critical path.  
- AC-3.2: Migration from pre-mission sessions restores tools as panes without data loss (files path, workspace selection, etc.).  
- AC-3.3: Grep/architecture guard: no new `fixedRightOnly` / parallel host for Files.

---

### Phase 4 — Persistence, multi-window, polish

**Work**

- Snapshot chrome-origin panes in workspace/session restore.  
- Multi-window: move Files or left list to another window (panel-id moves already exist; prove no kind switch).  
- Performance: file explorer in freeform canvas does not reintroduce list invalidation storms (snapshot-boundary rules).  
- Docs + CHANGELOG + localization audit.

**Acceptance**

- AC-4.1: Quit/relaunch restores positions of left-origin and right-origin panes.  
- AC-4.2: Dogfood matrix from Phase 0 green for all `dockable-*` inventory rows (or recorded deferrals).  
- AC-4.3: CHANGELOG + locale audit complete.  
- AC-4.4: Tagged build dogfoodable via reload tag + optional `gdock` update.

---

## 5. Contract Sketch (VAL-* families)

Author full `VAL-*` files after Phase 0. Families:

| Family | Covers |
|--------|--------|
| `VAL-INV-*` | Inventory completeness, no silent cuts |
| `VAL-LEFT-*` | Left chrome placeability, undock/dock, restore |
| `VAL-RIGHT-*` | Right chrome / Files placeability, undock/dock, restore |
| `VAL-PLACE-*` | Shared verbs: split, canvas, window, focus, empty-column collapse |
| `VAL-ENTRY-*` | Shortcuts, palette, CLI/socket shared paths |
| `VAL-MIGRATE-*` | Session migration from fixed chrome |
| `VAL-PERF-*` | List snapshot boundaries / no 100% CPU loops |
| `VAL-BUILD-*` / `VAL-DOCS-*` | Build, fork policy if any, docs |

**Hard fail examples**

- Files only available inside fixed `⌘⌥B` rail.  
- Left workspace list only available in fixed left column.  
- Canvas kind exists but primary UX still forces fixed host.  
- Dummy registry factories.  
- Dual code paths for “show files” (chrome vs pane) that diverge.

---

## 6. Dogfood Matrix (minimum)

For **Files** and **each left primary tool**:

1. Default layout open  
2. Undock to horizontal/vertical split  
3. Move to freeform canvas  
4. Close and reopen via command/shortcut (preferred placement)  
5. Quit / relaunch restore  
6. Second window move (if multi-window in scope)

Record video or screenshots optional; automated mount/focus/restore tests required for core kinds.

---

## 7. Risks

| Risk | Mitigation |
|------|------------|
| Scope shrink to “Files as canvas kind only” | Phase 0 inventory + AC-2.1/2.2 require **both** left and right |
| Performance (explorer + LazyVStack rules) | Explicit PERF assertions; follow list snapshot boundary policy |
| Focus/shortcut routing breaks when pane moves | Shared action paths; UI tests for explorer shortcuts |
| Migration breaks sessions | Legacy decode + fixtures |
| Token burn / restart loops | One project id; abort dupes; resume only |
| Overlap with canvas-dockable | Reuse package; forbid re-implementation |

---

## 8. Success Criteria (mission done)

1. User can place **left primary chrome tools** and **right primary chrome tools** in splits, canvas, and (if supported) other windows.  
2. No mandatory fixed-only prison for Files or the main left list.  
3. Default layout still usable and familiar, composed of panes.  
4. Restore works.  
5. Contract assertions validated with evidence; gates green.  
6. Dogfood on tagged build; user can say the product matches “put that wherever I want” for **left and right**, not only canvas terminals.

---

## 9. Open Questions (resolve in Phase 0 decisions)

1. Exact left stack members in v1 (workspace list only vs full feed/PR chrome).  
2. Keep optional edge “snap to right” affordance or pure free placement?  
3. Rename/replace `toggleFileExplorer` (⌘⌥B) semantics.  
4. Float vs canvas-only for chrome tools.  
5. Whether custom sidebars / extensions already cover some left tools.

---

## 10. Suggested first commands after accept

```bash
# New isolated worktree + branch (do not reuse closed mission as “restart”)
# ... create worktree ...

# Dogfood prior foundation if needed
gdock              # opens canvas-dockable DEV app
gdock --build      # rebuild that tag

# This mission: own tag e.g. all-ui-dockable
./scripts/reload.sh --tag all-ui-dockable --launch
```

---

## 11. Document control

| Version | Date | Note |
|---------|------|------|
| 0.1 | 2026-07-28 | Draft after canvas-dockable dogfood; user demand for full chrome docking |

**Status:** Draft — needs Phase 0 inventory + user accept before implementation planning.
