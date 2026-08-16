# PRD: Vault Automated Session Filter & Repo Focus

## 0. Source Context

**Derived From:** Working request 2026-08-03 — add a Vault filter that hides automated sessions by default (user-generated only), and when the active panel/workspace is in a git repo, focus that repo’s section in Vault (scroll into view, dim others, expand chats up to 15).
**Feature Name:** Vault Automated Session Filter & Repo Focus
**PRD Owner:** Brian Stoker
**Last Updated:** 2026-08-03 (rev 2 — binary origin policy)
**Repository:** `stokd-cloud/ghostty-dock` (fork of `manaflow-ai/cmux`), branch `main`
**Landing:** fork-only on `main`
**Authoring mode:** prd-create (not prd-forge)

### Summary

Improve the **Vault** right-rail tool (user-facing name for the session index: `SessionIndexView` / `SessionIndexStore`) so power users can keep noise down and stay oriented on the repo they are working in.

1. **Automated-session filter** — a control-bar toggle (default **off**) that, when off, shows only **user-generated** sessions and hides **automated** (stokd-chat-originated) ones. Turning the toggle **on** reveals stokd-chat sessions as well.
2. **Repo focus on panel change** — when the active workspace/panel cwd changes and that path is inside a git repository, Vault focuses the matching **directory** section: scroll it into view if needed, slightly gray out non-focused sections, and expand the focused section to show **up to 15** session rows (vs the current global collapsed limit of 5).

**Buckets (load-bearing, black-and-white):**

| Bucket | Meaning | Filter default |
|---|---|---|
| **User-generated** | Agent sessions **not** created via stokd chat (human terminal launches, etc.) | Visible when “Show automated” is **off** |
| **Automated** | Agent sessions **created via stokd chat** | Hidden when “Show automated” is **off** |

Classification is **not** a confidence heuristic. Origin must be a durable, binary field known from spawn / first SessionStart (see Phase 1).

### Source inventory (read-only)

| Surface | Role today |
|---|---|
| `Sources/SessionIndexView.swift` | Vault UI: grouping pills, “This folder only”, reload; sections use `collapsedRowLimit = 5` |
| `Sources/SessionIndexStore.swift` | Entries, grouping (directory/agent), scope-to-cwd filter, section order |
| `Sources/SessionIndexModels.swift` | `SessionEntry` model (no origin field yet) |
| `Sources/SessionIndexTable*.swift` | AppKit table host used for scrolling / row application |
| `Sources/RightSidebarPanelView.swift` / `RightSidebarToolPanel.swift` | Mount Vault; push `currentDirectory` into the store on workspace cwd changes |
| `CLI/cmux.swift` + agent hook path | Every agent fires `session-start`; upserts `~/.cmuxterm/<agent>-hook-sessions.json` with workspace/surface/pid/launchCommand |
| `ClaudeHookSessionRecord` / sibling agent stores | Bind sessions to panes; **do not yet persist a stokd-chat origin bit** |
| `Sources/AppDelegate+AgentChat.swift` | Stokd/agent-chat server launch stamps `CMUX_AGENT_CHAT_*` on the **chat server**, not yet a durable per-coding-agent origin on SessionStart |
| `Packages/macOS/CmuxGit/...` | Resolve git work-tree roots for “am I in a repo?” |
| `cmuxTests/SessionIndex*.swift` | Existing unit coverage patterns for Vault |

### Investigation note (rev 2 grounding)

SessionStart **already runs for every agent** (including non-stokd-chat launches) and records workspace/surface identity. What is **missing** is an explicit, durable **origin** field: `selectedAgentLaunchEnvironment` strips most env, so chat-related keys are not retained on hook records today. Therefore Phase 1 **must codify** origin (stamp at stokd-chat spawn + capture on SessionStart), not guess from partial signals.

### Non-goals

