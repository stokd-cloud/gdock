# Complete Phase Review

**Project:** Stokd Widgets: Global Config + Per-Model Token Usage
**Slug:** stokd-widgets-global-config-per-model-token-usage
**Generated:** 2026-07-30T07:31:34.983073+00:00

## Included Phases

- Phase 1: Prerequisite gate + `StokdWidgetKit` foundation (`phase-01-prerequisite-gate-stokdwidgetkit-foundation.md`)
- Phase 2: Token data plane + widget host (`phase-02-token-data-plane-widget-host.md`)
- Phase 3: Widget implementations (`phase-03-widget-implementations.md`)
- Phase 4: Entrypoints, localization, and rollout enablement (`phase-04-entrypoints-localization-and-rollout-enablement.md`)

---

# Phase 1: Prerequisite gate + `StokdWidgetKit` foundation

**Project:** Stokd Widgets: Global Config + Per-Model Token Usage
**Slug:** stokd-widgets-global-config-per-model-token-usage
**Review Mode:** complete

## Work Items

### 1.1: Dockable gate + `StokdWidgetKit` package skeleton

**Implementation Details**

- **Gate:** verify the canvas Dockable refactor has landed in `main` before any other work item in this PRD starts. Concretely: `Packages/macOS/CmuxDockable/Sources/CmuxDockable/DockableKind.swift` exists on `main` and `git merge-base --is-ancestor` confirms the mission branch is an ancestor of `origin/main`. If the gate fails, this PRD is blocked — do not fall back to the `PanelType` shape.
- Create `Packages/macOS/StokdWidgetKit/` (macOS group: consumers are the macOS app only, per the group rule in `CLAUDE.md`).
  - `Package.swift`: name `StokdWidgetKit`, platform `.macOS(.v14)`, one library product `StokdWidgetKit`, one test target `StokdWidgetKitTests`. Dependencies: `.package(path: "../CmuxFoundation")` (same-group form) for `FileWatcher` / `RecursivePathWatcher`, and `.package(path: "../CmuxDockable")`.
  - Directory layout: `Sources/StokdWidgetKit/{Config,Tokens,CLI,Model}/`.
- Register the package in the workspace by running `python3 scripts/check-workspace-package-groups.py --write` (never hand-edit `cmux.xcworkspace/contents.xcworkspacedata`).
- Add `StokdWidgetKit` to the `PACKAGES=(...)` array in the `swift-package-tests` job of `.github/workflows/ci.yml`. This is load-bearing: CI's own comment states the `cmux-unit` scheme "does not execute the SPM package test targets", so an unlisted package's `swift test` is compiled but **never gated**.
- Do **not** ignore `Package.resolved` — `scripts/check-package-resolved-policy.py` fails on cmux-owned packages that do.
- Failure modes: package added but absent from the workspace file (CI `--check` drift failure); package added but absent from the CI `PACKAGES` array (silent non-gating); `.gitignore` ignoring `Package.resolved` (policy failure).

**Acceptance Criteria**

- AC-1.1.a: `Packages/macOS/StokdWidgetKit/Package.swift` declares exactly one library product named `StokdWidgetKit` and one test target named `StokdWidgetKitTests` → a `swift build` of the package succeeds with no other product emitted.
- AC-1.1.b: The Dockable gate holds → `test -f Packages/macOS/CmuxDockable/Sources/CmuxDockable/DockableKind.swift` exits 0.
- AC-1.1.c: `swift build --package-path Packages/macOS/StokdWidgetKit` → exit 0.
- AC-1.1.d: `python3 scripts/check-workspace-package-groups.py --check` → exit 0 (no workspace drift after registration).
- AC-1.1.e: `grep -q 'StokdWidgetKit' .github/workflows/ci.yml` → exit 0 (package is a real CI gate, not merely compiled).
- AC-1.1.f: `python3 scripts/check-package-resolved-policy.py` → exit 0.

### 1.2: Config schema descriptor decoder + layered value model

**Implementation Details**

- Add `Sources/StokdWidgetKit/Config/StokdConfigFieldDescriptor.swift`. Decodes the **flat JSON array** emitted by `stokd config schema --json` (74 entries as of stokd 0.2.53). Descriptor keys, exhaustively: `key`, `type`, `default`, `enumValues` (optional), `group`, `label`, `description`, `scope`, `secret`, `localOnly`.

  ```swift
  public struct StokdConfigFieldDescriptor: Codable, Sendable, Equatable {
      public let key: String                    // dot-path, e.g. "agents.maxConcurrent"
      public let type: StokdConfigFieldType
      public let defaultValue: StokdConfigValue? // JSON "default"; may be null
      public let enumValues: [String]?
      public let group: String
      public let label: String
      public let description: String
      public let scope: StokdConfigScope
      public let secret: Bool
      public let localOnly: Bool
  }
  ```

- `StokdConfigFieldType` must handle the **live descriptor's duplicate boolean spelling**: the schema emits both `"bool"` (10 fields) and `"boolean"` (8 fields) for the same concept. Decode both to a single `.boolean` case. Full observed type set: `string` (20), `number` (13), `bool` (10), `boolean` (8), `string[]` (9), `enum` (7), `object` (7). An unrecognized `type` decodes to `.unsupported(String)` and the field renders read-only rather than throwing — a newer CLI must not break the widget.
- `StokdConfigScope`: `.global` (3 fields), `.workspace`, `.both` (71 fields). Decoded leniently; unknown → `.both`.
- `StokdConfigValue`: a small JSON-value enum (`.string`, `.number`, `.bool`, `.stringArray`, `.object`, `.null`) so `default` and per-layer values round-trip without `Any`.
- Add `Sources/StokdWidgetKit/Config/StokdLayeredValue.swift`, porting the extension's `computeLayeredValue` contract (`apps/code/extensions/stokd/src/config-editor-bridge.ts`) verbatim in semantics:

  ```swift
  public struct StokdLayeredValue: Sendable, Equatable {
      public let defaultValue: StokdConfigValue?
      public let globalValue: StokdConfigValue?     // from ~/.stokd/config.yaml
      public let workspaceValue: StokdConfigValue?  // from <ws>/.stokd/config.yaml
      public let effectiveValue: StokdConfigValue?  // workspace ?? global ?? default
      public var origin: StokdConfigOrigin { ... }  // .workspace / .global / .default
  }
  ```

- Add `getDotPath(_ root: StokdConfigValue, _ key: String) -> StokdConfigValue?` — segment-walks a dot-path, returning nil if any segment misses (direct port of the extension helper).
- Add `serializeForCli(_ value: StokdConfigValue) -> String`: arrays comma-joined, booleans `"true"`/`"false"`, scalars stringified. This is the single positional `VALUE` argument the writer verb expects.
- Failure modes: malformed JSON from the CLI (surface the raw stderr, render an error tile, never crash); a field whose `type` is `object` (render read-only with a "edit in YAML" affordance — the CLI writer takes a scalar/CSV positional only); `secret: true` fields (currently 0, but must render masked and non-editable if the CLI ever emits one).

**Acceptance Criteria**

- AC-1.2.a: `StokdConfigFieldType` decodes `"bool"` and `"boolean"` to the same case, and an unknown type string to `.unsupported` → no decode error for any of the three.
- AC-1.2.b: Decoding the live descriptor array yields a count equal to the CLI's own count, with zero decode errors → parity, not a hardcoded 74.
- AC-1.2.c: `effectiveValue` precedence is workspace > global > default, and `origin` reports the layer that won → verified for all three orderings.
- AC-1.2.d: `serializeForCli` renders `["a","b"]` as `a,b` and `true` as `true`.
- AC-1.2.e: `swift test --package-path Packages/macOS/StokdWidgetKit --filter StokdConfigDescriptorTests` → exit 0.
- AC-1.2.f: `stokd config schema --json | python3 -c 'import json,sys; d=json.load(sys.stdin); assert isinstance(d,list) and d; ks={k for f in d for k in f}; assert ks <= {"key","type","default","enumValues","group","label","description","scope","secret","localOnly"}, ks; print(len(d))'` → exit 0, printing the field count. This pins the contract the decoder is written against and fails loudly if a CLI upgrade adds a descriptor key.

