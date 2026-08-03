# Phase 5: Persistence, localization, and rollout

**Project:** Stokd Rail Panels — First Slice
**Slug:** stokd-rail-panels-first-slice
**Review Mode:** complete

## Work Items

### 5.1: Snapshot persistence for stokd rail membership

**Implementation Details**

- **Landing:** fork-only.
- Persist section membership, order, collapse, extents, and right-rail tab selection including stokd kinds using **additive optional** snapshot fields only — **never** bump `SessionSnapshotSchema.currentVersion` and never add a `SessionWorkspaceLayoutSnapshot` case.
- Round-trip unit test: seed layout → encode → decode → equal membership.
- Failure modes: unknown future kind → skip; corrupt optional → default seed once.

**Acceptance Criteria**

- AC-5.1.a: Round-trip unit test exit 0 for stokd-inclusive layout.
- AC-5.1.b: `rg` shows no increment of `SessionSnapshotSchema.currentVersion` in the change set relative to pre-phase baseline (version remains 1).
- AC-5.1.c: `./scripts/test-unit.sh -only-testing:cmuxTests/StokdRailPanelPersistenceTests CMUX_SKIP_ZIG_BUILD=1 test` → exit 0.

### 5.2: Localization audit and dogfood gate

**Implementation Details**

- **Landing:** fork-only.
- Every new user-facing string uses `String(localized:)` with en+ja entries `state == translated` and `ja != en` for non-identical natural text.
- Actor wiring: palette/debug can open/focus each stokd panel via the same invoker path as other rail tools.
- Tagged dogfood: `CMUX_SKIP_ZIG_BUILD=1 ./scripts/reload.sh --tag stokd-rail-panels` builds; with flag on, cold window matches §0 layout.
- Bonsplit clean: `git -C vendor/bonsplit status --porcelain` empty; pinned SHA unchanged.

**Acceptance Criteria**

- AC-5.2.a: Localization keys for stokd panel titles exist in en and ja.
- AC-5.2.b: `./scripts/lint-pbxproj-test-wiring.sh` → exit 0.
- AC-5.2.c: Tagged reload compiles (or unit suites above all green if CI skips full app) → exit 0.
- AC-5.2.d: `git -C vendor/bonsplit rev-parse HEAD` equals pin `48643102d6b68400069429bd43c15d7bda2b00a1` (or current PRD pin if rail PRD updates it — do not change bonsplit in this project).

