# Complete Phase Review

**Project:** Update Workload Routing Integrity PR
**Slug:** update-workload-routing-integrity-pr
**Generated:** 2026-08-01T14:10:30.813236+00:00

## Included Phases

- Phase 1: Establish the canonical slug set (`phase-01-establish-the-canonical-slug-set.md`)
- Phase 2: Unknown input stops being silent (`phase-02-unknown-input-stops-being-silent.md`)
- Phase 3: Roles resolve through the workload registry (`phase-03-roles-resolve-through-the-workload-registry.md`)
- Phase 4: Remove the hardcoded model pins (`phase-04-remove-the-hardcoded-model-pins.md`)

---

# Phase 1: Establish the canonical slug set

**Project:** Update Workload Routing Integrity PR
**Slug:** update-workload-routing-integrity-pr
**Review Mode:** complete

## Work Items

### 1.1: Rename the two workload slugs

**Implementation Details**

- **Landing:** fork-only — `mono` is the product repository; there is no upstream.
- In `apps/cli/src/llm_routing.rs`, rename the `TaskClass` enum arm `Task` to `Worker` and `OrchestrationCode` to `Orchestration` (enum at `:237`), and update `slug()` (`:288`) to return `"worker"` and `"orchestration"`.
- The compiler will flag every remaining consumer, because the `match self` arms in this file are exhaustive and wildcard-free. Work through each until `cargo build -p stokd` is clean. Expect arms in `slug()`, `required_capabilities()`, `preferred_eval_dimension()`, `quality_sensitivity()`, the capability floor, `local_role()`, and `target_tier()`.
- Update `known_workload_slugs()` at `apps/cli/src/commands/model.rs:496` to the new spellings.
- Do **not** introduce a wildcard arm anywhere while doing this. The compiler-enforced exhaustiveness is the safety property that makes the rename tractable; a wildcard added for convenience would silently absorb the next rename.
- Failure modes: a consumer that formats the slug into a string literal elsewhere will not be caught by the compiler — grep for the literals `"task"` and `"orchestrationCode"` across `apps/cli/src/` and triage each hit, since some are unrelated uses of the common word "task".

**Acceptance Criteria**

- AC-1.1.a: `TaskClass::Worker.slug() == "worker"` and `TaskClass::Orchestration.slug() == "orchestration"` → the canonical spellings are in place.
- AC-1.1.b: No `slug()` arm returns `"task"` or `"orchestrationCode"` → the old spellings are gone from the canonical source.
- AC-1.1.c: `cargo build -p stokd` exits 0 → every compiler-visible consumer was updated.
- AC-1.1.d: The `TaskClass` `match self` blocks contain no wildcard arm → future renames stay compiler-enforced.

### 1.2: Alias the legacy spellings and migrate config

**Implementation Details**

- **Landing:** fork-only.
- In `task_class_for_role` (`apps/cli/src/router/execute.rs:168`), add the legacy spellings as **explicit alias arms**, exactly matching the shape already used for titles at `:179`:
  `"worker" | "task" => TaskClass::Worker` and `"orchestration" | "orchestrationCode" => TaskClass::Orchestration`.
- Add a config migration so a user config carrying `models.workloads.task` or `models.workloads.orchestrationCode` resolves into the `worker` and `orchestration` policies. Follow the existing per-key legacy migration pattern in `apps/cli/src/config.rs` (the file already carries several such migrations for renamed keys, and an alias table for `llm.workloads` → `models.workloads`).
- Where both the legacy and canonical spellings are present in one config, the canonical wins and the legacy one raises the integrity finding defined in 2.2. Silently merging two spellings of the same setting is exactly the ambiguity this project exists to remove.
- Aliases are a documented, auditable decision with a finite list. This is the distinction from the wildcard being removed in 2.1: an alias says *these two names mean this*, a wildcard says *anything I do not recognize means the expensive one*.
- Failure modes: a config with both spellings and conflicting model chains must not silently pick one without reporting.

**Acceptance Criteria**

- AC-1.2.a: `task_class_for_role("task") == TaskClass::Worker` and `task_class_for_role("orchestrationCode") == TaskClass::Orchestration` → legacy work-plan YAML keeps routing correctly.
- AC-1.2.b: A config written with `models.workloads.task` yields the same model chain under the `worker` policy after load → existing customer configs survive the rename.
- AC-1.2.c: The same holds for `models.workloads.orchestrationCode` → `orchestration`.
- AC-1.2.d: A config carrying both spellings resolves to the canonical one and raises a finding → ambiguity is surfaced, not guessed at.
- AC-1.2.e: `cargo test -p stokd config::` exits 0 → migration tests pass.

### 1.3: Realign the TypeScript mirrors

**Implementation Details**

