# Phase 2: Default seed layout

**Project:** Stokd Rail Panels — Left Rail Slice
**Slug:** stokd-rail-panels-first-slice
**Review Mode:** complete

## Work Items

### 2.1: Seed the left-rail stack

**Implementation Details**

- **Landing:** fork-only.
- Extend `SidebarDockSeeding` (or sibling) so when the gate is on and the stokd seed generation is not yet applied:
  - **Left:** keep/ensure the workspaces section at top; create sections Global Config, Worktrees, Usage in that vertical order (Usage bottom).
- Reuse the prerequisite PRD's idempotent marker (seed generation int / `stokdPanelsSeedApplied`) — advance it rather than adding a second marker — so re-open does not re-insert duplicates or reset user layout.
- Do not touch right-rail seeding; the Work tab remains owned by the prerequisite PRD.
- Flag-off: seed path no-ops for stokd kinds.
- Failure modes: partial seed failure leaves non-stokd rails intact; log and continue.

**Acceptance Criteria**

- AC-2.1.a: Unit seed of an empty registry with the flag on produces left order Workspaces → Global Config → Worktrees → Usage.
- AC-2.1.b: Second seed call does not duplicate stokd sections.
- AC-2.1.c: Flag off → seed does not introduce stokd kinds.
- AC-2.1.d: Seeding leaves the right-rail tool tab strip byte-identical to its pre-seed state.
- AC-2.1.e: `./scripts/test-unit.sh -only-testing:cmuxTests/StokdRailPanelSeedTests CMUX_SKIP_ZIG_BUILD=1 test` → exit 0.