- Redesigning Vault layout, grouping modes, or the “Show more” popover UX beyond the focused-section row limit.
- Cloud vault sync (`vault/` Go CLI / web APIs).
- Filtering by agent type, model, or PR status (only automated vs user-generated).
- Auto-switching grouping mode (focus is defined for **directory** grouping; see Decision in §5).
- Fuzzy / best-effort classification that hides user work when origin is missing without a defined migration policy (see §5 for historical sessions).
- Upstream `manaflow-ai/cmux` PR unless later extracted; this is fork-only gdock work.

---

## 1. Objectives & Constraints

### Objectives

- Make session origin **binary and knowable**: every coding-agent session is either **stokd-chat** (automated) or **user** (user-generated). No “unknown” product bucket.
- Default Vault list shows **user-generated sessions only**; stokd-chat sessions stay hidden until the user turns the filter toggle on.
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
- Origin must be **codified** (spawn stamp + SessionStart persistence), not inferred from incomplete env capture.

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

## Phase 1: Binary origin (stokd-chat vs user) and filter toggle

**Purpose:** Repo-focus UX must operate on the **already-filtered** session set. Origin must be codified before Vault can filter; Phase 2 must not invent a second filter path.

### 1.1 Codify durable session origin at stokd-chat spawn + SessionStart

**Dependencies:** none

**Landing:** fork-only

**Implementation Details**

- **Product rule (black-and-white):** a coding-agent session is exactly one of:
  - `stokdChat` → **automated** (created via stokd chat)
  - `user` → **user-generated** (any other origin: human terminal launch, wrappers that are not stokd chat, etc.)
- **Why SessionStart is the write path:** every supported agent already fires `cmux <agent>-hook session-start` / generic hook `session-start` (see `CLI/CMUXCLI+AgentHookCatalog.swift`, `CLI/cmux.swift`). That path already upserts `~/.cmuxterm/<agent>-hook-sessions.json` with `workspaceId`, `surfaceId`, `pid`, and `launchCommand`. Origin belongs on that same first-hook record.
- **Stamp at spawn (stokd-chat only):** every path that creates an agent **through stokd chat** must put a durable, non-secret marker on the **agent process environment** before the first SessionStart, e.g. `CMUX_SESSION_ORIGIN=stokd-chat` (exact key name may match house style; must be stable and documented in code). Do **not** rely on ambient inheritance of `CMUX_AGENT_CHAT_*` server launch vars alone — those today target the chat server sidecar (`AppDelegate+AgentChat`), not the coding agent, and are stripped by `selectedAgentLaunchEnvironment`.
- **Capture on SessionStart (all agents):** on the first SessionStart upsert, persist an explicit `sessionOrigin` field on the hook-session record (all agent stores that Vault joins, not only Claude). Read origin from the process env / trusted launch capture **before** the selective env filter that drops most keys. Rules:
  - If `CMUX_SESSION_ORIGIN=stokd-chat` (or equivalent) is present → write `sessionOrigin = stokdChat`.
  - Else → write `sessionOrigin = user`.
  - Do **not** leave the field absent for new writes after this ships. Optional decode for old records: treat missing as historical (see AC + §5 migration).
- **Immutability:** once set on a session id, origin does not flip on later hooks (prompt-submit / stop). Forks that mint a **new** session id get a new SessionStart and their own origin from **their** spawn env.
- Failure modes: SessionStart cannot resolve pane → still persist origin if session id is known; missing stamp on non-stokd-chat path → `user` (correct). Stokd-chat path that forgets to stamp → tests must fail (that is a product bug, not “unknown”).

**Acceptance Criteria**

- AC-1.1.a: Hook-session record schema includes a durable `sessionOrigin` (or equivalent) with values covering `stokdChat` and `user` → structural.
- AC-1.1.b: SessionStart write path sets `sessionOrigin = stokdChat` when the spawn stamp is present, else `user` → unit/integration tests on the upsert helper (no full agent required).
- AC-1.1.c: Stokd-chat spawn path(s) set the origin stamp env on the coding-agent process (not only on the chat server) → `rg` + unit or focused launch-env test.
- AC-1.1.d: `./scripts/test-unit.sh -only-testing:cmuxTests/SessionOriginHookTests test` → exit 0 (name may match final suite; must exist and be wired).
- AC-1.1.e: `./scripts/lint-pbxproj-test-wiring.sh` → exit 0 for new test files.

