# VS Code-Parity File Tree: Excludes and Git Integration

## 0. Source Context

**Derived From:** "add a setting that is enabled by default that will make the file tree act like the vs code file tree — aka respect the excludes and whatever else the vs code file editor supports. also there must be some fork or something that adds git support to the file tree, version histories etc. If not something popular we can steal from, then lets determine what the minimal supported feature set we need to handle that and scope that for the prd too."
**Feature Name:** VS Code-Parity File Tree
**PRD Owner:** Brian Stoker
**Last Updated:** 2026-07-31

### Summary

The cmux right-sidebar file explorer currently lists every directory entry, filtered only by a
single `showHiddenFiles` dotfile toggle (`Sources/FileExplorerStore.swift`). It has no notion of
`files.exclude`-style globs and no notion of `.gitignore`, so a tree rooted at a JS or Xcode
project is dominated by `node_modules/`, `DerivedData/`, `.git/`, and build output. Meanwhile
`Sources/FileExplorerSearchController.swift` already excludes those directories from ripgrep
search, so the tree and search disagree about what is in the project.

This project adds an **`explorer.vscodeCompat`-style behavior that is ON by default**: a
declarative, VS Code-compatible exclusion engine (glob-based `files.exclude` semantics plus
`.gitignore` parsing) shared by the tree, the watcher, and search — and then a **minimal but
genuinely useful git layer** on the tree: status badges and ignored-dimming on top of the
existing color-only decoration, plus per-file version history that opens revisions in the diff
viewer cmux already ships.

### Prior art surveyed (what we are stealing from, and why there is no "fork")

There is no popular *fork* of a file tree that adds git history — the capability is assembled
in mainstream editors from three separate, well-documented mechanisms, and those are our
sources:

1. **VS Code Explorer + SCM decorations (built-in).** `files.exclude` /
   `files.watcherExclude` / `search.exclude` glob maps, `explorer.excludeGitIgnore`, and the
   `FileDecorationProvider` API that the built-in Git extension uses to paint per-file badges
   (`M`, `A`, `D`, `U`, `C`, `R`), themed colors, and dimmed-ignored entries. Verified defaults
   from `microsoft/vscode` `src/vs/workbench/contrib/files/browser/files.contribution.ts`:
   `files.exclude` = `{"**/.git": true, "**/.svn": true, "**/.hg": true, "**/.DS_Store": true,
   "**/Thumbs.db": true}`; `files.watcherExclude` = `{".git/objects/**": true,
   ".git/subtree-cache/**": true, ".hg/store/**": true, "*/.git/objects/**": true,
   "*/.git/subtree-cache/**": true, "*/.hg/store/**": true}`;
   `explorer.excludeGitIgnore` = `false`; `explorer.decorations.badges` = `true`;
   `explorer.decorations.colors` = `true`; `explorer.compactFolders` = `true`;
   `explorer.fileNesting.enabled` = `false`.
2. **VS Code Timeline view** (1.44+): a per-file, provider-based history list combining git
   commits touching that file with local (non-git) edit history. This is the shape we copy for
   "version histories", because it degrades gracefully outside a repo.
3. **GitLens**: file history navigation and "open changes with previous revision". We take the
   *interaction* (pick a revision → see a diff) but not the blame/CodeLens surface, which is an
   editor feature cmux does not have.

Deliberately **out of scope** (documented in §5 so it is a decision, not an omission): inline
blame, CodeLens, commit graph, stage/unstage from the tree, merge-conflict resolution UI,
`explorer.fileNesting`, and non-git SCMs.

### Repo-grounded starting point

| Capability | Today | File |
|---|---|---|
| Directory listing + dotfile filter | `showHidden` boolean only | `Sources/FileExplorerStore.swift` |
| Hidden-files persistence | `UserDefaults` `fileExplorer.showHidden`, defaults true | `Sources/FileExplorerState.swift` |
| Git status map | `git status --porcelain=v1 -z`, local + SSH, parent-dir rollup | `Sources/GitStatusProvider.swift` |
| Git status model | `enum GitFileStatus { modified, added, deleted, renamed, untracked }` | `Sources/GitFileStatus.swift` |
| Tree decoration | name **color** only, no badge, no ignored state | `Sources/FileExplorerCellView.swift`, `Sources/FileExplorerPalette.swift` |
| Tree ↔ store wiring | `store.gitStatusByPath[node.path]` per row | `Sources/FileExplorerView.swift` |
| Directory watching | `FileWatcher` at 300 ms throttle on the root | `Sources/FileExplorerStore.swift`, `Packages/macOS/CmuxFoundation` |
| Search exclusions | hardcoded rg `--glob !…` list; rg already honors `.gitignore` | `Sources/FileExplorerSearchController.swift` |
| Git plumbing package | repo resolution, refs, index, config, watch paths | `Packages/macOS/CmuxGit` |
| Diff rendering | full diff viewer panel + `cmux diff` CLI | `Sources/Panels/DiffViewerLiveHTTPSession.swift` |
| Settings schema | `fileExplorer` object exists, only `doubleClickAction` | `web/data/cmux.schema.json` |

