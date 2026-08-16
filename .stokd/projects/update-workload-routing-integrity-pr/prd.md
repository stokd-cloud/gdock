Reading the full prompt and source context to produce the PRD.Drafting an implementation-ready PRD from the source slug `workload-routing-integrity`, using the required structure and conservative defaults.Found a related project folder — loading it for source context.Found prior workload-aware orchestration work — loading that PRD and related context.Found the merged PR for this PRD — fetching its content.Emitting the recovered, implementation-ready PRD and recording session disposition.# PRD: Workload Routing Integrity

## 0. Source Context

**Derived From:** Working session with the requester, 2026-07-31 → 2026-08-01, tracing how Zenith-derived agent roles pick their models.
**Feature Name:** Workload Routing Integrity
**PRD Owner:** Brian Stoker
**Last Updated:** 2026-08-01
**Repository:** `stokd-cloud/mono`, crate `stokd` at `apps/cli/`.
**Base commit:** `eda841e5a`

### Summary

Model selection for LLM sub-roles is currently spread across four unrelated mechanisms, one workload slug collides with an unrelated domain term, and three separate paths resolve unknown input by silently falling back to the most expensive model or to a hardcoded pin. This project consolidates role model selection onto the workload registry, renames the two misleading slugs, and makes every unknown input either explicitly aliased or loudly reported.

### Why this matters commercially

This is being built to sell to enterprise vendors, which raises the bar on three of these defects specifically:

- **Cost.** An unrecognized workload slug resolves to `TaskClass::OrchestrationCode` — the heaviest coding model — with no error and no log. A typo in customer config is an unbounded, silent spend increase.
- **Auditability.** "Which model processed this request, and why?" currently has no answer for any role that fell through a wildcard or inherited a frontmatter pin.
- **Data residency.** A silent reroute does not merely change the model; it can change the **provider**, moving traffic to a vendor or region the customer never approved. That is a compliance incident, not a bug.

### The four competing mechanisms today

| # | Mechanism | Scope | Problem |
|---|---|---|---|
| 1 | `models.workloads.<slug>` | 12 slugs, closed by the `TaskClass` enum | The intended home. Only `judge` and `title` are cleanly wired through it. |
| 2 | `zenith.roles.<role>.model` | 4 Zenith roles | Parallel namespace with its own resolver and alias table; dead-ends at provider rotation instead of consulting #1. |
| 3 | `governance.toolJudge.model` | 1 bespoke key | Shadows `models.workloads.judge`. |
| 4 | Agent markdown frontmatter | 8 files | Hardcoded `model: sonnet`. Not configurable at all. |

This project addresses #2 and #4 and leaves #3 as recorded follow-up (§5).

### Load-bearing facts, verified at `eda841e5a`

- `TaskClass` is declared at `apps/cli/src/llm_routing.rs:237`; `slug()` at `:288`. Its `match self` arms are exhaustive with no wildcard, so renaming an arm is compiler-enforced across all consumers.
- `task_class_for_role(role: &str)` at `apps/cli/src/router/execute.rs:168` maps a **string** to a `TaskClass`. Its final arm, `apps/cli/src/router/execute.rs:184`, is `_ => TaskClass::OrchestrationCode`. Because the input is a string from work-plan YAML, no compiler check reaches it.
- The same function already demonstrates the explicit-alias pattern this project adopts: `"title" | "titleGen" => TaskClass::TitleGen` at `apps/cli/src/router/execute.rs:179`.
- `resolve_role_model` at `apps/cli/src/zenith/role_model.rs:257` resolves in the order: explicit flag → the `RoleDefaults` chain (from `zenith.roles.<role>.model`) → `RoleModel { provider: None, model: None }`. It never consults `models.workloads`. `Role` is at `:22`, `RoleDefaults` at `:51`.
- Unknown config keys are dropped without comment — `apps/cli/src/config.rs:2059`: *"unknown keys are ignored by serde default."*
- An integrity subsystem already exists and is the correct home for reporting that: `IntegritySource` at `apps/cli/src/integrity_state.rs:25` includes a `ConfigDrift` variant, `IntegritySeverity` at `:36` has `Warning` and `Error`, and the surface is already wired to `stokd integrity report` and a heal path.
- `known_workload_slugs()` at `apps/cli/src/commands/model.rs:496` is the display-side slug list.
- All eight agent definitions carry `model: sonnet`: the four repo-root files under `.claude/agents/` and the four vendored copies under `apps/cli/src/zenith/prompts/agents/`. The vendored copies are stamped over at runtime by `apps/cli/src/zenith/agent_surface.rs`; the repo-root four are authoritative whenever Claude Code spawns those agents directly, and are read at runtime by `apps/cli/src/zenith/review.rs`.
- The TypeScript mirrors disagree with Rust today: `packages/shared/src/types/telemetry-workload.ts` spells the slug `orchestration` while Rust spells it `orchestrationCode`, and `apps/code/extensions/stokd/src/model-configuration.ts` uses the alias `titleGen` for the `title` slug.

