# Brand Identity De-hardcoding for Fork Rebranding

## 0. Source Context

**Derived From:** "Simplify fork rebranding. cmux is reused code from everywhere; the least they could do would be to land a PR that reduced the amount of times the word `cmux` was hard coded throughout the codebase. When attempting my rebrand I have to jump through hoops in order to configure my pipeline where I can take downstream changes and also do my own thing. It found like 79k instances. We should identify the different contexts in which it is used — application name vs CLI vs ENV prefix etc. — and be able to update a couple different things and generate the exact same build afterwards."

**Feature Name:** Brand Identity De-hardcoding
**PRD Owner:** Brian Stoker (`stokd-cloud/ghostty-dock`)
**Last Updated:** 2026-07-28
**Revision:** 2 — revised after a three-lens adversarial review; see §5 for the defect log.
**Upstream:** `manaflow-ai/cmux` · **Fork:** `stokd-cloud/ghostty-dock`

### Summary

The literal token `cmux` appears **94,010 times across 5,310 files**. That figure is exactly reproducible at commit `6e788a05f3` with:

```bash
rg -oi 'cmux' --hidden -g '!.git' -g '!ghostty/**' -g '!vendor/**' . | wc -l   # 94010
rg -li 'cmux' --hidden -g '!.git' -g '!ghostty/**' -g '!vendor/**' . | wc -l   # 5310
```

Those occurrences are not one thing. They are at least a dozen structurally distinct identity contexts: product display name, macOS bundle-ID root, iOS bundle-ID root, CLI binary name, `CMUX_*` environment prefix, config directory, runtime state directory, socket path, URL scheme, exported UTType root, os_log subsystem, keychain service, ExtensionKit extension-point ID, Sparkle feed URL, package/registry names, and localized prose. Today a fork must find and edit all of them by hand, and there is no way to prove the result is equivalent to an unmodified build.

This PRD introduces a single brand manifest plus a code generator, migrates the *identity* contexts (not the prose, not the internal symbol names) to consume it, and adds an executable build-equivalence gate so a rebrand is provably a no-op when the manifest holds current values. It is written so the bulk of the work lands as **upstream PRs** that benefit every fork, with only manifest values and fork-sync plumbing staying fork-only.

Critically, this is **not** a mass rename. Every default in the manifest is exactly today's value, so a correct implementation changes the built product's identity surface by zero bytes. That property is the primary acceptance gate, not a nice-to-have.

### Grounded findings this PRD is built on

- **Existing seams already prove the concept.** `scripts/reload.sh` already rewrites app name, bundle ID, socket path, URL scheme, and ~15 `LSEnvironment` keys per `--tag` via `xcodebuild` arguments and `PlistBuddy`. `ios/Config/Shared.xcconfig` and `ios/Config/Release.xcconfig` already drive `ios/Config/Info.plist` entirely through `$(...)` substitution. The macOS side is the outlier.
- **No single source of truth exists.** A repo-wide search for `BrandConfig`, `AppConstants`, or `AppIdentity` returns zero hits. Identity is split between build settings and unrelated Swift string literals.
- **There is no root `Package.swift`.** `Sources/` is a plain Xcode native-target source group. The five native targets are `cmux`, `cmux-cli`, `CmuxDockTilePlugin`, `cmuxTests`, `cmuxUITests`. SwiftPM packages under `Packages/` are consumed through `XCLocalSwiftPackageReference` entries. This shapes Phase 2 decisively — see §5, Defect 1.
- **Six distinct bundle-ID literals exist in the project file,** not one: the `com.cmuxterm` root appears as `.app`, `.app.debug`, `.app.docktileplugin`, `.app.docktileplugin.debug`, `.apptests`, and `.appuitests`. Any verification that anchors on a single exact form is nearly vacuous — see §5, Defect 3.
- **A prior rename in this codebase was never fully propagated.** `ai.manaflow.cmux` (a former bundle ID) survives as an os_log subsystem in **11 live, non-test files**, including `Sources/VaultAgentRegistry.swift:392`, four files under `Packages/Shared/CmuxAuthRuntime`, and four under `Packages/iOS/CmuxMobileTerminal` (as `ai.manaflow.cmux.ios`). A stale `ai.manaflow.cmuxterm.plist` path also persists in `homebrew-cmux/Casks/cmux.rb:23` and `scripts/build-sign-upload.sh:191`, matching no bundle ID this repo currently produces — so the cask's preference cleanup is already silently broken. This PRD's inventory tool exists specifically so that class of failure cannot recur silently.
- **There is a precedent to follow.** Commit `d675f0a0e3` ("rebrand: mux -> cmux-tui (#7710)") renamed a whole subproject: it kept the wire protocol version stable, shipped dual-read env/config fallbacks rather than a hard cutover, deliberately left trusted-publisher-pinned CI workflow filenames untouched, and claimed a "grep audit clean" as its verification step. This PRD generalises that last step into a committed, CI-enforced tool.
- **No reproducibility check exists today.** Nothing in the repo compares two builds. Artifact-level integrity checks do exist (`shasum` pinning of the GhosttyKit xcframework, `otool` SDK assertions, `codesign -d --entitlements` assertions), which is the pattern the new equivalence gate imitates.

## 1. Objectives & Constraints

### Objectives

- Define a closed, documented taxonomy of the identity contexts `cmux` occupies, with a committed, machine-readable census so the count can be tracked rather than guessed.
- Introduce exactly one file a fork edits to rebrand the identity surface, with generated per-language constants so no consumer hardcodes a brand token.
- Guarantee, by executable check, that with default manifest values the built app's identity surface is byte-identical to a pre-change build.
- Keep the upstream-facing change set PR-sized, self-contained, and free of fork-specific content.
- Close the currently-undefined `upstream-main` to `main` ingest path so the fork can actually consume downstream changes — the stated motivation.

### Constraints

- **No behavioural change.** Defaults equal current values. Any diff in the built identity surface is a defect, not a trade-off.
- **Localized prose is out of scope.** `Resources/Localizable.xcstrings` (~2,842 `cmux` hits) and the 20 `web/messages` catalogues (1,117–1,422 hits each) contain product-name *prose*, not identifiers. Touching them triggers `.github/review-bot-rules/full-internationalization.md`, which requires complete translations for every locale in the same PR. Prose is inventoried and categorised but not migrated here.
- **Internal symbol names are out of scope.** Existing Swift module names (`CmuxCore`, `CmuxSettings`, …), Xcode target names, and directory names stay. Renaming them would make every upstream ingest a mass-conflict event, which is the exact cost this PRD exists to avoid.
- **Registry-bound and trust-bound names must not move.** npm/PyPI/crates names, the Homebrew cask, and OIDC trusted-publisher workflow filenames are left alone, per the `#7710` precedent.
- **Sparkle keys are cryptographic, not cosmetic.** `SUPublicEDKey` is a real Ed25519 public key bound to the maintainers' private key. A fork needs its own keypair; renaming never substitutes for re-keying.
- **Review-bot compatibility.** `.github/review-bot-rules/no-ambient-global-state.md` flags new static/global namespaces and `.github/review-bot-rules/swift-architectural-rethink.md` flags compat shims that paper over a missing single source of truth. The generated type is a single source of truth, which those rules ask for, and every compat fallback carries a stated removal criterion at its call site.
- **CI is currently `workflow_dispatch`-only.** `.github/workflows/ci.yml` is explicitly paused for PRs and pushes. New guards are wired into the existing `workflow-guard-tests` job so they activate when CI resumes, and every guard must also be runnable locally.
- **Upstream governs its own PR conventions.** `.github/pull_request_template.md` and `.github/review-bot-rules/` belong to this repository. A PR opened against `manaflow-ai/cmux` is governed by *that* repository's template and bot configuration. Upstream PR descriptions must not paste this fork's bot-mention block.

## 1.5 Required Toolchain

| Tool | Min Version | Install Command | Verify Command |
|------|-------------|-----------------|----------------|
| Xcode | per `.xcode-version` | Apple Developer downloads | `cat .xcode-version && xcodebuild -version` |
| Python | 3.11 | `brew install python@3.11` | `python3 --version` |
| Bun | 1.1 | `brew install oven-sh/bun/bun` | `bun --version` |
| Zig | per `ghostty` submodule pin | `brew install zig` | `zig version` |
| ripgrep | 14 | `brew install ripgrep` | `rg --version` |
| GitHub CLI | 2.40 | `brew install gh` | `gh --version` |
| actionlint | 1.7 | `brew install actionlint` | `actionlint --version` |

Note: `scripts/reload.sh` requires `CMUX_SKIP_ZIG_BUILD=1` on hosts whose Zig is newer than the `ghostty` submodule pin; every reload invocation below sets it.

## 2. Execution Phases

## Phase 1: Census and Taxonomy

**Purpose:** Nothing downstream can be scoped, sized, or proven without a measurement instrument. The category set produced by work items 1.1 and 1.2 literally determines the key set of the Phase 2 manifest, so authoring that manifest earlier would mean guessing. This phase writes no product code and can land first with zero risk. Work item 1.3 does not gate Phase 2 and may proceed in parallel with it.

### 1.1 Brand occurrence inventory tool

**Landing:** upstream-PR

**Implementation Details**
- Create `scripts/brand-inventory.py` (new file), a dependency-free Python 3.11 script.
- It walks the repo from the git root, excluding: `.git/`, `ghostty/`, `vendor/bonsplit/`, `homebrew-cmux/`, `node_modules/`, `.build/`, `build-universal/`, `DerivedData/`, and any path matched by `git check-ignore`. The three excluded submodules are excluded because they are separately-owned repositories; `vendor/stack-auth-swift-sdk-prerelease/` is *not* excluded and is counted (it currently contributes zero hits). This list matches the Summary's stated methodology exactly.
- For every case-insensitive match of `cmux` it emits one record: `path`, `line`, `column`, `matched_text`, `category`, `subcategory`.
- Classification is rule-driven and ordered; the first matching rule wins. Rules are declared as a **single literal table assigned once at module top level** so a reviewer can read the whole taxonomy in one screen. Categories are exactly those enumerated in work item 1.2.
- Any occurrence matching no rule is assigned `unclassified`. That is a first-class output, not an error — the tool's honesty depends on it being visible.
- Modes: default prints a per-category summary to stdout; `--tsv <path>` writes the full per-occurrence record set sorted by `(category, path, line)`; `--json` writes the summary as JSON; `--summary-tsv <path>` writes the **per-category count table only** (one row per category, ~23 rows) — this is the format committed as the baseline in 1.3, *not* the ~94k-row full dump; `--check <baseline.tsv>` compares per-category counts against a summary baseline and exits 1 if any category increased.
- Failure modes: non-UTF-8 files decode with `errors="replace"` and never crash; binary files skipped via null-byte sniff; symlinks not followed; a missing baseline in `--check` mode exits 2 with a distinct message, not 1.
- Output is deterministic: sorted paths, `LC_ALL=C` ordering, no timestamps, no absolute paths.