Two constraints fall out of that table and shape every phase below:

- **The explorer has a remote (SSH) provider.** Every exclusion decision must be computable
  from data the SSH path can also produce, or must degrade to "no filtering" rather than
  breaking remote trees.
- **`Sources/FileExplorerView.swift` rows sit under a lazy list boundary.** Per `CLAUDE.md`,
  rows may not hold store references; decoration data must arrive as immutable value snapshots.

---

## 1. Objectives & Constraints

### Objectives

- Make the default file tree show *the project*, not the build output: VS Code-compatible
  `files.exclude` globs plus `.gitignore` exclusion, ON by default, in one shared engine.
- Keep one exclusion source of truth across tree, file watcher, and search so the three
  surfaces never disagree about what is in the project.
- Give the tree the minimum git signal that makes it feel like VS Code: status **badges** and
  **dimmed ignored entries**, not just the existing name tint.
- Ship per-file **version history** that reuses the existing diff viewer rather than inventing
  a new revision UI.
- Make every new behavior configurable in `~/.config/cmux/cmux.json`, visible in Settings, and
  fully localized in both supported locales.

### Constraints

- Default-on is a behavior change for existing users: it must be a single, discoverable,
  reversible toggle, and the tree must state when entries are hidden by it.
- `Sources/FileExplorerStore.swift` and `Sources/FileExplorerView.swift` are on
  typing-latency-adjacent paths; exclusion matching and git decoration must be computed off the
  main thread and delivered as prepared snapshots.
- The snapshot-boundary rule in `CLAUDE.md` forbids passing stores into row views. Decorations
  are value types.
- The remote SSH provider must keep working; git history is local-repo-only in this project and
  must be absent (not broken) on remote roots.
- `.gitignore` parsing must handle nested ignore files, negation (`!`), directory-only
  patterns (`foo/`), anchoring (`/foo`), and `**`. Correctness here is the whole feature.
- Every user-facing string must land in `Resources/Localizable.xcstrings` (en + ja) and every
  schema description in `web/messages/en.json` and `web/messages/ja.json`.
- New tests must be wired into `cmux.xcodeproj/project.pbxproj` or they silently never run
  (`scripts/lint-pbxproj-test-wiring.sh`).

---

## 1.5 Required Toolchain

| Tool | Min Version | Install Command | Verify Command |
|------|-------------|-----------------|----------------|
| Xcode / xcodebuild | 16.0 | Mac App Store or developer.apple.com | `xcodebuild -version` |
| Swift | 6.0 | bundled with Xcode | `swift --version` |
| git | 2.39 | `xcode-select --install` | `git --version` |
| ripgrep (`rg`) | 14.0 | `brew install ripgrep` | `rg --version` |
| Python 3 | 3.11 | bundled with macOS / `brew install python` | `python3 --version` |
| Node.js (web schema/messages) | 20 | `brew install node` | `node --version` |

---

## 2. Execution Phases

## Phase 1: Exclusion Engine

**Purpose:** Must come first because it is the only phase that introduces new decision logic
with no UI. Every later phase (tree filtering, watcher, search, git-ignored dimming) consumes
this engine's API; building the UI first would mean building it against an API that does not
exist yet. This phase is pure model code in a package, unit-testable without launching the app.

### 1.1 VS Code-compatible glob matcher

**Implementation Details**

- New module `Packages/macOS/CmuxFileFilter` (Shared-free, macOS group; consumers are
  `Sources/FileExplorer*` and, later, the search controller).
- Implement `GlobPattern` supporting the VS Code glob subset: `/` segment separator, `*`
  (zero-or-more within a segment), `?` (one char within a segment), `**` (any number of
  segments including none), `{a,b}` grouping, `[a-z]` ranges.
- Implement the two `files.exclude` value forms: `true`/`false`, and the sibling clause
  `{"when": "$(basename).ts"}` which matches only if a sibling file substituting `$(basename)`
  exists. The sibling form requires the matcher to accept an injected sibling-name set so it
  stays pure and testable.
- Matching is performed against the workspace-root-relative POSIX path. Per VS Code semantics,
  a bare `example` matches only at the root; `**/example` matches at any depth.
- Failure modes: malformed pattern → the pattern is skipped and a diagnostic recorded, never a
  crash and never a "hide everything" outcome; unbalanced `{`/`[` is malformed.

**Acceptance Criteria**

- AC-1.1.a: `GlobPattern` is a value type with no reference to `FileExplorerStore` or any
  `ObservableObject` → confirmed by inspection of the new package's imports.
