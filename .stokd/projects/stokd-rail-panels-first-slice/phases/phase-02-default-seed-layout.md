# Phase 2: Default seed layout

**Project:** Stokd Rail Panels — First Slice
**Slug:** stokd-rail-panels-first-slice
**Review Mode:** complete

## Work Items

### 2.1: Seed left stack and right Work tab

**Implementation Details**

- **Landing:** fork-only.
- Extend `SidebarDockSeeding` (or sibling) so when gate is on and stokd seed generation is not yet applied:
  - **Left:** keep/ensure workspaces section at top; create sections Global Config, Worktrees, Usage in that vertical order (Usage bottom).
  - **Right:** ensure Tools section includes Work as a tab with Files, Find, Vault (order: Files, Find, Vault, Work unless existing user order already customized).
- Idempotent marker (e.g. seed generation int / “stokdPanelsSeedApplied”) so re-open does not re-insert duplicates or reset user layout.
- Flag-off: seed path no-ops for stokd kinds.
- Failure modes: partial seed failure leaves non-stokd rails intact; log and continue.

**Acceptance Criteria**

- AC-2.1.a: Unit seed of empty registry with flag on produces left order Workspaces → Global Config → Worktrees → Usage and right tools including Work.
- AC-2.1.b: Second seed call does not duplicate stokd sections/tabs.
- AC-2.1.c: Flag off → seed does not introduce stokd kinds.
- AC-2.1.d: `./scripts/test-unit.sh -only-testing:cmuxTests/StokdRailPanelSeedTests CMUX_SKIP_ZIG_BUILD=1 test` → exit 0.

