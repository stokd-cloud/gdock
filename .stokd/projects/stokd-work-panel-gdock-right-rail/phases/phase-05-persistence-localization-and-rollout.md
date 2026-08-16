# Phase 5: Persistence, localization, and rollout

**Project:** Stokd Work Panel (gdock right rail)
**Slug:** stokd-work-panel-gdock-right-rail
**Review Mode:** complete

## Work Items

### 5.1: Snapshot persistence for stokd rail membership

**Dependencies:** 3.2, 4.1

**Implementation Details**

- **Landing:** fork-only.
- Persist right-rail tool membership, order, and selected tab including `stokdWork` using **additive optional** snapshot fields only — **never** bump `SessionSnapshotSchema.currentVersion` and never add a `SessionWorkspaceLayoutSnapshot` case.
- Round-trip: seed layout → encode → decode → equal membership and selection.
- These rules are the contract the sibling left-rail PRD reuses for its sections.
- Failure modes: unknown future kind → skip; corrupt optional → fall back to the default seed once.

**Acceptance Criteria**

- AC-5.1.a: Round-trip of a Work-inclusive layout preserves membership, order, and selected tab.
- AC-5.1.b: `SessionSnapshotSchema.currentVersion` is unchanged from the pre-phase baseline (remains 1).
- AC-5.1.c: A snapshot containing an unknown stokd kind decodes with that entry skipped and no crash.
- AC-5.1.d: `./scripts/test-unit.sh -only-testing:cmuxTests/StokdWorkPanelPersistenceTests CMUX_SKIP_ZIG_BUILD=1 test` → exit 0.

### 5.2: Localization audit and dogfood gate

**Dependencies:** 1.2, 3.2, 4.1, 5.1

**Implementation Details**

- **Landing:** fork-only.
- Every new user-facing string uses `String(localized:)` with en+ja entries in `Resources/Localizable.xcstrings`, `state == translated`, and `ja != en` for non-identical natural text. Covered surfaces: tool tab title, empty state, error state, any beta-settings row added in 1.2.
- Palette/debug can open and focus Work through the same invoker path as other rail tools.
- Tagged dogfood: `CMUX_SKIP_ZIG_BUILD=1 ./scripts/reload.sh --tag stokd-work-panel` builds; with the flag on, a cold window matches §0.
- Bonsplit clean: `git -C vendor/bonsplit status --porcelain` empty; pinned SHA unchanged.

**Acceptance Criteria**

- AC-5.2.a: Every new Work string key exists in both en and ja with `state == translated`.
- AC-5.2.b: No bare English literal in new Work Swift sources' `Text(`/`Button(`/alert titles.
- AC-5.2.c: `./scripts/lint-pbxproj-test-wiring.sh` → exit 0.
- AC-5.2.d: Tagged reload compiles → exit 0 (or, where the environment cannot build the app, all suites in this PRD green with that substitution recorded in the session output).
- AC-5.2.e: `git -C vendor/bonsplit status --porcelain` empty and `git -C vendor/bonsplit rev-parse HEAD` equals the pin `48643102d6b68400069429bd43c15d7bda2b00a1`.