- AC-1.1.b: The five VS Code default `files.exclude` keys (`**/.git`, `**/.svn`, `**/.hg`,
  `**/.DS_Store`, `**/Thumbs.db`) each match their target at depth 0 and at depth 3 → asserted
  by unit test.
- AC-1.1.c: A malformed pattern (`"{unclosed"`) is reported as malformed and matches nothing →
  asserted by unit test.
- AC-1.1.d: `swift test --package-path Packages/macOS/CmuxFileFilter` → exit 0.

**Acceptance Tests**

- Test-1.1.a: Unit — `GlobPatternTests` covers `*`, `?`, `**`, `{}`, `[]`, root-anchoring vs
  `**/` prefix, and case sensitivity.
- Test-1.1.b: Unit — `GlobSiblingClauseTests` covers the `{"when": "$(basename).ts"}` form,
  including the negative case where no sibling exists.
- Test-1.1.c: Unit — `GlobMalformedPatternTests` asserts malformed patterns are inert.

**Verification Commands**

```bash
swift test --package-path Packages/macOS/CmuxFileFilter --filter GlobPattern
swift test --package-path Packages/macOS/CmuxFileFilter --filter GlobSiblingClause
swift test --package-path Packages/macOS/CmuxFileFilter --filter GlobMalformedPattern
```

### 1.2 Gitignore parser and hierarchical matcher

**Implementation Details**