**Acceptance Criteria**
- AC-1.1.a: The rule table is a single literal assignment at module top level → a reviewer can enumerate every category without reading the walk logic.
- AC-1.1.b: The classifier returns the expected category for a fixture line representing each category → classification is correct, not merely present.
- AC-1.1.c: Two consecutive runs on the same tree produce byte-identical TSV output → usable as a committed baseline.
- AC-1.1.d: `python3 scripts/brand-inventory.py --json` → exit 0, valid JSON, `total` greater than 90000.
- AC-1.1.e: `python3 scripts/brand-inventory.py --check /nonexistent.tsv` → exit 2, not 1 or 0.
- AC-1.1.f: No output record has a path under `ghostty/`, `vendor/bonsplit/`, or `homebrew-cmux/` → excluded submodules genuinely excluded.
- AC-1.1.g: `--summary-tsv` output has fewer than 40 lines → the committed baseline is a summary, not a full dump.

**Acceptance Tests**
- Test-1.1.a: Unit — grep the module for exactly one rule-table assignment at top level.
- Test-1.1.b: Unit — feed one fixture line per category to the classifier, assert the returned category.
- Test-1.1.c: Regression — run twice, `diff` the TSVs, assert empty.
- Test-1.1.d: Integration — parse `--json`, assert `total > 90000`.
- Test-1.1.e: Unit — `--check` with a missing path, assert exit 2.
- Test-1.1.f: Integration — assert no record path starts with an excluded submodule prefix.
- Test-1.1.g: Unit — count lines of `--summary-tsv`, assert under 40.

**Verification Commands**
```bash
python3 scripts/brand-inventory.py --json > /tmp/bi.json   # (new file)
python3 -c "import json; d=json.load(open('/tmp/bi.json')); assert d['total']>90000, d['total']"
python3 scripts/brand-inventory.py --tsv /tmp/a.tsv && python3 scripts/brand-inventory.py --tsv /tmp/b.tsv   # (new file)
diff -q /tmp/a.tsv /tmp/b.tsv
! rg -q '^(ghostty|vendor/bonsplit|homebrew-cmux)/' /tmp/a.tsv
python3 scripts/brand-inventory.py --summary-tsv /tmp/s.tsv && test "$(wc -l < /tmp/s.tsv)" -lt 40   # (new file)
python3 scripts/brand-inventory.py --check /nonexistent.tsv; test $? -eq 2   # (new file)
```

### 1.2 Identity taxonomy document

**Landing:** upstream-PR

**Implementation Details**
- Create `docs/brand-identity.md` (new file) defining every category the tool emits. For each: a one-line definition, whether it is compile-time or runtime, whether it is a cross-process contract, whether it is externally published, and whether this PRD migrates it. Non-migrated categories carry an explicit `reason:` field.
- The closed category set is: `product-name`, `bundle-id-macos`, `bundle-id-ios`, `cli-binary`, `daemon-binary`, `env-prefix`, `config-path`, `state-path`, `socket-path`, `url-scheme`, `uttype`, `log-subsystem`, `keychain-service`, `extension-point-id`, `update-feed`, `package-registry-name`, `swift-module-name`, `xcode-target-name`, `localized-prose`, `docs-and-marketing`, `test-fixture`, `ci-workflow-name`, `unclassified`.
- It must record the three coexisting identifier roots and characterise `ai.manaflow.cmux` explicitly as **residue from an incomplete prior rename**, citing the live non-test occurrences (`Sources/VaultAgentRegistry.swift:392` and the `Packages/Shared/CmuxAuthRuntime` files) rather than any test fixture. A parser-test fixture that happens to contain the string is not evidence and must not be cited as such.
- It must document the cross-process contract subset explicitly: which env vars and paths the app, the CLI, `cmuxd`, and the TUI must agree on.

**Acceptance Criteria**
- AC-1.2.a: Every category string emitted by the inventory tool has a corresponding heading in the document → tool and doc cannot drift.
- AC-1.2.b: The document names all three identifier roots and characterises `ai.manaflow.cmux` with explicit "prior rename" residue framing, not a bare mention.
- AC-1.2.c: Each non-migrated category carries a non-empty `reason:` field.
- AC-1.2.d: The document cites at least one live non-test file for the `ai.manaflow.cmux` claim.
- AC-1.2.e: The tool-to-doc category cross-check exits 0.

**Acceptance Tests**
- Test-1.2.a: Integration — extract category names from the tool's JSON and headings from the doc, assert set equality.
- Test-1.2.b: Unit — assert all three roots present and assert "prior rename" framing appears within the same section as `ai.manaflow.cmux`.
- Test-1.2.c: Unit — assert every `migrated: no` entry has a non-empty `reason:`.
- Test-1.2.d: Unit — assert `VaultAgentRegistry.swift` or a `CmuxAuthRuntime` path is cited.
- Test-1.2.e: Regression — the cross-check runs in CI so adding a tool category without documenting it fails.

**Verification Commands**
```bash
test -f docs/brand-identity.md   # (new file)
rg -q 'com\.cmuxterm\.app' docs/brand-identity.md   # (new file)
rg -q 'dev\.cmux\.ios' docs/brand-identity.md   # (new file)
rg -q 'prior rename' docs/brand-identity.md   # (new file)
rg -q 'VaultAgentRegistry|CmuxAuthRuntime' docs/brand-identity.md   # (new file)
python3 scripts/brand-inventory.py --json > /tmp/bi.json   # (new file)
python3 -c "
import json,re,sys
d=json.load(open('/tmp/bi.json')); doc=open('docs/brand-identity.md').read()
missing=[c for c in d['categories'] if not re.search(r'^#+\s.*'+re.escape(c), doc, re.M)]
print('missing:', missing); sys.exit(1 if missing else 0)"
```

### 1.3 Committed baseline and non-increase ratchet

**Landing:** upstream-PR

**Implementation Details**
- Generate and commit `scripts/brand-inventory-baseline.tsv` (new file) using `--summary-tsv` — the per-category count table (~23 rows), not the full per-occurrence dump. A 94k-row file would not be reviewable in a PR and would undercut the very claim this work item makes.
- Create `tests/test_ci_brand_inventory_ratchet.sh` (new file) invoking the tool in `--check` mode, following the wrapper convention of `tests/test_ci_pbxproj_test_wiring.sh`.
- Wire it into the `workflow-guard-tests` job in `.github/workflows/ci.yml` alongside the other guard steps.
- The ratchet is **non-increase**, not equality: a category count may fall freely, but may not rise. Later phases reduce counts without a baseline update on every commit, while new hardcoding is blocked.
- Document baseline regeneration and when it is legitimate in `docs/brand-identity.md`.

**Acceptance Criteria**
- AC-1.3.a: The baseline is tracked by git and has fewer than 40 lines → reviewable in diffs.
- AC-1.3.b: `./tests/test_ci_brand_inventory_ratchet.sh` → exit 0 on the unmodified tree.
- AC-1.3.c: Introducing a new hardcoded `cmux` token in a migrated category makes the ratchet exit 1 → the guard is not vacuous.
- AC-1.3.d: `.github/workflows/ci.yml` contains a `workflow-guard-tests` step invoking the ratchet script.

**Acceptance Tests**
- Test-1.3.a: Unit — `git ls-files --error-unmatch` on the baseline, and a line count assertion.
- Test-1.3.b: Integration — ratchet on a clean tree, exit 0.
- Test-1.3.c: Regression — add a scratch Swift file carrying a bundle-ID literal, re-run, assert exit 1, then remove it. This is the red proof.
- Test-1.3.d: Unit — grep the workflow for the script name.

**Verification Commands**
```bash
git ls-files --error-unmatch scripts/brand-inventory-baseline.tsv   # (new file)
test "$(wc -l < scripts/brand-inventory-baseline.tsv)" -lt 40   # (new file)
./tests/test_ci_brand_inventory_ratchet.sh   # (new file)
rg -q 'test_ci_brand_inventory_ratchet' .github/workflows/ci.yml
printf 'let probe = "com.cmuxterm.app.scratch"\n' > ./ScratchProbe.swift
./tests/test_ci_brand_inventory_ratchet.sh; rc=$?; rm -f ./ScratchProbe.swift; test $rc -eq 1   # (new file)
```

## Phase 2: Brand Manifest, Package, and Generator

**Purpose:** Cannot begin until work items 1.1 and 1.2 have closed the category set, because the manifest's key set *is* the migrated subset of that taxonomy. Everything in Phases 3 through 5 consumes the package and generated artefacts produced here, so they must exist and be byte-stable before any consumer can reference them. Work item 1.3 is not a prerequisite and may land in parallel.

### 2.1 The brand manifest

**Landing:** upstream-PR

**Implementation Details**
- Create `config/brand.json` (new file): the single file a fork edits. Every value defaults to exactly today's value, verified against the sources cited in this PRD.
- Key set, one per migrated category: `productName` (`cmux`), `bundleIdMacOS` (`com.cmuxterm.app`), `bundleIdIOS` (`dev.cmux.ios`), `cliBinaryName` (`cmux`), `daemonBinaryName` (`cmuxd`), `envPrefix` (`CMUX`), `configDirName` (`cmux`), `configFileName` (`cmux.json`), `stateDirName` (`cmux`), `socketBaseName` (`cmux`), `urlScheme` (`cmux`), `utTypeRoot` (`com.cmux`), `logSubsystem` (`com.cmuxterm.app`), `keychainServiceRoot` (`com.cmuxterm.app`), `extensionPointSuffix` (`cmux.sidebar`), `loopbackHost` (`cmux-loopback.localtest.me`), `updateFeedURL`, `sparklePublicKey`, `dmgAssetName` (`cmux-macos.dmg`), `githubRepo` (`manaflow-ai/cmux`), `homepageDomain` (`cmux.com`).
- A `legacy` object carries read-only compatibility values consumed in Phase 4: `envPrefixes` (`["CMUX"]`), `configDirNames` (`["cmux"]`), `bundleIdRoots` (`["ai.manaflow.cmux"]`), `logSubsystems` (`["ai.manaflow.cmux", "ai.manaflow.cmux.ios"]`), `keychainServiceRoots` (`["com.cmuxterm.app"]`).
- A sibling `config/brand.schema.json` (new file) constrains the shape: all keys required, all string values non-empty, `envPrefix` matching `^[A-Z][A-Z0-9_]*$`, both bundle IDs matching reverse-DNS, `updateFeedURL` an absolute https URL.
- Deliberately **absent** keys, because they are registry- or trust-bound: npm/PyPI/crates package names, the Homebrew cask name, Swift module names, Xcode target names, CI workflow filenames. `docs/brand-identity.md` states this.
- `sparklePublicKey` carries upstream's existing public key as its default. This is a *relocation* of an already-public value embedded in shipped binaries, not a new disclosure; the upstream PR description must say so to pre-empt a secret-scanner false positive.

**Acceptance Criteria**
- AC-2.1.a: Every manifest value equals the value currently in the repo at the file cited for it → the manifest describes today, it does not propose a change.
- AC-2.1.b: `config/brand.json` validates against `config/brand.schema.json`.
- AC-2.1.c: The manifest contains no key for any registry- or trust-bound name.
- AC-2.1.d: A manifest with an empty-string value fails schema validation → the schema is not permissive.
- AC-2.1.e: `loopbackHost` is present and equals the literal in `Resources/Info.plist` → the Phase 3 consumer has a defined source.

**Acceptance Tests**
- Test-2.1.a: Integration — assert `bundleIdMacOS` appears in `cmux.xcodeproj/project.pbxproj` and `bundleIdIOS` in `ios/Config/Shared.xcconfig`.
- Test-2.1.b: Unit — validate against the schema.
- Test-2.1.c: Unit — assert the excluded key names are absent.
- Test-2.1.d: Regression — set a value to `""` in a temp copy, assert validation fails.
- Test-2.1.e: Unit — assert `loopbackHost` matches the `Resources/Info.plist` literal.

