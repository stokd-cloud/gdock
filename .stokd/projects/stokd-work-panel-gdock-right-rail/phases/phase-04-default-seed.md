# Phase 4: Default seed

**Project:** Stokd Work Panel (gdock right rail)
**Slug:** stokd-work-panel-gdock-right-rail
**Review Mode:** complete

## Work Items

### 4.1: Seed Work into the right-rail tool tab strip

**Dependencies:** 1.2, 3.2

**Implementation Details**

- **Landing:** fork-only.
- Extend `SidebarDockSeeding` (or sibling) so that when the gate is on and the stokd seed generation has not been applied, the right rail's Tools section includes Work as a tab alongside Files, Find, Vault — order Files, Find, Vault, Work unless the user has already customized the order.
- Idempotent marker (seed generation int / `stokdPanelsSeedApplied`) shared with the sibling left-rail PRD so re-open never re-inserts duplicates or resets user layout.
- Flag-off: the seed path no-ops for stokd kinds.
- Left rail is not modified by this PRD's seed.
- Failure modes: partial seed failure leaves non-stokd rails intact; log and continue.

**Acceptance Criteria**

- AC-4.1.a: Seeding an empty registry with the flag on yields right-rail tools Files, Find, Vault, Work in that order.
- AC-4.1.b: A second seed call does not duplicate the Work tab and does not reset a customized order.
- AC-4.1.c: Flag off → seed introduces no stokd kinds.
- AC-4.1.d: Seeding does not add or reorder any left-rail section.
- AC-4.1.e: `./scripts/test-unit.sh -only-testing:cmuxTests/StokdWorkPanelSeedTests CMUX_SKIP_ZIG_BUILD=1 test` → exit 0.