### Decisions carried in from the working session

- `task` → `worker`. The current name collides with the work-item type, which is a distinct domain concept.
- `orchestrationCode` → `orchestration`. Shorter, and it resolves the existing Rust/TypeScript drift rather than creating new drift.
- Zenith role → workload mapping: Orchestrator → `orchestration`, Worker → `worker`, Validator → `evaluator`, TerminalReviewer → `evaluator`. Validator and TerminalReviewer share `evaluator` because that slug already means "decides whether work is truly finished, and what remains if not" — which is what both roles do. The per-role `zenith.roles.*` override still distinguishes them for anyone who wants that.
- `investigator` becomes a new slug. It is the one Zenith helper role no existing slug covers: high-volume, read-only, context-heavy evidence gathering, where the ideal model differs most from the session model.
- `feature-reviewer` and `flow-validator` get **no** new slugs; they ride `codeReview`.
- `orchestrator` and `worker` as *Zenith roles* remain roles, not new slugs; they map onto existing ones.

## 1. Objectives & Constraints

### Objectives

- One canonical slug set, with `worker` and `orchestration` replacing `task` and `orchestrationCode`, mirrored consistently into both TypeScript consumers.
- Existing customer configs keep working across the rename, via explicit aliases rather than a catch-all.
- Zenith role model selection resolves through `models.workloads` when no flag and no `zenith.roles` value is supplied.
- No model identifier is hardcoded anywhere in the resolution path or in any shipped agent definition.
- An unknown workload key is reported as an integrity finding instead of being silently dropped, and the two rename casualties are offered as an auto-heal.
- An unrecognized role slug fails the job that used it, rather than silently resolving to the most expensive model.

### Constraints

- **A config typo must never prevent the daemon from starting.** Unknown workload keys are reported at `Error` severity and skipped; config load continues. Taking an agent fleet down over one misspelled key is a worse enterprise failure than the typo.
- **No new mechanism where one exists.** Unknown-key reporting uses `IntegritySource::ConfigDrift` and the existing heal path. Aliases follow the `"title" | "titleGen"` precedent already in `apps/cli/src/router/execute.rs:179`.
- **The terminal fallback stays provider-rotation** (`provider: None, model: None`). This project adds a config-driven layer above it; it must not introduce a default model literal.
- Renames land atomically with every consumer. A half-applied rename is invisible until the bill arrives, because of the wildcard at `apps/cli/src/router/execute.rs:184`.
- `TaskClass` match arms are exhaustive and wildcard-free by design; that property must be preserved so the compiler keeps finding consumers.
- `mono` has many concurrent worktrees. Every phase rebases on current `main` before landing.
- Public CLI behavior for `stokd model workload <slug> <model>` must keep working for both old and new spellings for at least one release.

## 1.5 Required Toolchain

| Tool | Min Version | Install Command | Verify Command |
|------|-------------|-----------------|----------------|
| Rust toolchain | stable 1.75 | `rustup toolchain install stable` | `cargo --version` |
| Node.js | 20 | `nvm install 20` | `node --version` |
| pnpm | 9 | `corepack enable` | `pnpm --version` |
| git | 2.39 | `brew install git` | `git --version` |

The crate under change is `stokd` (`apps/cli/Cargo.toml`). Rust verification uses `cargo test -p stokd <filter>` and `cargo build -p stokd`, run from the repository root.

## 2. Execution Phases

## Phase 1: Establish the canonical slug set

**Purpose:** This phase must come first because every later phase resolves against the final slug set — Phase 2 validates unknown keys against it, Phase 3 maps Zenith roles onto it, and Phase 4's pin removal is only safe once those mappings exist. Renaming after any of those would mean revising them twice. The renames must also land atomically with their consumers, because the wildcard at `apps/cli/src/router/execute.rs:184` makes a missed consumer silent rather than loud.

### 1.1 Rename the two workload slugs

**Dependencies:** none

**Landing:** fork-only

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