- `GitignoreRuleSet` in `Packages/macOS/CmuxFileFilter`, parsing one `.gitignore` file into
  ordered rules. Must implement, per gitignore(5): comments (`#`), blank-line skip, trailing
  whitespace trimming unless escaped, negation (`!`), directory-only (`foo/`), anchored
  (`/foo`, or any pattern containing a non-trailing `/`), unanchored basename patterns, `**`
  leading/trailing/middle, and `\` escapes.
- `GitignoreStack` composes rule sets found from the repo root down to the directory being
  listed, plus `.git/info/exclude` and the user's `core.excludesFile` if configured. Last
  matching rule wins, and a deeper file's rule outranks a shallower one.
- Ordering rule that matters and is easy to get wrong: a directory excluded by a parent rule is
  not re-included by a negation inside it unless the directory itself is re-included first.
  This is asserted explicitly.
- Repo root resolution reuses `Packages/macOS/CmuxGit` (`GitMetadataService+RepositoryResolution.swift`)
  rather than shelling out again.
- Failure modes: unreadable `.gitignore` → treated as empty, recorded as a diagnostic; no repo
  → empty stack, everything visible.

**Acceptance Criteria**

- AC-1.2.a: A rule set built from a fixture `.gitignore` classifies each fixture path as
  ignored/not-ignored matching `git check-ignore` output for the same fixture → asserted by
  unit test using a checked-in fixture repo.
- AC-1.2.b: Negation inside an excluded directory does **not** re-include, and negation after
  re-including the directory **does** → asserted by unit test.
- AC-1.2.c: Nested `.gitignore` in a subdirectory overrides the root file for paths under it →
  asserted by unit test.
- AC-1.2.d: `swift test --package-path Packages/macOS/CmuxFileFilter --filter Gitignore` → exit 0.

**Acceptance Tests**

- Test-1.2.a: Unit — `GitignoreParserTests` (syntax forms).
- Test-1.2.b: Unit — `GitignoreStackTests` (nesting, precedence, negation ordering).
- Test-1.2.c: Integration — `GitignoreParityTests` builds a temp repo, runs the real
  `git check-ignore -v --stdin` over a path corpus, and asserts our verdict matches git's for
  every path. This is the parity guarantee; a mismatch fails the build.

**Verification Commands**

```bash
swift test --package-path Packages/macOS/CmuxFileFilter --filter Gitignore
swift test --package-path Packages/macOS/CmuxFileFilter --filter GitignoreParity
```

### 1.3 Unified `FileVisibilityPolicy` façade

**Implementation Details**

- `FileVisibilityPolicy` is the single API the rest of the app calls:
  `func visibility(of path: String, isDirectory: Bool, siblings: Set<String>) -> FileVisibility`
  returning `.visible`, `.hiddenByExcludeGlob(pattern:)`, `.hiddenByGitignore(rule:)`, or
  `.ignoredButShown(rule:)`.
- Composes, in order: dotfile rule (existing `showHiddenFiles`), `files.exclude` globs,
  `.gitignore` stack. The `.ignoredButShown` case exists so Phase 3 can dim rather than hide
  when the user turns exclusion off but leaves decorations on.
- Policy construction is cheap and snapshot-based: a `FileVisibilityPolicySnapshot` value is
  built off-main from settings + parsed ignore files, then handed to the store. No lazily
  re-reading `.gitignore` during a row render.
- Exposes `diagnostics: [PolicyDiagnostic]` (malformed patterns, unreadable ignore files) for
  the Phase 4 Settings surface.
- Failure modes: an empty/failed snapshot must fall back to "show everything except dotfiles",
  i.e. today's behavior — never to an empty tree.

**Acceptance Criteria**

- AC-1.3.a: `FileVisibilityPolicy` and `FileVisibilityPolicySnapshot` are `Sendable` value
  types with no `import SwiftUI` and no `ObservableObject` reference → confirmed by inspection.
- AC-1.3.b: With an all-defaults snapshot, `.git`, `.DS_Store`, and `Thumbs.db` resolve to
  `.hiddenByExcludeGlob`, and an ordinary source file resolves to `.visible` → asserted by test.
- AC-1.3.c: An intentionally-failed snapshot resolves every non-dotfile path to `.visible`
  (fail-open) → asserted by test.
- AC-1.3.d: `swift test --package-path Packages/macOS/CmuxFileFilter --filter FileVisibilityPolicy` → exit 0.

**Acceptance Tests**

- Test-1.3.a: Unit — `FileVisibilityPolicyTests` covers precedence order across the three
  layers and each returned case.
- Test-1.3.b: Unit — `FileVisibilityPolicyFailOpenTests` asserts the degraded path.
- Test-1.3.c: Performance — `FileVisibilityPolicyPerfTests` classifies 50,000 synthetic paths
  and asserts total wall time under 250 ms, so a large tree cannot stall the store.

**Verification Commands**

```bash
swift test --package-path Packages/macOS/CmuxFileFilter --filter FileVisibilityPolicy
swift test --package-path Packages/macOS/CmuxFileFilter --filter FileVisibilityPolicyPerf
python3 scripts/check-workspace-package-groups.py --check
python3 scripts/check-package-resolved-policy.py
```

---

## Phase 2: Wire the Tree, the Watcher, and Search to the Policy

**Purpose:** Cannot start until Phase 1 exists, because this phase has no logic of its own — it
replaces three independent, divergent filters (`showHidden` in the store, the unfiltered
`FileWatcher`, and the hardcoded rg glob list) with calls into the one engine. Doing this before
the engine exists would mean writing the same filtering twice.

### 2.1 Store consumes the policy; default-on setting introduced

**Implementation Details**

- `Sources/FileExplorerStore.swift`: `listDirectory(path:showHidden:)` gains the policy
  snapshot. Entries resolving to a hidden case are dropped from the returned node list; entries
  resolving to `.ignoredButShown` are returned with an `isIgnored` flag on the node model.
- The local provider filters in-process. The SSH provider filters the `ls` output using the same
  policy snapshot, with the ignore stack fetched over the existing SSH channel in the same
  round-trip pattern `GitStatusProvider.fetchStatusSSH` already uses; if the fetch fails, the
  remote tree falls back to unfiltered (fail-open), matching AC-1.3.c.
- New setting `fileExplorer.vscodeCompatibleExcludes`, **default `true`**, persisted alongside
  the existing `fileExplorer.showHidden` key in `Sources/FileExplorerState.swift`. When false,
  behavior is byte-for-byte today's behavior.
- New settings `fileExplorer.filesExclude` (glob map, defaults to the five VS Code defaults) and
  `fileExplorer.excludeGitIgnore` (bool). Note the deliberate divergence from VS Code:
  `explorer.excludeGitIgnore` defaults `false` upstream; we default it **`true`**, because the
  stated goal is that the tree shows the project. This is called out in §5.
- Policy snapshot rebuild is triggered by settings change and by the existing `FileWatcher`
  seeing a `.gitignore` write; rebuild happens off-main and is applied in one `@Published`
  assignment to avoid mid-render churn.

**Acceptance Criteria**

- AC-2.1.a: With the setting at its default in a repo whose `.gitignore` contains
  `node_modules/`, a `node_modules` directory at the root is absent from the store's node list →
  asserted by test.
- AC-2.1.b: With `fileExplorer.vscodeCompatibleExcludes` set to `false`, the store's node list
  for the same fixture is identical to the pre-change list → asserted by a golden-list test.
- AC-2.1.c: `.git` is absent from the tree at default settings even with `showHiddenFiles` true
  → asserted by test.
- AC-2.1.d: `xcodebuild test -project cmux.xcodeproj -scheme cmux -destination 'platform=macOS' -derivedDataPath /tmp/cmux-vscode-tree -only-testing:cmuxTests/FileExplorerVisibilityTests`
  → exit 0 and reports a nonzero executed-test count.

**Acceptance Tests**

- Test-2.1.a: Unit — `FileExplorerVisibilityTests` (new, wired into `project.pbxproj`) drives
  the store against a temp fixture repo and asserts filtered vs unfiltered node lists.
- Test-2.1.b: Regression — the setting-off path is asserted equal to a checked-in golden list so
  the escape hatch cannot silently rot.
- Test-2.1.c: Unit — SSH provider filtering asserted against a recorded `ls`+ignore transcript.

**Verification Commands**

```bash
./scripts/lint-pbxproj-test-wiring.sh
xcodebuild test -project cmux.xcodeproj -scheme cmux -configuration Debug \
  -destination 'platform=macOS' -derivedDataPath /tmp/cmux-vscode-tree \
  -only-testing:cmuxTests/FileExplorerVisibilityTests
