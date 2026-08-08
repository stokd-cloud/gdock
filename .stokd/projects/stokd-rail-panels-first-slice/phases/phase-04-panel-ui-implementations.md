# Phase 4: Panel UI implementations

**Project:** Stokd Rail Panels — Left Rail Slice
**Slug:** stokd-rail-panels-first-slice
**Review Mode:** complete

## Work Items

### 4.1: Worktrees panel (left section)

**Implementation Details**

- **Landing:** fork-only.
- Implement Worktrees section: inventory from Git/local worktree discovery for the active repo (document source of truth in code; do not hard-depend only on incomplete CLI if git is authoritative).
- Rows: path, branch, dirty; open/reveal minimum; land/review actions optional for this slice if unsafe.
- Failure modes: non-git cwd → empty + explanation.

**Acceptance Criteria**

- AC-4.1.a: Fixture repo produces expected worktree rows in unit tests.
- AC-4.1.b: Non-git path yields empty state without crash.
- AC-4.1.c: `./scripts/test-unit.sh -only-testing:cmuxTests/StokdWorktreesPanelTests CMUX_SKIP_ZIG_BUILD=1 test` → exit 0.

### 4.2: Global Config panel (left section)

**Implementation Details**

- **Landing:** fork-only.
- Schema-driven settings UI from CLI schema descriptor; scope from active window focused workspace cwd.
- Show layered provenance when cheap; writes only through CLI writer with explicit scope (default workspace; global requires deliberate switch).
- Failure modes: CLI missing → “stokd CLI not found” state; unknown field types render read-only.

**Acceptance Criteria**

- AC-4.2.a: Schema fixture renders ≥1 field group.
- AC-4.2.b: Write path unit test asserts `stokd config set` argv, never FileManager write to yaml.
- AC-4.2.c: `./scripts/test-unit.sh -only-testing:cmuxTests/StokdGlobalConfigPanelTests CMUX_SKIP_ZIG_BUILD=1 test` → exit 0.

### 4.3: Usage panel (left section, bottom)

**Implementation Details**

- **Landing:** fork-only.
- Per provider → per model token/cost breakdown for supported timespans.
- Prefer file-watch/incremental ingest; include reasoning tokens and restart-safe provider dedupe when data model supports it; mark unmeasured cache columns unavailable rather than fake zeros.
- Failure modes: no stores → configured-but-unobserved rows or empty state, not crash.

**Acceptance Criteria**

- AC-4.3.a: Fixture usage records aggregate into provider/model rows.
- AC-4.3.b: Missing cache columns do not display as measured zero when unavailable.
- AC-4.3.c: `./scripts/test-unit.sh -only-testing:cmuxTests/StokdUsagePanelTests CMUX_SKIP_ZIG_BUILD=1 test` → exit 0.
