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