```

### 2.2 Watcher and search adopt the same policy

**Implementation Details**

- `Sources/FileExplorerStore.swift`: the `FileWatcher` registration honors a
  `watcherExclude` set seeded with the VS Code defaults (`.git/objects/**`,
  `.git/subtree-cache/**`, `.hg/store/**`, and their `*/`-prefixed forms), so a rebase or a
  large `git gc` cannot storm the tree with refresh events.
- `Sources/FileExplorerSearchController.swift`: the hardcoded `excludedSearchGlobs` array is
  replaced by globs derived from the policy plus a new `fileExplorer.searchExclude` setting.
  ripgrep already honors `.gitignore`, so the gitignore layer is expressed by *not* passing
  `--no-ignore`; only the `files.exclude`/`search.exclude` layer is passed as `--glob !…`.
- Failure mode: if policy derivation fails, the search controller falls back to today's
  hardcoded list rather than searching with no exclusions.

**Acceptance Criteria**

- AC-2.2.a: The literal `excludedSearchGlobs` hardcoded array no longer exists in
  `Sources/FileExplorerSearchController.swift` as the sole source of exclusions → confirmed by
  `rg` returning no unconditional use of it in the argument builder.
- AC-2.2.b: A search in a fixture repo does not return hits from a `.gitignore`d directory,
  and does return them when `fileExplorer.excludeGitIgnore` is false → asserted by test.
- AC-2.2.c: Writing 500 files under `.git/objects/` in a fixture repo produces zero tree
  refresh callbacks → asserted by test.
- AC-2.2.d: `xcodebuild test … -only-testing:cmuxTests/FileExplorerSearchExclusionTests` → exit 0.

**Acceptance Tests**

- Test-2.2.a: Integration — `FileExplorerSearchExclusionTests` runs the real search controller
  against a temp fixture repo.
- Test-2.2.b: Regression — `FileExplorerWatcherExcludeTests` asserts the `.git/objects` storm is
  suppressed.

**Verification Commands**

```bash
./scripts/lint-pbxproj-test-wiring.sh
xcodebuild test -project cmux.xcodeproj -scheme cmux -configuration Debug \
  -destination 'platform=macOS' -derivedDataPath /tmp/cmux-vscode-tree \
  -only-testing:cmuxTests/FileExplorerSearchExclusionTests \
  -only-testing:cmuxTests/FileExplorerWatcherExcludeTests
```

---

## Phase 3: Minimal Git Layer — Decorations and Version History

**Purpose:** Depends on Phase 2 because ignored-dimming requires the policy's
`.ignoredButShown` case and because git decoration must be applied to the *filtered* node list,
not the raw listing. Attempting this earlier would decorate rows that Phase 2 then removes.
This phase is where the "minimal supported feature set" for git is actually defined and built.

### 3.1 Decoration model: badges, colors, ignored dimming

**Implementation Details**

- Extend `Sources/GitFileStatus.swift` with `conflicted` and `ignored`, and add
  `stagedChange`/`unstagedChange` so a file can carry both index and worktree state (VS Code
  shows the more significant one and tooltips both). `Sources/GitStatusProvider.swift` already
  parses both porcelain columns; today it collapses them.
- New value type `FileTreeDecoration { badge: Character?, colorRole: GitColorRole, isDimmed: Bool,
  tooltip: String }`, computed off-main in the store and stored in
  `decorationsByPath: [String: FileTreeDecoration]`. Rows receive the decoration **by value**,
  satisfying the `CLAUDE.md` snapshot-boundary rule — `Sources/FileExplorerView.swift` continues
  to pass a precomputed `let` into `Sources/FileExplorerCellView.swift`.
- Badge glyphs follow VS Code: `M` modified, `A` added, `D` deleted, `R` renamed, `U` untracked,
  `C` conflicted. Colors come from `Sources/FileExplorerPalette.swift`, extended with conflict
  and ignored roles.
- Ignored entries (only reachable when `excludeGitIgnore` is off) render dimmed rather than
  hidden. Directory rollup keeps the existing `markParentDirectories` behavior in
  `Sources/GitStatusProvider.swift`.
- New settings mirroring VS Code: `fileExplorer.decorations.badges` (default `true`),
  `fileExplorer.decorations.colors` (default `true`), `fileExplorer.gitDecorations.enabled`
  (default `true`).
- Failure modes: not a repo, or `git status` fails → empty decoration map, tree renders exactly
  as it does with git absent. No error banner for the common "not a repo" case.

**Acceptance Criteria**

- AC-3.1.a: `Sources/FileExplorerCellView.swift` receives `FileTreeDecoration` as a value and
  holds no store/`ObservableObject` reference → confirmed by inspection against the
  snapshot-boundary rule.
- AC-3.1.b: For a fixture repo with one file in each of modified/added/deleted/renamed/
  untracked/conflicted states, the computed badge characters are exactly `M A D R U C` →
  asserted by test.
- AC-3.1.c: With `fileExplorer.decorations.badges` false, every computed decoration has a nil
  badge while colors are unchanged → asserted by test.
- AC-3.1.d: A file that is both index-modified and worktree-modified produces a tooltip naming
  both states → asserted by test.
- AC-3.1.e: `xcodebuild test … -only-testing:cmuxTests/FileExplorerGitDecorationTests` → exit 0.

**Acceptance Tests**

- Test-3.1.a: Unit — `FileExplorerGitDecorationTests` (new, pbxproj-wired) builds a temp repo in
  each state and asserts badge/color/dim/tooltip.
- Test-3.1.b: Regression — extends `cmuxTests/FileExplorerGitStatusProviderTests.swift` to cover
  the newly-preserved index/worktree split and the conflict (`UU`, `AA`, `DD`) porcelain codes.

**Verification Commands**

```bash
./scripts/lint-pbxproj-test-wiring.sh
xcodebuild test -project cmux.xcodeproj -scheme cmux -configuration Debug \
  -destination 'platform=macOS' -derivedDataPath /tmp/cmux-vscode-tree \
  -only-testing:cmuxTests/FileExplorerGitDecorationTests \
  -only-testing:cmuxTests/FileExplorerGitStatusProviderTests
