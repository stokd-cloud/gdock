# PRD: Vault Automated Session Filter & Repo Focus

## 0. Source Context

**Derived From:** Working request 2026-08-03 — add a Vault filter that hides automated sessions by default (user-generated only), and when the active panel/workspace is in a git repo, focus that repo’s section in Vault (scroll into view, dim others, expand chats up to 15).
**Feature Name:** Vault Automated Session Filter & Repo Focus
**PRD Owner:** Brian Stoker
**Last Updated:** 2026-08-03
**Repository:** `stokd-cloud/ghostty-dock` (fork of `manaflow-ai/cmux`), branch `main`
**Landing:** fork-only on `main`
**Authoring mode:** prd-create (not prd-forge)

### Summary

Improve the **Vault** right-rail tool (user-facing name for the session index: `SessionIndexView` / `SessionIndexStore`) so power users can keep noise down and stay oriented on the repo they are working in.

1. **Automated-session filter** — a control-bar toggle (default **off**) that, when off, shows only **user-generated** sessions and hides **automated** ones. Turning the toggle **on** reveals automated sessions as well.
2. **Repo focus on panel change** — when the active workspace/panel cwd changes and that path is inside a git repository, Vault focuses the matching **directory** section: scroll it into view if needed, slightly gray out non-focused sections, and expand the focused section to show **up to 15** session rows (vs the current global collapsed limit of 5).

### Source inventory (read-only)

| Surface | Role today |
|---|---|
| `Sources/SessionIndexView.swift` | Vault UI: grouping pills, “This folder only”, reload; sections use `collapsedRowLimit = 5` |
| `Sources/SessionIndexStore.swift` | Entries, grouping (directory/agent), scope-to-cwd filter, section order |
| `Sources/SessionIndexModels.swift` | `SessionEntry` model (no automation flag yet) |
| `Sources/SessionIndexTable*.swift` | AppKit table host used for scrolling / row application |
| `Sources/RightSidebarPanelView.swift` / `RightSidebarToolPanel.swift` | Mount Vault; push `currentDirectory` into the store on workspace cwd changes |
| `Packages/macOS/CmuxGit/...` | Resolve git work-tree roots for “am I in a repo?” |
| `cmuxTests/SessionIndex*.swift` | Existing unit coverage patterns for Vault |

### Non-goals

- Redesigning Vault layout, grouping modes, or the “Show more” popover UX beyond the focused-section row limit.
- Cloud vault sync (`vault/` Go CLI / web APIs).
- Filtering by agent type, model, or PR status (only automated vs user-generated).
- Auto-switching grouping mode (focus is defined for **directory** grouping; see Decision in §5).
- Upstream `manaflow-ai/cmux` PR unless later extracted; this is fork-only gdock work.

---

## 1. Objectives & Constraints

### Objectives

- Default Vault list shows **user-generated sessions only**; automated sessions stay hidden until the user turns the filter toggle on.
- Persist the filter preference across launches (same class of UX as grouping).
- On active panel/workspace directory change, if the cwd is inside a git work tree, identify the matching Vault directory section for that repo and: focus it, scroll if off-screen, dim non-focused sections, expand focused section chats to **≤ 15** rows.
- When not in a repo (or no matching section), clear focus chrome: no dimming, default row limits.
- All new user-facing strings localized en+ja; new gdock settings use the `gdock.` prefix.

### Constraints

- **Fork-only** on `stokd-cloud/ghostty-dock` `main`.
- **TDD:** red tests before implementation for each behavioral work item (Axiom 5).
- **Snapshot boundary:** no `@ObservedObject` / store references below the Vault list subtree boundary; pass focus/dim/limit as value snapshots + closures (see `IndexSectionActions` pattern in `SessionIndexView.swift`).
- **No state mutation in view `body`:** focus updates happen from cwd/workspace observers, not from list projection.
- New settings ids: `gdock.vault.*` (not under upstream `sidebar.*` / `app.*` unless grandfathered).
- New tests wired into `cmux.xcodeproj`; `./scripts/lint-pbxproj-test-wiring.sh` green.
- Prefer pure classifier unit tests that do not require a full app launch.

---

## 1.5 Required Toolchain