- **Landing:** fork-only.
- **The two mirrors live in different repositories, and this splits the work item.** `apps/code` is a **git submodule** (`.gitmodules`: `url = git@github.com:stokd-cloud/code.git`, `branch = main`), tracked in `mono` as a gitlink. `packages/shared` is an ordinary tree inside `mono`. So the UI mirror is a change to a separate repo plus a pointer bump, while the telemetry mirror is a plain in-repo edit. Sequence the submodule side first — commit and push in `apps/code` on its `main`, then commit the updated gitlink in `mono` — so the pointer never references an unpushed commit. Note the submodule is not populated in a fresh worktree; run `git submodule update --init apps/code` before editing.
- `apps/code/extensions/stokd/src/model-configuration.ts` — in `WORKLOAD_CATEGORIES`, rename the `task` row's key to `worker` and the `orchestrationCode` row's key to `orchestration`. Update the `orchestrationCode` row's label, which currently reads "Project Phase Work Item" — the label is what the rename exists to fix, since that string describes a work item rather than a model workload.
- `packages/shared/src/types/telemetry-workload.ts` — the `WorkloadClass` union already contains `orchestration`, so that member becomes correct rather than changing. Add `worker`.
- These two files are hand-maintained mirrors of the Rust slug set with no compile-time link to it. Add a check that fails when they drift, so the next rename cannot silently desynchronize them.
- Failure modes: the UI list is display-only, so a stale entry does not error — it simply shows a workload the user cannot configure, or omits one they can.

**Acceptance Criteria**

- AC-1.3.a: `WORKLOAD_CATEGORIES` contains rows keyed `worker` and `orchestration`, and no row keyed `task` or `orchestrationCode` → the settings UI matches the canonical slugs.
- AC-1.3.b: `WorkloadClass` in `packages/shared` includes `orchestration` and `worker` → telemetry classes match.
- AC-1.3.c: A drift check compares the TypeScript slug set against the Rust `slug()` values and fails on mismatch → the mirrors cannot silently desync again.
- AC-1.3.d: The TypeScript build and lint pass → no type breakage in dependents of `WorkloadClass`.
- AC-1.3.e: The `apps/code` submodule commit referenced by `mono` is reachable on that repository's `main` before the gitlink bump lands → the pointer never references an unpushed commit.


---

# Phase 2: Unknown input stops being silent

**Project:** Update Workload Routing Integrity PR
**Slug:** update-workload-routing-integrity-pr
**Review Mode:** complete

## Work Items

### 2.1: Replace the catch-all routing arm

**Implementation Details**

- **Landing:** fork-only.
- Remove `_ => TaskClass::OrchestrationCode` at `apps/cli/src/router/execute.rs:184`. Change `task_class_for_role` to return `Option<TaskClass>` (or a `Result` carrying the offending slug), so an unrecognized role slug is representable as "no mapping" rather than silently becoming the heaviest model.
- Update the call sites to handle the absent case by **failing that job** with a message naming the unrecognized slug and listing the valid ones. Do not abort the process and do not fall back to a model.
- The docstring at `apps/cli/src/router/execute.rs:164-167` currently justifies the wildcard as making delegation "always deterministic and never panics". Determinism is preserved — the mapping stays a pure table — and returning `None` does not panic. Update that comment so it does not read as an argument for reinstating the wildcard.
- Keep the alias arms from 1.2. The distinction being encoded: known legacy spellings are mapped, unknown input is refused.
- Failure modes: a work plan authored against a future slug fails its job with a clear message rather than running expensively against the wrong model.

**Acceptance Criteria**

- AC-2.1.a: `task_class_for_role("definitelyNotASlug")` yields no mapping rather than `Orchestration` → unknown input is no longer absorbed.
- AC-2.1.b: Every canonical slug and both legacy aliases still map correctly → the change does not regress known input.
- AC-2.1.c: A work plan naming an unrecognized role fails that job with an error naming the slug, and the process continues → blast radius is the job, not the daemon.
- AC-2.1.d: No wildcard arm remains in `task_class_for_role` → the silent path is gone.
- AC-2.1.e: `cargo test -p stokd router::` exits 0.

### 2.2: Report unknown workload keys as integrity findings

**Implementation Details**

- **Landing:** fork-only.
- Today unknown config keys are dropped by serde without comment (`apps/cli/src/config.rs:2059`). After config load, compare the keys present under `models.workloads` against the canonical slug set plus the legacy aliases, and emit one `IntegrityFinding` per unrecognized key.
- Use the existing subsystem rather than a new one: `IntegritySource::ConfigDrift` (`apps/cli/src/integrity_state.rs:25`) and `IntegritySeverity::Error` (`:36`). Findings surface through the already-wired `stokd integrity report` path and the daemon's healer.
- The finding message names the offending key and lists the valid slugs. A user who typed `jugde` should be told `judge` exists.
- **Config load must not abort.** The unrecognized key is skipped and everything else loads. One typo must never stop the daemon from starting; the requirement is that the problem is impossible to miss, not that it is fatal.
- For the two known rename casualties, `task` and `orchestrationCode`, additionally offer an auto-heal through the existing integrity heal path, rewriting the key to its canonical spelling. This turns the migration into something the product performs for the customer rather than a release note asking them to hand-edit YAML.
- Failure modes: a key that is a legacy alias is healed, not merely reported; a key that is neither canonical nor alias is reported and skipped, never guessed at.

**Acceptance Criteria**

