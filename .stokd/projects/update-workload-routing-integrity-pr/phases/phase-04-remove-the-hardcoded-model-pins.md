# Phase 4: Remove the hardcoded model pins

**Project:** Update Workload Routing Integrity PR
**Slug:** update-workload-routing-integrity-pr
**Review Mode:** complete

## Work Items

### 4.1: Unpin the agent surface

**Implementation Details**

- **Landing:** fork-only.
- Remove the `model:` frontmatter line from the four repo-root definitions under `.claude/agents/` — `contract-review.md`, `feature-reviewer.md`, `flow-validator.md`, `investigator.md` — all currently `model: sonnet`. These are authoritative whenever Claude Code spawns the agents directly, and are read at runtime by `apps/cli/src/zenith/review.rs`. With the line absent, the agent inherits the session model rather than forcing sonnet.
- Remove the same line from the four vendored copies under `apps/cli/src/zenith/prompts/agents/`. In those files the value is already overwritten at runtime by `apps/cli/src/zenith/agent_surface.rs`, so it is a placeholder — but a placeholder that reads as a pin to anyone auditing the repository, which is precisely how this defect went unnoticed. If a line must remain for format reasons, it should be a comment stating that the value is stamped at runtime.
- After this change, no shipped asset in the repository names a model. Add a repository check asserting that, so a future contributor cannot reintroduce a pin by copying an existing agent file.
- Failure modes: an agent spawned outside both paths inherits the session model, which is the documented and intended behavior rather than a silent fallback.

**Acceptance Criteria**

- AC-4.1.a: Zero `model:` frontmatter lines remain across the four `.claude/agents/*.md` files → the authoritative definitions are unpinned.
- AC-4.1.b: Zero remain across the four `apps/cli/src/zenith/prompts/agents/*.md` files → the vendored placeholders no longer read as pins.
- AC-4.1.c: A repository check fails if any agent markdown reintroduces a `model:` line → the fix cannot silently regress.
- AC-4.1.d: The runtime stamping path still sets a model for the vendored copies when a role resolves one → removing the placeholder did not break stamping.
- AC-4.1.e: `cargo test -p stokd zenith::agent_surface` exits 0.