| Tool | Min Version | Install Command | Verify Command |
|------|-------------|-----------------|----------------|
| macOS | 14.0 | (OS) | `sw_vers -productVersion` |
| Xcode | 15.0 | App Store | `xcodebuild -version` |
| Swift | 6.0 | (bundled with Xcode) | `swift --version` |
| Python 3 | 3.9 | Xcode CLT | `python3 --version` |

Working directory for all Verification Commands: ghostty-dock repo root.

```bash
./scripts/setup.sh   # once per machine if GhosttyKit missing
```

Prefer `CMUX_SKIP_ZIG_BUILD=1` when available for tagged reloads / unit runs that otherwise invoke Zig.

---

## 2. Execution Phases

## Phase 1: Automated classification and filter toggle

**Purpose:** Repo-focus UX must operate on the **already-filtered** session set. Classification and the show-automated toggle are the data-plane foundation; Phase 2 must not invent a second filter path.

### 1.1 Session automation classifier

**Dependencies:** none

**Landing:** fork-only

**Implementation Details**

- Introduce a small pure classifier (new file preferred, e.g. `Sources/SessionAutomationClassifier.swift`, or a tightly scoped extension next to `SessionEntry` if that matches local style) that maps a `SessionEntry` (and any newly added fields) → `isAutomated: Bool`.
- **Classification contract (load-bearing Decision — see §5):**
  - Mark **automated** only when provenance is **confident** (prefer false negatives over false positives so user sessions are never hidden by mistake).
  - Positive automated signals (implement all that are cheaply available on current loaders; leave hooks for more):
    1. Nested / child / subagent provenance when the entry’s agent-specific metadata or resume identity indicates a parent session (fork-parent / subagent patterns already present in live agent / vault scanner code).
    2. Explicit automation provenance markers when present on the entry after loaders are extended (e.g. stokd task / one-shot / orchestrated spawn markers in session metadata or environment captured at index time).
    3. Agent adapters may contribute adapter-local rules behind the same classifier API (Hermes `source`, etc.) when unambiguous.
  - **Unknown → user-generated** (`isAutomated == false`).
- Extend `SessionEntry` (or a parallel projection used only by filtering) so the filter does not re-parse transcripts on every body refresh. Prefer computing `isAutomated` once at load/projection time.
- Failure modes: missing metadata → treat as user-generated; classifier must be pure and unit-testable without disk I/O.

**Acceptance Criteria**

- AC-1.1.a: A pure classifier API exists and is callable from unit tests without launching the app → inspect source / symbols.
- AC-1.1.b: Entries with confident automated provenance classify `isAutomated == true`; entries without signals classify `false` → unit asserts.
- AC-1.1.c: `./scripts/test-unit.sh -only-testing:cmuxTests/SessionAutomationClassifierTests CMUX_SKIP_ZIG_BUILD=1 test` → exit 0 (or equivalent Swift Testing filter once wired).
- AC-1.1.d: `./scripts/lint-pbxproj-test-wiring.sh` → exit 0 for any new test file.

**Acceptance Tests**

- Test-1.1.a: Unit — classifier type/function is exported and used by store filter path.
- Test-1.1.b: Unit — synthetic entries covering automated / user / unknown cases.
- Test-1.1.c: Executable gate for AC-1.1.c.
- Test-1.1.d: Regression — pbx wiring script.

**Verification Commands**

```bash
set -euo pipefail
rg -n 'SessionAutomationClassifier|isAutomated' Sources/
test -f cmuxTests/SessionAutomationClassifierTests.swift \
  || test -f cmuxTests/SessionIndexAutomationFilterTests.swift
./scripts/lint-pbxproj-test-wiring.sh
./scripts/test-unit.sh -only-testing:cmuxTests/SessionAutomationClassifierTests test \
  || ./scripts/test-unit.sh -only-testing:cmuxTests/SessionIndexAutomationFilterTests test
```

### 1.2 Show-automated filter (default off) in store + control bar

**Dependencies:** 1.1

**Landing:** fork-only

**Implementation Details**

- Add `@Published var showAutomatedSessions: Bool` on `SessionIndexStore`, default **`false`**.
- Persist via UserDefaults (and optionally settings catalog) under key **`gdock.vault.showAutomatedSessions`** (gdock prefix required). Default false.
- Apply filter in the same pipeline as `filteredEntriesForCurrentScope()` (or immediately after): when `showAutomatedSessions == false`, drop entries where `isAutomated == true`. When true, pass all (still respecting “This folder only”).
- UI: control-bar toggle next to “This folder only” / reload in `SessionIndexView.controlBar`, localized label e.g. “Show automated” (exact copy in localization keys). Accessibility id: `SessionFilterToggle.showAutomated`.
- Snapshot-boundary safe: toggle binds store at the control bar (above the list), not inside row cells.
- Failure modes: corrupt UserDefaults → fall back to false; empty after filter → existing empty Vault chrome still valid (copy may stay generic).