**Acceptance Tests**
- Test-1.1.a: Unit — `slug_values_are_canonical()` asserts both new slug strings.
- Test-1.1.b: Unit — `no_legacy_slug_is_returned()` iterates all `TaskClass` variants and asserts neither legacy string appears.
- Test-1.1.c: The build is the executable gate for AC-1.1.c.
- Test-1.1.d: Regression — `task_class_matches_have_no_wildcard()` greps the enum's impl block.

**Verification Commands**
```bash
set -euo pipefail
cargo build -p stokd
cargo test -p stokd llm_routing::
! grep -qE '=> *"(task|orchestrationCode)"' apps/cli/src/llm_routing.rs
```

### 1.2 Alias the legacy spellings and migrate config

**Dependencies:** 1.1

**Landing:** fork-only

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

**Acceptance Tests**
- Test-1.2.a: Unit — `legacy_role_slugs_alias_to_canonical()`.
- Test-1.2.b: Integration — `legacy_task_workload_key_migrates_to_worker()`.
- Test-1.2.c: Integration — `legacy_orchestration_code_key_migrates()`.
- Test-1.2.d: Regression — `both_spellings_prefers_canonical_and_reports()`.
- Test-1.2.e: The suite is the executable gate for AC-1.2.e.

**Verification Commands**
```bash
set -euo pipefail
grep -qF '"worker" | "task"' apps/cli/src/router/execute.rs
grep -qF '"orchestration" | "orchestrationCode"' apps/cli/src/router/execute.rs
cargo test -p stokd config::
cargo test -p stokd router::
```

### 1.3 Realign the TypeScript mirrors

**Dependencies:** 1.1

**Landing:** fork-only

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

**Acceptance Tests**
- Test-1.3.a: Unit — `workloadCategoriesUseCanonicalSlugs()`.
- Test-1.3.b: Unit — `workloadClassIncludesCanonicalSlugs()`.
- Test-1.3.c: Regression — `tsMirrorsMatchRustSlugs()` parses both sources and diffs the sets.
- Test-1.3.d: The package build is the executable gate for AC-1.3.d.
- Test-1.3.e: Regression — `submoduleCommitIsPushedBeforePointerBump()` asserts `git -C apps/code merge-base --is-ancestor HEAD origin/main` succeeds.

**Verification Commands**
```bash
set -euo pipefail
# apps/code is a submodule and is unpopulated in a fresh worktree.
git submodule update --init apps/code
grep -qF '"worker"' apps/code/extensions/stokd/src/model-configuration.ts
grep -qF '"orchestration"' apps/code/extensions/stokd/src/model-configuration.ts
! grep -qE 'key: "(task|orchestrationCode)"' apps/code/extensions/stokd/src/model-configuration.ts
grep -qF "'orchestration'" packages/shared/src/types/telemetry-workload.ts
grep -qF "'worker'" packages/shared/src/types/telemetry-workload.ts
# The gitlink must never point at an unpushed submodule commit.
git -C apps/code fetch origin main -q
git -C apps/code merge-base --is-ancestor HEAD origin/main
```

## Phase 2: Unknown input stops being silent

**Purpose:** This phase cannot precede Phase 1, because both of its deliverables validate against the canonical slug set: the alias arms from 1.2 must already exist before the catch-all can be removed without breaking legacy configs, and the unknown-key check has nothing correct to compare against until the slug set is final. It precedes Phase 3 so that when role resolution starts reading `models.workloads`, a misspelled key there is already reported rather than absorbed.

### 2.1 Replace the catch-all routing arm

**Dependencies:** 1.2

**Landing:** fork-only

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

**Acceptance Tests**
- Test-2.1.a: Unit — `unknown_role_slug_has_no_mapping()`.
- Test-2.1.b: Unit — `all_canonical_and_alias_slugs_map()` iterates the full set.
- Test-2.1.c: Integration — `unknown_role_fails_job_not_process()`.
- Test-2.1.d: Regression — `no_wildcard_arm_in_role_mapping()`.
- Test-2.1.e: The suite is the executable gate for AC-2.1.e.

**Verification Commands**
```bash
set -euo pipefail
! grep -qF '_ => TaskClass::OrchestrationCode' apps/cli/src/router/execute.rs
cargo test -p stokd router::
cargo build -p stokd
```

### 2.2 Report unknown workload keys as integrity findings

**Dependencies:** 1.2

**Landing:** fork-only

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

**Acceptance Tests**
- Test-2.2.a: Integration — `unknown_workload_key_emits_config_drift_finding()`.
- Test-2.2.b: Regression — `unknown_workload_key_does_not_abort_load()`.
- Test-2.2.c: Unit — `finding_message_lists_valid_slugs()`.
- Test-2.2.d: Integration — `legacy_slug_offers_heal_to_canonical()`.
- Test-2.2.e: Regression — `canonical_config_produces_no_findings()`.
- Test-2.2.f: The suite is the executable gate for AC-2.2.f.