**Verification Commands**
```bash
python3 -c "import json; json.load(open('config/brand.json'))"   # (new file)
python3 -c "
import json,re
b=json.load(open('config/brand.json'))
assert b['bundleIdMacOS'] in open('cmux.xcodeproj/project.pbxproj').read()
assert b['bundleIdIOS'] in open('ios/Config/Shared.xcconfig').read()
assert b['loopbackHost'] in open('Resources/Info.plist').read()
for k in ('npmPackage','homebrewCask','pypiPackage','cargoCrate','swiftModule'):
    assert k not in b, k
assert re.fullmatch(r'[A-Z][A-Z0-9_]*', b['envPrefix'])"
```

### 2.2 The CmuxBrandIdentity Swift package

**Landing:** upstream-PR

**Implementation Details**
- Create a new SwiftPM package at `Packages/Shared/CmuxBrandIdentity` (new file — a directory with `Package.swift` and `Sources/CmuxBrandIdentity/`). It goes in the `Shared` group because both the macOS app and the iOS app consume it, per the repo's `Packages/<Group>/<pkg>` convention.
- **This package exists because the app target's `Sources/` tree is not importable from a SwiftPM package.** `Packages/macOS/CmuxSettings/Package.swift` declares exactly one dependency, `.package(path: "../CmuxFoundation")`, and there is no root `Package.swift`. Emitting the brand constants into the app's own source tree would make Phase 4 uncompilable — see §5, Defect 1.
- The package has no dependencies. It exposes one product, `CmuxBrandIdentity`, containing one generated file written by work item 2.3.
- Add the dependency edge to every consumer package Phase 4 touches: `Packages/macOS/CmuxSettings/Package.swift` gains `.package(path: "../../Shared/CmuxBrandIdentity")` in `dependencies` and `.product(name: "CmuxBrandIdentity", package: "CmuxBrandIdentity")` in the `CmuxSettings` target's `dependencies`.
- Run `python3 scripts/check-workspace-package-groups.py --write` so `cmux.xcworkspace/contents.xcworkspacedata` reflects the new package, then confirm `--check` passes.
- Per `.github/review-bot-rules/swiftpm-package-resolved.md`, the root lockfile and every affected package-local `Package.resolved` must show the change in the same diff.

**Acceptance Criteria**
- AC-2.2.a: The new package manifest exists, declares zero dependencies, and exposes a `CmuxBrandIdentity` library product.
- AC-2.2.b: `Packages/macOS/CmuxSettings/Package.swift` declares the new package in both `dependencies` and the target's `dependencies` → the import will actually resolve.
- AC-2.2.c: `python3 scripts/check-workspace-package-groups.py --check` → exit 0.
- AC-2.2.d: `swift build` of the brand package alone → exit 0.
- AC-2.2.e: `swift build` of `Packages/macOS/CmuxSettings` → exit 0, proving the cross-package import resolves. This is the decisive check for the package-boundary fix.

**Acceptance Tests**
- Test-2.2.a: Unit — parse the manifest, assert product name and empty dependency list.
- Test-2.2.b: Unit — grep the consumer manifest for both dependency entries.
- Test-2.2.c: Integration — workspace group checker.
- Test-2.2.d: Integration — standalone package build.
- Test-2.2.e: Integration — consumer package build. Red before the dependency edge exists, green after.

**Verification Commands**
```bash
test -f Packages/Shared/CmuxBrandIdentity/Package.swift   # (new file)
rg -q 'CmuxBrandIdentity' Packages/macOS/CmuxSettings/Package.swift
python3 scripts/check-workspace-package-groups.py --check
swift build --package-path Packages/Shared/CmuxBrandIdentity   # (new file)
swift build --package-path Packages/macOS/CmuxSettings
```

### 2.3 Source generator

**Landing:** upstream-PR

**Implementation Details**
- Create `scripts/generate-brand-sources.py` (new file) reading `config/brand.json` and emitting four committed artefacts:
  - `config/Brand.xcconfig` (new file) — the emitted variable set is exactly: `BRAND_PRODUCT_NAME`, `BRAND_BUNDLE_ID`, `BRAND_BUNDLE_ID_IOS`, `BRAND_IOS_PRODUCT_NAME`, `BRAND_URL_SCHEME`, `BRAND_EXTENSION_POINT_SUFFIX`, `BRAND_UTTYPE_ROOT`, `BRAND_ENV_PREFIX`, `BRAND_UPDATE_FEED_URL`, `BRAND_LOOPBACK_HOST`. Note the **suffix** form, not a pre-composed extension-point ID: Phase 3 composes `$(BRAND_BUNDLE_ID).$(BRAND_EXTENSION_POINT_SUFFIX)`. This emitted set and Phase 3's consumed set are identical by construction — see §5, Defect 6.
  - `Packages/Shared/CmuxBrandIdentity/Sources/CmuxBrandIdentity/BrandIdentity.swift` (new file) — a single `public enum BrandIdentity` with `public static let` constants, one per manifest key, plus the `legacy` arrays.
  - `scripts/lib/brand.sh` (new file) — POSIX-shell `BRAND_*` assignments for `scripts/reload.sh` and friends to `source`.
  - `web/lib/generated/brand.ts` (new file) — an exported const object for web and docs consumers.
- Every generated file carries `DO NOT EDIT — generated by scripts/generate-brand-sources.py from config/brand.json` as its first line.
- `--check` regenerates into a temp dir and diffs against the committed files, exiting 1 on drift — the same build-then-diff pattern as the existing `agent-session-web-resources` CI job.
- Deterministic output: keys in manifest declaration order, no timestamps, trailing newline, LF endings.
- Failure modes: manifest missing exits 2; schema validation failure exits 3 naming the failing key; unwritable output dir exits 4.
- `BrandIdentity` is an `enum` with only `static let` members — a namespace of compile-time constants, not mutable ambient state. The rationale is stated in the generated file's header so `.github/review-bot-rules/no-ambient-global-state.md` reviewers see it inline.

**Acceptance Criteria**
- AC-2.3.a: All four generated files begin with the DO-NOT-EDIT header naming generator and manifest.
- AC-2.3.b: `python3 scripts/generate-brand-sources.py --check` → exit 0 on a clean tree.
- AC-2.3.c: Running the generator twice produces byte-identical output → determinism.
- AC-2.3.d: Editing a generated file by hand makes `--check` exit 1 → not vacuous.
- AC-2.3.e: The generated Swift declares no `var` of any kind, under any access modifier → cannot become ambient state.
- AC-2.3.f: Every `$(BRAND_*)` variable referenced by any consumer is defined in `config/Brand.xcconfig` → no undefined xcconfig variable can silently expand to empty.

**Acceptance Tests**
- Test-2.3.a: Unit — assert the header on each of the four outputs.
- Test-2.3.b: Integration — `--check` on a clean tree.
- Test-2.3.c: Regression — generate twice into temp dirs, `diff -r`, assert empty.
- Test-2.3.d: Regression — append a line to a generated file, assert `--check` exits 1, restore.
- Test-2.3.e: Unit — grep the generated Swift for any `var`, assert zero matches.
- Test-2.3.f: Integration — extract `$(BRAND_*)` references from all consumers and assert each is defined.

**Verification Commands**
```bash
python3 scripts/generate-brand-sources.py --check   # (new file)
for f in config/Brand.xcconfig Packages/Shared/CmuxBrandIdentity/Sources/CmuxBrandIdentity/BrandIdentity.swift scripts/lib/brand.sh web/lib/generated/brand.ts; do   # (new file)
  head -1 "$f" | rg -q 'DO NOT EDIT' || exit 1
done
! rg -q '\bvar\s' Packages/Shared/CmuxBrandIdentity/Sources/CmuxBrandIdentity/BrandIdentity.swift   # (new file)
for v in $(rg -oI '\$\(BRAND_[A-Z_]+\)' Resources/Info.plist ios/Config/Shared.xcconfig ios/Config/Release.xcconfig cmux.xcodeproj/project.pbxproj | rg -o 'BRAND_[A-Z_]+' | sort -u); do
  rg -q "^${v} =" config/Brand.xcconfig || { echo "UNDEFINED $v"; exit 1; }   # (new file)
done
```

### 2.4 Generator drift guard in CI

**Landing:** upstream-PR

**Implementation Details**
- Add a `workflow-guard-tests` step in `.github/workflows/ci.yml` running the generator in `--check` mode, mirroring how `python3 scripts/check-workspace-package-groups.py --check` is wired.
- Add the same invocation to the pre-commit hook installed by `scripts/install-git-hooks.sh`, alongside the existing `scripts/normalize-pbxproj.py` step.
- Document the regeneration command in `CONTRIBUTING.md` under a new "Brand identity" subsection.

**Acceptance Criteria**
- AC-2.4.a: `.github/workflows/ci.yml` contains a step invoking the generator in `--check` mode.
- AC-2.4.b: `scripts/install-git-hooks.sh` installs a hook that runs the generator check.
- AC-2.4.c: `CONTRIBUTING.md` documents the regeneration command.
- AC-2.4.d: With the manifest edited but generated files stale, `--check` exits 1 → the guard bites.

**Acceptance Tests**
- Test-2.4.a: Unit — grep the workflow.
- Test-2.4.b: Unit — grep the hook installer.
- Test-2.4.c: Unit — grep `CONTRIBUTING.md`.
- Test-2.4.d: Regression — mutate `productName`, run `--check`, assert exit 1, restore.

**Verification Commands**
```bash
rg -q 'generate-brand-sources' .github/workflows/ci.yml
rg -q 'generate-brand-sources' scripts/install-git-hooks.sh
rg -q 'generate-brand-sources' CONTRIBUTING.md
cp config/brand.json /tmp/brand.bak   # (new file)
python3 -c "
import json; p='config/brand.json'; b=json.load(open(p)); b['productName']='zzdrift'; json.dump(b, open(p,'w'))"
python3 scripts/generate-brand-sources.py --check; rc=$?; cp /tmp/brand.bak config/brand.json; test $rc -eq 1   # (new file)
```

## Phase 3: Build-Time Identity Migration

**Purpose:** Cannot start before work item 2.3, because the Xcode project must include a `config/Brand.xcconfig` that exists and the app targets must link a `CmuxBrandIdentity` product that exists. Work item 2.4 is a CI guard and is not a prerequisite. Within this phase 3.1 must precede 3.2, since the package must be referenced before build settings depend on it, and 3.5 must precede 3.6, since the golden must exist before anything verifies against it.

### 3.1 Wire the brand package into the Xcode project

**Landing:** upstream-PR

**Implementation Details**
- Add an `XCLocalSwiftPackageReference` for the brand package to `cmux.xcodeproj/project.pbxproj`, following the existing entries for other local packages.
- Add the `CmuxBrandIdentity` product to the `Frameworks` build phase of the `cmux` and `cmux-cli` targets so Swift sources in those targets can `import CmuxBrandIdentity`.
- **This work item exists because Phase 4's premise depends on it and nothing else delivered it.** Adding an xcconfig is text substitution over build settings; it does not put a Swift module into any target's link or import graph — see §5, Defect 2.
- Update the root `cmux.xcodeproj/project.xcworkspace/xcshareddata/swiftpm/Package.resolved` in the same diff.
- Run `python3 scripts/normalize-pbxproj.py` after editing so the diff stays reviewable.