- AC-2.2.a: A config containing `models.workloads.jugde` produces exactly one `ConfigDrift` finding naming that key → unknown keys are visible.
- AC-2.2.b: That same config still loads successfully and the daemon starts → a typo cannot take the fleet down.
- AC-2.2.c: The finding's message lists the valid slugs → the report is actionable without documentation.
- AC-2.2.d: A config containing `models.workloads.task` produces a finding whose heal action rewrites the key to `worker` → the rename self-migrates.
- AC-2.2.e: A config containing only canonical slugs produces zero findings → no false positives.
- AC-2.2.f: `cargo test -p stokd integrity` exits 0.


---

# Phase 3: Roles resolve through the workload registry

**Project:** Update Workload Routing Integrity PR
**Slug:** update-workload-routing-integrity-pr
**Review Mode:** complete

## Work Items

### 3.1: Fall through to `models.workloads` in role resolution

**Implementation Details**

- **Landing:** fork-only.
- `resolve_role_model` (`apps/cli/src/zenith/role_model.rs:257`) currently resolves: explicit flag → the `RoleDefaults` chain → `RoleModel { provider: None, model: None }`. Insert a workload lookup between the second and third steps.
- Mapping from `Role` (`apps/cli/src/zenith/role_model.rs:22`) to slug: `Orchestrator` → `orchestration`, `Worker` → `worker`, `Validator` → `evaluator`, `TerminalReviewer` → `evaluator`.
- Resolution precedence, in full: explicit flag, then `zenith.roles.<role>.model`, then `models.workloads.<slug>`, then provider rotation. The existing role fallback chains (validator → worker, terminal-reviewer → validator → worker, orchestrator → worker) continue to apply within the `zenith.roles` step only; the workload step uses the direct mapping above.
- **No model identifier literal may appear in this path.** The terminal fallback stays `provider: None, model: None`, which means "let provider rotation choose". The workload chain itself may resolve to `models.defaults`, which is config, not a hardcode.
- `resolve_role_model` needs access to the loaded config to perform the lookup. Thread it in explicitly rather than reaching for a global — the function is currently pure over its arguments and is tested that way.
- Failure modes: a role whose mapped slug has no configured chain falls through to provider rotation exactly as today; a role whose mapped slug is misspelled in config is reported by 2.2 and falls through.

**Acceptance Criteria**

- AC-3.1.a: With no flag and no `zenith.roles` entry, `Role::Worker` resolves to the model configured at `models.workloads.worker` → the fallthrough works.
- AC-3.1.b: The same holds for `Orchestrator` → `orchestration`, and for both `Validator` and `TerminalReviewer` → `evaluator`.
- AC-3.1.c: Precedence holds across all four levels: an explicit flag beats `zenith.roles`, which beats `models.workloads`, which beats provider rotation.
- AC-3.1.d: With no flag, no role default, and no workload entry, the result is `provider: None, model: None` → no hardcoded terminal fallback was introduced.
- AC-3.1.e: The body of `resolve_role_model` contains no quoted model identifier → the no-hardcode rule is mechanically enforced.
- AC-3.1.f: `cargo test -p stokd zenith::role_model` exits 0.

### 3.2: Add the `investigator` slug and route the helper agent through it

**Implementation Details**

- **Landing:** fork-only.
- Add an `Investigator` arm to `TaskClass` with slug `"investigator"`, following the same seven-arm checklist as 1.1 (`slug()`, `required_capabilities()`, `preferred_eval_dimension()`, `quality_sensitivity()`, capability floor, `local_role()`, `target_tier()`), plus `known_workload_slugs()` and both TypeScript mirrors from 1.3.
- Characterize it correctly rather than copying another arm: the investigator is high-volume, read-only, context-heavy evidence gathering. Its capability floor should be low and its local role should favor a large-context economy model — this is the workload where a wrong choice costs the most in tokens per unit of value.
- In `apps/cli/src/zenith/agent_surface.rs`, resolve the investigator agent through `models.workloads.investigator` first, falling back to the existing worker chain when unset. Preserve the deliberate existing behavior that the investigator never inherits the orchestrator's model — the module documents this as a fix for an upstream defect.
- The other three helper agents — `contract-review`, `feature-reviewer`, `flow-validator` — get no new slug and continue on the validator chain, which now reaches `evaluator` via 3.1.
- Failure modes: with no `investigator` entry configured, behavior is identical to today.

**Acceptance Criteria**

- AC-3.2.a: `TaskClass::Investigator.slug() == "investigator"` and it appears in `known_workload_slugs()` → the slug is live and discoverable.
- AC-3.2.b: The investigator agent resolves to `models.workloads.investigator` when set → the new key is honored.
- AC-3.2.c: With `investigator` unset, the agent resolves through the worker chain exactly as before → additive, not breaking.
- AC-3.2.d: The investigator never resolves to the orchestrator's model → the existing upstream-defect fix is preserved.
- AC-3.2.e: Both TypeScript mirrors include `investigator` → the settings UI can configure it.
- AC-3.2.f: `cargo test -p stokd zenith::` exits 0.


---

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