**Verification Commands**
```bash
set -euo pipefail
grep -qF 'ConfigDrift' apps/cli/src/config.rs
cargo test -p stokd integrity
cargo test -p stokd config::
```

## Phase 3: Roles resolve through the workload registry

**Purpose:** This phase depends on Phase 1 for the slug names it maps onto, and follows Phase 2 so that a misspelled workload key encountered during role resolution is already reported rather than silently absorbed. It must precede Phase 4, because removing the frontmatter pins before this fallthrough exists would drop those agents to provider defaults rather than to configured workload models — a regression in configurability rather than the intended improvement.

### 3.1 Fall through to `models.workloads` in role resolution

**Dependencies:** 1.1, 2.2

**Landing:** fork-only

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

**Acceptance Tests**
- Test-3.1.a: Integration — `worker_role_resolves_from_workload()`.
- Test-3.1.b: Integration — `all_four_roles_map_to_expected_slugs()`.
- Test-3.1.c: Integration — `resolution_precedence_is_flag_then_roles_then_workloads_then_rotation()` asserts all four levels in one ordered test.
- Test-3.1.d: Regression — `terminal_fallback_is_provider_rotation_not_a_literal()`.
- Test-3.1.e: Regression — `resolver_contains_no_model_literal()`.
- Test-3.1.f: The suite is the executable gate for AC-3.1.f.

**Verification Commands**
```bash
set -euo pipefail
grep -qF 'workloads' apps/cli/src/zenith/role_model.rs
cargo test -p stokd zenith::role_model
cargo build -p stokd
```

### 3.2 Add the `investigator` slug and route the helper agent through it

**Dependencies:** 3.1

**Landing:** fork-only

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

**Acceptance Tests**
- Test-3.2.a: Unit — `investigator_slug_is_registered()`.
- Test-3.2.b: Integration — `investigator_agent_uses_workload_model()`.
- Test-3.2.c: Regression — `investigator_falls_back_to_worker_chain()`.
- Test-3.2.d: Regression — `investigator_never_inherits_orchestrator_model()`.
- Test-3.2.e: Unit — `tsMirrorsIncludeInvestigator()`.
- Test-3.2.f: The suite is the executable gate for AC-3.2.f.

**Verification Commands**
```bash
set -euo pipefail
grep -qF 'investigator' apps/cli/src/llm_routing.rs
grep -qF 'investigator' apps/cli/src/commands/model.rs
grep -qF 'investigator' apps/cli/src/zenith/agent_surface.rs
cargo test -p stokd zenith::
```

## Phase 4: Remove the hardcoded model pins

**Purpose:** This phase must come last. Removing the frontmatter pins before Phase 3 exists would drop those four agents to provider defaults rather than to configured workload models, which is a regression in configurability — the pins, however wrong, are at least deterministic. Only once role resolution reaches the workload registry does deleting a pin move an agent from "always sonnet" to "whatever the operator configured", which is the actual goal.

### 4.1 Unpin the agent surface

**Dependencies:** 3.1, 3.2

**Landing:** fork-only

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

**Acceptance Tests**
- Test-4.1.a: Regression — `committed_agents_have_no_model_pin()`.
- Test-4.1.b: Regression — `vendored_agents_have_no_model_pin()`.
- Test-4.1.c: Regression — `agent_pin_guard_rejects_reintroduction()` runs the guard against a fixture containing a pin.
- Test-4.1.d: Integration — `stamping_still_applies_resolved_model()`.
- Test-4.1.e: The suite is the executable gate for AC-4.1.e.

**Verification Commands**
```bash
set -euo pipefail
for f in .claude/agents/contract-review.md .claude/agents/feature-reviewer.md \
         .claude/agents/flow-validator.md .claude/agents/investigator.md \
         apps/cli/src/zenith/prompts/agents/contract-review.md \
         apps/cli/src/zenith/prompts/agents/feature-reviewer.md \
         apps/cli/src/zenith/prompts/agents/flow-validator.md \
         apps/cli/src/zenith/prompts/agents/investigator.md; do
  grep -q '^model:' "$f" && { echo "PIN REMAINS: $f"; exit 1; }
done
cargo test -p stokd zenith::agent_surface
```

## 3. Completion Criteria