### 1.3: `StokdCLIRunner` with cwd binding + write routing

**Implementation Details**

- Add `Sources/StokdWidgetKit/CLI/StokdCLIRunner.swift`:

  ```swift
  public struct StokdCLIResult: Sendable { public let code: Int32; public let stdout: String; public let stderr: String }

  public actor StokdCLIRunner {
      public init(executablePath: String? = nil)          // nil → resolve
      public func run(_ args: [String], workingDirectory: URL?) async -> StokdCLIResult
      public func runJSON<T: Decodable>(_ args: [String], as: T.Type, workingDirectory: URL?) async throws -> T
  }
  ```

- **Executable resolution order:** `STOKD_CLI_PATH` env → `~/.stokd/bin/stokd` → `~/.local/bin/stokd` → `/usr/local/bin/stokd` → `PATH` lookup. First existing executable wins. Unresolvable → every call returns `code: 127` with a fixed `stderr` and the widgets render a "stokd CLI not found" tile. Never crash, never silently no-op.
- **`workingDirectory` is the load-bearing parameter.** The CLI resolves the workspace config from **its own process cwd** via `find_workspace_config` (`stokd-cloud/mono` → `apps/cli/src/config.rs:3623`), which walks up from cwd looking for `.stokd/config.yaml` and stops at a `.git` root, the home directory, or the filesystem root. Therefore setting `Process.currentDirectoryURL` to the active window's cwd is the entire mechanism that gives the config widget the right context. Passing `nil` means "global scope only" and must be used deliberately, never as a default fallback.
- Add `Sources/StokdWidgetKit/Config/StokdConfigWriter.swift` wrapping the canonical writer verbs — the widget never touches YAML:
  - write, workspace scope: `config` `set` `<KEY>` `<VALUE>` `--workspace`, run with `workingDirectory` = active cwd.
  - write, global scope: same without `--workspace` (requires explicit UI confirmation; see 3.2).
  - write, env overlay: `--env <ENV>` (the CLI routes `mongodb.*` here automatically).
  - revert: `config` `unset` `<KEY>` `[--workspace]` `[--env <ENV>]`.
  - Non-zero exit → return the CLI's real stderr text unmodified to the UI. Never swallow, never rephrase.