**Acceptance Criteria**

- AC-1.2.a: Default `showAutomatedSessions == false` → only non-automated entries appear in `sectionsForCurrentGrouping()` / visible entries.
- AC-1.2.b: Toggling true includes automated entries without requiring a full reload from disk.
- AC-1.2.c: Preference survives process restart via `gdock.vault.showAutomatedSessions` / UserDefaults.
- AC-1.2.d: `./scripts/test-unit.sh -only-testing:cmuxTests/SessionIndexAutomationFilterTests test` → exit 0.
- AC-1.2.e: Localization keys for the toggle exist for en and ja in `Resources/Localizable.xcstrings`.

**Acceptance Tests**

- Test-1.2.a: Unit — store with mixed automated/user entries; default filter hides automated.
- Test-1.2.b: Unit — flip flag; section membership updates.
- Test-1.2.c: Unit — round-trip persistence (UserDefaults suite isolation).
- Test-1.2.d: Executable suite for AC-1.2.d.
- Test-1.2.e: Structural — `rg` / JSON parse of xcstrings for both locales.

**Verification Commands**

```bash
set -euo pipefail
rg -n 'showAutomatedSessions|gdock\.vault\.showAutomatedSessions|SessionFilterToggle\.showAutomated' Sources/ Resources/
rg -n 'sessionIndex\.(filter|show)\.automated|Show automated' Resources/Localizable.xcstrings
./scripts/test-unit.sh -only-testing:cmuxTests/SessionIndexAutomationFilterTests test
```

---

## Phase 2: Repo focus on panel change (scroll, dim, expand ≤15)

**Purpose:** Depends on Phase 1 so the focused section’s visible chats are the correct filtered set. Focus chrome without the filter would expand automated noise the user already asked to hide by default.

### 2.1 Resolve focused directory section from workspace cwd / git root

**Dependencies:** Phase 1 complete

**Landing:** fork-only

**Implementation Details**

- When `SessionIndexStore.currentDirectory` changes (already driven by workspace cwd observers in `RightSidebarToolPanel` / `ContentView`), compute an optional **focus target**:
  1. If cwd is nil/empty → clear focus.
  2. Resolve git **work-tree root** via `CmuxGit` repository resolution when possible.
  3. Match a directory-grouping `SectionKey` / `IndexSection`:
     - Prefer exact match on normalized absolute cwd or work-tree root against section paths.
     - Else: section path equal to work-tree root, or the deepest section path that is a prefix of cwd / shares the same work-tree root (document the exact precedence in code comments + tests).
  4. If grouping is **agent**, do **not** force-switch grouping (Decision §5); clear focus chrome or apply no-op focus (tests pin the chosen behavior: **no dimming / no expand when grouping != directory**).
- Expose focus as store or view-model state, e.g. `focusedSectionKey: SectionKey?`, updated only from directory observers / explicit apply helpers — never from list `body`.
- Failure modes: not a git repo → no focus; matching section missing (no sessions for that repo) → no focus; path normalization differences (`/private/var` vs `/var`) must use the same path standardization helpers already used for scope filtering.

**Acceptance Criteria**

- AC-2.1.a: Cwd inside a repo with a matching directory section → `focusedSectionKey` points at that section.
- AC-2.1.b: Cwd outside any repo → focus cleared.
- AC-2.1.c: Agent grouping → no focus chrome applied (per Decision).
- AC-2.1.d: `./scripts/test-unit.sh -only-testing:cmuxTests/SessionIndexRepoFocusTests test` → exit 0.

**Acceptance Tests**

- Test-2.1.a: Unit — synthetic sections + cwd/work-tree root fixtures.
- Test-2.1.b: Unit — non-repo path clears focus.
- Test-2.1.c: Unit — agent grouping suppresses focus effects.
- Test-2.1.d: Executable gate.

**Verification Commands**