**Acceptance Criteria**
- AC-3.1.a: `cmux.xcodeproj/project.pbxproj` contains an `XCLocalSwiftPackageReference` whose path is the brand package.
- AC-3.1.b: Both `cmux` and `cmux-cli` targets list the `CmuxBrandIdentity` product in their framework dependencies.
- AC-3.1.c: `./scripts/check-pbxproj.sh` → exit 0.
- AC-3.1.d: A Swift file in the app target can `import CmuxBrandIdentity` and build → the wiring actually works.
- AC-3.1.e: `CMUX_SKIP_ZIG_BUILD=1 ./scripts/reload.sh --tag brand-p31` → exit 0.

**Acceptance Tests**
- Test-3.1.a: Unit — grep the pbxproj for the package reference.
- Test-3.1.b: Unit — grep each target's framework phase for the product.
- Test-3.1.c: Integration — pbxproj checker.
- Test-3.1.d: Integration — add a temporary file importing the module, build, remove it.
- Test-3.1.e: E2E — tagged reload build.

**Verification Commands**
```bash
rg -q 'CmuxBrandIdentity' cmux.xcodeproj/project.pbxproj
./scripts/check-pbxproj.sh
CMUX_SKIP_ZIG_BUILD=1 ./scripts/reload.sh --tag brand-p31
```

### 3.2 macOS build settings routed through the manifest

**Landing:** upstream-PR

**Implementation Details**
- Add `config/Brand.xcconfig` as a base configuration file for the `cmux`, `cmux-cli`, `CmuxDockTilePlugin`, `cmuxTests`, and `cmuxUITests` targets.
- Replace the literal values with references: `PRODUCT_NAME = $(BRAND_PRODUCT_NAME)`, the bundle-ID setting to `$(BRAND_BUNDLE_ID)`, `CMUX_SIDEBAR_EXTENSION_POINT_ID = $(BRAND_BUNDLE_ID).$(BRAND_EXTENSION_POINT_SUFFIX)`, `CMUX_AUTH_CALLBACK_SCHEME = $(BRAND_URL_SCHEME)`.
- **All six bundle-ID literals must move, not just the app's.** The `com.cmuxterm` root currently appears in six distinct forms across these five targets (`.app`, `.app.debug`, `.app.docktileplugin`, `.app.docktileplugin.debug`, `.apptests`, `.appuitests`). The Debug and test variants compose their suffixes from `$(BRAND_BUNDLE_ID)` rather than hardcoding — see §5, Defect 3.
- Run `python3 scripts/normalize-pbxproj.py` and confirm `./scripts/check-pbxproj.sh` passes.
- Failure mode: an xcconfig not actually applied silently yields an empty `PRODUCT_NAME`, producing an app named `.app`. The equivalence gate in 3.6 catches this; do not rely on the build merely succeeding.

**Acceptance Criteria**
- AC-3.2.a: No `com.cmuxterm` bundle-ID literal in any form remains in the project file → all six variants migrated, not just one.
- AC-3.2.b: No literal product-name assignment for `cmux` remains in the project file.
- AC-3.2.c: `./scripts/check-pbxproj.sh` → exit 0.
- AC-3.2.d: For each of the five named targets, `xcodebuild -showBuildSettings` reports the same resolved bundle ID as before the change.
- AC-3.2.e: `CMUX_SKIP_ZIG_BUILD=1 ./scripts/reload.sh --tag brand-p32` → exit 0.

**Acceptance Tests**
- Test-3.2.a: Unit — unanchored grep for the `com.cmuxterm` root, assert zero matches.
- Test-3.2.b: Unit — grep for the product-name literal, assert zero matches.
- Test-3.2.c: Integration — pbxproj checker.
- Test-3.2.d: Integration — resolve build settings per target, compare against recorded pre-change values.
- Test-3.2.e: E2E — tagged reload build.

**Verification Commands**
```bash
! rg -q 'PRODUCT_BUNDLE_IDENTIFIER = com\.cmuxterm' cmux.xcodeproj/project.pbxproj
! rg -q 'PRODUCT_NAME = cmux;' cmux.xcodeproj/project.pbxproj
./scripts/check-pbxproj.sh
for t in cmux cmux-cli CmuxDockTilePlugin cmuxTests cmuxUITests; do
  xcodebuild -project cmux.xcodeproj -target "$t" -showBuildSettings 2>/dev/null \
    | rg -q 'PRODUCT_BUNDLE_IDENTIFIER = com\.cmuxterm' || { echo "UNRESOLVED $t"; exit 1; }
done
CMUX_SKIP_ZIG_BUILD=1 ./scripts/reload.sh --tag brand-p32
```

### 3.3 iOS build settings routed through the manifest

**Landing:** upstream-PR

**Implementation Details**
- Add `#include "../../config/Brand.xcconfig"` at the top of `ios/Config/Shared.xcconfig`.
- Replace the literals: `PRODUCT_NAME = $(BRAND_IOS_PRODUCT_NAME)`, `PRODUCT_DISPLAY_NAME = $(BRAND_IOS_PRODUCT_NAME)`, the bundle-ID setting to `$(BRAND_BUNDLE_ID_IOS)`, `CMUX_IOS_URL_SCHEME = $(BRAND_URL_SCHEME)-ios-dev`.
- Apply the same treatment to `ios/Config/Release.xcconfig`, preserving its `BETA` display-name suffix and `dev.cmux.app.beta` bundle ID by composing them from `BRAND_*` values.
- `ios/Config/Info.plist` needs no edit — it already consumes these through `$(...)` substitution.
- Do **not** touch `ios/scripts/upload-testflight.sh`. Its `IOS_BETA_BUNDLE_ID` and `IOS_APPSTORE_BUNDLE_ID` defaults are bound to real App Store Connect records; changing them requires provisioning work outside this PRD. Record this in `docs/brand-identity.md`.

**Acceptance Criteria**
- AC-3.3.a: `ios/Config/Shared.xcconfig` contains no literal `dev.cmux.ios` and no bare product-name literal.
- AC-3.3.b: `ios/Config/Release.xcconfig` still yields the `BETA` display name and `dev.cmux.app.beta` bundle ID after substitution.
- AC-3.3.c: The TestFlight upload script is unmodified by this work item.
- AC-3.3.d: `xcodebuild -showBuildSettings` for the iOS target reports the unchanged pre-migration bundle ID.

**Acceptance Tests**
- Test-3.3.a: Unit — grep the xcconfigs for the literals, assert absent.
- Test-3.3.b: Integration — resolve settings, assert display name and bundle ID.
- Test-3.3.c: Unit — `git diff --name-only` does not list the upload script.
- Test-3.3.d: Integration — compare `showBuildSettings` before and after.

**Verification Commands**
```bash
! rg -q 'dev\.cmux\.ios' ios/Config/Shared.xcconfig
rg -q 'BRAND_' ios/Config/Shared.xcconfig
test "$(git diff --name-only origin/main -- ios/scripts/upload-testflight.sh | wc -l)" -eq 0
```

### 3.4 Info.plist literal removal

**Landing:** upstream-PR

**Implementation Details**
- In `Resources/Info.plist`, replace the two `UTExportedTypeDeclarations` identifiers with `$(BRAND_UTTYPE_ROOT).sidebar-tab-reorder` and `$(BRAND_UTTYPE_ROOT).filepreview.transfer`, and `SUFeedURL` with `$(BRAND_UPDATE_FEED_URL)`.
- **The ATS loopback host is handled conditionally.** `cmux-loopback.localtest.me` sits at `Resources/Info.plist:232` as a `<key>` inside the `NSExceptionDomains` dictionary — a dict *key*, not a string value. Xcode's `$(...)` substitution is documented for values; substitution into dictionary keys is not established anywhere in this codebase. This work item must first *empirically verify* that a build substitutes it correctly. If it does, migrate it to `$(BRAND_LOOPBACK_HOST)`. If it does not, leave the literal in place and record `loopbackHost` as a non-migrated category with that reason. Do not assume — see §5, Defect 5.
- Leave `NSDockTilePlugIn` and `OSAScriptingDefinition` as literals; they name build products whose target names this PRD does not rename. Record both as non-migrated.
- The four `NS*UsageDescription` strings are user-facing prose, categorised `localized-prose`, and are **not** touched.
- Do not touch `SUPublicEDKey` — it already reads `$(SPARKLE_PUBLIC_KEY)`, and the key material is a re-keying concern.

**Acceptance Criteria**
- AC-3.4.a: `Resources/Info.plist` contains no literal `com.cmux.` UTType identifier.
- AC-3.4.b: `Resources/Info.plist` contains no literal upstream releases feed URL.
- AC-3.4.c: The four `NS*UsageDescription` strings are unchanged → prose scope boundary respected.
- AC-3.4.d: A built app's `UTExportedTypeDeclarations` identifiers resolve to the same strings as before.
- AC-3.4.e: The loopback host is either substituted and verified resolving correctly in a built app, or left literal and recorded as non-migrated with a stated reason. Exactly one of the two holds.

**Acceptance Tests**
- Test-3.4.a: Unit — grep for the UTType literals, assert zero matches.
- Test-3.4.b: Unit — grep for the literal feed URL, assert zero matches.
- Test-3.4.c: Regression — diff the usage-description values against pre-change values.
- Test-3.4.d: Integration — `PlistBuddy` the built app's UTType identifiers.
- Test-3.4.e: Integration — `PlistBuddy` the built app's `NSExceptionDomains` keys; assert the resolved key is the expected host in either branch.

**Verification Commands**
```bash
! rg -q 'com\.cmux\.(sidebar-tab-reorder|filepreview)' Resources/Info.plist
! rg -q 'github\.com/manaflow-ai/cmux/releases' Resources/Info.plist
rg -q 'would like to' Resources/Info.plist
APP="$(CMUX_SKIP_ZIG_BUILD=1 ./scripts/reload.sh --tag brand-p34 | rg -A1 '^App path:' | tail -1 | sed 's/^ *//')"
/usr/libexec/PlistBuddy -c 'Print :UTExportedTypeDeclarations:0:UTTypeIdentifier' "$APP/Contents/Info.plist" | rg -q 'sidebar-tab-reorder'
/usr/libexec/PlistBuddy -c 'Print :NSAppTransportSecurity:NSExceptionDomains' "$APP/Contents/Info.plist" | rg -q 'localtest\.me'
```

### 3.5 Golden identity manifest bootstrap

**Landing:** upstream-PR

**Implementation Details**
- Create `scripts/extract-brand-identity.sh` (new file): a **standalone, dependency-free** extractor taking a built `.app` path and printing a normalised identity manifest. It depends on nothing this PRD introduces, so it can run against an unmodified merge-base checkout.
- It prints, sorted and whitespace-normalised: `CFBundleIdentifier`, `CFBundleName`, `CFBundleDisplayName`, `CFBundleExecutable`, every `CFBundleURLSchemes` entry, every `UTExportedTypeDeclarations` identifier, `NSExtensionPointIdentifier`, `NSDockTilePlugIn`, `OSAScriptingDefinition`, **every `NSAppTransportSecurity:NSExceptionDomains` key**, `SUFeedURL`, `SUPublicEDKey`, every `LSEnvironment` key/value pair, and the entitlement keys from `codesign -d --entitlements :-`. Version and build numbers are elided so the manifest is stable across releases.
- The `NSExceptionDomains` keys are included specifically so 3.4's conditional loopback migration is covered by the gate. Omitting them would let a real ATS regression pass green — see §5, Defect 5.
- **The bootstrap procedure is explicit and scripted**, because the extractor is authored on a tree that already carries earlier phases. `scripts/capture-brand-golden.sh` (new file) does: (1) `git worktree add` a detached worktree at the merge-base commit; (2) copy the standalone extractor into it — it is standalone precisely so this works; (3) build there with a tagged reload; (4) run the extractor; (5) write `scripts/brand-identity-golden.txt` (new file) into the feature branch; (6) remove the temp worktree. Without this, AC-3.5.a is unfulfillable — see §5, Defect 4.
- Commit the golden. Regenerating it is a reviewable diff; a change to it is a change to the product's identity surface and must be argued in the PR.