```

### 3.2 Per-file version history (Timeline-shaped, minimal)

**Implementation Details**

- **Minimal supported feature set, chosen deliberately.** A file's context menu gains
  **"File History"**, which opens a revision list panel containing, per entry: short SHA,
  subject, author, relative date. Backed by
  `git log --follow --format=%H%x00%an%x00%aI%x00%s -n <limit> -- <path>` run through the
  non-locking (`GIT_OPTIONAL_LOCKS=0`) pattern already established in
  `Sources/GitStatusProvider.swift`.
- Selecting a revision opens a diff of `<sha>^:<path>` against `<sha>:<path>` in the **existing**
  diff viewer (`Sources/Panels/DiffViewerLiveHTTPSession.swift`), reusing the `cmux diff`
  rendering path. No new diff renderer is written.
- Two additional entries at the top of the list when applicable: **Working Tree vs HEAD** and
  **Staged vs HEAD**, so the common case (what did I just change) is one click.
- Explicitly **not** in the minimal set, and each is a §5 decision: inline blame, CodeLens,
  commit graph, restore-this-revision, stage/unstage from the tree, local (non-git) edit
  history, and history for directories.
- History is **local-repo only**. On an SSH root, or outside a repo, the menu item is absent —
  not present-and-failing.
- History is fetched lazily on menu invocation with a `-n 100` cap and a "Load more" affordance;
  it is never fetched during tree listing, so it cannot affect scroll or typing latency.
- Failure modes: `git log` non-zero exit → the panel shows a localized error row and the tree is
  untouched; a path with no history (untracked) → localized empty state.

**Acceptance Criteria**

- AC-3.2.a: For a fixture repo with three commits touching a file, the history model returns
  exactly three entries in reverse-chronological order with correct SHAs → asserted by test.
- AC-3.2.b: A file renamed in history returns entries from before the rename (`--follow`
  behavior) → asserted by test.
- AC-3.2.c: On a non-repo directory and on an SSH-backed root, the history action is reported
  unavailable rather than producing an error → asserted by test.
- AC-3.2.d: Selecting a revision produces a diff request whose left/right refs are
  `<sha>^:<path>` and `<sha>:<path>` → asserted by test against a recording diff-viewer double.
- AC-3.2.e: `xcodebuild test … -only-testing:cmuxTests/FileExplorerHistoryTests` → exit 0.

**Acceptance Tests**

- Test-3.2.a: Integration — `FileExplorerHistoryTests` (new, pbxproj-wired) builds a temp repo
  with commits and a rename, and asserts the parsed model.
- Test-3.2.b: Unit — availability matrix (local repo / local non-repo / SSH root).
- Test-3.2.c: Integration — revision selection asserted against a recording diff-viewer double.

**Verification Commands**

```bash
./scripts/lint-pbxproj-test-wiring.sh
xcodebuild test -project cmux.xcodeproj -scheme cmux -configuration Debug \
  -destination 'platform=macOS' -derivedDataPath /tmp/cmux-vscode-tree \
  -only-testing:cmuxTests/FileExplorerHistoryTests
