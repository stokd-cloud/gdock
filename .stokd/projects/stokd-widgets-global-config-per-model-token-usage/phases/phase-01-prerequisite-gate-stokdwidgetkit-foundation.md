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