**Acceptance Criteria**
- AC-3.5.a: The golden was produced by the capture script against the merge-base commit, and re-running that script on an unchanged merge base reproduces it byte-identically → a genuine, re-derivable control.
- AC-3.5.b: The extractor references no file this PRD creates → it can run at the merge base.
- AC-3.5.c: Two extractions from the same app produce byte-identical output → determinism.
- AC-3.5.d: The golden contains no version-shaped token → stable across releases.
- AC-3.5.e: The golden contains at least one `NSExceptionDomains` key → ATS surface is covered.

**Acceptance Tests**
- Test-3.5.a: E2E — run the capture script twice against the merge base, `diff`, assert empty and matching the committed file.
- Test-3.5.b: Unit — grep the extractor for any path this PRD introduces, assert zero matches.
- Test-3.5.c: Unit — extract twice from one app, `diff`, assert empty.
- Test-3.5.d: Unit — grep the golden for a version-shaped token, assert absent.
- Test-3.5.e: Unit — grep the golden for the loopback host.

**Verification Commands**
```bash
./scripts/capture-brand-golden.sh --verify-reproducible   # (new file)
! rg -q 'brand\.json|BrandIdentity|brand-inventory' scripts/extract-brand-identity.sh   # (new file)
! rg -q '[0-9]+\.[0-9]+\.[0-9]+' scripts/brand-identity-golden.txt   # (new file)
rg -q 'localtest\.me' scripts/brand-identity-golden.txt   # (new file)
```

### 3.6 Build-equivalence gate

**Landing:** upstream-PR

**Implementation Details**
- Create `scripts/check-brand-build-equivalence.sh` (new file). `--verify <app>` runs the standalone extractor against the app and diffs the result against the committed golden, exiting 1 on any difference.
- This is the executable form of "generate the exact same build afterwards". It asserts **identity-surface equality, not binary byte-equality**, because Swift builds embed non-deterministic UUIDs and build paths; claiming bit-identical binaries would be an unverifiable promise.
- Wire into `workflow-guard-tests` where a built app is available, and document local usage in `docs/brand-identity.md`.

**Acceptance Criteria**
- AC-3.6.a: `--verify` on an app built at the tip of Phase 3 → exit 0. This is the green proof for the phase.
- AC-3.6.b: Changing any manifest value, regenerating, and rebuilding makes `--verify` exit 1 → the gate is not vacuous.
- AC-3.6.c: `--verify` against a missing or non-app path exits 2, distinct from a real mismatch.
- AC-3.6.d: The failure output names the specific differing keys → a failure is actionable.

**Acceptance Tests**
- Test-3.6.a: E2E — build at Phase 3 tip, `--verify`, assert exit 0.
- Test-3.6.b: Regression — set `productName` to `zzbrand`, regenerate, rebuild, assert exit 1, revert. This is the red proof.
- Test-3.6.c: Unit — invoke with a bogus path, assert exit 2.
- Test-3.6.d: Unit — force a mismatch, assert the differing key name appears in stderr.

**Verification Commands**
```bash
APP="$(CMUX_SKIP_ZIG_BUILD=1 ./scripts/reload.sh --tag brand-eq | rg -A1 '^App path:' | tail -1 | sed 's/^ *//')"
./scripts/check-brand-build-equivalence.sh --verify "$APP"   # (new file)
./scripts/check-brand-build-equivalence.sh --verify /nonexistent.app; test $? -eq 2   # (new file)
```

## Phase 4: Runtime Path and Cross-Process Contract Migration

**Purpose:** Cannot start before work item 3.1, because `CmuxBrandIdentity` must be an importable, linked product before any Swift call site can reference it. Work items 3.3 through 3.6 are not start-blockers, but 3.6's gate must be green before this phase is considered *done*, since this is the phase that touches cross-process contracts.

### 4.1 Configuration path resolution

**Landing:** upstream-PR

**Implementation Details**
- Replace the hardcoded `.config/cmux/cmux.json` path segments with `BrandIdentity`-derived values at `Packages/macOS/CmuxSettings/Sources/CmuxSettings/Stores/CmuxConfigLocation.swift`, `Sources/CmuxConfig.swift`, `Sources/KeyboardShortcutSettingsFileStore.swift`, and `CLI/CMUXCLI+DocsSettings.swift`.
- Introduce a single resolver returning the ordered candidate list: the brand path first, then every `legacy.configDirNames` path. Reads walk the list and use the first hit; writes always target the brand path.
- **Non-destructive by construction:** the legacy file is never deleted, moved, or truncated.
- Failure modes: both paths absent falls through to existing defaults unchanged; brand path unreadable but legacy readable uses legacy and logs once at debug level; a directory where a file is expected skips that candidate rather than throwing.
- One resolver, one mutation path — satisfying the repo's shared-behaviour policy rather than adding a second optimistic copy per call site.
- **Removal criterion for the legacy fallback:** drop it two minor releases after the first release carrying the brand path, recorded in `docs/brand-identity.md`.

**Acceptance Criteria**
- AC-4.1.a: All four cited files derive their path from `BrandIdentity` rather than a string literal.
- AC-4.1.b: With only a legacy config present, the app reads it → no user loses settings.
- AC-4.1.c: After a write, the brand path exists and the legacy file is byte-unchanged → non-destructive.
- AC-4.1.d: With defaults, the resolved path is exactly `~/.config/cmux/cmux.json` → behaviour unchanged.
- AC-4.1.e: The legacy fallback's removal criterion is documented.
- AC-4.1.f: `./scripts/test-unit.sh` → exit 0.

**Acceptance Tests**
- Test-4.1.a: Unit — grep the four files for the literal, assert zero matches.
- Test-4.1.b: Unit — resolver test with only the legacy file present.
- Test-4.1.c: Regression — write settings, assert the legacy file's hash is unchanged.
- Test-4.1.d: Unit — assert the default resolved path string.
- Test-4.1.e: Unit — grep the doc for the removal criterion.
- Test-4.1.f: Integration — full unit suite.

**Verification Commands**
```bash
! rg -q '"\.config/cmux' Sources/CmuxConfig.swift Sources/KeyboardShortcutSettingsFileStore.swift CLI/CMUXCLI+DocsSettings.swift Packages/macOS/CmuxSettings/Sources/CmuxSettings/Stores/CmuxConfigLocation.swift
rg -q 'removal criterion' docs/brand-identity.md   # (new file)
./scripts/test-unit.sh
```

### 4.2 State directory, socket paths, and channel classification

**Landing:** upstream-PR

**Implementation Details**
- Replace the literal state directory name in `Packages/macOS/CmuxSettings/Sources/CmuxSettings/SocketControl/CmuxStateDirectory.swift` with `BrandIdentity.stateDirName`, keeping `legacyApplicationSupportURL` for the documented pre-0.64.20 external-client compatibility.
- Replace the bundle-ID literal comparisons in `SocketControl/SocketControlSettings.swift`, `SocketControl/SocketControlSettings+DefaultSocketPath.swift`, and `SocketControl/SocketPathMarkerFiles.swift` with comparisons derived from `BrandIdentity.bundleIdMacOS` plus a channel enum (`.stable`, `.debug`, `.nightly`, `.staging`).
- **Classification fails closed.** If a bundle ID matches neither the brand root nor any `legacy.bundleIdRoots` entry, the resolver returns an explicit `.unknown` and the caller refuses to bind rather than defaulting to `.stable`. Silently falling through to `.stable` would bind the wrong socket with the wrong password scoping — the exact correctness bug `.github/review-bot-rules/reliability-single-source-of-truth.md` prohibits.
- Replace the socket filename literals with values composed from `BrandIdentity.socketBaseName`.
- **This is the highest-risk work item in the PRD.** A missed literal does not fail loudly. The Phase 1 ratchet plus fail-closed classification are what make that failure visible.
- The keychain service in `SocketControl/SocketControlPasswordStore.swift` derives from `BrandIdentity.keychainServiceRoot`. The store reads `legacy.keychainServiceRoots` as a fallback and re-writes under the brand name on next successful access. **Removal criterion:** the legacy read is dropped one minor release after the re-write path ships, recorded in `docs/brand-identity.md`. This is a read-once-then-migrate path, not a steady-state second source of truth.

**Acceptance Criteria**
- AC-4.2.a: No bundle-ID string literal remains in any file under the `SocketControl` directory.
- AC-4.2.b: Classification returns `.debug` for a tagged debug bundle ID, `.stable` for the bare brand bundle ID, and `.unknown` for an unrecognised one → fails closed.
- AC-4.2.c: With defaults, the resolved debug socket path is exactly `/tmp/cmux-debug.sock` → unchanged behaviour.
- AC-4.2.d: A password stored under a legacy keychain service is still readable, and is re-written under the brand service.
- AC-4.2.e: The keychain fallback's removal criterion is documented.
- AC-4.2.f: `./scripts/test-unit.sh` → exit 0.

**Acceptance Tests**
- Test-4.2.a: Unit — grep the `SocketControl` directory for the `com.cmuxterm` root, assert zero matches.
- Test-4.2.b: Unit — table-driven classification over stable, debug, tagged, nightly, staging, and garbage bundle IDs.
- Test-4.2.c: Unit — assert the default socket path string.
- Test-4.2.d: Regression — seed a legacy-service keychain item, assert read then re-write.
- Test-4.2.e: Unit — grep the doc.
- Test-4.2.f: Integration — unit suite.

**Verification Commands**
```bash
! rg -q 'com\.cmuxterm' Packages/macOS/CmuxSettings/Sources/CmuxSettings/SocketControl/
./scripts/test-unit.sh
```

### 4.3 Environment variable indirection in Swift

**Landing:** upstream-PR

**Implementation Details**
- Scope is deliberately narrow: only the **cross-process contract** subset named in `docs/brand-identity.md` — `CMUX_SOCKET_PATH`, `CMUXD_UNIX_PATH`, `CMUX_BUNDLE_ID`, `CMUX_TAG`, `CMUX_BUNDLED_CLI_PATH`, `CMUX_AUTH_CALLBACK_SCHEME`, `CMUX_WORKSPACE_ID`, `CMUX_SURFACE_ID`. The remaining ~1,200 `CMUX_*` names are internal or test-only and stay literal; migrating them would balloon the diff past PR size for no contract benefit.
- Add `BrandIdentity.env(_ suffix: String) -> String` composing `"\(envPrefix)_\(suffix)"`, and a reader trying the brand-prefixed name first then every `legacy.envPrefixes` variant, returning the first non-nil.
- Writers export **both** the brand-prefixed and legacy names during the compatibility window — the dual-export approach commit `d675f0a0e3` used for `CMUX_TUI_*` and `CMUX_MUX_*`.
- Swift-side call sites: `Sources/CloudVMActionLauncher.swift`, `Sources/AppDelegate+CmuxSSHURL.swift`, `Sources/Workspace.swift`. The shell-string case in `Sources/SSHPTYAttachStartupCommandBuilder.swift` is **not** handled here — it is work item 4.4.
- Because the default `envPrefix` is `CMUX`, brand and legacy names are identical today and dual-export is a literal no-op, which the equivalence gate confirms via an unchanged `LSEnvironment` block.
- **Removal criterion:** legacy env reads are dropped two minor releases after the brand names ship.

