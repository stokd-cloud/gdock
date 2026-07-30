# Phase 4: Entrypoints, localization, and rollout enablement

**Project:** Stokd Widgets: Global Config + Per-Model Token Usage
**Slug:** stokd-widgets-global-config-per-model-token-usage
**Review Mode:** complete

## Work Items

### 4.1: Entrypoints across every surface

**Implementation Details**

- Per the `CLAUDE.md` shared-behavior policy, every entrypoint funnels through **one** shared action layer. Add `Sources/StokdWidgetActions.swift`:

  ```swift
  @MainActor enum StokdWidgetActions {
      @discardableResult static func openConfigWidget(for workspace: Workspace, focus: Bool = true) -> StokdConfigWidgetPanel?
      @discardableResult static func openTokenUsageWidget(for workspace: Workspace, focus: Bool = true) -> StokdTokenUsageWidgetPanel?
  }
  ```

  Each resolves `bonsplitController.focusedPaneId` then calls the 2.6 open-or-focus factory — exactly the `WorkspaceTodoActions.openTodoPane` shape (`Sources/WorkspaceTodoFeature.swift`).
- Register at every surface, modeled on the `workspaceTodo` trace:
  - **Command palette:** contributions + handlers in a new `Sources/ContentView+StokdWidgetCommandPalette.swift`, using `CommandPaletteCommandContribution` and `registry.register(commandId:handler:)` with ids `palette.openStokdConfigWidget` and `palette.openStokdTokenUsageWidget`.
  - **Keyboard shortcuts:** two cases in `Sources/KeyboardShortcutSettings.swift` (enum case + label + dispatch arm). Per the shortcut policy each must also be editable in Settings, settable via `~/.config/cmux/cmux.json`, and documented in the keyboard-shortcut and configuration docs (`docs/configuration.md`).
  - **Socket/CLI:** verbs `workspace.stokd.configWidget.open` and `workspace.stokd.tokenUsage.open` in a new `Sources/TerminalController+ControlStokdWidgets.swift`. If either should be allowed to take focus, add it to `focusIntentV2Methods` in `Sources/TerminalController.swift:260` — otherwise it will silently fail to focus.
  - **Context menu / sidebar:** entries calling the shared actions.
  - **Session restore:** the 2.6 factories, gate-aware.
- Update `docs/cli-contract.md` and `docs/configuration.md` for the new verbs, shortcuts, and the `stokd.widgets.enabled` key.
- Failure modes: an entrypoint bypassing the shared action (duplicated logic — the exact thing the policy forbids); a socket verb absent from the focus allowlist; a shortcut added to the enum but not to Settings.

**Acceptance Criteria**

- AC-4.1.a: Every entrypoint routes through `StokdWidgetActions` → no call site constructs a widget panel or calls a factory directly outside `StokdWidgetActions` and session restore.
- AC-4.1.b: Both palette commands are registered and open the singleton pane.
- AC-4.1.c: Both shortcuts exist in `KeyboardShortcutSettings` and are Settings-editable.
- AC-4.1.d: Both socket verbs exist and are dispatched → `grep -q 'workspace.stokd.configWidget.open' Sources/TerminalController+ControlStokdWidgets.swift` exits 0.
- AC-4.1.e: Docs updated → `grep -q 'stokd.widgets.enabled' docs/configuration.md` exits 0.
- AC-4.1.f: All entrypoints are gate-aware → with the gate off, no palette entry, shortcut, or socket verb creates a widget.
- AC-4.1.g: `xcodebuild ... -only-testing:cmuxTests/StokdWidgetEntrypointTests test` → exit 0.

### 4.2: Localization audit + a real localization gate

**Implementation Details**

- Enumerate every user-facing string introduced by this PRD — widget titles, timespan labels, scope labels and the global-write confirmation, provenance badges, provider-state labels (observed / un-instrumented / idle), `unpriced` / `unregistered` / `unavailable` markers, empty states, error framing, palette titles and subtitles, shortcut labels, Settings rows — and add each to `Resources/Localizable.xcstrings` with translations for **all 20** locales: `ar bs da de en es fr it ja km ko nb pl pt-BR ru th tr uk zh-Hans zh-Hant`. `CLAUDE.md`'s "English and Japanese" claim is stale; the catalog carries 20 and 4,172 keys today.
- `defaultValue`, English fallback text, and CLI-supplied descriptor text do **not** count as localization. Descriptor `label`/`description` come from the CLI in English and are explicitly out of scope for translation — say so in the handoff rather than leaving it ambiguous.
- There is **no** localization CI gate in this repo (`ls scripts/ | grep -iE 'local|l10n|xcstrings'` is empty; no workflow references one). Since this PRD adds user-facing strings across 20 locales and the convention is otherwise unenforced, add `scripts/check-localization-coverage.py`: given a set of key prefixes (`stokdWidget.*`), assert every key has a non-empty translation for all 20 locales, exit 1 listing gaps. Wire it into the `workflow-guard-tests` job of `.github/workflows/ci.yml` alongside the other `check-*` guards.
- Run `rg` over changed Swift files for newly introduced bare English string literals in `Text(`/`Button(`/alert titles.
- Failure modes: a key added for `en` only (the new gate catches it); a locale key present but empty (gate treats empty as missing); a string hardcoded in a view (the `rg` sweep).