```bash
set -euo pipefail
rg -n 'focusedSectionKey|repoFocus|SessionIndexRepoFocus' Sources/ cmuxTests/
./scripts/lint-pbxproj-test-wiring.sh
./scripts/test-unit.sh -only-testing:cmuxTests/SessionIndexRepoFocusTests test
```

### 2.2 Expand focused section (≤15), dim others, scroll into view

**Dependencies:** 2.1

**Landing:** fork-only

**Implementation Details**

- **Row limit:** focused section uses `rowLimit = 15` (constant, e.g. `SessionIndexView.focusedRowLimit = 15`); all other sections keep the existing `collapsedRowLimit = 5` (or remain collapsed if user-collapsed — Decision §5: focus **expands** the focused section even if it was user-collapsed, and does not force-collapse others).
- **Dim:** non-focused sections receive a mild gray-out (opacity in the ~0.45–0.65 range, matching existing drag-dim language in `IndexSectionView`) when `focusedSectionKey != nil`. Focused section stays full opacity. When focus is nil, all sections full opacity.
- **Scroll:** when focus target changes to a non-nil section, scroll the Vault table so the section header is visible (use `SessionIndexTableController` / existing viewport APIs; add a minimal scroll-to-row API if missing). Debounce or coalesce rapid cwd thrash so scroll is not janky.
- Pass `isFocused` / `isDimmed` / effective `rowLimit` as **value snapshots** into `SessionIndexTableRow.section(...)` so Equatable row identity remains stable; update `IndexSectionView.==` accordingly.
- Localization: no new chrome strings required if dimming is visual-only; if a focus affordance needs a11y labels, localize them.
- Failure modes: table not yet laid out → retry scroll on next apply; missing row id → no-op scroll without crash.

**Acceptance Criteria**

- AC-2.2.a: Focused section presents up to 15 entries without requiring “Show more” for the 6th–15th when they exist in the section snapshot.
- AC-2.2.b: Non-focused sections are visually dimmed when focus is active; undimmed when focus clears.
- AC-2.2.c: Focus change triggers a scroll-to-section request for the focused section key.
- AC-2.2.d: `./scripts/test-unit.sh -only-testing:cmuxTests/SessionIndexRepoFocusTests test` → exit 0 (includes expand/dim/scroll request unit coverage).
- AC-2.2.e: Snapshot-boundary audit: no new store observation below the list boundary (`rg` / code review checklist in test comments).

**Acceptance Tests**

- Test-2.2.a: Unit — row projection / section render input uses 15 for focused key.
- Test-2.2.b: Unit — dim flags on non-focused rows when focus set.
- Test-2.2.c: Unit — scroll request emitted with expected section key (controller spy / published intent).
- Test-2.2.d: Executable gate.
- Test-2.2.e: Structural / regression note in suite.

**Verification Commands**

```bash
set -euo pipefail
rg -n 'focusedRowLimit|15|isDimmed|isFocused|scrollTo' Sources/SessionIndexView.swift Sources/SessionIndexTable*.swift Sources/SessionIndexStore.swift
./scripts/test-unit.sh -only-testing:cmuxTests/SessionIndexRepoFocusTests test
./scripts/test-unit.sh -only-testing:cmuxTests/SessionIndexAutomationFilterTests test
```

### 2.3 Localization audit and gdock settings catalog entry

**Dependencies:** 2.2

**Landing:** fork-only

**Implementation Details**

- Ensure every new user-facing string (toggle label, help/tooltip, a11y) uses `String(localized:defaultValue:)` and has en+ja entries in `Resources/Localizable.xcstrings`.
- Register `gdock.vault.showAutomatedSessions` in the gdock settings catalog / JSON path support if that is the house pattern for toggles that also appear in the Vault chrome (mirror how other gdock keys are registered). If the toggle is chrome-only like “This folder only”, still keep the UserDefaults key under `gdock.vault.*` and document it.
- No docs site page required for this slice; Settings search aliases optional.

**Acceptance Criteria**

- AC-2.3.a: Changed localization keys exist for en and ja.
- AC-2.3.b: No bare English string literals introduced for the new toggle in SwiftUI `Text`/`Button`/`help`.
- AC-2.3.c: `python3 -c` / `rg` audit of touched keys passes (locale parity check in Verification Commands).

**Acceptance Tests**

- Test-2.3.a: Structural — xcstrings parity for new keys.
- Test-2.3.b: Structural — `rg` for new defaultValue keys in Sources.
- Test-2.3.c: Executable locale check script in Verification Commands.