**Acceptance Criteria**
- AC-4.3.a: The three Swift call sites read env vars through the helper, not bare literals.
- AC-4.3.b: With a non-default `envPrefix`, a value set under the legacy name is still read → no silent breakage for existing shells and CI scripts.
- AC-4.3.c: With the default prefix, the built app's `LSEnvironment` block is byte-identical to the golden.
- AC-4.3.d: The compatibility window's removal criterion is documented.
- AC-4.3.e: The ~1,200 internal `CMUX_*` names are untouched → diff stays PR-sized.

**Acceptance Tests**
- Test-4.3.a: Unit — grep the three files for the migrated literal names, assert zero matches.
- Test-4.3.b: Unit — set `envPrefix` to `ZZ`, set only the legacy name, assert the reader returns it.
- Test-4.3.c: Integration — equivalence gate, `LSEnvironment` section matches.
- Test-4.3.d: Unit — grep the doc.
- Test-4.3.e: Integration — assert the inventory's `env-prefix` category fell by fewer than 50.

**Verification Commands**
```bash
! rg -q '"CMUX_SOCKET_PATH"|"CMUX_BUNDLED_CLI_PATH"|"CMUX_WORKSPACE_ID"|"CMUX_SURFACE_ID"' Sources/CloudVMActionLauncher.swift Sources/AppDelegate+CmuxSSHURL.swift Sources/Workspace.swift
./scripts/test-unit.sh
```

### 4.4 Environment variable indirection in generated shell strings

**Landing:** upstream-PR

**Implementation Details**
- `Sources/SSHPTYAttachStartupCommandBuilder.swift` does not read env vars in Swift. It **composes a POSIX shell script string** that runs in a different process on a remote host and reads `$CMUX_SOCKET_PATH`, `$CMUX_WORKSPACE_ID`, and `$CMUX_SURFACE_ID` by literal name. The Swift-side dual-read design of 4.3 has no analogue here — revision 1 of this PRD omitted the case entirely — see §5, Defect 7.
- The composed shell text must itself express the fallback. Each reference becomes a `${BRAND_NAME:-${LEGACY_NAME:-}}` expression built via Swift interpolation from `BrandIdentity.envPrefix` and `legacy.envPrefixes`, so the remote shell resolves the brand name first and falls back to the legacy name.
- Add a helper on `BrandIdentity` emitting this shell-fallback expression for a given suffix, so the pattern is written once rather than hand-rolled per call site.
- With default values the brand and legacy prefixes are both `CMUX`, so the emitted expression must collapse to exactly the current literal text rather than a redundant self-referential fallback. Assert that explicitly — a doubled self-reference would be behaviour-preserving but a gratuitous diff.

**Acceptance Criteria**
- AC-4.4.a: The file contains no bare `$CMUX_` reference in its composed shell strings.
- AC-4.4.b: With defaults, the composed shell text is byte-identical to the pre-change text → no gratuitous diff.
- AC-4.4.c: With a non-default `envPrefix`, the composed text contains both the brand and legacy names in a shell fallback expression.
- AC-4.4.d: The generated shell text is valid POSIX shell → `sh -n` accepts it.
- AC-4.4.e: `./scripts/test-unit.sh` → exit 0.

**Acceptance Tests**
- Test-4.4.a: Unit — grep the file for a bare `$CMUX_` token, assert zero matches.
- Test-4.4.b: Regression — snapshot the composed command with defaults, assert byte-equality with the recorded pre-change string.
- Test-4.4.c: Unit — set `envPrefix` to `ZZ`, assert both names appear in a `:-` expression.
- Test-4.4.d: Integration — pipe the composed text through `sh -n`.
- Test-4.4.e: Integration — unit suite.

**Verification Commands**
```bash
! rg -q '\$CMUX_[A-Z_]+' Sources/SSHPTYAttachStartupCommandBuilder.swift
! rg -q '"CMUX_SOCKET_PATH"' Sources/SSHPTYAttachStartupCommandBuilder.swift
./scripts/test-unit.sh
```

### 4.5 Shell tooling routed through the manifest

**Landing:** upstream-PR

**Implementation Details**
- `scripts/reload.sh` sources `scripts/lib/brand.sh` near the top and replaces its hardcoded app name, bundle ID, socket paths, derived-data prefix, and URL scheme with `${BRAND_*}` compositions.
- `scripts/cmux-debug-cli.sh` does the same for its socket path and bundle-ID resolution.
- All existing flags (`--tag`, `--name`, `--bundle-id`, `--derived-data`, `--launch`) keep their current precedence: an explicit flag still overrides the brand-derived default.
- Do not rename the scripts; their filenames are referenced by `CLAUDE.md`, `CONTRIBUTING.md`, CI workflows, and contributor muscle memory.
- **The app-and-CLI round-trip is asserted here, not in 4.2**, because the CLI's own socket resolution lives in this work item. Asserting it earlier would only pass by accident, since default values equal legacy values — see §5, Defect 8.

**Acceptance Criteria**
- AC-4.5.a: `scripts/reload.sh` sources the generated brand library and contains no `com.cmuxterm` literal.
- AC-4.5.b: `scripts/cmux-debug-cli.sh` contains no `com.cmuxterm` literal.
- AC-4.5.c: `--bundle-id` still overrides the brand-derived default → flag precedence preserved.
- AC-4.5.d: The tagged socket path is unchanged from the pre-migration value for the same tag.
- AC-4.5.e: A tagged build plus a CLI `list-workspaces` round-trips → the app and CLI agree on the socket after both sides are migrated.

**Acceptance Tests**
- Test-4.5.a: Unit — grep for the literal and the `source` line.
- Test-4.5.b: Unit — grep the debug CLI.
- Test-4.5.c: Integration — reload with an explicit `--bundle-id`, assert the built app carries it.
- Test-4.5.d: Regression — compare the computed socket path against the pre-change value.
- Test-4.5.e: E2E — tagged build and CLI round-trip.

**Verification Commands**
```bash
rg -q 'brand\.sh' scripts/reload.sh
! rg -q 'com\.cmuxterm' scripts/reload.sh scripts/cmux-debug-cli.sh
CMUX_SKIP_ZIG_BUILD=1 ./scripts/reload.sh --tag brand-p45 --launch
CMUX_TAG=brand-p45 scripts/cmux-debug-cli.sh list-workspaces
```

## Phase 5: Ratchet, Rebrand Proof, and Documentation

**Purpose:** Cannot start before Phase 4 has landed, because the `config-path`, `state-path`, and `socket-path` categories only reach zero once Phase 4's migrations exist, and the smoke test needs every consumer already routed through the manifest or it would report a false pass.

### 5.1 Ratchet tightening

**Landing:** upstream-PR

**Implementation Details**
- Regenerate `scripts/brand-inventory-baseline.tsv` at the tip of Phase 4.
- Convert the migrated categories to a **hard ceiling of zero outside generated files and the manifest**: `bundle-id-macos`, `bundle-id-ios`, `uttype`, `url-scheme`, `extension-point-id`, `update-feed` (reachable after Phase 3) and `config-path`, `state-path`, `socket-path` (reachable after Phase 4).
- Non-migrated categories keep non-increase semantics.
- The PR description records before/after per-category counts so the reduction is a reviewable number rather than a claim.

**Acceptance Criteria**
- AC-5.1.a: Migrated categories report zero occurrences outside generated files and the manifest.
- AC-5.1.b: `./tests/test_ci_brand_inventory_ratchet.sh` → exit 0 at the Phase 5 tip.
- AC-5.1.c: Reintroducing a bundle-ID literal into a Swift source file fails the ratchet → the tightened gate bites.
- AC-5.1.d: The total count fell measurably versus the Phase 1 baseline.

**Acceptance Tests**
- Test-5.1.a: Integration — assert per-category zero for the migrated set.
- Test-5.1.b: Integration — ratchet green.
- Test-5.1.c: Regression — inject a literal, assert exit 1, revert.
- Test-5.1.d: Integration — compare totals against the Phase 1 baseline.

**Verification Commands**
```bash
./tests/test_ci_brand_inventory_ratchet.sh   # (new file)
python3 scripts/brand-inventory.py --json > /tmp/bi5.json   # (new file)
python3 -c "
import json,sys
d=json.load(open('/tmp/bi5.json'))
m=['bundle-id-macos','bundle-id-ios','config-path','state-path','socket-path','url-scheme','uttype','extension-point-id','update-feed']
bad={k:d['categories'][k] for k in m if d['categories'].get(k,0)>0}
print('nonzero:', bad); sys.exit(1 if bad else 0)"
```

### 5.2 End-to-end rebrand smoke test

**Landing:** upstream-PR

**Implementation Details**
- Create `scripts/rebrand-smoke-test.sh` (new file). It: (1) backs up `config/brand.json`; (2) writes a throwaway brand (`productName: zzbrand`, `bundleIdMacOS: com.zzbrand.app`, `envPrefix: ZZBRAND`, and so on); (3) regenerates sources; (4) builds a tagged Debug app; (5) extracts the identity manifest and asserts **zero** occurrences of any original brand token; (6) restores the manifest and regenerates; (7) **builds a second time with defaults** and asserts that extraction matches the committed golden exactly.
- Step 7 is a distinct second build. A single throwaway-branded build cannot satisfy a default-value golden comparison — revision 1 conflated the two — see §5, Defect 9.
- **Output contract:** the script writes the throwaway-branded app path to `/tmp/brand-smoke-rebranded-app` and the default-config app path to `/tmp/brand-smoke-default-app`, both plain single-line files. These are stated here, in Implementation Details, because the verification commands depend on them.
- A `trap` restores the manifest and regenerates on **any** exit path, including failure and interrupt. The two temp path files are the only artefacts intentionally left behind.
- It never touches the user's real config, sockets, or keychain — the throwaway brand guarantees fully disjoint paths, which is itself part of what the test proves.
- This is the direct executable answer to "update a couple of things and generate the exact same build afterwards".

**Acceptance Criteria**
- AC-5.2.a: After the throwaway rebrand, the extracted identity manifest contains zero occurrences of `cmux` or `cmuxterm`.
- AC-5.2.b: The script restores the manifest and all generated files on both success and failure → `git status --porcelain` is empty afterwards.
- AC-5.2.c: The rebranded app's socket, config, and state paths are disjoint from the default ones.
- AC-5.2.d: The second, default-config build's extraction matches the golden exactly.
- AC-5.2.e: `./scripts/rebrand-smoke-test.sh` → exit 0.

**Acceptance Tests**
- Test-5.2.a: E2E — rebrand, build, grep the extraction, assert zero hits.
- Test-5.2.b: Regression — force a mid-run failure, assert the tree is still clean.
- Test-5.2.c: Integration — assert path disjointness.
- Test-5.2.d: Integration — default-config build diffs clean against the golden.
- Test-5.2.e: E2E — whole script exits 0.