```

---

## Phase 4: Surfacing, Localization, Documentation, and Rollout

**Purpose:** Must be last because it documents and exposes the settings and menu items that
Phases 2 and 3 introduce; their final key names and default values are not known until those
phases land. Per `CLAUDE.md` this phase also carries the mandatory localization audit, which can
only be run once the full set of user-facing strings exists.

### 4.1 Settings, schema, shortcuts, and command palette

**Implementation Details**

- Add every new key to `web/data/cmux.schema.json` under the existing `fileExplorer` object
  (`additionalProperties: false`, so omission is a hard failure):
  `vscodeCompatibleExcludes`, `filesExclude`, `excludeGitIgnore`, `searchExclude`,
  `watcherExclude`, `decorations.badges`, `decorations.colors`, `gitDecorations.enabled`,
  `history.maxEntries`.
- Add matching Settings UI rows (`Packages/macOS/CmuxSettingsUI`) including a diagnostics
  disclosure that surfaces `FileVisibilityPolicy.diagnostics` (malformed globs, unreadable
  ignore files), so a user who mistypes a glob is told rather than left with a wrong tree.
- Add a **"Toggle VS Code-Compatible Excludes"** action reachable from the command palette and
  the file explorer header (`Sources/FileExplorerHeaderView.swift`), plus a
  `KeyboardShortcutSettings` entry per the repo shortcut policy. One shared action path per the
  shared-behavior rule — the header button, the palette entry, and the settings toggle all call
  the same mutation.
- Add "File History" to the file explorer context menu and the command palette through that same
  shared action path.

**Acceptance Criteria**

- AC-4.1.a: Every new setting appears in `web/data/cmux.schema.json` with a `description` and a
  `descriptionKey` → asserted by a schema test.
- AC-4.1.b: The toggle is reachable from Settings, the command palette, and the explorer header,
  and all three route through one action → confirmed by inspection plus a test asserting a
  single mutation entry point.
- AC-4.1.c: The new shortcut is present in `KeyboardShortcutSettings` and round-trips through
  `~/.config/cmux/cmux.json` → asserted by test.
- AC-4.1.d: `node -e "JSON.parse(require('fs').readFileSync('web/data/cmux.schema.json','utf8'))"`
  → exit 0.

**Acceptance Tests**

- Test-4.1.a: Unit — schema completeness test asserting each new key has description +
  descriptionKey.
- Test-4.1.b: Unit — extends `cmuxTests/FileExplorerShortcutSettingsTests.swift` for the new
  shortcut.
- Test-4.1.c: Integration — command palette / header / settings all dispatch the same action.

**Verification Commands**

```bash
node -e "JSON.parse(require('fs').readFileSync('web/data/cmux.schema.json','utf8'))"
xcodebuild test -project cmux.xcodeproj -scheme cmux -configuration Debug \
  -destination 'platform=macOS' -derivedDataPath /tmp/cmux-vscode-tree \
  -only-testing:cmuxTests/FileExplorerShortcutSettingsTests
