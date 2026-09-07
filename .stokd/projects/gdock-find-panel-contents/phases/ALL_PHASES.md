# Complete Phase Review

**Project:** Gdock Find Panel — Contents...
**Slug:** gdock-find-panel-contents
**Generated:** 2026-09-07T13:13:17.195395+00:00

## Included Phases

- Phase 1: Ship Find contents / filenames / replace (`phase-01-ship-find-contents-filenames-replace.md`)

---

# Phase 1: Ship Find contents / filenames / replace

**Project:** Gdock Find Panel — Contents...
**Slug:** gdock-find-panel-contents
**Review Mode:** complete

## Work Items

### 1.1: Query model and ripgrep argument builder

**Implementation Details**

- Extend `FileSearchController` / `FileSearchSnapshot` with a value-type
  query: scope (`contents` | `fileNames` | `both`), matchCase, wholeWord,
  regex, includeGlobs, excludeGlobs, useIgnoreFiles, limit
  (`all` | `open` | `changed`).
- Keep rg as the process. Contents: current `--json` match path with flags
  replacing the hardcoded `--smart-case --fixed-strings`. File names: rg
  file listing filtered by the query (literal or regex) against relative
  paths. Both: one contents search + one filename search, merged by path.
- Map flags: matchCase → `--case-sensitive` (else `--smart-case`);
  wholeWord → `--word-regexp`; regex off → `--fixed-strings`. Invalid regex
  → `.failed` with a localized message.
- Include/exclude → extra `--glob`. useIgnoreFiles off → `--no-ignore`.
  Open/Changed restrict the path arguments, not a second engine.
- Remote roots stay `.unsupported`. Empty query stays `.idle`.
- Failure modes: missing rg (existing message), non-zero rg other than 1
  (existing), invalid regex, malformed glob (skip that glob, do not hide
  everything).

**Acceptance Criteria**

- AC-1.1.a: A `FileSearchQuery` value type exists with scope, match flags,
- and filter fields and does not reference `FileExplorerStore` → import
- inspection.
- AC-1.1.b: Contents / File names / Both against the fixture tree return
- the hit kinds in VAL-FIND-001 → `FileSearchScopeTests` fail before the
- builder exists, pass after.
- AC-1.1.c: `rg --fixed-strings` is absent from the argument list when
- regex is on, and invalid regex emits `.failed` → `FileSearchMatchFlagTests`.
- AC-1.1.d: Exclude glob `DerivedData/**` drops those hits; useIgnoreFiles
- off includes a gitignored fixture file → `FileSearchFilterTests`.

### 1.2: Grouped results and line navigation

**Dependencies:** 1.1

**Implementation Details**

- Replace the flat `[FileSearchResult]` presentation in Find with a grouped
  snapshot: file header (path, NAME badge, counts) + nested content rows
  (line, column, preview, match ranges).
- Contents: file headers + nested content only. File names: file headers
  with NAME, no nested content. Both: merge as VAL-FIND-004.
- Open: content row → existing file-open path with line/column. NAME row →
  path only. Missing file → status, no crash.
- Tree/list toggle, refresh, stop, collapse-all, dismiss bind to the
  existing cancel/search APIs; they do not invent a second process.
- Rows receive immutable snapshots; no store below the table boundary.

**Acceptance Criteria**

- AC-1.2.a: Both grouping matches VAL-FIND-004 on the fixture →
- `FileSearchResultGroupingTests`.
- AC-1.2.b: Content-row open payload includes line and column; NAME-row
- open payload is path-only → `FileSearchOpenTargetTests`.
- AC-1.2.c: Result cell views compile without importing `FileExplorerStore`.

### 1.3: Replace pipeline

**Dependencies:** 1.1

**Implementation Details**

- Add a replace controller that consumes the grouped snapshot + replace
  string + scope (match / file / folder / all) + preserveCase.
- `isReplaceEnabled` is false when scope is File names.
- Preview is a list of `{path, line, before, after}` computed in memory
  before any write. Multi-file or folder/all requires confirm.
- Apply writes through the local file provider only. Record a batch undo
  snapshot. Partial failure stops, reports the file, keeps prior writes in
  the undo batch.
- Preserve-case uses identifier-style case preservation (Foo/foo/FOO), not
  locale title-case.
- Failure modes: file disappeared, file not writable, replace regex
  invalid → per-file error, no crash.

**Acceptance Criteria**

- AC-1.3.a: File names → replace disabled; Both apply does not rename →
- `FileSearchReplaceSafetyTests`.
- AC-1.3.b: Each apply scope, preview, confirm-on-multi-file, preserve-case,
- undo, and partial-write failure pass → `FileSearchReplaceApplyTests`.
- AC-1.3.c: Replace types do not import AppKit; writes go through an
- injected file writer in tests.

### 1.4: Find chrome matching the mockup

**Dependencies:** 1.2, 1.3

**Implementation Details**

- Rebuild the Find header in `FileExplorerContainerView` to match
  `mockup.png`: query field, match toggles, replace field (collapsed),
  scope segmented control always visible, Filters disclosure, results
  toolbar (refresh/stop, tree/list, collapse, dismiss).
- Default: replace row and filter rows hidden. Expanded state used for
  review/screenshots.
- At ≤240pt width, stack vertically; scope control remains fully visible.
- Accessibility ids for new controls (`FileExplorerSearchScope`,
  `FileExplorerReplaceField`, match toggles) so UITests can drive them.
- Presentation `.files` continues to hide this chrome (enforced in 1.5).

**Acceptance Criteria**

- AC-1.4.a: Scope control width > 0 at 240pt panel width → layout test.
- AC-1.4.b: Replace and Filters start collapsed → unit test on
- `isReplaceExpanded` / `isFiltersExpanded` defaults.
- AC-1.4.c: Tagged dogfood screenshot of expanded Find compared to
- `mockup.png` for control presence (scope Both, NAME badge, replace row,
- include/exclude, All/Open/Changed).

### 1.5: Isolation, catalog, localization, and wiring

**Dependencies:** 1.4

**Implementation Details**

- Guard Find-only chrome behind `presentation == .find`.
- Do not route terminal/browser Cmd+F through the new Find header.
  `findInDirectory` remains Cmd+Shift+F → Find rail.
- Add replace / toggle-regex shortcuts (VS Code-like Cmd+Option+F and
  Cmd+Alt+R are candidates) as new `KeyboardShortcutSettings.Action`
  cases, Settings-editable, documented.
- New `gdock.find*` keys in `GdockCatalogSection` for last-used scope,
  match flags, and filter expansion if persisted; first-use default
  Contents even when persisted flags exist.
- Localize every new string in `Resources/Localizable.xcstrings` and web
  schema copy in `web/messages/en.json` + `web/messages/ja.json`.
- Wire every new `cmuxTests/*.swift` file into the pbxproj.

**Acceptance Criteria**

- AC-1.5.a: Files presentation has no replace field / scope control →
- `FileExplorerFindIsolationTests`.
- AC-1.5.b: Existing find / findInDirectory routing tests still pass.
- AC-1.5.c: `gdock.find` appears in the settings catalog; no new keys
- under `app.*` / `sidebar.*`.
- AC-1.5.d: `./scripts/lint-pbxproj-test-wiring.sh` exits 0.
- AC-1.5.e: Localization audit lists every new Find string in en+ja.