**Acceptance Tests**

- Test-1.1.a: Unit — decode/encode hook record with `sessionOrigin`.
- Test-1.1.b: Unit — SessionStart upsert helper given env with/without stamp.
- Test-1.1.c: Unit — stokd-chat spawn env builder includes stamp.
- Test-1.1.d: Executable gate for AC-1.1.d.
- Test-1.1.e: Regression — pbx wiring.

**Verification Commands**

```bash
set -euo pipefail
rg -n 'sessionOrigin|CMUX_SESSION_ORIGIN|stokdChat|stokd-chat' CLI/ Sources/ Packages/macOS/CMUXAgentLaunch/ || true
rg -n 'sessionOrigin|CMUX_SESSION_ORIGIN' CLI/cmux.swift Sources/ || true
test -f cmuxTests/SessionOriginHookTests.swift \
  || test -f cmuxTests/SessionIndexAutomationFilterTests.swift
./scripts/lint-pbxproj-test-wiring.sh
./scripts/test-unit.sh -only-testing:cmuxTests/SessionOriginHookTests test \
  || ./scripts/test-unit.sh -only-testing:cmuxTests/SessionIndexAutomationFilterTests test
```

### 1.2 Vault join: SessionEntry.origin → isAutomated

**Dependencies:** 1.1

**Landing:** fork-only

**Implementation Details**

- Extend `SessionEntry` with a binary origin field used by Vault, e.g. `sessionOrigin: SessionOrigin` where `SessionOrigin` is `{ stokdChat, user }` (or `isAutomated: Bool` derived only from that enum — not from multi-heuristic scoring).
- When Vault loaders build `SessionEntry` rows (JSONL / SQL / registered agents), **join** by agent kind + session id into the corresponding `~/.cmuxterm/<agent>-hook-sessions.json` origin field. Join is pure data, not a UI-time guess.
- `isAutomated == (sessionOrigin == .stokdChat)`. There is no third product state for filter membership.
- **Historical sessions** (records written before origin existed): apply the §5 migration decision (must be explicit in code + tests). Default for rev 2: pre-origin records are treated as **`user`** only after an audited one-time rule is documented; implementers must not invent a silent “confidence” middle ground. Prefer a migration that re-stamps from still-available spawn evidence if any; otherwise classify as `user` and document the cutover date in code comments/tests.
- Pure mapper/classifier (`SessionAutomationClassifier` or thinner) maps origin → filter membership for unit tests without disk I/O when given a pre-joined entry.

**Acceptance Criteria**

- AC-1.2.a: `SessionEntry` carries origin / automated membership for filter use → structural.
- AC-1.2.b: Joined stokd-chat origin ⇒ automated; joined user origin ⇒ not automated → unit asserts.
- AC-1.2.c: Historical missing-origin policy is covered by an explicit test (not an implicit “unknown” branch in production API).
- AC-1.2.d: `./scripts/test-unit.sh -only-testing:cmuxTests/SessionAutomationClassifierTests test` → exit 0 \
  or the unified `SessionIndexAutomationFilterTests` suite.

**Acceptance Tests**

- Test-1.2.a: Unit — entry field present.
- Test-1.2.b: Unit — stokdChat vs user.
- Test-1.2.c: Unit — historical missing-origin policy.
- Test-1.2.d: Executable gate.

**Verification Commands**

```bash
set -euo pipefail
rg -n 'sessionOrigin|isAutomated|SessionOrigin' Sources/SessionIndexModels.swift Sources/SessionIndexStore.swift Sources/ || true
./scripts/test-unit.sh -only-testing:cmuxTests/SessionAutomationClassifierTests test \
  || ./scripts/test-unit.sh -only-testing:cmuxTests/SessionIndexAutomationFilterTests test
```