**Verification Commands**
```bash
./scripts/rebrand-smoke-test.sh   # (new file)
test "$(git status --porcelain | wc -l)" -eq 0
./scripts/extract-brand-identity.sh "$(cat /tmp/brand-smoke-rebranded-app)" > /tmp/rebranded.txt   # (new file)
! rg -qi 'cmux' /tmp/rebranded.txt
./scripts/check-brand-build-equivalence.sh --verify "$(cat /tmp/brand-smoke-default-app)"   # (new file)
```

### 5.3 Fork documentation

**Landing:** upstream-PR

**Implementation Details**
- Create `docs/forking.md` (new file): the exact steps to rebrand a fork — edit `config/brand.json`, run the generator, run the smoke test, generate a fresh Sparkle keypair, point `updateFeedURL` at the fork's releases, and re-provision App Store Connect records if shipping iOS.
- It must state plainly what a manifest edit does **not** do: it does not rename Swift modules, Xcode targets, directories, registry package names, the Homebrew cask, or localized prose, and it does not re-key Sparkle. Each carries a one-line reason.
- Add a "Brand identity" section to `CONTRIBUTING.md` linking to both new documents.
- All new documentation is contributor-facing English prose, not shipped UI strings, so `.github/review-bot-rules/full-internationalization.md` does not apply. State this in the PR description to pre-empt a bot false positive.

**Acceptance Criteria**
- AC-5.3.a: `docs/forking.md` lists every step including Sparkle re-keying and App Store Connect provisioning.
- AC-5.3.b: It enumerates the non-covered surfaces with a reason each, at least six entries.
- AC-5.3.c: `CONTRIBUTING.md` links to both new documents.
- AC-5.3.d: No shipped UI string was added or changed by this work item.

**Acceptance Tests**
- Test-5.3.a: Unit — grep for `SUPublicEDKey` and App Store Connect.
- Test-5.3.b: Unit — assert a "Not covered" section with at least six entries.
- Test-5.3.c: Unit — grep `CONTRIBUTING.md` for both paths.
- Test-5.3.d: Regression — assert the localization catalogues are unmodified.

**Verification Commands**
```bash
rg -q 'SUPublicEDKey' docs/forking.md   # (new file)
rg -q 'App Store Connect' docs/forking.md   # (new file)
rg -q 'docs/brand-identity.md' CONTRIBUTING.md
test "$(git diff --name-only origin/main -- Resources/Localizable.xcstrings web/messages/en.json | wc -l)" -eq 0
```

## Phase 6: Upstream Submission and Fork Ingest

**Purpose:** Cannot start before Phase 5, because the fork-side work items depend on the complete migrated surface and the upstream sequence's final unit is Phase 5 itself. Individual upstream PRs are opened as soon as *their own* phase is green — PR N does not wait for Phase 5 — which work item 6.1 states explicitly.

### 6.1 Upstream PR split

**Landing:** upstream-PR

**Implementation Details**
- Cut each upstream unit as a topic branch **from `upstream-main`**, never from `main`, so no fork-local content leaks in. Fetch the mirror with `git fetch origin upstream-main:refs/remotes/origin/upstream-main` — there is no `upstream` remote configured locally.
- **Branch naming is contractual:** the five branches are named exactly `brand-p1` through `brand-p5`. These are git branch names and are distinct from the `reload.sh --tag` values used elsewhere in this PRD.
- Five PRs, each independently buildable and reviewable: (1) inventory tool, taxonomy doc, baseline, ratchet; (2) manifest, brand package, generator, drift guard; (3) package wiring, build settings, Info.plist, golden, equivalence gate; (4) runtime paths and cross-process contracts; (5) ratchet tightening, smoke test, fork docs.
- **Each PR is opened as soon as its own phase is green**, not after all five are complete. PR 1 is upstream-neutral hygiene and can go first while later phases are still in progress.
- **Upstream governs its own conventions.** These PRs target `manaflow-ai/cmux`, so that repository's PR template and bot configuration apply. Do **not** paste this fork's review-trigger bot block into an upstream PR — those bots are configured for this fork. Read upstream's own `CONTRIBUTING.md` and PR template before writing descriptions.
- PRs 3 and 4 change build and runtime surfaces. Where upstream's template asks for a demo video, state plainly that equivalence-gate output and CI dispatch-run logs are offered instead, and why — do not assert the substitution is self-evidently equivalent.
- PR 4 must state that the ~1,200 internal `CMUX_*` names are intentionally untouched, with the reason, so a reviewer does not read the partial migration as an oversight.
- **Validate the premise before building PR 2.** Open a draft issue or discussion upstream about the manifest location and key naming first. Upstream is a commercial product whose maintainers have limited incentive to accept build indirection whose primary beneficiary is a fork; a "we don't want a brand-manifest system" response sinks Phases 2 through 6. PR 1 stands alone as genuinely upstream-neutral hygiene regardless of that answer.
- No PR modifies `.github/workflows/` filenames, the TestFlight upload script, or any registry package name.

**Acceptance Criteria**
- AC-6.1.a: Every upstream branch's merge base is `upstream-main`, not `main`.
- AC-6.1.b: Each PR builds and its verification commands pass independently of later PRs.
- AC-6.1.c: No PR diff touches a workflow filename, the TestFlight upload script, or a registry package name.
- AC-6.1.d: No upstream PR description contains this fork's bot-mention block.
- AC-6.1.e: An upstream issue or discussion validating the manifest approach exists before PR 2 is opened.

**Acceptance Tests**
- Test-6.1.a: Integration — `git merge-base --is-ancestor` per branch.
- Test-6.1.b: E2E — check out each branch in isolation, run its verification commands.
- Test-6.1.c: Unit — `git diff --name-only` per branch against the excluded paths.
- Test-6.1.d: Unit — grep each PR body for the bot handles, assert absent.
- Test-6.1.e: Unit — assert the upstream discussion URL is recorded in PR 2's description.

**Verification Commands**
```bash
git fetch origin upstream-main:refs/remotes/origin/upstream-main
for b in brand-p1 brand-p2 brand-p3 brand-p4 brand-p5; do
  git merge-base --is-ancestor origin/upstream-main "$b" || { echo "BAD BASE $b"; exit 1; }
  if git diff --name-only origin/upstream-main.."$b" | rg -q '^(\.github/workflows/|ios/scripts/upload-testflight)'; then
    echo "EXCLUDED PATH IN $b"; exit 1
  fi
done
```

### 6.2 Fork brand values

**Landing:** fork-only

**Implementation Details**
- On `main` in `stokd-cloud/ghostty-dock`, set `config/brand.json` to the Ghostty Dock values: `productName: "Ghostty Dock"`, `cliBinaryName: "gdock"`, `bundleIdMacOS: "cloud.stokd.ghostty-dock"`, `envPrefix: "GDOCK"`, `configDirName: "ghostty-dock"`, `socketBaseName: "gdock"`, `urlScheme: "gdock"`, and the fork's own `githubRepo` and `updateFeedURL`.
- Populate `legacy.envPrefixes` with `["CMUX"]` and `legacy.configDirNames` with `["cmux"]` so an existing `~/.config/cmux` keeps working. Per the fork's standing rebrand posture, `~/.config/cmux` is never deleted — migration is a non-destructive copy with the original left intact as a fallback.
- Generate a fork-owned Sparkle keypair and set `sparklePublicKey` accordingly. Renaming alone would leave the fork trusting upstream's signing key.
- This is the **entire** fork rebrand of the identity surface: one file plus a regenerate. That single-file property is the PRD's headline claim and this work item demonstrates it.

**Acceptance Criteria**
- AC-6.2.a: The rebrand touches exactly `config/brand.json` plus generated files → the claim holds.
- AC-6.2.b: A built app reports the Ghostty Dock bundle ID and display name.
- AC-6.2.c: An existing `~/.config/cmux/cmux.json` is still read and remains byte-unchanged after the app writes settings.
- AC-6.2.d: `sparklePublicKey` differs from upstream's value → the fork is not trusting upstream's key.

**Acceptance Tests**
- Test-6.2.a: Unit — `git diff --name-only` lists only the manifest and generated files.
- Test-6.2.b: E2E — build, assert bundle ID and display name.
- Test-6.2.c: Regression — seed a legacy config, launch, write settings, assert read and hash-unchanged.
- Test-6.2.d: Unit — compare against upstream's key, assert different.

**Verification Commands**
```bash
python3 scripts/generate-brand-sources.py   # (new file)
test "$(git diff --name-only | rg -cv '^(config/brand\.json|config/Brand\.xcconfig|Packages/Shared/CmuxBrandIdentity/|scripts/lib/brand\.sh|web/lib/generated/)')" -eq 0
CMUX_SKIP_ZIG_BUILD=1 ./scripts/reload.sh --tag gdock
```

### 6.3 Upstream-to-main ingest

**Landing:** fork-only

**Implementation Details**
- `.github/workflows/sync-upstream.yml` today only fast-forwards `upstream-main` from `upstream/main` and hard-fails with an issue if it cannot. **Nothing merges `upstream-main` into `main`** — the ingest half of the fork flow is undefined and the fork silently falls behind at roughly 100 upstream commits per day.
- Create `.github/workflows/ingest-upstream.yml` (new file). It is triggered by `on: workflow_run` on the `sync-upstream` workflow's completion and checks the triggering run's conclusion before proceeding. A second independent cron would give only wall-clock ordering, not a guarantee, and could read `upstream-main` mid-push.
- It creates or updates a branch `ingest/upstream-<date>` from `main`, merges `origin/upstream-main`, and opens a PR to `main`.
- On a clean merge it runs the brand ratchet, the generator drift check, and the unit suite, and labels the PR `ingest:clean`.
- On conflict it does **not** force anything: it pushes the conflicted branch, opens a PR labelled `ingest:conflict`, and comments with the conflicted paths so a human resolves them.
- The workflow must never push to `main` directly and never touch `upstream-main`, preserving the pristine-mirror invariant.
- `.github/CODEOWNERS` assigns `/.github/workflows/` to an upstream maintainer's handle. Confirm that handle has collaborator access on the fork, or add a fork-scoped CODEOWNERS entry naming a stokd-cloud maintainer, or this fork-only workflow PR is unmergeable by policy.
- Because the fork's rebrand is confined to the manifest and generated files, the expected conflict surface is small. The ingest PR's conflict count is the ongoing measurement of whether that assumption holds.

**Acceptance Criteria**
- AC-6.3.a: The workflow contains no `git push` naming `main` or `upstream-main` as a destination, in any phrasing including a bare branch name → invariants preserved.
- AC-6.3.b: The workflow is triggered by `workflow_run` on `sync-upstream` and declares no `schedule:` key → ordering is structural, not wall-clock.
- AC-6.3.c: A clean ingest opens a PR labelled `ingest:clean` with the guard checks green.
- AC-6.3.d: A conflicting ingest opens a PR labelled `ingest:conflict` listing conflicted paths, and does not force-push.
- AC-6.3.e: `actionlint` passes on the new workflow.
- AC-6.3.f: CODEOWNERS coverage for the new file is resolved on the fork.

