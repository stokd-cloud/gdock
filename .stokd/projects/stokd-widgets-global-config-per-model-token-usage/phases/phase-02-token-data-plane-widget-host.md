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

