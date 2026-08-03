# Phase 3: Minimal data plane

**Project:** Stokd Rail Panels — First Slice
**Slug:** stokd-rail-panels-first-slice
**Review Mode:** complete

## Work Items

### 3.1: CLI runner and API client stubs for panels

**Implementation Details**

- **Landing:** fork-only.
- Add a minimal runner that resolves `stokd` executable (`STOKD_CLI_PATH` → `~/.stokd/bin/stokd` → PATH) and runs commands with an explicit working directory (active workspace cwd).
- Add thin REST client for local stokd API (default `http://localhost:8167`) for Work list endpoints (tasks/projects paged) — URLProtocol-testable.
- Config schema read path for Global Config: prefer `stokd config schema --json` when available; layered value reads may parse YAML layers read-only.
- Usage ingest: prefer watching provider stores over 60s full poll; accept thin poll as interim if watch lands in same phase’s last item — document chosen path.
- **Never** write config files from the app; writes only via `stokd config set`.
- Failure modes: CLI missing → structured error code 127; API down → empty list + banner-ready error; never fatal process exit.

**Acceptance Criteria**

- AC-3.1.a: Unit — executable resolution order with fixtures.
- AC-3.1.b: Unit — Work API decoder accepts paged fixture JSON.
- AC-3.1.c: Unit — config write path only constructs CLI argv (no FileManager write to config.yaml).
- AC-3.1.d: `swift test` or unit suite for the data plane target → exit 0.