**Acceptance Tests**
- Test-6.3.a: Unit — extract every `git push` line and assert none names `main` or `upstream-main` as a destination, covering the `HEAD:main`, `branch:main`, and bare `main` phrasings.
- Test-6.3.b: Unit — grep for the `workflow_run` trigger and assert no `schedule:` key.
- Test-6.3.c: Integration — dispatch against a clean state, assert PR and label.
- Test-6.3.d: Regression — dispatch with a seeded conflict, assert the conflict label and no force-push.
- Test-6.3.e: Unit — `actionlint`.
- Test-6.3.f: Unit — assert a CODEOWNERS entry covers the file with a fork-accessible owner.

**Verification Commands**
```bash
test -f .github/workflows/ingest-upstream.yml   # (new file)
! rg -q 'git push[^\n]*\b(main|upstream-main)\b' .github/workflows/ingest-upstream.yml   # (new file)
rg -q 'workflow_run' .github/workflows/ingest-upstream.yml   # (new file)
! rg -q '^\s*schedule:' .github/workflows/ingest-upstream.yml   # (new file)
actionlint .github/workflows/ingest-upstream.yml   # (new file)
```

## 3. Completion Criteria

The project is complete when all of the following hold simultaneously:

- The inventory tool, taxonomy document, and committed per-category baseline exist, and the ratchet runs in `workflow-guard-tests`.
- `config/brand.json` is the only hand-edited source of brand identity, and the generator drift check is green in CI and in the pre-commit hook.
- The brand package builds standalone and `Packages/macOS/CmuxSettings` builds against it, proving the cross-package import resolves.
- Every migrated category reports zero occurrences outside generated files and the manifest.
- With default manifest values, a built app's identity surface matches the committed golden byte for byte, and that golden is re-derivable from the merge base by a committed script.
- The rebrand smoke test exits 0, proving a throwaway rebrand moves every identity value together with no residue, that a default-config rebuild still matches the golden, and that the tree restores cleanly.
- `./scripts/test-unit.sh` and `./scripts/check-pbxproj.sh` exit 0, and a tagged reload builds and round-trips over its socket.
- Five upstream PRs are open from branches `brand-p1` through `brand-p5` cut off `upstream-main`, each independently buildable, none carrying this fork's bot block.
- The fork's `main` carries Ghostty Dock values in `config/brand.json` and nothing else brand-related.
- `.github/workflows/ingest-upstream.yml` exists, is `workflow_run`-triggered, and has produced at least one real ingest PR.

## 4. Rollout & Validation

### Rollout Strategy

- **Phase-by-phase, each behind its own gate.** Phases 1 and 2 add only new files, a new package, and CI checks; they cannot regress the product. Phase 3 is the first to touch the build and ends by establishing the equivalence gate. Phase 4 is the highest-risk phase and lands only after that gate exists.
- **Validate the premise upstream before investing in Phase 2.** PR 1 is upstream-neutral hygiene and stands on its own. Phases 2 through 6 are contingent on upstream accepting the manifest approach; get a signal first.
- **The golden file is the rollback trigger.** Any unexplained diff against it fails the phase; the fix is to correct the migration, never to regenerate the golden to match. Regenerating is legitimate only when the identity surface is *intended* to change, argued in the PR.
- **Compatibility windows are time-boxed.** The legacy config-path, env-prefix, and keychain-service fallbacks each carry an explicit removal criterion in `docs/brand-identity.md` rather than being left open-ended.
- **Per-phase rollback is a single revert.** Each phase is a self-contained PR whose consumers are all downstream of it.
- **CI is currently `workflow_dispatch`-only.** Until it resumes on PRs, every guard added here must be run manually via dispatch on each PR, with the run URL recorded in the PR description. A green local run is not CI coverage.

### Post-Launch Validation

- Track per-category inventory totals over time; migrated categories must stay at zero and the overall total must not climb.
- Track the conflicted-path count on each `ingest:conflict` PR. A sustained rise means the thin-skin assumption is breaking down and the scope boundary needs revisiting.
- Confirm on the first fork release that Sparkle updates resolve against the fork's own feed and key, and that an existing `~/.config/cmux` installation upgrades without losing settings.
- Confirm the previously drifted `ai.manaflow.cmux` os_log subsystems either now derive from the manifest or are explicitly recorded as non-migrated — the failure this PRD exists to prevent repeating.
- Fix the stale `ai.manaflow.cmuxterm.plist` zap path in `homebrew-cmux/Casks/cmux.rb` and `scripts/build-sign-upload.sh`; it matches no current bundle ID, so the cask's preference cleanup is silently broken today, independent of this work.

## 5. Open Questions

### Defect log — fixed in revision 2

A three-lens adversarial review found defects in revision 1. Nine were reproduced empirically against this repository before being accepted. Recorded so the fixes are not silently undone:

- **Defect 1 (fatal).** Revision 1 emitted the brand constants into the app target's own source tree while Phase 4 referenced them from inside `Packages/macOS/CmuxSettings`. That package declares one dependency and there is no root `Package.swift`; a SwiftPM package cannot import the enclosing Xcode target's sources. Phase 4 could not compile. **Fixed** by work item 2.2, which creates `Packages/Shared/CmuxBrandIdentity` and adds explicit dependency edges.
- **Defect 2 (fatal).** Phase 4's stated premise was that Phase 3 "added the file to the target's sources", but no work item did so — adding an xcconfig is build-setting substitution, not module membership. **Fixed** by new work item 3.1.
- **Defect 3.** The bundle-ID assertion anchored on one exact literal form and matched 1 of the 6 real variants; three of the five named targets could stay hardcoded and still pass. **Fixed** by unanchoring the pattern and adding a per-target resolution check in 3.2.
- **Defect 4.** The golden had to be captured from the merge base, but the only extractor was created inside the same work item on a tree already carrying earlier phases, so the criterion was unfulfillable. **Fixed** by splitting a standalone extractor and a scripted merge-base capture into work item 3.5.
- **Defect 5.** The ATS loopback host is a plist *dictionary key*, not a value, and `$()` substitution into dict keys is unestablished here; the equivalence gate also omitted `NSExceptionDomains` entirely, so a real ATS regression would have passed green. **Fixed** by making 3.4's migration conditional on empirical verification and adding the ATS keys to the extracted manifest in 3.5.
- **Defect 6.** The generator emitted an extension-point *ID* variable while the consumer referenced an extension-point *suffix* variable that was never defined; Xcode expands undefined variables to empty. **Fixed** by fixing the emitted set to the suffix form and adding AC-2.3.f, which asserts every referenced `BRAND_*` variable is defined.
- **Defect 7.** `Sources/SSHPTYAttachStartupCommandBuilder.swift` embeds env-var names inside generated POSIX shell strings that run in a different process. The Swift-side dual-read design had no analogue and the file was not covered by any verification command. **Fixed** by new work item 4.4.
- **Defect 8.** The env-prefix verification checked 2 of the 4 call sites its own text named, and the cross-process round-trip was asserted before the CLI side was migrated. **Fixed** by checking all named files and moving the round-trip assertion to 4.5.
- **Defect 9.** The smoke test described one build but claimed a default-config golden match, and its temp-file contract appeared only in the verification block. **Fixed** by specifying two builds and naming both output paths in Implementation Details.
- **Defect 10 (broken gate).** A verification command piped JSON into a `python3 -` heredoc; the heredoc hijacks stdin, so the script never receives the piped data and raises a JSON decode error. Reproduced live. The check could never pass. **Fixed** by using `python3 -c` throughout.
- **Defect 11 (vacuous gate).** The ingest workflow's push assertion missed `git push origin main` and `git push origin branch:main`, catching only the `HEAD:main` form. **Fixed** by anchoring on the destination ref in AC-6.3.a.
- **Defect 12.** Overstated phase dependencies (Phase 2 on all of Phase 1, Phase 3 on the CI guard, Phase 4 on all of Phase 3, Phase 6 on all of 1–5) violated the spec's requirement that phase boundaries be genuine. **Fixed** by narrowing each Purpose to its real prerequisite.
- **Defect 13.** Assorted: `actionlint` was required but missing from the toolchain table; the mutable-state regex missed `private`, `internal`, and `fileprivate` static vars; the baseline's shape was unspecified and implied a 94k-row file; branch names existed only in a verification command; the exclusion list contradicted the Summary's stated methodology. All fixed in place.
- **Defect 14.** The prior-rename drift claim cited a parser-test fixture, which is not evidence. The claim is true but the citation was wrong: the string survives in 11 live non-test files. **Fixed** by re-grounding the citation.

One reviewer claim was **rejected**: that the 94,010 figure was not reproducible. Re-running the stated methodology at commit `6e788a05f3` yields exactly 94,010 occurrences across 5,310 files. The reviewer's lower figure used different exclusions. The Summary now records the literal command.

### Autonomous decisions

- **Scope excludes localized prose** — inventoried but not migrated, because the full-internationalization rule requires complete translations for all 20 locales in the same PR, which would dwarf the identity change and make the upstream PRs unreviewable.
- **Scope excludes existing Swift module, Xcode target, and directory names** — renaming them would convert every future upstream ingest into a mass-conflict event, the exact cost this PRD eliminates.
- **Equivalence is asserted over the identity surface, not binary bytes** — Swift builds embed non-deterministic UUIDs, build paths, and timestamps; promising byte-identical binaries would be unverifiable.
- **Env-prefix migration is limited to the cross-process contract subset** — ~8 names rather than ~1,200, because only those require multi-binary agreement.
- **Compatibility via dual-read fallbacks rather than a hard cutover** — the pattern commit `d675f0a0e3` already established in this repo, now with explicit removal criteria so the fallbacks are time-boxed.
- **Channel classification fails closed** — an unrecognised bundle ID yields `.unknown` and refuses to bind, rather than defaulting to `.stable` and silently binding the wrong socket.
- **`BrandIdentity` is a constants-only `enum` in its own package** — satisfying the no-ambient-global-state rule by construction and the package-boundary requirement by necessity.
- **The ratchet starts as non-increase, then tightens to zero** — so Phase 1 can land immediately without blocking the work items that reduce the counts.

### Genuinely open

None blocks any Phase 1 work item. The upstream-acceptance question blocks Phase 2 by explicit design.

- **Will upstream accept the premise at all?** `manaflow-ai/cmux` is a commercial product; its `CONTRIBUTING.md` grants Manaflow, Inc. a relicensing right. Maintainers have limited incentive to accept build indirection whose primary beneficiary is a fork. Work item 6.1 now requires validating this before PR 2 is opened.
- **Is the stale `ai.manaflow.cmuxterm` preference path legacy residue or live?** It matches no bundle ID this repo produces. Resolve with upstream before deciding whether the cask's zap stanza is fixed or removed.
- **Which iOS bundle ID is actually live in App Store Connect?** `ios/Config/Shared.xcconfig` says `dev.cmux.ios`; the TestFlight upload script defaults to `dev.cmux.app.beta` and `com.cmux.app`. Three conventions coexist and this cannot be settled from the repository alone.
- **Does Xcode substitute `$(...)` into plist dictionary keys?** Work item 3.4 requires empirical verification rather than assumption, and branches on the answer.
- **Should `cmuxd` be in scope?** `scripts/reload.sh` references a `cmuxd/` directory that does not exist in this checkout and is guarded by a directory test. Confirm whether it is expected to exist before treating the daemon binary name as a live migration target.
- **Does the CODEOWNERS owner for `.github/workflows/` have access on the fork?** If branch protection enforces code-owner review and the named upstream handle has no collaborator access here, work item 6.3's PR is unmergeable until a fork-scoped entry is added.