**Acceptance Criteria**

- AC-4.2.a: Every `stokdWidget.*` key has a non-empty value in all 20 locales.
- AC-4.2.b: `python3 scripts/check-localization-coverage.py --prefix stokdWidget` → exit 0.
- AC-4.2.c: The gate actually fails on a gap → removing one locale's value for one key makes the script exit non-zero.
- AC-4.2.d: The gate is wired into CI → `grep -q 'check-localization-coverage' .github/workflows/ci.yml` exits 0.
- AC-4.2.e: No bare English literal remains in the new views → an `rg` sweep of `Text("`/`Button("` over the files added by Phase 3 and 4.1 returns no hits.
- AC-4.2.f: `python3 -c "import json; d=json.load(open('Resources/Localizable.xcstrings')); ks=[k for k in d['strings'] if k.startswith('stokdWidget.')]; assert ks, 'no stokdWidget keys'; print(len(ks))"` → exit 0, printing the key count.

### 4.3: Upstream PR submission, gate default, and final green

**Implementation Details**

- **Upstream submission** for the single upstreamable unit (2.2, `JSONLTailReader`):
  - There is currently **no `upstream` git remote** — only `origin` → `git@github.com:stokd-cloud/ghostty-dock.git`. The maintainer must add `manaflow-ai/cmux` as a remote; this PRD does not add or modify remotes.
  - Branch from `origin/upstream-main` (the pristine mirror maintained by `.github/workflows/sync-upstream.yml`, Model B), cherry-pick only the 2.2 commit — `Packages/macOS/CmuxFoundation/.../JSONLTailReader.swift` plus its tests — and confirm the diff contains no stokd identifier and no `StokdWidgetKit` reference. Read `CONTRIBUTING.md` and `.github/PULL_REQUEST_TEMPLATE*` if present and conform.
  - Frame it as generic FileWatch infrastructure. Do not mention stokd, widgets, or token usage.
- **Fork-only diff hygiene:** confirm no fork-only change leaked into the upstream branch, and that `docs/ghostty-fork.md` records the new fork-only surface area per the fork-doc convention.
- **Flip the gate default** `stokd.widgets.enabled` to `true` in `Sources/CmuxConfig.swift`. This is the last functional change in the PRD.
- Add a `CHANGELOG.md` entry.
- **Full green:** run every CI gate that touches this work — pbxproj wiring and normalization, workspace groups, lockfile policy, feature-flag lint, test determinism, the new localization gate, the `StokdWidgetKit` and `CmuxFoundation` package tests, and the full app-host suite for the new test classes.
- Failure modes: upstream branch contaminated with fork code (grep guard); gate flipped before the suites are green (ordering); a new package still absent from the CI `PACKAGES` array (1.1's AC, re-verified here since the array is easy to lose in a rebase).

**Acceptance Criteria**

- AC-4.3.a: The upstream branch is **prepared by this work item** (it does not pre-exist) and its diff is stokd-free → after creating `upstream/jsonl-tail-reader` from `origin/upstream-main` and cherry-picking only the 2.2 commit, `git diff origin/upstream-main --name-only` lists exactly `Packages/macOS/CmuxFoundation/Sources/CmuxFoundation/FileWatch/JSONLTailReader.swift` plus its test file, and `git diff origin/upstream-main | grep -ci stokd` returns 0. The verification block below creates the branch, so the command is runnable at verification time rather than assuming prior state.
- AC-4.3.b: `stokd.widgets.enabled` defaults to `true` → `grep -q 'widgets' Sources/CmuxConfig.swift` and the default-value test asserts `true`.
- AC-4.3.c: `CHANGELOG.md` contains an entry naming both widgets.
- AC-4.3.d: `docs/ghostty-fork.md` records the fork-only surface added here.
- AC-4.3.e: Every workflow-guard gate passes: `./scripts/lint-pbxproj-test-wiring.sh`, `./scripts/check-pbxproj.sh`, `python3 scripts/check-workspace-package-groups.py --check`, `python3 scripts/check-package-resolved-policy.py`, `python3 scripts/lint-feature-flags.py`, `python3 scripts/check-test-determinism.py --strict`, `python3 scripts/check-localization-coverage.py --prefix stokdWidget` → all exit 0.
- AC-4.3.f: Both package test suites pass: `swift test --package-path Packages/macOS/StokdWidgetKit` and `swift test --package-path Packages/macOS/CmuxFoundation` → exit 0.
- AC-4.3.g: The full app-host suite for this work passes with a non-zero executed-test count across all seven new test classes.
- AC-4.3.h: A tagged Debug build succeeds → `./scripts/reload.sh --tag stokd-widgets` exits 0 (with `CMUX_SKIP_ZIG_BUILD=1`, required in this environment because host zig 0.16.0 does not match the ghostty 0.15.2 pin).