- Add `Sources/StokdWidgetKit/Config/StokdWorkspaceConfigLocator.swift` — a Swift reimplementation of `find_workspace_config` used only to *display* which file a write will land in (and to detect "no workspace config yet"). It must match the Rust walk exactly, including the order quirk that `.stokd/config.yaml` is tested **before** the `.git` stop condition, so a git root that has a config is found rather than skipped.
- Layer reads do **not** go through the CLI: `stokd config get` and `stokd config show` have **no `--json` flag**, so structured reads parse the two YAML files directly (mirroring the extension's `loadGlobalConfig` / `loadWorkspaceConfig`). A minimal YAML subset reader suffices — the descriptor tells us each field's type, so the reader only needs scalars, string arrays, and nested maps.
- Failure modes: CLI absent (127 path above); CLI present but a different major version emitting an unknown descriptor key (1.2's lenient decode + the AC-1.2.f contract probe); cwd pointing into a deleted directory (locator returns nil, widget falls back to global-only display with an explicit banner).

**Acceptance Criteria**

- AC-1.3.a: `run(_:workingDirectory:)` sets the child process cwd → a probe invocation reports the passed directory, not the app's cwd.
- AC-1.3.b: Unresolvable executable → `code == 127` and a non-empty `stderr`, with no thrown error and no crash.
- AC-1.3.c: `StokdWorkspaceConfigLocator` matches the Rust walk on four cases: config in cwd; config in a parent below the git root; git root with a config (found); git root without a config (nil, does not escape to `$HOME`).
- AC-1.3.d: The writer never emits a direct file write → the only mutation path in the package is the CLI runner.
- AC-1.3.e: `swift test --package-path Packages/macOS/StokdWidgetKit --filter StokdCLIRunnerTests` → exit 0.
- AC-1.3.f: `swift test --package-path Packages/macOS/StokdWidgetKit --filter StokdWorkspaceConfigLocatorTests` → exit 0.
- AC-1.3.g: No `FileHandle`/`Data.write`/`String.write` call targets a `config.yaml` path anywhere in the package → `! grep -rn 'config\.yaml' Packages/macOS/StokdWidgetKit/Sources --include=*.swift | grep -qE '\.write|createFile'` exits 0.


---

# Phase 2: Token data plane + widget host

**Project:** Stokd Widgets: Global Config + Per-Model Token Usage
**Slug:** stokd-widgets-global-config-per-model-token-usage
**Review Mode:** complete

## Work Items

### 2.1: Provider transcript record decoders

**Implementation Details**

- Add `Sources/StokdWidgetKit/Tokens/` with one decoder per provider store, behind a common protocol:

  ```swift
  public struct TokenCounts: Sendable, Equatable, AdditiveArithmetic {
      public var input: Int; public var output: Int
      public var cacheRead: Int; public var cacheWrite: Int
  }
  public struct TokenUsageRecord: Sendable, Equatable {
      public let timestamp: Date
      public let provider: String        // normalized: "claude", "codex", "gemini", "grok"
      public let model: String           // "unknown" only when genuinely absent
      public let sessionId: String
      public let cwd: String?
      public let isSidechain: Bool
      public let counts: TokenCounts
  }
  public protocol ProviderTranscriptDecoder: Sendable {
      static var provider: String { get }
      static var watchRoots: [URL] { get }
      func decode(line: String, state: inout DecoderState) -> TokenUsageRecord?
  }
  /// Per-file carry-over state. Reset when a file's cursor restarts at 0.
  public struct DecoderState: Sendable, Equatable {
      /// Codex latches the model from a `turn_context` line for following
      /// `token_count` lines; nil until the first one is seen.
      public var latchedModel: String?
      /// Gemini OTel spans carry the session id out-of-band from usage records.
      public var latchedSessionId: String?
      /// Count of lines skipped as unparseable, surfaced as a diagnostics value.
      public var skippedLineCount: Int
      public init()
  }
  ```

- `ClaudeTranscriptDecoder` — `~/.claude/projects/**/*.jsonl` (4,598 files on the reference machine at authoring time; the richest source). One record per assistant message. Field mapping, exact:
  - `message.model` → `model`
  - `message.usage.input_tokens` → `counts.input`
  - `message.usage.output_tokens` → `counts.output`
  - `message.usage.cache_read_input_tokens` → `counts.cacheRead`
  - `message.usage.cache_creation_input_tokens` → `counts.cacheWrite`
  - `timestamp`, `sessionId`, `cwd`, `isSidechain` from the record root.
  - Ignore `message.usage.iterations[]` — it restates the same totals and double-counts if summed.
- `CodexTranscriptDecoder` — `~/.codex/sessions/**/rollout-*.jsonl` (1,382 files). **Stateful:** a `turn_context.payload.model` line sets the model for subsequent `token_count` lines in that file. `DecoderState` carries that latch; a `token_count` before any `turn_context` yields `model: "unknown"` rather than being dropped.
- `GeminiOTelDecoder` — `~/.gemini/tmp/<id>-otel/` (267 dirs). Model from the OTel `model` attribute.
- `GrokSQLiteReader` — `~/.grok/grok.db`, `SELECT model, input_tokens, output_tokens, created_at FROM usage_events`. **Grok has no cache columns**; `cacheRead`/`cacheWrite` are structurally `0` and the widget must mark them unavailable, not zero-as-measured.
- Providers with **no** local store: `droid`/`factory`, `amp`, `bedrock`, `openrouter`, `lmStudio`, `devin`. These are rendered as configured-but-unobserved rows (see 3.3), never omitted, so the widget never implies a provider is idle when it is merely un-instrumented.
- Failure modes: a truncated final line (partial append) → decoder returns nil and the cursor is **not** advanced past it, so it is re-read intact on the next event; a record with usage but no model → `"unknown"`; unparseable JSON → skip that line, advance the cursor, increment a diagnostics counter.

**Acceptance Criteria**

- AC-2.1.a: `ClaudeTranscriptDecoder` maps `cache_creation_input_tokens` → `cacheWrite` and `cache_read_input_tokens` → `cacheRead` → a fixture record with all four dimensions distinct decodes to exactly those four values.
- AC-2.1.b: Summing a Claude record does **not** include `usage.iterations[]` → a fixture whose `iterations` restate the totals decodes to the un-doubled counts.
- AC-2.1.c: `CodexTranscriptDecoder` latches the model across lines → a fixture with one `turn_context` then three `token_count` lines yields three records all carrying that model.
- AC-2.1.d: A `token_count` with no preceding `turn_context` yields `model == "unknown"` and is **not** dropped.
- AC-2.1.e: A truncated trailing line yields nil and leaves the consumed-offset unchanged.
- AC-2.1.f: `swift test --package-path Packages/macOS/StokdWidgetKit --filter TranscriptDecoderTests` → exit 0.

### 2.2: `JSONLTailReader` — incremental byte-offset tail

**Implementation Details**

- This work item is deliberately **generic and stokd-free** so it can go upstream as a self-contained PR. It lands in `Packages/macOS/CmuxFoundation/Sources/CmuxFoundation/FileWatch/JSONLTailReader.swift`, beside the existing `FileWatcher` / `RecursivePathWatcher` / `FileSystemEventStream` / `FileWatchClock`.

  ```swift
  public struct JSONLTailReader: Sendable {
      public struct Cursor: Codable, Sendable, Equatable {
          public var byteOffset: Int
          public var mtimeUnixMs: Int
      }
      public enum TailOutcome: Sendable {
          case appended(lines: [String], cursor: Cursor)
          case unchanged
          case truncatedRestart(lines: [String], cursor: Cursor)
      }
      public func tail(path: URL, from cursor: Cursor?) throws -> TailOutcome
  }
  ```

- Semantics: read only `[cursor.byteOffset, EOF)`. Yield only **complete** lines — a trailing fragment with no newline is excluded and the returned offset stops before it, so the next call re-reads it whole. If the file's size is now **smaller** than the cursor offset (rotation/truncation), return `.truncatedRestart` after re-reading from 0 rather than returning garbage or throwing.
- Memory bound: never load the whole file. Read in a fixed buffer (64 KiB) from the offset forward. A 1.9 MB transcript that grew by 800 bytes must read ~800 bytes, not 1.9 MB.
- Add `TokenIngestCursorStore` (fork-only, in `StokdWidgetKit`) persisting `[String: Cursor]` keyed `"<provider>:<absolute-path>"` — mirroring the shape stokd already uses at `~/.stokd/telemetry/ingest-cursors.json`. Persist to the app's own container (`Application Support/cmux/stokd-token-cursors.json`), **not** to stokd's file, so the widget never contends with `stokd telemetry sync`. Atomic write, sorted keys.
- Failure modes: file deleted between event and read (return `.unchanged`, drop the cursor); permission denied (propagate, counted in diagnostics); a cursor for a path that no longer exists (pruned on save).
- Upstream framing: the PR adds one file plus tests, touches no cmux-specific type, and is described purely as "incremental line-oriented tailing for the existing FileWatch utilities". No stokd identifier appears in it.

**Acceptance Criteria**

- AC-2.2.a: Tailing a file that grew by N bytes reads only the new region → a 1 MiB file appended with one 40-byte line reports bytes-read < 4096.
- AC-2.2.b: A trailing fragment without a newline is excluded and the cursor stops before it → the next tail, after the newline arrives, returns that line exactly once.
- AC-2.2.c: A file truncated below the cursor returns `.truncatedRestart` with lines re-read from offset 0.
- AC-2.2.d: An unchanged file returns `.unchanged` and performs no line allocation.
- AC-2.2.e: `swift test --package-path Packages/macOS/CmuxFoundation --filter JSONLTailReaderTests` → exit 0.
- AC-2.2.f: The upstream unit is stokd-free → `! grep -riq 'stokd' Packages/macOS/CmuxFoundation/Sources/CmuxFoundation/FileWatch/JSONLTailReader.swift` exits 0.

### 2.3: Watch-driven aggregator

**Implementation Details**

- Add `Sources/StokdWidgetKit/Tokens/TokenUsageIngestor.swift` — an actor owning the whole watch→tail→decode→fold pipeline. **This is the item that answers "watch, not poll."**
- Watch strategy, and why: use **one** `RecursivePathWatcher` (FSEvents) covering all transcript roots — `~/.claude/projects`, `~/.codex/sessions`, `~/.gemini/tmp` — **not** one `FileWatcher` per file. Its real signature is `public init?(paths: [String], clock: any FileWatchClock = SystemFileWatchClock())`, which takes a **plural** path list, so a single watcher covers every root; 4,598 + 1,385 kqueue descriptors would exhaust the per-process fd budget and is the wrong primitive. `~/.grok/grok.db` gets a separate `FileWatcher` on the `-wal` sibling (SQLite writes land there first) — `FileWatcher.init(path:throttle:clock:)` **does** accept `throttle:`, so pass `.milliseconds(750)` there.
- **The init is failable.** `RecursivePathWatcher.init?` returns nil when `paths` is empty or the `FSEventStream` cannot be created or started. Filter the root list to existing directories first; if the filtered list is empty (a machine that has run no instrumented provider), skip watching entirely and render the empty state — do not force-unwrap and do not treat nil as a fatal error.
- **Coalescing is already provided; do not attempt to configure it.** `RecursivePathWatcher` exposes **no** `throttle:` parameter — its coalescing is internal and fixed: `private static let streamLatency = 0.25` (the `FSEventStream` latency) plus `private static let throttleInterval: Duration = .milliseconds(250)` (a leading-edge throttle), giving a worst-case change-to-yield of roughly 500 ms. That is sufficient for this use and is the reason no custom interval is specified for the recursive watcher.
- **A second, explicit fold debounce is still required**, and it lives in the ingestor rather than the watcher: coalesce watcher events into at most one fold per `foldDebounce` (default `.milliseconds(750)`), injected for tests via the same `FileWatchClock` abstraction the watchers use. During an active agent turn a transcript is appended many times per second, and the watcher's 250 ms window can still yield ~4 events/sec; without the ingestor-side debounce the widget would re-fold on each.
- On a debounced fold: stat the changed subtree, tail only files whose `mtime`/size moved past their cursor, decode new lines, fold into the aggregate, persist cursors, publish one snapshot. Untouched files are never opened.
- Aggregate shape — bucketed so all four timespans are answered without rescanning:

  ```swift
  public struct TokenUsageKey: Hashable, Sendable, Codable {
      public let provider: String   // normalized: "claude", "codex", "gemini", "grok"
      public let model: String      // "unknown" when unattributable
  }
  public struct TokenUsageAggregate: Sendable, Equatable, Codable {
      // (provider, model) → hours-since-epoch → counts. Ring-limited, see pruning.
      public private(set) var buckets: [TokenUsageKey: [Int: TokenCounts]]
      // (provider, model) → lifetime counts. Never pruned, persisted across launches.
      public private(set) var lifetime: [TokenUsageKey: TokenCounts]
      public func summary(for timespan: TokenUsageTimespan, now: Date) -> TokenUsageSnapshot
  }
  public struct TokenUsageSnapshot: Sendable, Equatable {
      public let timespan: TokenUsageTimespan
      public let generatedAt: Date
      public let newestRecordAt: Date?                 // drives the staleness indicator
      public let rows: [TokenUsageRow]                 // one per (provider, model)
      public let unpricedModelCount: Int
      public let totalCostUsd: Decimal                 // priced rows only
  }
  public struct TokenUsageRow: Sendable, Equatable {
      public let key: TokenUsageKey
      public let counts: TokenCounts
      public let cacheDimensionsAvailable: Bool        // false for grok
      public let price: ModelPriceResolution
      public let isRegistered: Bool                    // present in `stokd model list`
  }
  public enum TokenUsageTimespan: String, Sendable, CaseIterable { case last24h, week, month, total }
  ```

- **Timespans are rolling windows, not calendar periods.** Buckets are hour-granularity, keyed by hours-since-epoch computed from the record's own UTC timestamp. `last24h` / `week` / `month` sum the trailing **24 / 168 / 720** buckets relative to `now`. They are explicitly *not* calendar-aligned: "week" means the last 168 hours, not the user's Sunday-to-Saturday week. This is chosen so the value is stable and timezone-independent, and so no recomputation is needed at midnight or across a timezone change. The UI labels them `24h` / `7d` / `30d` accordingly, so the display never implies calendar alignment.
- **`total` is a persisted lifetime accumulator, not a sum of retained buckets.** `summary(for: .total)` reads `lifetime`, never `buckets`. `lifetime` is folded on every record, is never pruned, and is **persisted alongside the cursors** (same file, same atomic write) so it survives app restarts. Without persistence `total` would silently reset on every launch while still being labeled "total" — the exact failure this separation prevents.
- **Cold start** must not walk 6,000 files. On first launch, in order: (1) seed `lifetime` and the in-window buckets from `GET /api/telemetry/token-usage` on `local.baseUrl:port` (default `http://localhost:8167`) when reachable, marking those rows `backfilled`; (2) if the endpoint is unreachable, perform a **bounded local backfill** instead — for each transcript file whose `mtime` falls inside the 720-hour window, tail from the start, hard-capped at `backfillFileLimit = 400` files and `backfillByteLimit = 64 MiB` total, newest `mtime` first, and record whether the cap was hit so the UI can say history is partial. Files outside the window are never opened. (3) Set every remaining cursor to current EOF so only live appends are tailed thereafter. This closes the gap where a machine that never reaches the API could otherwise never populate `week`/`month`. All ingest work runs off the main actor; only the published snapshot crosses to it.
- **Bounded memory.** Prune `buckets` older than the 720-hour window on each fold; `lifetime` absorbs the pruned counts first so nothing is lost. Retained state is O(providers × models × 720), not O(all history).
- The realtime gateway (`:8166`, `subscribeTelemetry`) may be subscribed as an **optional nudge** to trigger an out-of-band fold, since `telemetry.cost_update` carries no `model` and cannot itself update the breakdown. It must be strictly optional: unreachable gateway or unset `REDIS_URL` changes nothing about correctness.
- Failure modes: watch root does not exist (a provider the user never ran) → skip, no error tile; FSEvents stream drop → `RecursivePathWatcher` re-arms and a full cursor-based re-tail reconciles; cursor file corrupt → discard, reseed from EOF, log once.

**Acceptance Criteria**

- AC-2.3.a: The ingestor opens only files whose cursor moved → after touching 1 of 50 fixture transcripts, the recorded open-count is exactly 1.
- AC-2.3.b: A nil `RecursivePathWatcher.init?` is handled without crashing → constructing the ingestor with an empty/nonexistent root list yields a live ingestor in an explicit `noWatchableRoots` state, and no force-unwrap of the watcher appears in the file.
- AC-2.3.c: N appends inside one `foldDebounce` window produce exactly one published snapshot, with counts reflecting all N, driven by an injected `FileWatchClock` rather than wall-clock sleeping.
- AC-2.3.d: `summary(for:)` sums the trailing 24 / 168 / 720 buckets for `last24h`/`week`/`month`, and reads `lifetime` (not buckets) for `total`, asserted with a synthetic clock.
- AC-2.3.e: Pruning bounds retained buckets and loses nothing → after folding 5,000 hours of synthetic records, per-key bucket count ≤ 720 while `total` still reports all 5,000 hours.
- AC-2.3.f: `lifetime` survives a restart → persisting, discarding the in-memory aggregate, and reloading yields the same `total` as before.
- AC-2.3.g: The API-unreachable cold start still populates the window under its caps → with the endpoint stubbed unreachable and 500 in-window fixture files, at most `backfillFileLimit` are opened and the partial-history flag is set.
- AC-2.3.h: No polling timer exists → `! grep -rnE 'Timer\.scheduledTimer|DispatchQueue.*asyncAfter|RunLoop.*add' Packages/macOS/StokdWidgetKit/Sources/StokdWidgetKit/Tokens/TokenUsageIngestor.swift` exits 0. `Task.sleep` is deliberately **not** in this pattern set, because the debounce is legitimately implemented with a clock-driven sleep; the guard targets recurring timers, which is the actual anti-pattern. Debounce correctness is covered by AC-2.3.c instead, which is the behavioral check a grep cannot make.
- AC-2.3.i: `swift test --package-path Packages/macOS/StokdWidgetKit --filter TokenUsageIngestorTests` → exit 0.

### 2.4: Provider/model registry + price resolution

**Implementation Details**

- Add `Sources/StokdWidgetKit/Model/StokdModelRegistry.swift`. Sources the model universe from `stokd model list --json`, whose real shape is an array of **provider groups**:

  ```swift
  public struct StokdModelListGroup: Codable, Sendable { public let provider: String; public let source: String; public let models: [StokdModelListEntry] }
  public struct StokdModelListEntry: Codable, Sendable {
      public let id: String; public let displayName: String; public let provider: String
      public let source: String; public let capability: Double; public let capabilities: [String]
      public let benchmarks: [String: Double]
      // `pricing` is intentionally NOT decoded — see below.
  }
  ```

- **Do not read pricing from `stokd model list`.** The `pricing` field is `Option<ModelPricing>` and is `None` at every construction site in `apps/cli/src/provider_discovery.rs` (lines 200, 240, 321, 329, 337, 391, 636, 656, 812, 924); the only `Some(...)` is inside a `#[cfg(test)]` block. Because of `skip_serializing_if = "Option::is_none"` the key is absent from every cached model. Treating it as a price source would yield silent zeros.
- Provider list comes from the effective config's `providers` array, which is **polymorphic**: bare strings (`claude`, `gemini`, …) and maps (`{name: lmStudio, endpoint:, port:, apiKey:}`). Flatten to names. Apply the CLI's own normalization so config names line up with transcript providers and price keys — mirroring `discovery_provider_key()` (`apps/cli/src/commands/model.rs:346`): `lmStudio` → `lm-studio`, `claudeCode` → `claude`, `openai`/`chatgpt` → `codex`.
- Add `Sources/StokdWidgetKit/Model/ModelPriceTable.swift` — a checked-in Swift port of `LLM_MODEL_PRICING` from `stokd-cloud/mono` → `packages/shared/src/types/cost.ts` (20 entries, `PRICING_SOURCE_VERSION = '2026-04-24'`), carrying `inputUsdPerMtok`, `outputUsdPerMtok`, optional `cacheReadUsdPerMtok` / `cacheWriteUsdPerMtok`, and the long-context triple.
  - Matching is **first-hit substring on the lowercased model id**, so **table order is contractual** (`gpt-5.4-mini` must precede `gpt-5.4`; a bare `gpt-5` catch-all must be last). Encode the order and assert it.
  - Cost = Σ over the four dimensions at their rates. Unlike the Rust implementation (`apps/cli/src/runtime/token_usage.rs:98-105`), **do not** fall back to the input rate for an unpriced cache dimension — that silently invents cost. An unpriced dimension contributes 0 and flips the row's status to `.partiallyPriced`.
  - Resolution result is explicit: `.priced`, `.partiallyPriced`, or `.unpriced(reason:)`. The UI must render `.unpriced` as tokens-only with a marker, never as `$0.00`.
- Known pricing gaps to represent honestly rather than paper over: `openrouter` and `lmStudio` have **no** table entry anywhere (lmStudio is local, so `$0` is genuinely correct there and should be labeled local, not unpriced); `amp` has a deliberately empty table upstream; `grok` is priced in the TS table but empty in the Rust one; `bedrock` is priced in Rust but absent from TS; `claude-fable-5` matches **no** pattern; `claude-opus-5` matches the `opus` substring and would be billed at Opus-4 rates. Every one of these renders `.unpriced` or `.partiallyPriced` rather than a wrong number.
- Failure modes: CLI unavailable → fall back to the on-disk discovery cache `~/.stokd/cache/provider-models/<provider>.json` (24 h TTL, `{fetched_at, provider, models}`) and label the registry stale; a transcript model absent from the registry → still shown, tagged `unregistered` (real usage must never be hidden by a stale registry).

**Acceptance Criteria**

- AC-2.4.a: `stokd model list --json` decodes as an array of provider groups → decoding the live output yields ≥ 1 group and zero errors.
- AC-2.4.b: `pricing` is not consulted → `! grep -q 'pricing' Packages/macOS/StokdWidgetKit/Sources/StokdWidgetKit/Model/StokdModelRegistry.swift` exits 0.
- AC-2.4.c: Provider-name normalization matches the CLI → `lmStudio`→`lm-studio`, `claudeCode`→`claude`, `chatgpt`→`codex`.
- AC-2.4.d: Price matching is order-sensitive and correct → `gpt-5.4-mini` resolves to the mini entry, not the `gpt-5.4` entry.
- AC-2.4.e: An unpriced cache dimension contributes 0 and yields `.partiallyPriced` — never the input rate.
- AC-2.4.f: `claude-fable-5` resolves `.unpriced` and its rendered cost is a marker, not `$0.00`.
- AC-2.4.g: `stokd model list --json | python3 -c 'import json,sys; d=json.load(sys.stdin); assert isinstance(d,list); assert all("provider" in g and "models" in g for g in d); print(sum(len(g["models"]) for g in d))'` → exit 0, printing the model count.
- AC-2.4.h: `swift test --package-path Packages/macOS/StokdWidgetKit --filter ModelPriceTableTests` → exit 0.

### 2.5: `WidgetTile` chrome

**Implementation Details**

- Add `Sources/StokdWidgetKit/UI/WidgetTile.swift` — the shared compact-tile container that makes these panes read as macOS-style widgets rather than full panels: rounded rect (continuous corner radius 20), translucent material background, a small-caps header row (title + optional trailing accessory), generous interior padding, and a single emphasized primary metric slot above a denser detail region.

  ```swift
  public struct WidgetTile<Header: View, Body_: View>: View {
      public init(style: WidgetTileStyle = .standard, @ViewBuilder header: () -> Header, @ViewBuilder content: () -> Body_)
  }
  public enum WidgetTileStyle: Sendable { case standard, compact }
  ```

- Sizing contract: a tile declares an intrinsic minimum of 220×220 pt (`standard`) / 220×120 pt (`compact`) and degrades gracefully above that. It must remain legible at the minimum, since a dockable canvas pane can be resized freely.
- Theme: honor the host's `PanelAppearance` / `WindowAppearanceSnapshot` (both are already threaded into `PanelContentView`) rather than hardcoding light/dark colors.
- **Rendering discipline** (per `CLAUDE.md`, non-negotiable): the tile is a pure value-driven view. It takes no `ObservableObject`, no `@EnvironmentObject`, no store reference. Any list inside a tile's content passes immutable row snapshots plus closure action bundles across the `ForEach` boundary — the pattern established by `IndexSectionActions` / `SectionGapActions` in `Sources/SessionIndexView.swift`. Nothing in the tile writes `@Published` state from a body computation.
- Failure modes: content taller than the tile → internal scroll, tile never grows unbounded; missing data → an explicit empty state, never a blank tile.

**Acceptance Criteria**

- AC-2.5.a: `WidgetTile` declares no store reference of any form → neither a property wrapper (`@ObservedObject`/`@EnvironmentObject`/`@StateObject`/`@Bindable`) **nor** a plain property typed as a store (`let`/`var` whose type ends in `Store`, `Manager`, `Model`, or `Panel`). `CLAUDE.md` forbids both below a list boundary, so a wrapper-only grep is insufficient.
- AC-2.5.b: Both styles report their documented minimum intrinsic sizes.
- AC-2.5.c: The tile resolves colors from the injected appearance, not literals → no hardcoded `Color(red:green:blue:)` or `.white`/`.black` fill in the file.
- AC-2.5.d: `swift test --package-path Packages/macOS/StokdWidgetKit --filter WidgetTileTests` → exit 0.
- AC-2.5.e: Overflowing content scrolls rather than expanding the tile → a tile given 100 rows reports the same declared height as one given 1 row.

### 2.6: Dockable registration + snapshot payloads

**Implementation Details**

- Add two `DockableKind` cases in `Packages/macOS/CmuxDockable/Sources/CmuxDockable/DockableKind.swift`: `stokdConfigWidget`, `stokdTokenUsageWidget`. `DockableKind` is `CaseIterable` (unlike the legacy `PanelType`), so the parity tests added by the refactor (`DockableKindParityTests`, `DockableKindsMatrixTests`) will pick them up automatically — confirm they do rather than assuming.
- Add two panel classes under `Sources/Panels/Stokd/`: `StokdConfigWidgetPanel`, `StokdTokenUsageWidgetPanel`. Each conforms to `Dockable` (and `Panel` for as long as both protocols coexist), supplying `dockableKind`, `dockableTitle`, `makeDockContentView(context:)`, and `encodeDockPayload()`. Model them on `WorkspaceTodoPanel` (`Sources/Panels/WorkspaceTodoPanel.swift`, 64 lines — the minimum viable panel) for shape, and on `ProjectPanel` (`Sources/Panels/ProjectPanel.swift`) for its explicit load-state enum, which both widgets need:

  ```swift
  public enum StokdWidgetLoadState: Sendable, Equatable { case idle, loading, loaded, failed(String) }
  ```

- **Singleton semantics**, per `docs/gdock-side-controls-iteration.md` ("Singleton: one of each kind; shortcut = focus or create that one"). Add open-or-focus factories in a new `Sources/Workspace+StokdWidgetPanes.swift` (a separate file because `Sources/Workspace.swift` is at its length budget — the same reason `Workspace+TodoPane.swift` exists):

  ```swift
  @discardableResult func openOrFocusStokdConfigWidget(inPane paneId: PaneID, focus: Bool = true) -> StokdConfigWidgetPanel?
  @discardableResult func openOrFocusStokdTokenUsageWidget(inPane paneId: PaneID, focus: Bool = true) -> StokdTokenUsageWidgetPanel?
  ```

  Each mirrors `openOrFocusWorkspaceTodoSurface`: create the bonsplit tab with a `SurfaceKind`, `bindSurface(_:toPanelId:)`, then `publishCmuxSurfaceCreated(...)`. Add two `SurfaceKind` constants in `Packages/macOS/CmuxWorkspaces/.../Values/SurfaceKind.swift`.
- **Persistence.** Under the Dockable shape a kind carries an opaque `DockableSnapshot.payload`, so no new optional field is added to `SessionPanelSnapshot`. Payloads:
  - `StokdConfigWidgetPayload { group: String?, searchQuery: String?, scopePreference: String }`
  - `StokdTokenUsageWidgetPayload { timespan: String, groupByProvider: Bool, expandedProviders: [String] }`
  Both `Codable`. Round-trip through the legacy decoder path (`Sources/SessionPanelSnapshot+DockableCodec.swift`) must be verified, since that codec is what keeps pre-refactor session files loadable.
- **Feature gate.** Both widgets are constructible only when `stokd.widgets.enabled` is `true` in `~/.config/cmux/cmux.json`. Add a `stokd` section to `Sources/CmuxConfig.swift` carrying `widgets.enabled` (default `false` until Phase 4 flips it). This work item gates exactly two things — **the open-or-focus factories and session restore** — because those are the only construction paths that exist in Phase 2. A session file naming a disabled widget must restore as absent, not crash. Gating the palette, shortcut, and socket entrypoints is deliberately **not** in scope here: those surfaces are created in 4.1 and are gated there by AC-4.1.f. Specifying them now would make this item's criteria untestable against a phase that has not run.
- Add the two `SurfaceKind` constants explicitly: `SurfaceKind.stokdConfigWidget` (raw value `"stokdConfigWidget"`) and `SurfaceKind.stokdTokenUsageWidget` (raw value `"stokdTokenUsageWidget"`), in `Packages/macOS/CmuxWorkspaces/Sources/CmuxWorkspaces/Core/Values/SurfaceKind.swift`.
- New test files must be wired into `cmux.xcodeproj/project.pbxproj` (`PBXFileReference` + `PBXSourcesBuildPhase`). An unwired test file compiles nowhere and reports "Executed 0 tests" while appearing to pass — the exact failure `scripts/lint-pbxproj-test-wiring.sh` exists to catch.
- Failure modes: a `DockableKind` case added without a factory arm (caught by the refactor's `DockableRegistrationTests`); payload schema change without a decoder (round-trip test); gate off but palette entry visible (gate test).

**Acceptance Criteria**

- AC-2.6.a: Both `DockableKind` cases exist and appear in `allCases` → the refactor's parity/matrix suites cover them with no manual list edit.
- AC-2.6.b: Both panel classes exist → `for c in StokdConfigWidgetPanel StokdTokenUsageWidgetPanel; do grep -rq "class $c" Sources/Panels/Stokd/ || exit 1; done` exits 0.
- AC-2.6.c: Open-or-focus is singleton → calling the factory twice in one workspace yields the same panel id and does not create a second surface.
- AC-2.6.d: Both payloads round-trip through `DockableSnapshot` unchanged, including through the legacy codec path.
- AC-2.6.e: With `stokd.widgets.enabled` false, both open-or-focus factories return nil and session restore of a snapshot naming either kind produces no panel and does not crash.
- AC-2.6.f: `grep -q 'widgets' Sources/CmuxConfig.swift` exits 0 (the gate key is a real config key, not a literal sprinkled at call sites).
- AC-2.6.g: Both `SurfaceKind` constants exist → `grep -q 'stokdConfigWidget' Packages/macOS/CmuxWorkspaces/Sources/CmuxWorkspaces/Core/Values/SurfaceKind.swift` exits 0.
- AC-2.6.h: `./scripts/lint-pbxproj-test-wiring.sh` and `./scripts/check-pbxproj.sh` → both exit 0 (every new test file is actually compiled; objectVersion pin and normalization preserved).
- AC-2.6.i: The app-host suites run and are **non-empty** → the `xcodebuild ... test` invocation exits 0 **and** its output does not contain `Executed 0 tests`. Checking exit status alone is insufficient: an unwired test file makes xcodebuild report `Executed 0 tests` while still exiting 0, which is exactly the vacuous pass `scripts/lint-pbxproj-test-wiring.sh` exists to prevent, so the executed-count assertion is made explicitly in the verification block.


---

# Phase 3: Widget implementations

**Project:** Stokd Widgets: Global Config + Per-Model Token Usage
**Slug:** stokd-widgets-global-config-per-model-token-usage
**Review Mode:** complete

## Work Items

### 3.1: Active-window cwd → config scope context

**Implementation Details**

- Add `Sources/Panels/Stokd/StokdWidgetContextResolver.swift`. This is the mechanism behind "leverage the cwd of whatever the active window is to provide the context to show the right things in all cases."
- Resolution chain, in order, reusing the existing accessors rather than inventing one: `AppDelegate.activeTabManagerForCommands(preferredWindow:)` (`Sources/AppDelegate+ShortcutRoutingWindow.swift:36`, which already falls back key-window → `NSApp.mainWindow` → live context → any live context) → `TabManager.selectedWorkspace` (`Sources/TabManager.swift:756`) → `Workspace.currentDirectory` (`Sources/Workspace.swift:2161`).
- Prefer the **focused surface's** reported directory when available — `Workspace.reportedPanelDirectory(panelId:)` (`Sources/Workspace+SidebarDirectories.swift:48`) for `focusedPanelId` (`Sources/Workspace.swift:2330`) — falling back to `Workspace.currentDirectory`. A workspace with several terminals in different repos should reflect the one the user is actually in.
- **Reactivity.** Observe with a `Publishers.MergeMany` exactly as `RightSidebarToolPanel.observeWorkspaceRootChanges(_:)` does (`Sources/RightSidebarToolPanel.swift:170`) — merging `workspace.$currentDirectory` (`Sources/Workspace.swift:2161`), `workspace.$panelDirectories` (`Sources/Workspace.swift:2367`), and `workspace.currentDirectoryChangeRevisionPublisher()`. **The merge is mandatory, not belt-and-braces:** `currentDirectoryChangeRevisionPublisher()` (`Sources/Workspace+SidebarDirectories.swift:118`) filters on `presentedDirectoryOnly == true`, but the `currentDirectory` `didSet` posts `userInfo: ["workspaceId": id]` **without** that key, so that publisher alone never fires for the ordinary cwd-change path.
- Also react to the active *window* changing (not just the cwd within a window): observe `NSWindow.didBecomeKeyNotification` and re-resolve. A widget in window A must show A's context while A is focused, even though the pane itself lives in one window — the requirement is "the active window", so a widget mounted in a non-key window renders the key window's context and labels which workspace it is reporting on.
- Emit an explicit context value so the UI can always say what it is showing:

  ```swift
  public struct StokdConfigContext: Sendable, Equatable {
      public let workspaceId: UUID?
      public let cwd: URL?
      public let workspaceConfigPath: URL?   // nil when no <ws>/.stokd/config.yaml exists
      public let repoSlug: String?
  }
  ```

- `workspaceConfigPath` comes from `StokdWorkspaceConfigLocator` (1.3). When nil, the widget shows global values with an explicit "no workspace config — writes will create `<cwd>/.stokd/config.yaml`" affordance rather than silently writing globally.
- All state changes happen in the `.sink`, never in a body computation, per the `CLAUDE.md` no-mutation-in-body rule.
- Failure modes: no windows (resolver returns an empty context, widget shows global-only); cwd inside a deleted dir (locator nil, banner shown); rapid window switching (coalesce to the trailing resolution).

**Acceptance Criteria**

- AC-3.1.a: The resolver returns the key window's workspace context, not the pane's host window's, when they differ.
- AC-3.1.b: Focused-surface directory wins over workspace `currentDirectory` when both are present and differ.
- AC-3.1.c: Observation merges all three publishers → `grep -q 'MergeMany' Sources/Panels/Stokd/StokdWidgetContextResolver.swift` exits 0 and the file references `$currentDirectory`.
- AC-3.1.d: A cwd change with no `presentedDirectoryOnly` key still updates the context → the regression that `currentDirectoryChangeRevisionPublisher()` alone would miss.
- AC-3.1.e: With no `<ws>/.stokd/config.yaml`, `workspaceConfigPath` is nil and the resolved write target is `<cwd>/.stokd/config.yaml`.
- AC-3.1.f: No `@Published` write occurs inside a body computation → `! grep -nE 'var body' -A 40 Sources/Panels/Stokd/StokdWidgetContextResolver.swift | grep -qE 'self\.[a-zA-Z]+ = |Task \{ @MainActor'` exits 0.
- AC-3.1.g: `xcodebuild ... -only-testing:cmuxTests/StokdWidgetContextResolverTests test` → exit 0.

### 3.2: Global Config widget view

**Implementation Details**

- Add `Sources/Panels/Stokd/StokdConfigWidgetView.swift`, rendered inside `WidgetTile`.
- Layout: header shows the resolved context (workspace name + short cwd) and a scope control; primary metric slot shows the count of keys overridden at the current scope; detail region is a grouped, searchable field list. With 74 fields across 23 groups, the tile opens on a **group summary** (group name + override count) and drills into one group — a flat 74-row list is unusable at tile size.
- Fields render by descriptor `type`: `.boolean` → toggle; `.enum` → picker over `enumValues`; `.number` → numeric field with validation; `.string` → text field; `.stringArray` → token/CSV editor; `.object` → **read-only** with an "open in editor" affordance, because the writer verb accepts one positional scalar/CSV value; `.unsupported` → read-only.
- Each row shows a **provenance badge** from `StokdLayeredValue.origin` (default / global / workspace) and, when overridden, a revert affordance calling the unset verb at that scope.
- **Scope control.** Default write scope is `workspace`. Switching to `global` requires an explicit confirmation naming the file, because `~/.stokd/config.yaml` reshapes behavior across every repo and session. Fields whose descriptor `scope` is `.global` (3 of 74) are workspace-disabled with an explanatory label. A `secret: true` field renders masked and non-editable (0 today, but the descriptor carries the flag).
- **Write path.** Every mutation calls `StokdConfigWriter` (1.3) with `workingDirectory` = the resolved context cwd. On success, re-read the affected layer and re-derive the row — do not optimistically assume the written value landed, since the CLI's validators may normalize it. On failure, keep the edit in the field, surface the CLI's verbatim stderr inline, and leave the row dirty. Per the `CLAUDE.md` shared-behavior rule there is exactly **one** mutation path; no per-row optimistic copy.
- **List discipline.** The field list is a `LazyVStack`, so every row receives an immutable value snapshot plus a closure action bundle — no row holds a store reference, per the snapshot-boundary rule. The bundle is declared explicitly:

  ```swift
  struct StokdConfigRowActions: Sendable {
      let write: @MainActor (_ key: String, _ value: StokdConfigValue) -> Void
      let revert: @MainActor (_ key: String) -> Void
      let copyKey: @MainActor (_ key: String) -> Void
      let revealInFile: @MainActor (_ key: String) -> Void
  }
  ```

- **Deterministic ordering** (so two implementations agree): groups are ordered by the descriptor array's own order as emitted by the CLI, not alphabetically, because that order is already curated; within a group, fields keep descriptor order. Search spans **all** groups and, while a query is active, replaces the group-summary view with a flat result list; clearing the query returns to the group summary. Drill-down is one level deep with a single back affordance to the summary.
- All labels/descriptions come from the descriptor (already English text from the CLI). Widget **chrome** strings — title, scope labels, confirmation copy, error framing, empty states — are cmux-owned UI and must be localized across all 20 locales in `Resources/Localizable.xcstrings`.
- Failure modes: schema fetch fails (error tile with retry, no partial form); write rejected (above); context has no workspace config (create-on-write affordance from 3.1); descriptor with an unknown type (read-only, never a crash).

**Acceptance Criteria**

- AC-3.2.a: Every descriptor `type` maps to a defined control, with `.object` and `.unsupported` read-only → no descriptor renders as an editable free-text field by accident.
- AC-3.2.b: Provenance badge matches `StokdLayeredValue.origin` for all three layer orderings.
- AC-3.2.c: Default write scope is workspace, and a global write requires explicit confirmation → an unconfirmed global write issues no CLI call.
- AC-3.2.d: Descriptor `scope == .global` fields are disabled under workspace scope.
- AC-3.2.e: A failed write preserves the pending edit and surfaces the CLI stderr verbatim; the row stays dirty.
- AC-3.2.f: A successful write re-reads the layer rather than trusting the submitted value.
- AC-3.2.g: No row view holds a store reference of any form → neither a property wrapper nor a plain store-typed (`*Store`/`*Manager`/`*Panel`) property, since `CLAUDE.md` forbids both below the `LazyVStack` boundary.
- AC-3.2.h: `xcodebuild ... -only-testing:cmuxTests/StokdConfigWidgetTests test` → exit 0.

### 3.3: Token Usage widget view

**Implementation Details**

- Add `Sources/Panels/Stokd/StokdTokenUsageWidgetView.swift`, rendered inside `WidgetTile`.
- Layout: header carries a four-way timespan selector (`24h` / `Week` / `Month` / `Total`); the primary metric slot shows total cost for the timespan with total tokens beneath; the detail region is a **provider → model** disclosure list. This is the specific gap in the existing extension view, which renders one flat row per model with no provider grouping — neither usage endpoint groups by provider (`getTokenUsage` groups by model and a derived work-item "workload"), so the widget joins provider itself from the ingest records.
- Every provider configured in the effective config appears, even with zero observed usage, in one of three explicit states: **observed** (a local transcript store exists and was read), **un-instrumented** (configured but no local store adapter — `droid`, `amp`, `bedrock`, `openrouter`, `lmStudio`, `devin`), or **idle** (store exists, no records in this timespan). A configured provider must never silently vanish.
- Per-model rows show the four dimensions separately (input / output / cache-read / cache-write) plus cost. Grok rows mark cache dimensions **unavailable** rather than `0`, since `usage_events` has no cache columns. Unpriced models show tokens with an `unpriced` marker and are excluded from the cost total, with a footer noting how many models were excluded — never a fabricated `$0.00` folded into a total.
- Models observed in transcripts but absent from `stokd model list` render tagged `unregistered`; models registered but unused render only under an explicit "show unused" toggle, so a 65-model bedrock registry does not bury actual usage.
- A dedicated `unknown` row appears whenever unattributed usage exists, with its share of the total. It is **per-provider**, not global — `TokenUsageKey` carries the provider, so unattributed Codex usage and unattributed Gemini usage are distinct rows and the user can tell which provider's attribution is degrading. Making this visible is the point: it beats a quietly-wrong breakdown.
- **Deterministic ordering:** providers sort by descending timespan cost, then by descending total tokens, then by name — so the expensive thing is first and the order is stable when costs tie or are absent. Models within a provider use the same comparator. Un-instrumented and idle providers sort last, after all observed ones. A model id observed under two different providers yields **two** rows (one per `TokenUsageKey`); they are never merged, since the same id can be served at different prices by different providers.
- Data flows from the 2.3 ingestor's published snapshot. The view **subscribes**; it owns no timer and performs no I/O. `LazyVStack` rows take value snapshots + closure bundles per the snapshot-boundary rule.
- Show a staleness indicator derived from the newest ingested record's timestamp, plus a manual refresh affordance (a user-initiated fold, not a recurring timer).
- Failure modes: no provider store present at all (empty state explaining that no local transcripts were found, listing where it looked); ingestor error (error tile with the failing root); API backfill unreachable at cold start (render live-only data with a "history unavailable" note).

**Acceptance Criteria**

- AC-3.3.a: Rows group provider → model, and every configured provider appears in exactly one of observed / un-instrumented / idle.
- AC-3.3.b: Grok cache dimensions render unavailable, not `0`.
- AC-3.3.c: Unpriced models are excluded from the cost total and counted in a footer → a fixture with one priced and one unpriced model shows only the priced model's cost in the total.
- AC-3.3.d: An `unknown` bucket with usage is rendered with its share, never dropped.
- AC-3.3.e: All four timespans re-derive from the same aggregate without re-reading files → switching timespans issues zero file opens.
- AC-3.3.f: The view owns no timer → `! grep -nE 'Timer\.scheduledTimer|Task\.sleep' Sources/Panels/Stokd/StokdTokenUsageWidgetView.swift` exits 0.
- AC-3.3.g: No row view holds a store reference of any form → neither a property wrapper nor a plain store-typed (`*Store`/`*Manager`/`*Panel`) property, since `CLAUDE.md` forbids both below the `LazyVStack` boundary.
- AC-3.3.h: `xcodebuild ... -only-testing:cmuxTests/StokdTokenUsageWidgetTests test` → exit 0.


---

# Phase 4: Entrypoints, localization, and rollout enablement

**Project:** Stokd Widgets: Global Config + Per-Model Token Usage
**Slug:** stokd-widgets-global-config-per-model-token-usage
**Review Mode:** complete

## Work Items

### 4.1: Entrypoints across every surface

**Implementation Details**

- Per the `CLAUDE.md` shared-behavior policy, every entrypoint funnels through **one** shared action layer. Add `Sources/StokdWidgetActions.swift`:

  ```swift
  @MainActor enum StokdWidgetActions {
      @discardableResult static func openConfigWidget(for workspace: Workspace, focus: Bool = true) -> StokdConfigWidgetPanel?
      @discardableResult static func openTokenUsageWidget(for workspace: Workspace, focus: Bool = true) -> StokdTokenUsageWidgetPanel?
  }
  ```

  Each resolves `bonsplitController.focusedPaneId` then calls the 2.6 open-or-focus factory — exactly the `WorkspaceTodoActions.openTodoPane` shape (`Sources/WorkspaceTodoFeature.swift`).
- Register at every surface, modeled on the `workspaceTodo` trace:
  - **Command palette:** contributions + handlers in a new `Sources/ContentView+StokdWidgetCommandPalette.swift`, using `CommandPaletteCommandContribution` and `registry.register(commandId:handler:)` with ids `palette.openStokdConfigWidget` and `palette.openStokdTokenUsageWidget`.
  - **Keyboard shortcuts:** two cases in `Sources/KeyboardShortcutSettings.swift` (enum case + label + dispatch arm). Per the shortcut policy each must also be editable in Settings, settable via `~/.config/cmux/cmux.json`, and documented in the keyboard-shortcut and configuration docs (`docs/configuration.md`).
  - **Socket/CLI:** verbs `workspace.stokd.configWidget.open` and `workspace.stokd.tokenUsage.open` in a new `Sources/TerminalController+ControlStokdWidgets.swift`. If either should be allowed to take focus, add it to `focusIntentV2Methods` in `Sources/TerminalController.swift:260` — otherwise it will silently fail to focus.
  - **Context menu / sidebar:** entries calling the shared actions.
  - **Session restore:** the 2.6 factories, gate-aware.
- Update `docs/cli-contract.md` and `docs/configuration.md` for the new verbs, shortcuts, and the `stokd.widgets.enabled` key.
- Failure modes: an entrypoint bypassing the shared action (duplicated logic — the exact thing the policy forbids); a socket verb absent from the focus allowlist; a shortcut added to the enum but not to Settings.

**Acceptance Criteria**

- AC-4.1.a: Every entrypoint routes through `StokdWidgetActions` → no call site constructs a widget panel or calls a factory directly outside `StokdWidgetActions` and session restore.
- AC-4.1.b: Both palette commands are registered and open the singleton pane.
- AC-4.1.c: Both shortcuts exist in `KeyboardShortcutSettings` and are Settings-editable.
- AC-4.1.d: Both socket verbs exist and are dispatched → `grep -q 'workspace.stokd.configWidget.open' Sources/TerminalController+ControlStokdWidgets.swift` exits 0.
- AC-4.1.e: Docs updated → `grep -q 'stokd.widgets.enabled' docs/configuration.md` exits 0.
- AC-4.1.f: All entrypoints are gate-aware → with the gate off, no palette entry, shortcut, or socket verb creates a widget.
- AC-4.1.g: `xcodebuild ... -only-testing:cmuxTests/StokdWidgetEntrypointTests test` → exit 0.

### 4.2: Localization audit + a real localization gate

**Implementation Details**

- Enumerate every user-facing string introduced by this PRD — widget titles, timespan labels, scope labels and the global-write confirmation, provenance badges, provider-state labels (observed / un-instrumented / idle), `unpriced` / `unregistered` / `unavailable` markers, empty states, error framing, palette titles and subtitles, shortcut labels, Settings rows — and add each to `Resources/Localizable.xcstrings` with translations for **all 20** locales: `ar bs da de en es fr it ja km ko nb pl pt-BR ru th tr uk zh-Hans zh-Hant`. `CLAUDE.md`'s "English and Japanese" claim is stale; the catalog carries 20 and 4,172 keys today.
- `defaultValue`, English fallback text, and CLI-supplied descriptor text do **not** count as localization. Descriptor `label`/`description` come from the CLI in English and are explicitly out of scope for translation — say so in the handoff rather than leaving it ambiguous.
- There is **no** localization CI gate in this repo (`ls scripts/ | grep -iE 'local|l10n|xcstrings'` is empty; no workflow references one). Since this PRD adds user-facing strings across 20 locales and the convention is otherwise unenforced, add `scripts/check-localization-coverage.py`: given a set of key prefixes (`stokdWidget.*`), assert every key has a non-empty translation for all 20 locales, exit 1 listing gaps. Wire it into the `workflow-guard-tests` job of `.github/workflows/ci.yml` alongside the other `check-*` guards.
- Run `rg` over changed Swift files for newly introduced bare English string literals in `Text(`/`Button(`/alert titles.
- Failure modes: a key added for `en` only (the new gate catches it); a locale key present but empty (gate treats empty as missing); a string hardcoded in a view (the `rg` sweep).

**Acceptance Criteria**

- AC-4.2.a: Every `stokdWidget.*` key has a non-empty value in all 20 locales.
- AC-4.2.b: `python3 scripts/check-localization-coverage.py --prefix stokdWidget` → exit 0.
- AC-4.2.c: The gate actually fails on a gap → removing one locale's value for one key makes the script exit non-zero.
- AC-4.2.d: The gate is wired into CI → `grep -q 'check-localization-coverage' .github/workflows/ci.yml` exits 0.
- AC-4.2.e: No bare English literal remains in the new views → an `rg` sweep of `Text("`/`Button("` over the files added by Phase 3 and 4.1 returns no hits.
- AC-4.2.f: `python3 -c "import json; d=json.load(open('Resources/Localizable.xcstrings')); ks=[k for k in d['strings'] if k.startswith('stokdWidget.')]; assert ks, 'no stokdWidget keys'; print(len(ks))"` → exit 0, printing the key count.

### 4.3: Upstream PR submission, gate default, and final green

**Implementation Details**

- **Upstream submission** for the single upstreamable unit (2.2, `JSONLTailReader`):
  - There is currently **no `upstream` git remote** — only `origin` → `git@github.com:stokd-cloud/ghostty-dock.git`. The maintainer must add `manaflow-ai/cmux` as a remote; this PRD does not add or modify remotes.
  - Branch from `origin/upstream-main` (the pristine mirror maintained by `.github/workflows/sync-upstream.yml`, Model B), cherry-pick only the 2.2 commit — `Packages/macOS/CmuxFoundation/.../JSONLTailReader.swift` plus its tests — and confirm the diff contains no stokd identifier and no `StokdWidgetKit` reference. Read `CONTRIBUTING.md` and `.github/PULL_REQUEST_TEMPLATE*` if present and conform.
  - Frame it as generic FileWatch infrastructure. Do not mention stokd, widgets, or token usage.
- **Fork-only diff hygiene:** confirm no fork-only change leaked into the upstream branch, and that `docs/ghostty-fork.md` records the new fork-only surface area per the fork-doc convention.
- **Flip the gate default** `stokd.widgets.enabled` to `true` in `Sources/CmuxConfig.swift`. This is the last functional change in the PRD.
- Add a `CHANGELOG.md` entry.
- **Full green:** run every CI gate that touches this work — pbxproj wiring and normalization, workspace groups, lockfile policy, feature-flag lint, test determinism, the new localization gate, the `StokdWidgetKit` and `CmuxFoundation` package tests, and the full app-host suite for the new test classes.
- Failure modes: upstream branch contaminated with fork code (grep guard); gate flipped before the suites are green (ordering); a new package still absent from the CI `PACKAGES` array (1.1's AC, re-verified here since the array is easy to lose in a rebase).

**Acceptance Criteria**

- AC-4.3.a: The upstream branch is **prepared by this work item** (it does not pre-exist) and its diff is stokd-free → after creating `upstream/jsonl-tail-reader` from `origin/upstream-main` and cherry-picking only the 2.2 commit, `git diff origin/upstream-main --name-only` lists exactly `Packages/macOS/CmuxFoundation/Sources/CmuxFoundation/FileWatch/JSONLTailReader.swift` plus its test file, and `git diff origin/upstream-main | grep -ci stokd` returns 0. The verification block below creates the branch, so the command is runnable at verification time rather than assuming prior state.
- AC-4.3.b: `stokd.widgets.enabled` defaults to `true` → `grep -q 'widgets' Sources/CmuxConfig.swift` and the default-value test asserts `true`.
- AC-4.3.c: `CHANGELOG.md` contains an entry naming both widgets.
- AC-4.3.d: `docs/ghostty-fork.md` records the fork-only surface added here.
- AC-4.3.e: Every workflow-guard gate passes: `./scripts/lint-pbxproj-test-wiring.sh`, `./scripts/check-pbxproj.sh`, `python3 scripts/check-workspace-package-groups.py --check`, `python3 scripts/check-package-resolved-policy.py`, `python3 scripts/lint-feature-flags.py`, `python3 scripts/check-test-determinism.py --strict`, `python3 scripts/check-localization-coverage.py --prefix stokdWidget` → all exit 0.
- AC-4.3.f: Both package test suites pass: `swift test --package-path Packages/macOS/StokdWidgetKit` and `swift test --package-path Packages/macOS/CmuxFoundation` → exit 0.
- AC-4.3.g: The full app-host suite for this work passes with a non-zero executed-test count across all seven new test classes.
- AC-4.3.h: A tagged Debug build succeeds → `./scripts/reload.sh --tag stokd-widgets` exits 0 (with `CMUX_SKIP_ZIG_BUILD=1`, required in this environment because host zig 0.16.0 does not match the ghostty 0.15.2 pin).

