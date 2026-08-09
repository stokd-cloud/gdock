# Phase 2: Minimal stokd data plane

**Project:** Stokd Work Panel (gdock right rail)
**Slug:** stokd-work-panel-gdock-right-rail
**Review Mode:** complete

## Work Items

### 2.1: stokd CLI runner

**Implementation Details**

- **Landing:** fork-only.
- Add a minimal runner that resolves the `stokd` executable in order: `STOKD_CLI_PATH` → `~/.stokd/bin/stokd` → `PATH`.
- Runs commands with an explicit working directory (the active workspace cwd), returns structured stdout/stderr/exit code; never blocks the main actor.
- **Never** write config files from the app; any future write path constructs `stokd config set` argv only.
- Failure modes: CLI missing → structured error with code 127, surfaced as panel state; never a fatal process exit.

**Acceptance Criteria**

- AC-2.1.a: Executable resolution follows `STOKD_CLI_PATH` → `~/.stokd/bin/stokd` → `PATH` against fixtures.
- AC-2.1.b: Missing executable yields a structured error (code 127), not a crash or `fatalError`.
- AC-2.1.c: No source under `Sources/Stokd/` writes to `config.yaml` via `FileManager`/`Data.write`.
- AC-2.1.d: `./scripts/test-unit.sh -only-testing:cmuxTests/StokdCLIRunnerTests CMUX_SKIP_ZIG_BUILD=1 test` → exit 0.

### 2.2: Local stokd API client for tasks and projects

**Dependencies:** 2.1

**Implementation Details**

- **Landing:** fork-only.
- Add a thin REST client for the local stokd API (default `http://localhost:8167`, overridable) covering the paged task and project list endpoints used by Work.
- `URLProtocol`-testable: all requests go through an injectable `URLSession` configuration so tests run offline against fixtures.
- Decode into value types (no reference-type stores leaking below a list boundary — see the snapshot-boundary rule in `CLAUDE.md`).
- Failure modes: API down / non-2xx / decode failure → empty result plus a banner-ready error value; never fatal, never a hang without timeout.

**Acceptance Criteria**

- AC-2.2.a: Paged fixture JSON for tasks and projects decodes into the expected value types.
- AC-2.2.b: Connection refused and non-2xx responses map to a structured error, and the result is an empty list plus error — not a throw across the UI boundary.
- AC-2.2.c: Requests target the configured base URL, defaulting to `http://localhost:8167`.
- AC-2.2.d: `./scripts/test-unit.sh -only-testing:cmuxTests/StokdWorkAPIClientTests CMUX_SKIP_ZIG_BUILD=1 test` → exit 0.