### 1.3 Show-automated filter (default off) in store + control bar

**Dependencies:** 1.2

**Landing:** fork-only

**Implementation Details**

- Add `@Published var showAutomatedSessions: Bool` on `SessionIndexStore`, default **`false`**.
- Persist via UserDefaults (and optionally settings catalog) under key **`gdock.vault.showAutomatedSessions`** (gdock prefix required). Default false.
- Apply filter in the same pipeline as `filteredEntriesForCurrentScope()` (or immediately after): when `showAutomatedSessions == false`, drop entries where `isAutomated == true` (stokd-chat). When true, pass all (still respecting “This folder only”).
- UI: control-bar toggle next to “This folder only” / reload in `SessionIndexView.controlBar`, localized label e.g. “Show automated” (exact copy in localization keys). Accessibility id: `SessionFilterToggle.showAutomated`.
- Snapshot-boundary safe: toggle binds store at the control bar (above the list), not inside row cells.
- Failure modes: corrupt UserDefaults → fall back to false; empty after filter → existing empty Vault chrome still valid (copy may stay generic).

**Acceptance Criteria**

- AC-1.3.a: Default `showAutomatedSessions == false` → only user-origin entries appear in `sectionsForCurrentGrouping()` / visible entries.
- AC-1.3.b: Toggling true includes stokd-chat entries without requiring a full reload from disk.
- AC-1.3.c: Preference survives process restart via `gdock.vault.showAutomatedSessions` / UserDefaults.
- AC-1.3.d: `./scripts/test-unit.sh -only-testing:cmuxTests/SessionIndexAutomationFilterTests test` → exit 0.
- AC-1.3.e: Localization keys for the toggle exist for en and ja in `Resources/Localizable.xcstrings`.

**Acceptance Tests**

- Test-1.3.a: Unit — store with mixed stokd-chat/user entries; default filter hides stokd-chat.
- Test-1.3.b: Unit — flip flag; section membership updates.
- Test-1.3.c: Unit — round-trip persistence (UserDefaults suite isolation).
- Test-1.3.d: Executable suite for AC-1.3.d.
- Test-1.3.e: Structural — `rg` / JSON parse of xcstrings for both locales.

**Verification Commands**

```bash
set -euo pipefail
rg -n 'showAutomatedSessions|gdock\.vault\.showAutomatedSessions|SessionFilterToggle\.showAutomated' Sources/ Resources/
rg -n 'sessionIndex\.(filter|show)\.automated|Show automated' Resources/Localizable.xcstrings
./scripts/test-unit.sh -only-testing:cmuxTests/SessionIndexAutomationFilterTests test
```

---

## Phase 2: Repo focus on panel change (scroll, dim, expand ≤15)

**Purpose:** Depends on Phase 1 so the focused section’s visible chats are the correct filtered set (user-generated by default). Focus chrome without the filter would expand stokd-chat sessions the user already asked to hide by default.

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
2. Origin is binary and durable: stokd-chat spawn stamps + SessionStart persists `sessionOrigin`; Vault joins that bit into `SessionEntry`.
3. Default Vault behavior shows only **user** origin sessions; **stokd-chat** sessions appear only when the toggle is on.
4. Changing the active panel/workspace into a git repo focuses the matching Vault directory section: scrolled into view, others dimmed, focused section shows up to 15 chats.
5. Outside a repo / no match / agent grouping: no erroneous dimming or forced expand.
6. Localization audit for new strings complete (en+ja); `gdock.vault.showAutomatedSessions` is the persistence key.
7. Snapshot-boundary and no-state-in-body rules respected; pbx test wiring lint green.
8. Fork-only: no requirement to open an upstream cmux PR for this feature.

---

## 4. Rollout & Validation

### Rollout Strategy

