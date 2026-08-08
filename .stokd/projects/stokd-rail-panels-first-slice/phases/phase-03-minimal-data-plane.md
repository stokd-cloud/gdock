# Phase 3: Config and usage data access

**Project:** Stokd Rail Panels — Left Rail Slice
**Slug:** stokd-rail-panels-first-slice
**Review Mode:** complete

## Work Items

### 3.1: Config schema access and usage ingest

**Implementation Details**

- **Landing:** fork-only.
- **Reuse** the stokd CLI runner from `docs/stokd-work-panel.prd.md` (executable resolution, working directory, structured errors). Do not add a second runner or a second executable-resolution path.
- Config schema read path for Global Config: prefer `stokd config schema --json` via that runner; layered value reads may parse YAML layers read-only.
- Config write path: construct `stokd config set …` argv only. **Never** write config files from the app.
- Usage ingest: prefer watching provider stores over a 60s full poll; accept a thin poll as an interim if the watch lands in this phase's last item — document the chosen path in code.
- Failure modes: CLI missing → the runner's structured error (code 127) surfaced as panel state; no stores → empty/unobserved state; never a fatal process exit.

**Acceptance Criteria**

- AC-3.1.a: Config schema fixture JSON decodes into the render model used by Phase 4.
- AC-3.1.b: Usage ingest maps fixture provider store records into aggregate-ready values.
- AC-3.1.c: The config write path only constructs CLI argv — no `FileManager`/`Data.write` to `config.yaml`.
- AC-3.1.d: `rg` shows exactly one stokd executable-resolution implementation in `Sources/` (the prerequisite's).
- AC-3.1.e: `./scripts/test-unit.sh -only-testing:cmuxTests/StokdConfigUsageDataTests CMUX_SKIP_ZIG_BUILD=1 test` → exit 0.