```

### 4.2 Localization audit and documentation

**Implementation Details**

- Every new user-facing string — settings labels and help text, header/palette action titles,
  context menu items, decoration tooltips, history panel empty/error states, diagnostics rows —
  added to `Resources/Localizable.xcstrings` with **both** `en` and `ja` translations. English
  `defaultValue` alone does not satisfy this.
- Every new `descriptionKey` added to **both** `web/messages/en.json` and
  `web/messages/ja.json`.
- Documentation: update the file explorer and configuration docs under `docs/` and the web docs
  to describe the default-on behavior, the VS Code compatibility surface and where it
  deliberately diverges (`excludeGitIgnore` default), and the git feature set with its explicit
  non-goals.
- Enumerate the changed user-facing surfaces in the handoff and state what audit was run, per
  `CLAUDE.md`.

**Acceptance Criteria**

- AC-4.2.a: Every message key added to `web/messages/en.json` in this project also exists in
  `web/messages/ja.json` → asserted by a key-parity script.
- AC-4.2.b: Every string catalog key added in this project has a non-empty `ja` translation
  state that is not `new`/`needs_review` → asserted by a parity script over
  `Resources/Localizable.xcstrings`.
- AC-4.2.c: No bare English string literal is introduced in a SwiftUI `Text(`/`Button(` in the
  changed files → asserted by an `rg` sweep over the diff.
- AC-4.2.d: The key-parity command below exits 0.

**Acceptance Tests**

- Test-4.2.a: Integration — locale key-parity check across `web/messages/*.json`.
- Test-4.2.b: Integration — `Localizable.xcstrings` en/ja parity for keys touched by this
  project.
- Test-4.2.c: Regression — `rg` sweep for bare literals in changed Swift files.

**Verification Commands**

```bash
python3 - <<'PY'
import json,sys
en=json.load(open('web/messages/en.json')); ja=json.load(open('web/messages/ja.json'))
def keys(d,p=''):
    for k,v in d.items():
        yield from keys(v,f'{p}{k}.') if isinstance(v,dict) else [f'{p}{k}']
missing=sorted(set(keys(en))-set(keys(ja)))
print('missing ja keys:',missing); sys.exit(1 if missing else 0)
PY
python3 - <<'PY'
import json,sys
c=json.load(open('Resources/Localizable.xcstrings'))
bad=[k for k,v in c['strings'].items()
     if 'ja' not in v.get('localizations',{})
     or v['localizations']['ja'].get('stringUnit',{}).get('state') in (None,'new','needs_review')]
print('untranslated ja keys:',len(bad)); sys.exit(1 if bad else 0)
PY
```

---

## 3. Completion Criteria

The project is complete when all of the following hold:

- The file explorer, at default settings on a fresh install, hides `.git`, `.DS_Store`,
  `Thumbs.db`, and every `.gitignore`d path, in a repo and on a non-repo directory alike.
- `fileExplorer.vscodeCompatibleExcludes = false` restores today's behavior exactly, proven by
  the golden-list regression test (AC-2.1.b).
- The tree, the file watcher, and ripgrep search all derive their exclusions from
  `FileVisibilityPolicy`; no surface retains an independent hardcoded exclusion list.
- `GitignoreParityTests` passes against real `git check-ignore` for the full fixture corpus.
- Tree rows show VS Code-equivalent badges and colors for modified/added/deleted/renamed/
  untracked/conflicted, with ignored entries dimmed when shown.
- "File History" lists commits for a file and opens a selected revision in the existing diff
  viewer; it is absent (not broken) outside a local repo.
- Every new setting is in `cmux.schema.json`, visible in Settings, and settable from
  `~/.config/cmux/cmux.json`; the toggle and File History are each reachable from all their
  intended entrypoints through one shared action path.
- Localization parity holds for `en` and `ja` across `Localizable.xcstrings` and
  `web/messages/*.json`, and docs describe the default-on behavior and its divergences.
- Every phase's Verification Commands exit 0 on the pushed HEAD, and
  `./scripts/lint-pbxproj-test-wiring.sh` passes so no new test is silently unwired.

## 4. Rollout & Validation

### Rollout Strategy

- Ship behind `fileExplorer.vscodeCompatibleExcludes`, default **on**, with the escape hatch in
  the explorer header (one click, no Settings trip) — this is the rollback for the riskiest
  behavior change in the project.
- Land Phase 1 and Phase 2 in separate PRs; Phase 1 is pure additive package code and can merge
  with zero user-visible change, so any regression in Phase 2 is bisectable to the wiring, not
  the engine.
- Git decorations (Phase 3.1) ship default-on because they are additive to an existing
  color-only decoration. **File History (Phase 3.2) ships default-on but is inert outside a
  local repo**, which is the majority-safe posture.
- Per the repo regression policy, each behavioral fix in this project uses the two-commit
  red/green structure so CI demonstrates the test catches the bug.
- Rollback triggers: a report of a *tracked* project file missing from the tree, a tree refresh
  loop, or measurable typing latency regression on the explorer-visible path. Any of these →
  flip the default to `false` in a patch release while the parity corpus is extended.

### Post-Launch Validation

- Watch for issues describing "my file disappeared from the tree" — these indicate a gitignore
  parity gap and each one becomes a new case in `GitignoreParityTests`.
- Confirm on a large repo (this one, with `node_modules/`, `DerivedData/`, and the `ghostty`
  submodule) that initial listing latency does not regress and that the watcher does not storm
  during `git gc` or a rebase.
- Confirm the SSH explorer still lists remote trees, with filtering applied when the ignore
  fetch succeeds and unfiltered when it fails.
- Track how often users disable the toggle; sustained disabling means the defaults are wrong,
  not that the feature is.

## 5. Open Questions

- **We default `excludeGitIgnore` to `true`; VS Code defaults it to `false`.** This is an
  intentional divergence chosen to satisfy the stated goal ("show the project"), and it is the
  single most user-visible decision in this PRD. Flagging it explicitly for a keep/revert call
  before Phase 2 merges.
- Should `files.exclude` be workspace-scoped (per cmux workspace root) in addition to global?
  VS Code supports both; this PRD scopes only global, and adding per-workspace overrides later
  is additive to `FileVisibilityPolicySnapshot`.
- Should we read a project's existing `.vscode/settings.json` for `files.exclude` /
  `search.exclude` and honor it? It would be genuine parity and costs little, but it means cmux
  silently obeys a file it does not own. Not scoped here.
- Local (non-git) file history — the other half of VS Code's Timeline — is excluded from the
  minimal set. It requires a shadow-copy store with its own retention and disk-budget policy,
  which is a project of its own.
- `explorer.compactFolders` (VS Code default `true`) and `explorer.fileNesting` are real parity
  gaps not scoped here. Compact folders in particular is cheap and highly visible; it is a
  candidate follow-up task rather than a phase in this project.
- The Phase 1.2 parity test shells out to real `git check-ignore`. If that proves slow on CI,
  the corpus may need sharding — decide when the first CI timing is observed, not before.
