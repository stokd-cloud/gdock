# Phase 4: Rollout Surfacing, Localization Audit, and Documentation

**Project:** Dockable Sidebar Spaces and Quad Split
**Slug:** dockable-sidebar-spaces-and-quad-split
**Review Mode:** complete

## Work Items

### 4.1: Settings surfacing and configuration

**Implementation Details**

- **Landing:** fork-only.
- The flag key `sidebar.beta.dock.enabled` (default `false`) is created in 1.1. This item does not redefine it; it surfaces it in Settings beside the existing Feed and Dock beta rows and accepts it from `~/.config/cmux/cmux.json` on the same path those use, then verifies the declared shape has not drifted.
- Deliberately not a PostHog flag: `scripts/lint-feature-flags.py` requires a `-release`/`-experiment`/`-permission` suffix, an owner, a `reviewBy` expiry, a `defaultWhenUnavailable`, and a single evaluation site — none of which suit a long-lived UI beta toggle read from several views. The Feed and Dock betas set the precedent.
- Default stays `false` for the whole of this PRD; flipping it is out of scope and gated on dogfood (§4).
- Localize the Settings row label and help text with `en` + `ja`.
- Failure modes: with the flag off, no rail writes a snapshot field and every rail renders its pre-PRD path; toggling at runtime cannot corrupt an existing snapshot because the fields are additive and simply unread.

**Acceptance Criteria**

- AC-4.1.a: A Settings row toggles `sidebar.beta.dock.enabled` and the value round-trips through `~/.config/cmux/cmux.json` → the flag is user-reachable by both routes.
- AC-4.1.b: `python3 scripts/lint-feature-flags.py` exits 0 → the PostHog registries are untouched and still lint clean.
- AC-4.1.c: `./scripts/test-unit.sh -only-testing:cmuxTests/SidebarDockBetaFlagTests CMUX_SKIP_ZIG_BUILD=1 test` → exit 0.
- AC-4.1.d: With the flag off, a written session file contains neither `leftSidebarDock` nor `rightSidebarDock` → the dark path is inert.
- AC-4.1.e: Toggling the flag leaves an existing session snapshot loadable → no corruption on either transition.
- AC-4.1.f: The Settings row label and help text have `en` + `ja` with `state == "translated"` and differing values.

### 4.2: Localization audit and documentation

**Implementation Details**

- **Landing:** fork-only.
- Enumerate every user-facing surface this project added and verify each has `en` + `ja` entries with `state == "translated"` and a `ja` value differing from `en`. The complete key list: `sidebarDock.splitRail.top`, `sidebarDock.splitRail.bottom` (1.2); the five quad keys `shortcut.splitQuad.label`, `menu.view.splitQuad`, `command.terminalSplitQuad.title`, `terminalContextMenu.splitQuad`, `workspace.tooltip.splitQuad` (1.4) — note there is deliberately **no** `command.terminalSplitQuad.subtitle`, because every built-in config action shares the single subtitle `command.cmuxConfig.builtInSubtitle` (`Sources/CmuxConfig.swift:1400`) and no per-action subtitle mechanism exists; demanding such a key would make this criterion unsatisfiable; `sidebarDock.workspaces.title` (2.2); the right-rail header strings (2.1); and the Settings row strings (4.1).
- Web-side catalogs: add `cmux.splitQuad` to the `nightlyActionRegistryDesc` and `actionTypeBuiltin` strings in `web/messages/en.json` and `web/messages/ja.json`; these are prose sentences carrying inline element tags, so the TSX consumer that renders them must gain a matching tag handler. Add the `splitQuad` entry with `en`/`ja` descriptions to the `split-panes` category in `web/data/cmux-shortcuts.ts`.
- **The shipped Dock docs page is localized and must not be missed:** `web/app/[locale]/(landing)/docs/dock/page.tsx` renders via `useTranslations("docs.dock")` from `web/messages/{en,ja}.json`. Updating only the internal `docs/dock.md` would leave the user-visible page stale in both locales, violating §1's "update every supported message catalog". Update the `docs.dock` keys covering the split affordances and shortcuts, including the Dock-focused shortcut behavior described at `docs/dock.md:23`.
- Run the prescribed audit: parse the touched localization files, compare changed keys across `en`/`ja`, and `rg` the changed Swift/TS/TSX/docs files for newly introduced bare English in `Text(`, `Button(`, `.help(`, `.safeHelp(`, `.tooltip(`, alert titles, and accessibility labels. Record the result in the handoff, including anything unverified. `defaultValue`, English fallback text, and schema descriptions do not count.
- Record the locale bookkeeping accurately: `Resources/Localizable.xcstrings` has 20 locales; `knownRegions` has 19 entries = 18 locales + Base, missing `km` and `uk`; `CLAUDE.md` and `skills/cmux-localization/SKILL.md` both say "English and Japanese". This PRD meets the `en` + `ja` bar and does not attempt the other 18.
- Add `docs/sidebar-docking.md` (NEW) documenting: rails as dock spaces; that a horizontal divider is Bonsplit `.vertical`; the drop bands being 25% edge bands with an 80pt floor, with the reachable band given for **both** rails (`x ∈ [80, 196]` at a 276pt right rail, `x ∈ [80, 160]` at a 240pt left rail, and unreachable at a left rail ≤ 160pt) and the non-drag command named as the primary path; that a rail holds N sections with no cap; that each section is collapsible via an imposed pixel extent and every boundary is a drag-resize handle; cross-rail moves; the placement matrix; and both persistence mechanisms (the session file and `layouts.json`).
- Update `docs/dock.md` to distinguish the Dock from sidebar dock spaces, and add a `CHANGELOG.md` entry.

**Acceptance Criteria**

- AC-4.2.a: Every key in the enumerated list has `en` + `ja` with `state == "translated"` and differing values → the audit passes for the complete surface list.
- AC-4.2.b: `docs/sidebar-docking.md` documents the orientation inversion, the drop-band geometry **with both rails' numbers including the unreachable ≤160pt left-rail case**, the absence of a section cap, the collapse mechanism, and both persistence mechanisms → the non-obvious constraints are written down against the real worst case.
- AC-4.2.c: All CI guard scripts pass → `./scripts/check-pbxproj.sh`, `python3 scripts/check-workspace-package-groups.py --check`, `python3 scripts/check-package-resolved-policy.py`, `./tests/test_ci_pbxproj_test_wiring.sh`, and `python3 tests/test_ci_sidebar_lazy_layout_guard.py` all exit 0.
- AC-4.2.d: `web/messages/en.json` and `ja.json` both contain `cmux.splitQuad`, and the `docs.dock` keys mention the quad affordance → the user-visible docs page is not stale in either locale.
- AC-4.2.e: `docs/dock.md` distinguishes the Dock from sidebar dock spaces → the two features are not conflated.
- AC-4.2.f: No bare English literal appears in a user-facing Swift call in any file this project changed → `rg` over the changed set is clean.

