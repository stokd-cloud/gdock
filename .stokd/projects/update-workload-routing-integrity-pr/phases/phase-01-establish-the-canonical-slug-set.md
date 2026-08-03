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