- Ship on gdock `main` behind no separate beta flag (Vault is already a shipped tool). Filter default **off** hides stokd-chat sessions (reduces noise).
- Dogfood via tagged reload: `./scripts/reload.sh --tag vault-auto-filter-repo-focus`.
- Manual dogfood checklist:
  1. Start an agent from **stokd chat**; confirm first SessionStart wrote `sessionOrigin=stokdChat` in the hook store; confirm Vault hides it by default.
  2. Start the same agent kind from a **human terminal**; confirm `sessionOrigin=user` and Vault shows it by default.
  3. Enable “Show automated”; confirm the stokd-chat session appears.
  4. Switch workspaces between two repos; confirm focus moves, dims others, expands to ≤15, scrolls.
  5. Open a non-repo folder; confirm focus chrome clears.
  6. Switch grouping to “By agent”; confirm no broken dim state.

### Post-Launch Validation

- **P0:** stokd-chat spawn path missing the origin stamp (sessions mis-bucketed as user). Treat as a codification bug, not a filter UX bug.
- **P0:** human terminal sessions incorrectly stamped stokd-chat (user work hidden by default).
- Watch for scroll jank on rapid pane switches; debounce if reported.
- Confirm “This folder only” still composes with the automated filter (AND semantics).

---

## 5. Open Questions

Resolved (including product correction 2026-08-03):

1. **Decision: “fault” means Vault** — the right-sidebar sessions tool (`SessionIndexView`), not a new panel.
2. **SUPERSEDED (rev 1): automated classification is conservative — unknown ⇒ user-generated.** Rejected by product: origin is **100% knowable** and must be codified, not approximated. Preferring false negatives is the wrong attitude for this filter.
3. **Decision (rev 2): two hard buckets** —
   - **Automated** = sessions **created via stokd chat**.
   - **User-generated** = every other agent session.
   - No third product bucket. No confidence scoring. No “unknown ⇒ user” as a design principle.
4. **Decision (rev 2): identification method** —
   - **Stamp** at stokd-chat spawn on the coding-agent process env (`CMUX_SESSION_ORIGIN=stokd-chat` or equivalent).
   - **Capture** on first SessionStart into `~/.cmuxterm/<agent>-hook-sessions.json` as durable `sessionOrigin`.
   - **Join** into Vault `SessionEntry` by agent + session id.
   - Grounding: SessionStart already fires for all agents and binds workspace/surface; it did **not** persist origin. `selectedAgentLaunchEnvironment` currently drops non-resume env, so chat markers are not “already there” on disk — they must be written as a first-class field before the selective env filter.
5. **Decision: filter default off means hide automated (stokd-chat)** — toggle label “Show automated”; off by default.
6. **Decision: persistence key** — `gdock.vault.showAutomatedSessions` (UserDefaults + gdock convention).
7. **Decision: focus applies in directory grouping only** — does not auto-switch away from agent grouping; agent grouping clears focus chrome.
8. **Decision: focused row limit = 15**, non-focused stay at 5; focus expands the focused section even if previously user-collapsed.
9. **Decision: dim is visual opacity only** — no reorder of sections to pin focused repo to top (scroll instead of reorder).
10. **Decision: “change panels”** — active workspace / focused pane cwd change (existing `currentDirectory` pipeline), not switching right-rail tool tabs alone.
11. **Decision: “current panel’s chats”** — session rows under the focused directory/repo section (not ACP agent chat transcripts).
12. **Decision (rev 2): historical sessions without `sessionOrigin`** — one-time cutover: treat missing field as **`user`** for filter membership **only after** the new SessionStart path is shipping, and document the cutover in tests. Do not invent an ongoing “unknown” API. If a better re-stamp from still-available evidence is found during implementation, replace this cutover with that re-stamp **and keep tests black-and-white**.

Still optional later (out of scope unless product steers):

- Settings row in Settings app for the same toggle (chrome toggle is sufficient for v1).
- Additional automated buckets beyond stokd chat (subagents, stokd one-shot CLI, etc.) — would be new explicit origin enum cases, not fuzzy heuristics.
- Pinning focused section to top of the list instead of scrolling.
- Upstreaming to `manaflow-ai/cmux`.