**Verification Commands**

```bash
set -euo pipefail
rg -n 'gdock\.vault\.showAutomatedSessions|sessionIndex\.(filter|show)\.|Show automated' \
  Sources/ Resources/Localizable.xcstrings Packages/macOS/CmuxSettings/ || true
python3 - <<'PY'
import json,sys
from pathlib import Path
p=Path("Resources/Localizable.xcstrings")
data=json.loads(p.read_text())
# Soft audit: any key containing showAutomated / sessionIndex filter automated must have en+ja
need=[]
for k,v in data.get("strings",{}).items():
    kl=k.lower()
    if "automated" in kl and ("session" in kl or "vault" in kl or "filter" in kl):
        locs=v.get("localizations") or {}
        for lang in ("en","ja"):
            if lang not in locs:
                need.append(f"{k} missing {lang}")
if need:
    print("MISSING:\n"+"\n".join(need)); sys.exit(1)
print("locale parity ok for automated-session keys (or none yet if keys use different names — re-run after impl)")
PY
```

---

## 3. Completion Criteria

The project is complete when all of the following hold:

1. Phase 1 and Phase 2 work items’ Verification Commands exit 0 on a clean tree with the feature implemented.
2. Default Vault behavior shows only user-generated sessions; automated sessions appear only when the toggle is on.
3. Changing the active panel/workspace into a git repo focuses the matching Vault directory section: scrolled into view, others dimmed, focused section shows up to 15 chats.
4. Outside a repo / no match / agent grouping: no erroneous dimming or forced expand.
5. Localization audit for new strings complete (en+ja); `gdock.vault.showAutomatedSessions` is the persistence key.
6. Snapshot-boundary and no-state-in-body rules respected; pbx test wiring lint green.
7. Fork-only: no requirement to open an upstream cmux PR for this feature.

---

## 4. Rollout & Validation

### Rollout Strategy

- Ship on gdock `main` behind no separate beta flag (Vault is already a shipped tool). Filter default **off** is the safe rollout (reduces noise).
- Dogfood via tagged reload: `./scripts/reload.sh --tag vault-auto-filter-repo-focus`.
- Manual dogfood checklist:
  1. Open Vault with mixed sessions; confirm automated (if any) hidden by default.
  2. Enable “Show automated”; confirm they appear.
  3. Switch workspaces between two repos; confirm focus moves, dims others, expands to ≤15, scrolls.
  4. Open a non-repo folder; confirm focus chrome clears.
  5. Switch grouping to “By agent”; confirm no broken dim state.

### Post-Launch Validation

- Watch for false-positive automated classification (user sessions hidden) — treat as P0; classifier must stay conservative.
- Watch for scroll jank on rapid pane switches; debounce if reported.
- Confirm “This folder only” still composes with the automated filter (AND semantics).

---

## 5. Open Questions

Resolved autonomously (steer if wrong):

1. **Decision: “fault” means Vault** — the right-sidebar sessions tool (`SessionIndexView`), not a new panel.
2. **Decision: automated classification is conservative** — unknown ⇒ user-generated; only confident provenance marks automated. Prefer missing automated sessions over hiding real user work.
3. **Decision: filter default off means hide automated** — toggle label “Show automated”; off by default.
4. **Decision: persistence key** — `gdock.vault.showAutomatedSessions` (UserDefaults + gdock convention).
5. **Decision: focus applies in directory grouping only** — does not auto-switch away from agent grouping; agent grouping clears focus chrome.
6. **Decision: focused row limit = 15**, non-focused stay at 5; focus expands the focused section even if previously user-collapsed.
7. **Decision: dim is visual opacity only** — no reorder of sections to pin focused repo to top (scroll instead of reorder).
8. **Decision: “change panels”** — active workspace / focused pane cwd change (existing `currentDirectory` pipeline), not switching right-rail tool tabs alone.
9. **Decision: “current panel’s chats”** — session rows under the focused directory/repo section (not ACP agent chat transcripts).

Still optional later (out of scope unless product steers):

- Settings row in Settings app for the same toggle (chrome toggle is sufficient for v1).
- Explicit per-agent automation taxonomies beyond confident provenance.
- Pinning focused section to top of the list instead of scrolling.
- Upstreaming to `manaflow-ai/cmux`.
