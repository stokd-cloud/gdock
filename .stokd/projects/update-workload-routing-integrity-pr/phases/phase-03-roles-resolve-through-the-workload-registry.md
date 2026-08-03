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