1. Every work item's Verification Commands block exits 0 on the pushed HEAD.
2. `cargo build -p stokd` and the full `cargo test -p stokd` suite exit 0.
3. `models.workloads` accepts `worker`, `orchestration`, and `investigator`; the legacy spellings `task` and `orchestrationCode` still resolve via explicit alias and are offered as an auto-heal.
4. A config containing an unrecognized workload key produces exactly one `ConfigDrift` integrity finding naming the key and listing valid slugs, and the daemon still starts.
5. `task_class_for_role` contains no wildcard arm, and an unrecognized role slug fails only the job that used it.
6. Each of the four Zenith roles resolves its model as flag → `zenith.roles` → `models.workloads` → provider rotation, with no model identifier literal anywhere in that path.
7. No file in the repository pins a model in agent frontmatter, and a guard prevents reintroduction.
8. The two TypeScript mirrors match the Rust slug set, enforced by a drift check.

## 4. Rollout & Validation

### Rollout Strategy

- Phase order is the landing order; each phase is independently landable and independently revertible.
- No feature flag. Phases 1 and 3 are behavior-preserving for any existing configuration: the renames are aliased, and the fallthrough only engages where resolution previously dead-ended at provider rotation. Phase 2 changes observable behavior only for configurations that were already silently broken. Phase 4 changes behavior only for agents that were already mispinned.
- Rebase on current `main` before each phase lands. `mono` has roughly ten active worktrees and moved twice during the authoring of this document.
- Rollback: each phase is a self-contained revert. The riskiest is Phase 1, since it touches the most files; it is also the most mechanically verified, being compiler-enforced.
- Announce the slug rename in release notes with the alias guarantee stated explicitly, so operators know their existing config keeps working and that the heal is available.

### Post-Launch Validation

- Watch for `ConfigDrift` findings in the field after release. A spike indicates either a real migration problem or a false positive in the unknown-key check; both need immediate attention, since this check is the one thing standing between a typo and a silent cost increase.
- Confirm no rise in job failures attributable to 2.1's stricter role mapping. Any such failure should name an unrecognized slug; if one does not, the error path is under-specified.
- Sample real routing decisions across the four Zenith roles and confirm each traces to a configured source — flag, `zenith.roles`, or `models.workloads` — rather than provider rotation. Heavy reliance on rotation would suggest operators have not configured the new keys and the defaults need revisiting.
- Verify token spend attributed to `orchestration` does not spike after Phase 1. A spike would indicate a consumer that was missed and is now routing through an alias into the wrong class.

## 5. Open Questions

Decisions taken during the session are recorded here alongside what remains open.

- Decision: **`task` → `worker`.** The old name collided with the work-item domain type, which made config discussions ambiguous.
- Decision: **`orchestrationCode` → `orchestration`.** Resolves existing Rust/TypeScript drift rather than adding to it.
- Decision: **Explicit aliases, never a wildcard.** A finite alias list is an auditable decision; a catch-all is an accident that looks like one. The `"title" | "titleGen"` arm already in `apps/cli/src/router/execute.rs:179` is the precedent.
- Decision: **Unknown workload key reports but does not abort.** Enterprise operators cannot have one typo prevent the daemon from starting; the requirement is that the problem is impossible to miss, not that it is fatal. The unrecognized *role* case in 2.1 is stricter — it fails that job — because the blast radius there is one job rather than the whole process.
- Decision: **Validator and TerminalReviewer both map to `evaluator`.** That slug already means "decides whether work is truly finished, and what remains if not", which is what both roles do. Operators who want them distinct still have `zenith.roles.*`.
- Decision: **`investigator` is the only new slug.** It is the one Zenith helper role no existing slug covers. `feature-reviewer` and `flow-validator` ride `codeReview`; `orchestrator` and `worker` map onto existing slugs.
- Decision: **No model literal in the resolution path.** The terminal fallback stays provider rotation. A workload chain resolving to `models.defaults` is configuration, not a hardcode.
- Open question: `governance.toolJudge.model` remains a bespoke key shadowing `models.workloads.judge`. Consolidating it is the obvious next cleanup, but it changes governance behavior and belongs in its own project. Does not block any work item here.
- Open question: `zenith.roles.<role>.model` survives this project as a per-role override above the workload layer. Whether it should eventually be retired in favor of workload keys alone is a product decision about how much per-mission control operators want. Does not block any work item here.
- Open question: `apps/cli/src/zenith/prompts/agents/` skill and prompt assets are vendored from upstream Zenith. Whether unpinning the vendored frontmatter creates a merge burden on future upstream syncs depends on how those syncs are performed, which is not currently documented. Worth resolving before the next vendored-asset refresh; does not block Phase 4.