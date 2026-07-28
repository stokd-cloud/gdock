# Brand Identity De-hardcoding for Fork Rebranding

## 0. Source Context

**Derived From:** "Simplify fork rebranding. cmux is reused code from everywhere; the least they could do is land a PR that reduces how many times the word `cmux` is hard-coded. Rebranding requires jumping through hoops to configure a pipeline that takes downstream changes and still does its own thing. ~79k instances were reported. Identify the different contexts it is used in (application name vs CLI vs ENV prefix etc.) and be able to update a couple of things and generate the exact same build afterwards."

**Feature Name:** Brand Identity De-hardcoding
**PRD Owner:** Brian Stoker (`stokd-cloud/ghostty-dock`)
**Last Updated:** 2026-07-28
**Upstream:** `manaflow-ai/cmux` · **Fork:** `stokd-cloud/ghostty-dock`

### Summary

The literal token `cmux` appears **94,010 times across 5,310 files** (measured case-insensitively, excluding the `ghostty/` and `vendor/bonsplit/` submodules). Those occurrences are not one thing — they are at least a dozen structurally distinct identity contexts (product display name, macOS bundle-ID root, iOS bundle-ID root, CLI binary name, `CMUX_*` environment prefix, config directory, runtime state directory, socket path, URL scheme, exported UTType root, os_log subsystem, keychain service, ExtensionKit extension-point ID, Sparkle feed URL, package/registry names, and localized prose). Today a fork must find and edit all of them by hand, and there is no way to prove the result is equivalent to an unmodified build.

This PRD introduces a single brand manifest plus a code generator, migrates the *identity* contexts (not the prose, not the internal symbol names) to consume it, and adds an executable build-equivalence gate so a rebrand is provably a no-op when the manifest holds the current values. It is written so the bulk of the work lands as **upstream PRs** that benefit every fork, with only manifest values and fork-sync plumbing staying fork-only.

Critically, this is **not** a mass rename. Every default in the manifest is exactly today's value, so a correct implementation changes the built product's identity surface by zero bytes. That property is the primary acceptance gate, not a nice-to-have.

### Grounded findings this PRD is built on

- **Existing seams already prove the concept.** `scripts/reload.sh` already rewrites app name, bundle ID, socket path, URL scheme, and ~15 `LSEnvironment` keys per `--tag` via `xcodebuild` arguments and `PlistBuddy`. `ios/Config/Shared.xcconfig` + `ios/Config/Release.xcconfig` already drive `ios/Config/Info.plist` entirely through `$(...)` substitution. The macOS side is the outlier.
- **No single source of truth exists.** A repo-wide search for `BrandConfig`, `AppConstants`, or `AppIdentity` returns zero hits. Identity is split between build settings and unrelated Swift string literals.
- **Three identifier roots already coexist and have drifted:** `com.cmuxterm.app` (current macOS bundle ID), `dev.cmux.ios` (iOS), and `ai.manaflow.cmux` (a *former* bundle ID still hardcoded in os_log subsystems — proven by `Packages/macOS/CMUXProjectModel/Tests` fixtures asserting `PRODUCT_BUNDLE_IDENTIFIER == "ai.manaflow.cmux"`). A previous rename in this codebase was never fully propagated. This PRD's inventory tool exists specifically so that cannot happen silently again.
- **There is a precedent to follow.** Commit `d675f0a0e3` ("rebrand: mux -> cmux-tui (#7710)") renamed a whole subproject: it kept the wire protocol version stable, shipped dual-read env/config fallbacks rather than a hard cutover, deliberately left trusted-publisher-pinned CI workflow filenames untouched, and claimed a "grep audit clean" as its verification step. This PRD generalises that last step into a committed, CI-enforced tool.
- **No reproducibility check exists today.** Nothing in the repo compares two builds. Artifact-level integrity checks do exist (`shasum` pinning of the GhosttyKit xcframework, `otool` SDK assertions, `codesign -d --entitlements` assertions), which is the pattern the new equivalence gate imitates.

## 1. Objectives & Constraints

### Objectives

- Define a closed, documented taxonomy of the identity contexts `cmux` occupies, with a committed, machine-readable census so the count can be tracked rather than guessed.
- Introduce exactly one file a fork edits to rebrand the identity surface, with generated per-language constants so no consumer hardcodes a brand token.
- Guarantee, by executable check, that with default manifest values the built app's identity surface is byte-identical to a pre-change build.
- Keep the upstream-facing change set PR-sized, self-contained, and free of fork-specific content.
- Close the currently-undefined `upstream-main` → `main` ingest path so the fork can actually consume downstream changes (the stated motivation).

### Constraints

- **No behavioural change.** Defaults equal current values. Any diff in the built identity surface is a defect, not a trade-off.
- **Localized prose is out of scope.** `Resources/Localizable.xcstrings` (~2,842 `cmux` hits) and the 20 `web/messages/*.json` catalogues (1,117–1,422 hits each) contain product-name *prose*, not identifiers. Touching them triggers `.github/review-bot-rules/full-internationalization.md`, which requires complete translations for every locale in the same PR. Prose is inventoried and categorised but not migrated here.
- **Internal symbol names are out of scope.** Swift module/package names (`CmuxCore`, `CmuxSettings`, …), Xcode target names, and directory names stay. Renaming them would make every upstream ingest a mass-conflict event, which is precisely the cost this PRD exists to avoid.
- **Registry-bound and trust-bound names must not move.** npm/PyPI/crates names, the Homebrew cask, and OIDC trusted-publisher workflow filenames are left alone, per the `#7710` precedent.
- **Sparkle keys are cryptographic, not cosmetic.** `SUPublicEDKey` is a real Ed25519 public key bound to the maintainers' private key. A fork needs its own keypair; the manifest carries the feed URL and key as values but the PRD never implies renaming substitutes for re-keying.
- **Review-bot compatibility.** `.github/review-bot-rules/no-ambient-global-state.md` flags new static/global namespaces and `.github/review-bot-rules/swift-architectural-rethink.md` flags compat shims that paper over a missing single source of truth. The generated type is a single source of truth (which those rules ask for) and every compat fallback is time-boxed and documented at its call site.
- **CI is currently `workflow_dispatch`-only.** `.github/workflows/ci.yml` is explicitly paused for PRs and pushes. New guards are wired into the existing `workflow-guard-tests` job so they activate when CI resumes, and every guard must also be runnable locally.

## 1.5 Required Toolchain

| Tool | Min Version | Install Command | Verify Command |
|------|-------------|-----------------|----------------|
| Xcode | per `.xcode-version` | Apple Developer downloads | `cat .xcode-version && xcodebuild -version` |
| Python | 3.11 | `brew install python@3.11` | `python3 --version` |
| Bun | 1.1 | `brew install oven-sh/bun/bun` | `bun --version` |
| Zig | per `ghostty` submodule pin | `brew install zig` | `zig version` |
| ripgrep | 14 | `brew install ripgrep` | `rg --version` |
| GitHub CLI | 2.40 | `brew install gh` | `gh --version` |

Note: `scripts/reload.sh` currently requires `CMUX_SKIP_ZIG_BUILD=1` on hosts whose Zig is newer than the `ghostty` submodule pin; every reload invocation below sets it.

## 2. Execution Phases

## Phase 1: Census and Taxonomy

**Purpose:** Nothing downstream can be scoped, sized, or proven without a measurement instrument. The category set produced here literally determines the key set of the Phase 2 manifest, and the baseline census is the only way to demonstrate that later phases reduce the hardcoded surface rather than merely relocating it. This phase writes no product code and can therefore land first with zero risk.

### 1.1 Brand occurrence inventory tool

**Landing:** upstream-PR

**Implementation Details**
- Create `scripts/brand-inventory.py` (new file), a dependency-free Python 3.11 script.
- It walks the repo from the git root, honouring a hardcoded exclusion list: `.git/`, `ghostty/`, `vendor/`, `node_modules/`, `.build/`, `build-universal/`, `DerivedData/`, and any path matched by `git check-ignore`.
- For every case-insensitive match of `cmux` it emits one record: `path`, `line`, `column`, `matched_text`, `category`, `subcategory`.
- Classification is rule-driven and ordered; the first matching rule wins. Rules are declared as a literal table at the top of the file so a reviewer can read the whole taxonomy in one screen. Categories are exactly those enumerated in work item 1.2.
- Any occurrence matching no rule is assigned category `unclassified`. `unclassified` is a first-class output, not an error — the tool's honesty depends on it being visible.
- Modes: default prints a per-category summary table to stdout; `--tsv <path>` writes the full record set sorted by `(category, path, line)`; `--json` writes the summary as JSON; `--check <baseline.tsv>` compares per-category counts against a baseline and exits 1 if any category *increased*.
- Failure modes to handle explicitly: non-UTF-8 files (decode with `errors="replace"`, never crash); binary files (skip via null-byte sniff); symlinks (do not follow); a missing baseline in `--check` mode (exit 2 with a distinct message, not 1).
- Output must be deterministic: sorted paths, `LC_ALL=C` ordering, no timestamps, no absolute paths.

**Acceptance Criteria**
- AC-1.1.a: The rule table is a single literal declaration at module top level → a reviewer can enumerate every category without reading the walk logic.
- AC-1.1.b: Given the same working tree, two consecutive runs produce byte-identical TSV output → the census is usable as a committed baseline.
- AC-1.1.c: `python3 scripts/brand-inventory.py --json` → exit 0 and valid JSON on stdout whose `total` field is greater than 90000.
- AC-1.1.d: `python3 scripts/brand-inventory.py --check /nonexistent.tsv` → exit 2, not 1 or 0.
- AC-1.1.e: The reported `ghostty/` and `vendor/` counts are zero → submodules are genuinely excluded.

**Acceptance Tests**
- Test-1.1.a: Unit — feed the classifier a fixture line per category and assert the returned category.
- Test-1.1.b: Regression — run the tool twice, `diff` the two TSVs, assert empty.
- Test-1.1.c: Integration — parse the `--json` output and assert `total > 90000`.
- Test-1.1.d: Unit — invoke `--check` with a missing path, assert exit code 2.
- Test-1.1.e: Integration — assert no output record has a path starting `ghostty/` or `vendor/`.

**Verification Commands**
```bash
python3 scripts/brand-inventory.py --json > /tmp/bi.json   # (new file)
python3 -c "import json,sys; d=json.load(open('/tmp/bi.json')); assert d['total']>90000, d['total']"
python3 scripts/brand-inventory.py --tsv /tmp/a.tsv && python3 scripts/brand-inventory.py --tsv /tmp/b.tsv   # (new file)
diff -q /tmp/a.tsv /tmp/b.tsv
! rg -q '^(ghostty|vendor)/' /tmp/a.tsv
python3 scripts/brand-inventory.py --check /nonexistent.tsv; test $? -eq 2   # (new file)
```

### 1.2 Identity taxonomy document

**Landing:** upstream-PR

**Implementation Details**
- Create `docs/brand-identity.md` (new file) defining every category the tool emits. For each: a one-line definition, whether it is compile-time or runtime, whether it is a cross-process contract, whether it is externally published, and whether this PRD migrates it.
- The closed category set is: `product-name`, `bundle-id-macos`, `bundle-id-ios`, `cli-binary`, `daemon-binary`, `env-prefix`, `config-path`, `state-path`, `socket-path`, `url-scheme`, `uttype`, `log-subsystem`, `keychain-service`, `extension-point-id`, `update-feed`, `package-registry-name`, `swift-module-name`, `xcode-target-name`, `localized-prose`, `docs-and-marketing`, `test-fixture`, `ci-workflow-name`, `unclassified`.
- The document must record, with file references, the three drifted identifier roots (`com.cmuxterm.app`, `dev.cmux.ios`, `ai.manaflow.cmux`) and state that `ai.manaflow.cmux` in os_log subsystems is residue from an incomplete prior rename.
- It must record the categories deliberately **not** migrated and the reason for each, so the scope boundary is reviewable rather than implicit.
- It must document the cross-process contract subset explicitly: which env vars and paths the app, the CLI, `cmuxd`, and the TUI must agree on.

**Acceptance Criteria**
- AC-1.2.a: Every category string emitted by `scripts/brand-inventory.py` has a corresponding section heading in `docs/brand-identity.md` → tool and doc cannot drift.
- AC-1.2.b: The document names all three identifier roots and marks `ai.manaflow.cmux` as prior-rename residue.
- AC-1.2.c: Each non-migrated category carries an explicit stated reason.
- AC-1.2.d: `python3 scripts/brand-inventory.py --json | python3 -c "..."` cross-check of category names against doc headings → exit 0.

**Acceptance Tests**
- Test-1.2.a: Integration — extract category names from the tool's JSON and heading slugs from the doc, assert set equality.
- Test-1.2.b: Unit — grep the doc for each of the three identifier roots, assert all present.
- Test-1.2.c: Unit — assert every category marked `migrated: no` has a non-empty `reason:` field.
- Test-1.2.d: Regression — the cross-check runs in CI so adding a tool category without documenting it fails.

**Verification Commands**
```bash
test -f docs/brand-identity.md   # (new file)
rg -q 'com\.cmuxterm\.app' docs/brand-identity.md   # (new file)
rg -q 'dev\.cmux\.ios' docs/brand-identity.md   # (new file)
rg -q 'ai\.manaflow\.cmux' docs/brand-identity.md   # (new file)
python3 scripts/brand-inventory.py --json | python3 - --doc docs/brand-identity.md <<'PY'
import json,sys,re
d=json.load(sys.stdin); doc=open(sys.argv[2]).read()
missing=[c for c in d['categories'] if not re.search(r'^#+\s.*`?%s`?'%re.escape(c), doc, re.M)]
sys.exit(1 if missing else 0)
PY
```

### 1.3 Committed baseline and non-increase ratchet

**Landing:** upstream-PR

**Implementation Details**
- Generate and commit `scripts/brand-inventory-baseline.tsv` (new file) from the tool at the merge base.
- Create `tests/test_ci_brand_inventory_ratchet.sh` (new file) invoking `python3 scripts/brand-inventory.py --check scripts/brand-inventory-baseline.tsv`, following the existing wrapper convention used by `tests/test_ci_pbxproj_test_wiring.sh`.
- Wire that test into the `workflow-guard-tests` job in `.github/workflows/ci.yml` as a new step, placed alongside the other guard steps.
- The ratchet is **non-increase**, not equality: a category count may fall freely (that is the point) but may not rise. This lets later phases reduce counts without a baseline update on every commit, while blocking new hardcoding.
- Document in `docs/brand-identity.md` how to regenerate the baseline and when doing so is legitimate.

**Acceptance Criteria**
- AC-1.3.a: `scripts/brand-inventory-baseline.tsv` is tracked by git → the census is reviewable in diffs.
- AC-1.3.b: `./tests/test_ci_brand_inventory_ratchet.sh` → exit 0 on the unmodified tree.
- AC-1.3.c: Introducing a new hardcoded `cmux` token in a migrated category makes the ratchet exit 1 → the guard is not vacuous.
- AC-1.3.d: `.github/workflows/ci.yml` contains a `workflow-guard-tests` step invoking the ratchet script.

**Acceptance Tests**
- Test-1.3.a: Unit — `git ls-files --error-unmatch` on the baseline path.
- Test-1.3.b: Integration — run the ratchet on a clean tree, assert exit 0.
- Test-1.3.c: Regression — append a line containing a hardcoded bundle-ID literal to a scratch Swift file, re-run, assert exit 1, then remove it. This is the red proof that the guard bites.
- Test-1.3.d: Unit — grep `.github/workflows/ci.yml` for the script name.

**Verification Commands**
```bash
git ls-files --error-unmatch scripts/brand-inventory-baseline.tsv   # (new file)
./tests/test_ci_brand_inventory_ratchet.sh   # (new file)
rg -q 'test_ci_brand_inventory_ratchet' .github/workflows/ci.yml
```

## Phase 2: Brand Manifest and Generator

**Purpose:** Cannot begin until Phase 1 closes the category set, because the manifest's key set *is* the migrated subset of that taxonomy — authoring it earlier would mean guessing. Everything in Phases 3 through 5 consumes the artefacts generated here, so they must exist and be byte-stable before any consumer can reference them.

### 2.1 The brand manifest

**Landing:** upstream-PR

**Implementation Details**
- Create `config/brand.json` (new file): the single file a fork edits. Every value defaults to exactly today's value, verified against the sources cited in this PRD.
- Key set, one per migrated category: `productName` (`cmux`), `bundleIdMacOS` (`com.cmuxterm.app`), `bundleIdIOS` (`dev.cmux.ios`), `cliBinaryName` (`cmux`), `daemonBinaryName` (`cmuxd`), `envPrefix` (`CMUX`), `configDirName` (`cmux`), `configFileName` (`cmux.json`), `stateDirName` (`cmux`), `socketBaseName` (`cmux`), `urlScheme` (`cmux`), `utTypeRoot` (`com.cmux`), `logSubsystem` (`com.cmuxterm.app`), `keychainServiceRoot` (`com.cmuxterm.app`), `extensionPointSuffix` (`cmux.sidebar`), `updateFeedURL`, `sparklePublicKey`, `dmgAssetName` (`cmux-macos.dmg`), `githubRepo` (`manaflow-ai/cmux`), `homepageDomain` (`cmux.com`).
- A `legacy` object carries read-only compatibility values consumed in Phase 4: `envPrefixes` (`["CMUX"]`), `configDirNames` (`["cmux"]`), `bundleIdRoots` (`["ai.manaflow.cmux"]`), `logSubsystems` (`["ai.manaflow.cmux", "ai.manaflow.cmux.ios"]`).
- A sibling `config/brand.schema.json` (new file) constrains the shape: all keys required, all string values non-empty, `envPrefix` matching `^[A-Z][A-Z0-9_]*$`, `bundleIdMacOS`/`bundleIdIOS` matching reverse-DNS, `updateFeedURL` an absolute https URL.
- Deliberately **absent** keys, because they are registry- or trust-bound: npm/PyPI/crates package names, the Homebrew cask name, Swift module names, Xcode target names, CI workflow filenames. `docs/brand-identity.md` states this.

**Acceptance Criteria**
- AC-2.1.a: Every manifest value equals the value currently in the repo at the file cited for it in this PRD → the manifest is a description of today, not a proposal.
- AC-2.1.b: `config/brand.json` validates against `config/brand.schema.json`.
- AC-2.1.c: The manifest contains no key for any registry- or trust-bound name.
- AC-2.1.d: A manifest with an empty-string value fails schema validation → the schema is not permissive.

**Acceptance Tests**
- Test-2.1.a: Integration — assert `bundleIdMacOS` equals the `PRODUCT_BUNDLE_IDENTIFIER` parsed from `cmux.xcodeproj/project.pbxproj` Release config, and `bundleIdIOS` equals the value in `ios/Config/Shared.xcconfig`.
- Test-2.1.b: Unit — validate the manifest against the schema.
- Test-2.1.c: Unit — assert the absence of the excluded key names.
- Test-2.1.d: Regression — mutate a value to `""` in a temp copy, assert validation fails.

**Verification Commands**
```bash
python3 -c "import json;json.load(open('config/brand.json'))"   # (new file)
python3 - <<'PY'
import json,re
b=json.load(open('config/brand.json'))
pbx=open('cmux.xcodeproj/project.pbxproj').read()
assert b['bundleIdMacOS'] in pbx, 'macOS bundle id not found in pbxproj'
assert b['bundleIdIOS'] in open('ios/Config/Shared.xcconfig').read()
for k in ('npmPackage','homebrewCask','pypiPackage','cargoCrate','swiftModule'):
    assert k not in b, f'{k} must not be in the manifest'
assert re.fullmatch(r'[A-Z][A-Z0-9_]*', b['envPrefix'])
PY
```

### 2.2 Source generator

**Landing:** upstream-PR

**Implementation Details**
- Create `scripts/generate-brand-sources.py` (new file) reading `config/brand.json` and emitting four committed artefacts:
  - `config/Brand.xcconfig` (new file) — `BRAND_PRODUCT_NAME`, `BRAND_BUNDLE_ID`, `BRAND_URL_SCHEME`, `BRAND_EXTENSION_POINT_ID`, `BRAND_UTTYPE_ROOT`, `BRAND_ENV_PREFIX`, and the iOS equivalents.
  - `Sources/Generated/BrandIdentity.swift` (new file) — a single `public enum BrandIdentity` with `static let` constants, one per manifest key, plus `static let legacyEnvPrefixes: [String]` and the other legacy arrays.
  - `scripts/lib/brand.sh` (new file) — POSIX-shell `BRAND_*` variable assignments for `scripts/reload.sh` and friends to `source`.
  - `web/lib/generated/brand.ts` (new file) — an exported const object for web/docs consumers.
- Every generated file carries a `DO NOT EDIT — generated by scripts/generate-brand-sources.py from config/brand.json` header as the first line.
- `--check` mode regenerates into a temp dir and diffs against the committed files, exiting 1 on drift. This follows the existing `agent-session-web-resources` CI pattern of build-then-`git diff --exit-code`.
- Output must be deterministic: keys emitted in manifest declaration order, no timestamps, trailing newline, LF line endings.
- Failure modes: manifest missing (exit 2), manifest failing schema validation (exit 3, with the failing key named), unwritable output dir (exit 4).
- `BrandIdentity` is an `enum` with only static members — it is a namespace of compile-time constants, not mutable ambient state. This is the single source of truth that `.github/review-bot-rules/reliability-single-source-of-truth.md` asks for; the rationale is stated in the file header so reviewers and bots see it inline.

**Acceptance Criteria**
- AC-2.2.a: All four generated files begin with the DO-NOT-EDIT header naming the generator and the manifest.
- AC-2.2.b: `python3 scripts/generate-brand-sources.py --check` → exit 0 on a clean tree.
- AC-2.2.c: Running the generator twice produces byte-identical output → determinism.
- AC-2.2.d: Editing a generated file by hand makes `--check` exit 1 → the check is not vacuous.
- AC-2.2.e: `BrandIdentity` declares no `var` and no mutable static storage → it cannot become ambient state.

**Acceptance Tests**
- Test-2.2.a: Unit — assert the header on each of the four outputs.
- Test-2.2.b: Integration — run `--check` on a clean tree, assert exit 0.
- Test-2.2.c: Regression — generate twice into temp dirs, `diff -r`, assert empty.
- Test-2.2.d: Regression — append a line to the generated Swift file, assert `--check` exits 1, then restore.
- Test-2.2.e: Unit — grep the generated Swift for `static var` / `var `, assert zero matches.

**Verification Commands**
```bash
python3 scripts/generate-brand-sources.py --check   # (new file)
for f in config/Brand.xcconfig Sources/Generated/BrandIdentity.swift scripts/lib/brand.sh web/lib/generated/brand.ts; do   # (new file)
  head -1 "$f" | rg -q 'DO NOT EDIT' || exit 1
done
! rg -q '^\s*(public\s+)?static\s+var|^\s*var\s' Sources/Generated/BrandIdentity.swift   # (new file)
```

### 2.3 Generator drift guard in CI

**Landing:** upstream-PR

**Implementation Details**
- Add a `workflow-guard-tests` step in `.github/workflows/ci.yml` running `python3 scripts/generate-brand-sources.py --check`, mirroring how `python3 scripts/check-workspace-package-groups.py --check` is wired.
- Add the same invocation to the pre-commit hook installed by `scripts/install-git-hooks.sh`, alongside the existing `scripts/normalize-pbxproj.py` step, so drift is caught before push rather than in CI.
- Document the regeneration command in `CONTRIBUTING.md` under a new "Brand identity" subsection.

**Acceptance Criteria**
- AC-2.3.a: `.github/workflows/ci.yml` contains a step invoking the generator in `--check` mode.
- AC-2.3.b: `scripts/install-git-hooks.sh` installs a hook that runs the generator check.
- AC-2.3.c: `CONTRIBUTING.md` documents how to regenerate after editing the manifest.
- AC-2.3.d: With the manifest edited but generated files stale, the CI step fails → the guard bites.

**Acceptance Tests**
- Test-2.3.a: Unit — grep the workflow for `generate-brand-sources.py`.
- Test-2.3.b: Unit — grep the hook installer for the same.
- Test-2.3.c: Unit — grep `CONTRIBUTING.md` for the regeneration command.
- Test-2.3.d: Regression — mutate `productName` in a temp copy of the manifest, run `--check` against it, assert exit 1.

**Verification Commands**
```bash
rg -q 'generate-brand-sources' .github/workflows/ci.yml
rg -q 'generate-brand-sources' scripts/install-git-hooks.sh
rg -q 'generate-brand-sources' CONTRIBUTING.md
```

## Phase 3: Build-Time Identity Migration

**Purpose:** Cannot start before Phase 2, because the Xcode project must `#include` a `config/Brand.xcconfig` that exists and the app target must compile a `BrandIdentity.swift` that exists. This phase is also where the build-equivalence golden file is captured, and that capture must happen against a tree where the generated inputs are already stable — otherwise the golden would encode a moving target.

### 3.1 macOS build settings routed through the manifest

**Landing:** upstream-PR

**Implementation Details**
- Add `config/Brand.xcconfig` as a base configuration file for the `cmux`, `cmux-cli`, `CmuxDockTilePlugin`, `cmuxTests`, and `cmuxUITests` targets in `cmux.xcodeproj/project.pbxproj`.
- Replace the literal values at the Debug and Release build-setting entries with references: `PRODUCT_NAME = $(BRAND_PRODUCT_NAME)`, `PRODUCT_BUNDLE_IDENTIFIER = $(BRAND_BUNDLE_ID)`, `CMUX_SIDEBAR_EXTENSION_POINT_ID = $(BRAND_BUNDLE_ID).$(BRAND_EXTENSION_POINT_SUFFIX)`, `CMUX_AUTH_CALLBACK_SCHEME = $(BRAND_URL_SCHEME)`.
- The Debug variants keep their existing suffixing behaviour (`… DEV`, `.debug`, `cmux-dev`) by composing from the `BRAND_*` values rather than by hardcoding.
- Run `python3 scripts/normalize-pbxproj.py` after editing so the diff stays reviewable, and confirm `./scripts/check-pbxproj.sh` still passes.
- Failure modes: an xcconfig not actually applied silently falls back to an empty `PRODUCT_NAME`, producing an app named `.app`. The equivalence gate in work item 3.4 is what catches this; do not rely on the build merely succeeding.

**Acceptance Criteria**
- AC-3.1.a: No literal `com.cmuxterm.app` or `PRODUCT_NAME = cmux` remains in `cmux.xcodeproj/project.pbxproj` → the pbxproj no longer owns identity.
- AC-3.1.b: `./scripts/check-pbxproj.sh` → exit 0.
- AC-3.1.c: A Debug build produces an app whose `CFBundleIdentifier` is unchanged from before the change.
- AC-3.1.d: `CMUX_SKIP_ZIG_BUILD=1 ./scripts/reload.sh --tag brand-p3` → exit 0.

**Acceptance Tests**
- Test-3.1.a: Unit — grep the pbxproj for the literals, assert zero matches.
- Test-3.1.b: Integration — run the pbxproj checker.
- Test-3.1.c: Integration — `PlistBuddy -c 'Print :CFBundleIdentifier'` on the built app, assert the expected value.
- Test-3.1.d: E2E — tagged reload build succeeds.

**Verification Commands**
```bash
./scripts/check-pbxproj.sh
! rg -q 'PRODUCT_BUNDLE_IDENTIFIER = com\.cmuxterm\.app;' cmux.xcodeproj/project.pbxproj
! rg -q 'PRODUCT_NAME = cmux;' cmux.xcodeproj/project.pbxproj
CMUX_SKIP_ZIG_BUILD=1 ./scripts/reload.sh --tag brand-p3
```

### 3.2 iOS build settings routed through the manifest

**Landing:** upstream-PR

**Implementation Details**
- Add `#include "../../config/Brand.xcconfig"` at the top of `ios/Config/Shared.xcconfig`.
- Replace the literals: `PRODUCT_NAME = $(BRAND_IOS_PRODUCT_NAME)`, `PRODUCT_DISPLAY_NAME = $(BRAND_IOS_PRODUCT_NAME)`, `PRODUCT_BUNDLE_IDENTIFIER = $(BRAND_BUNDLE_ID_IOS)`, `CMUX_IOS_URL_SCHEME = $(BRAND_URL_SCHEME)-ios-dev`.
- Apply the same treatment to `ios/Config/Release.xcconfig`, preserving its `BETA` display-name suffix and `dev.cmux.app.beta` bundle ID by composing them from `BRAND_*` values.
- `ios/Config/Info.plist` requires no edit — it already consumes these purely through `$(...)` substitution.
- Do **not** touch `ios/scripts/upload-testflight.sh`. Its `IOS_BETA_BUNDLE_ID` / `IOS_APPSTORE_BUNDLE_ID` defaults are bound to real App Store Connect records; changing them requires provisioning work outside this PRD. Record this in `docs/brand-identity.md`.

**Acceptance Criteria**
- AC-3.2.a: `ios/Config/Shared.xcconfig` contains no literal `dev.cmux.ios` and no bare `PRODUCT_NAME = cmux`.
- AC-3.2.b: `ios/Config/Release.xcconfig` still yields the `BETA` display name and `dev.cmux.app.beta` bundle ID after substitution.
- AC-3.2.c: `ios/scripts/upload-testflight.sh` is unmodified by this work item.
- AC-3.2.d: `xcodebuild -showBuildSettings` for the iOS target reports the unchanged pre-migration bundle ID.

**Acceptance Tests**
- Test-3.2.a: Unit — grep the xcconfigs for the literals, assert absent.
- Test-3.2.b: Integration — resolve build settings, assert display name and bundle ID.
- Test-3.2.c: Unit — `git diff --name-only` for this work item does not list the upload script.
- Test-3.2.d: Integration — compare `showBuildSettings` output before and after.

**Verification Commands**
```bash
! rg -q '^PRODUCT_BUNDLE_IDENTIFIER = dev\.cmux\.ios' ios/Config/Shared.xcconfig
rg -q 'BRAND_' ios/Config/Shared.xcconfig
git diff --name-only origin/main -- ios/scripts/upload-testflight.sh | wc -l | rg -q '^0$'
```

### 3.3 Info.plist literal removal

**Landing:** upstream-PR

**Implementation Details**
- In `Resources/Info.plist`, replace the remaining hardcoded identity literals with build-setting references: the two `UTExportedTypeDeclarations` identifiers `com.cmux.sidebar-tab-reorder` and `com.cmux.filepreview.transfer` become `$(BRAND_UTTYPE_ROOT).sidebar-tab-reorder` and `$(BRAND_UTTYPE_ROOT).filepreview.transfer`; `SUFeedURL` becomes `$(BRAND_UPDATE_FEED_URL)`; the `NSExceptionDomains` key `cmux-loopback.localtest.me` becomes `$(BRAND_LOOPBACK_HOST)`.
- Leave `NSDockTilePlugIn` (`CmuxDockTilePlugin.plugin`) and `OSAScriptingDefinition` (`cmux.sdef`) as literals — they name build products whose target names this PRD deliberately does not rename. Record both in `docs/brand-identity.md` under a non-migrated category.
- The four `NS*UsageDescription` strings ("A program running within cmux would like to…") are user-facing prose and are categorised `localized-prose`; they are out of scope per the Phase 1 constraint and are **not** touched here.
- Do not touch `SUPublicEDKey` — it already reads `$(SPARKLE_PUBLIC_KEY)`, and the key material itself is a re-keying concern, not a naming one.

**Acceptance Criteria**
- AC-3.3.a: `Resources/Info.plist` contains no literal `com.cmux.` UTType identifier.
- AC-3.3.b: `Resources/Info.plist` contains no literal `github.com/manaflow-ai/cmux` feed URL.
- AC-3.3.c: The `NS*UsageDescription` strings are unchanged → prose scope boundary respected.
- AC-3.3.d: A built app's `UTExportedTypeDeclarations` identifiers resolve to the same strings as before the change.

**Acceptance Tests**
- Test-3.3.a: Unit — grep the plist for `com.cmux.`, assert zero matches.
- Test-3.3.b: Unit — grep for the literal feed URL, assert zero matches.
- Test-3.3.c: Regression — diff the four usage-description values against the pre-change values, assert identical.
- Test-3.3.d: Integration — `PlistBuddy` the built app's UTType identifiers, assert unchanged values.

**Verification Commands**
```bash
! rg -q 'com\.cmux\.(sidebar-tab-reorder|filepreview)' Resources/Info.plist
! rg -q 'github\.com/manaflow-ai/cmux/releases' Resources/Info.plist
rg -q 'would like to' Resources/Info.plist
```

### 3.4 Build-equivalence golden gate

**Landing:** upstream-PR

**Implementation Details**
- Create `scripts/check-brand-build-equivalence.sh` (new file). Given a built `.app` path it extracts a normalised **identity manifest** and prints it deterministically: `CFBundleIdentifier`, `CFBundleName`, `CFBundleDisplayName`, `CFBundleExecutable`, every `CFBundleURLSchemes` entry, every `UTExportedTypeDeclarations` identifier, `NSExtensionPointIdentifier`, `NSDockTilePlugIn`, `OSAScriptingDefinition`, `SUFeedURL`, `SUPublicEDKey`, every `LSEnvironment` key/value pair, and the entitlement keys from `codesign -d --entitlements :-`.
- Values are sorted, whitespace-normalised, and version/build numbers are elided so the manifest is stable across version bumps.
- Commit `scripts/brand-identity-golden.txt` (new file), captured from a build of the **merge base** (pre-change). Regenerating it is a reviewable diff, which is exactly the intent — a change to the golden file is a change to the product's identity surface and must be justified in the PR.
- `--verify <app>` diffs a fresh extraction against the golden and exits 1 on any difference.
- This is the executable form of "generate the exact same build afterwards". It deliberately asserts identity-surface equality rather than binary byte-equality, because Swift builds embed non-deterministic UUIDs and paths; claiming bit-identical output would be an unverifiable promise.
- Wire into `workflow-guard-tests` where a built app is available, and document local usage in `docs/brand-identity.md`.

**Acceptance Criteria**
- AC-3.4.a: The golden file was captured from a merge-base build, not from a post-change build → it is a genuine control.
- AC-3.4.b: `./scripts/check-brand-build-equivalence.sh --verify <app>` → exit 0 for an app built at the tip of Phase 3.
- AC-3.4.c: Changing any manifest value and rebuilding makes `--verify` exit 1 → the gate is not vacuous.
- AC-3.4.d: Two extractions from the same app produce byte-identical output → determinism.
- AC-3.4.e: The extracted manifest contains no `MARKETING_VERSION` or build-number value → stable across releases.

**Acceptance Tests**
- Test-3.4.a: Integration — capture from a merge-base build, assert it differs from an empty file and records the pre-change bundle ID.
- Test-3.4.b: E2E — build at Phase 3 tip, run `--verify`, assert exit 0. This is the green proof of the whole phase.
- Test-3.4.c: Regression — set `productName` to `zzbrand`, regenerate, rebuild, assert `--verify` exits 1, then revert. This is the red proof.
- Test-3.4.d: Unit — extract twice, `diff`, assert empty.
- Test-3.4.e: Unit — grep the golden for a version-shaped token, assert absent.

**Verification Commands**
```bash
CMUX_SKIP_ZIG_BUILD=1 ./scripts/reload.sh --tag brand-eq
APP=$(CMUX_SKIP_ZIG_BUILD=1 ./scripts/reload.sh --tag brand-eq | rg -A1 '^App path:' | tail -1 | sed 's/^ *//')
./scripts/check-brand-build-equivalence.sh --verify "$APP"   # (new file)
./scripts/check-brand-build-equivalence.sh "$APP" > /tmp/e1.txt   # (new file)
./scripts/check-brand-build-equivalence.sh "$APP" > /tmp/e2.txt   # (new file)
diff -q /tmp/e1.txt /tmp/e2.txt
! rg -q '[0-9]+\.[0-9]+\.[0-9]+' scripts/brand-identity-golden.txt   # (new file)
```

## Phase 4: Runtime Path and Cross-Process Contract Migration

**Purpose:** Cannot start before Phase 3, because `Sources/Generated/BrandIdentity.swift` must actually be compiled into the app and its packages — which only happens once Phase 3 has added it to the target's sources — before any Swift call site can reference it. This phase is also the only one that touches cross-process contracts, so it must run after the build-equivalence gate exists to catch regressions.

### 4.1 Configuration path resolution

**Landing:** upstream-PR

**Implementation Details**
- Replace the hardcoded `.config/cmux/cmux.json` path segments with `BrandIdentity`-derived values at: `Packages/macOS/CmuxSettings/Sources/CmuxSettings/Stores/CmuxConfigLocation.swift` (`userConfigFile`, `legacyFallbackFile`), `Sources/CmuxConfig.swift` (`CmuxConfigStore.defaultGlobalConfigPath()`), `Sources/KeyboardShortcutSettingsFileStore.swift`, and `CLI/CMUXCLI+DocsSettings.swift`.
- Introduce a single resolver returning the ordered candidate list: the brand path first, then every `legacy.configDirNames` path. Reads walk the list and use the first hit; writes always target the brand path.
- **Non-destructive by construction:** the legacy file is never deleted, moved, or truncated. A fork's users keep a working fallback if they downgrade.
- Failure modes: both paths absent (fall through to existing defaults, unchanged); brand path unreadable but legacy readable (use legacy, log once at debug level); a directory where a file is expected (skip that candidate rather than throwing).
- One resolver, one mutation path — satisfying the repo's shared-behaviour policy rather than adding a second optimistic copy per call site.

**Acceptance Criteria**
- AC-4.1.a: All four cited files derive their path from `BrandIdentity` rather than a string literal.
- AC-4.1.b: With only a legacy config present, the app reads it → no user loses settings.
- AC-4.1.c: After a write, the brand path exists and the legacy file is byte-unchanged → non-destructive.
- AC-4.1.d: With defaults, the resolved path is exactly `~/.config/cmux/cmux.json` → behaviour is unchanged.
- AC-4.1.e: `./scripts/test-unit.sh` → exit 0.

**Acceptance Tests**
- Test-4.1.a: Unit — grep the four files for `".config/cmux"`, assert zero matches.
- Test-4.1.b: Unit — resolver test with only the legacy file present, assert it is chosen.
- Test-4.1.c: Regression — write settings, assert the legacy file's hash is unchanged.
- Test-4.1.d: Unit — assert the default resolved path string.
- Test-4.1.e: Integration — full unit suite green.

**Verification Commands**
```bash
! rg -q '"\.config/cmux' Sources/CmuxConfig.swift Sources/KeyboardShortcutSettingsFileStore.swift
! rg -q '"\.config/cmux' Packages/macOS/CmuxSettings/Sources/CmuxSettings/Stores/CmuxConfigLocation.swift
! rg -q '"\.config/cmux' CLI/CMUXCLI+DocsSettings.swift
./scripts/test-unit.sh
```

### 4.2 State directory, socket paths, and channel classification

**Landing:** upstream-PR

**Implementation Details**
- Replace the literal `directoryName = "cmux"` in `Packages/macOS/CmuxSettings/Sources/CmuxSettings/SocketControl/CmuxStateDirectory.swift` with `BrandIdentity.stateDirName`, keeping `legacyApplicationSupportURL` intact for the documented pre-0.64.20 external-client compatibility.
- Replace the bundle-ID literal comparisons in `SocketControl/SocketControlSettings.swift` (`baseDebugBundleIdentifier = "com.cmuxterm.app.debug"`), `SocketControl/SocketControlSettings+DefaultSocketPath.swift`, and `SocketControl/SocketPathMarkerFiles.swift` with comparisons derived from `BrandIdentity.bundleIdMacOS` plus a channel suffix enum (`.stable`, `.debug`, `.nightly`, `.staging`).
- Replace the socket filename literals (`/tmp/cmux-debug.sock`, `-nightly`, `-staging`) with values composed from `BrandIdentity.socketBaseName`.
- **This is the highest-risk work item in the PRD.** A missed literal does not fail loudly: the build falls through to `.stable` classification and silently binds the wrong socket with the wrong password scoping. The Phase 1 ratchet plus the AC below are what make that failure visible.
- The keychain service `com.cmuxterm.app.socket-control` in `SocketControl/SocketControlPasswordStore.swift` derives from `BrandIdentity.keychainServiceRoot`. Renaming it orphans stored passwords, so the store reads the legacy service name as a fallback and re-writes under the brand name on next successful access.

**Acceptance Criteria**
- AC-4.2.a: No bundle-ID string literal remains in any file under `Packages/macOS/CmuxSettings/Sources/CmuxSettings/SocketControl/`.
- AC-4.2.b: Channel classification returns `.debug` for a `…app.debug.<tag>` bundle ID and `.stable` for the bare brand bundle ID → tagged builds are not misclassified.
- AC-4.2.c: With defaults, the resolved debug socket path is exactly `/tmp/cmux-debug.sock` → unchanged behaviour.
- AC-4.2.d: A password stored under the legacy keychain service is still readable after migration.
- AC-4.2.e: `CMUX_TAG=brand-p4 scripts/cmux-debug-cli.sh list-workspaces` against a tagged build → exit 0, proving the app and CLI still agree on the socket.

**Acceptance Tests**
- Test-4.2.a: Unit — grep the SocketControl directory for `com.cmuxterm`, assert zero matches.
- Test-4.2.b: Unit — table-driven classification test over stable/debug/tagged/nightly/staging bundle IDs.
- Test-4.2.c: Unit — assert the default socket path string.
- Test-4.2.d: Regression — seed a legacy-service keychain item, assert the store reads it.
- Test-4.2.e: E2E — tagged build plus a CLI round-trip over the socket.

**Verification Commands**
```bash
! rg -q 'com\.cmuxterm' Packages/macOS/CmuxSettings/Sources/CmuxSettings/SocketControl/
CMUX_SKIP_ZIG_BUILD=1 ./scripts/reload.sh --tag brand-p4 --launch
CMUX_TAG=brand-p4 scripts/cmux-debug-cli.sh list-workspaces
./scripts/test-unit.sh
```

### 4.3 Environment variable prefix indirection

**Landing:** upstream-PR

**Implementation Details**
- Scope is deliberately narrow: only the **cross-process contract** subset identified in `docs/brand-identity.md`, namely `CMUX_SOCKET_PATH`, `CMUXD_UNIX_PATH`, `CMUX_BUNDLE_ID`, `CMUX_TAG`, `CMUX_BUNDLED_CLI_PATH`, `CMUX_AUTH_CALLBACK_SCHEME`, `CMUX_WORKSPACE_ID`, and `CMUX_SURFACE_ID`. The remaining ~1,200 `CMUX_*` names are internal or test-only and stay literal; migrating them would balloon the diff far past PR size for no contract benefit.
- Add a `BrandIdentity.env(_ suffix: String) -> String` helper composing `"\(envPrefix)_\(suffix)"`, and a reader that tries the brand-prefixed name first and then every `legacy.envPrefixes` variant, returning the first non-nil value.
- Writers export **both** the brand-prefixed and legacy names during the compatibility window — exactly the dual-export approach commit `d675f0a0e3` used for `CMUX_TUI_*` / `CMUX_MUX_*`.
- Call sites to update: `Sources/CloudVMActionLauncher.swift`, `Sources/AppDelegate+CmuxSSHURL.swift`, `Sources/SSHPTYAttachStartupCommandBuilder.swift`, `Sources/Workspace.swift`.
- Because the default `envPrefix` is `CMUX`, the brand and legacy names are identical today and dual-export is a literal no-op — which the equivalence gate confirms by showing an unchanged `LSEnvironment` block.
- Document the compatibility window and its removal criteria in `docs/brand-identity.md` so the fallback is time-boxed rather than permanent, addressing `.github/review-bot-rules/swift-architectural-rethink.md`.

**Acceptance Criteria**
- AC-4.3.a: The four cited call sites read env vars through the helper, not through bare string literals.
- AC-4.3.b: With a non-default `envPrefix`, a value set under the legacy name is still read → no silent breakage for existing shells and CI scripts.
- AC-4.3.c: With the default prefix, the built app's `LSEnvironment` block is byte-identical to the golden → dual-export is a no-op today.
- AC-4.3.d: The compatibility window's removal criteria are documented.
- AC-4.3.e: The ~1,200 internal `CMUX_*` names are untouched → diff stays PR-sized.

**Acceptance Tests**
- Test-4.3.a: Unit — grep the four files for the migrated literal names, assert zero matches.
- Test-4.3.b: Unit — set `envPrefix` to `ZZ`, set only `CMUX_SOCKET_PATH`, assert the reader returns it.
- Test-4.3.c: Integration — run the equivalence gate, assert the `LSEnvironment` section matches.
- Test-4.3.d: Unit — grep `docs/brand-identity.md` for the removal criteria heading.
- Test-4.3.e: Integration — assert the inventory's `env-prefix` category fell by fewer than 50.

**Verification Commands**
```bash
! rg -q '"CMUX_SOCKET_PATH"' Sources/CloudVMActionLauncher.swift Sources/Workspace.swift
./scripts/test-unit.sh
CMUX_SKIP_ZIG_BUILD=1 ./scripts/reload.sh --tag brand-p4b
```

### 4.4 Shell tooling routed through the manifest

**Landing:** upstream-PR

**Implementation Details**
- `scripts/reload.sh` sources `scripts/lib/brand.sh` near the top and replaces its hardcoded `APP_NAME="cmux DEV"`, `BUNDLE_ID="com.cmuxterm.app.debug.${TAG_ID}"`, `/tmp/cmux-debug-${TAG_SLUG}.sock`, `cmuxd-dev-${TAG_SLUG}.sock`, derived-data prefix `cmux-`, and URL scheme `cmux-dev-${TAG_SLUG}` with `${BRAND_*}` compositions.
- `scripts/cmux-debug-cli.sh` does the same for its socket path and bundle-ID resolution.
- All existing flags (`--tag`, `--name`, `--bundle-id`, `--derived-data`, `--launch`) keep their current precedence: an explicit flag still overrides the brand-derived default.
- Do not rename the scripts themselves; their filenames are referenced by `CLAUDE.md`, `CONTRIBUTING.md`, CI workflows, and every contributor's muscle memory.

**Acceptance Criteria**
- AC-4.4.a: `scripts/reload.sh` sources `scripts/lib/brand.sh` and contains no literal `com.cmuxterm.app`.
- AC-4.4.b: `CMUX_SKIP_ZIG_BUILD=1 ./scripts/reload.sh --tag brand-p4c` produces an app at the same derived-data path shape as before.
- AC-4.4.c: `--bundle-id` still overrides the brand-derived default → flag precedence preserved.
- AC-4.4.d: The tagged socket path is unchanged from the pre-migration value for the same tag.

**Acceptance Tests**
- Test-4.4.a: Unit — grep `scripts/reload.sh` for the literal and for the `source` line.
- Test-4.4.b: E2E — tagged reload, assert the printed `App path:` matches the expected shape.
- Test-4.4.c: Integration — reload with an explicit `--bundle-id`, assert the built app carries it.
- Test-4.4.d: Regression — compare the computed socket path against the pre-change value for tag `brand-p4c`.

**Verification Commands**
```bash
rg -q 'brand\.sh' scripts/reload.sh
! rg -q 'com\.cmuxterm\.app' scripts/reload.sh scripts/cmux-debug-cli.sh
CMUX_SKIP_ZIG_BUILD=1 ./scripts/reload.sh --tag brand-p4c
```

## Phase 5: Ratchet, Rebrand Proof, and Documentation

**Purpose:** Cannot start before Phases 1 through 4 have landed, because there must be a reduced surface to lock in and a real end-to-end rebrand to exercise. Tightening the ratchet earlier would block the very work items that reduce the counts, and the smoke test needs every consumer already routed through the manifest or it would report a false pass.

### 5.1 Ratchet tightening

**Landing:** upstream-PR

**Implementation Details**
- Regenerate `scripts/brand-inventory-baseline.tsv` at the tip of Phase 4.
- Convert the migrated categories (`bundle-id-macos`, `bundle-id-ios`, `config-path`, `state-path`, `socket-path`, `url-scheme`, `uttype`, `extension-point-id`, `update-feed`) from non-increase to a **hard ceiling of zero outside generated files**: any occurrence in a non-generated file fails the check.
- Non-migrated categories keep non-increase semantics.
- The PR description records the before/after per-category counts so the reduction is a reviewable number rather than a claim.

**Acceptance Criteria**
- AC-5.1.a: Migrated categories report zero occurrences outside generated files and the manifest.
- AC-5.1.b: `./tests/test_ci_brand_inventory_ratchet.sh` → exit 0 at the Phase 5 tip.
- AC-5.1.c: Reintroducing a bundle-ID literal into a Swift source file fails the ratchet → the tightened gate bites.
- AC-5.1.d: The total count fell measurably versus the Phase 1 baseline.

**Acceptance Tests**
- Test-5.1.a: Integration — assert per-category zero for the migrated set.
- Test-5.1.b: Integration — ratchet green.
- Test-5.1.c: Regression — inject a literal, assert exit 1, revert.
- Test-5.1.d: Integration — compare totals against the Phase 1 baseline, assert a decrease.

**Verification Commands**
```bash
./tests/test_ci_brand_inventory_ratchet.sh   # (new file)
python3 scripts/brand-inventory.py --json | python3 -c "
import json,sys; d=json.load(sys.stdin)
migrated=['bundle-id-macos','bundle-id-ios','config-path','state-path','socket-path','url-scheme','uttype','extension-point-id','update-feed']
bad={k:d['categories'][k] for k in migrated if d['categories'].get(k,0)>0}
sys.exit(1 if bad else 0)"
```

### 5.2 End-to-end rebrand smoke test

**Landing:** upstream-PR

**Implementation Details**
- Create `scripts/rebrand-smoke-test.sh` (new file). It copies the repo's manifest to a temp backup, writes a throwaway brand (`productName: zzbrand`, `bundleIdMacOS: com.zzbrand.app`, `envPrefix: ZZBRAND`, and so on), regenerates sources, builds a tagged Debug app, extracts the identity manifest, asserts **zero** occurrences of any original brand token in it, then restores the manifest, regenerates, and asserts the tree is clean.
- It must restore the manifest on any exit path, including failure and interrupt, via a `trap`.
- It never touches the user's real config, sockets, or keychain — the throwaway brand guarantees fully disjoint paths, which is itself part of what the test proves.
- This is the direct executable answer to "update a couple of things and generate the exact same build afterwards": run it with defaults and the identity manifest matches the golden exactly; run it with a throwaway brand and every identity value moves together with no residue.

**Acceptance Criteria**
- AC-5.2.a: After the throwaway rebrand, the extracted identity manifest contains zero occurrences of `cmux` or `cmuxterm`.
- AC-5.2.b: The script restores `config/brand.json` and all generated files on both success and failure → `git status --porcelain` is empty afterwards.
- AC-5.2.c: The rebranded app's socket, config, and state paths are disjoint from the default ones.
- AC-5.2.d: With the manifest left at defaults, the extraction matches `scripts/brand-identity-golden.txt` exactly.
- AC-5.2.e: `./scripts/rebrand-smoke-test.sh` → exit 0.

**Acceptance Tests**
- Test-5.2.a: E2E — rebrand, build, grep the extraction, assert zero hits.
- Test-5.2.b: Regression — force a mid-run failure, assert the tree is still clean.
- Test-5.2.c: Integration — assert path disjointness.
- Test-5.2.d: Integration — default-value run diffs clean against the golden.
- Test-5.2.e: E2E — the whole script exits 0.

**Verification Commands**
```bash
./scripts/rebrand-smoke-test.sh   # (new file)
git status --porcelain | wc -l | rg -q '^0$'
./scripts/check-brand-build-equivalence.sh --verify "$(cat /tmp/brand-smoke-app-path)"   # (new file)
```

### 5.3 Fork documentation

**Landing:** upstream-PR

**Implementation Details**
- Create `docs/forking.md` (new file): the exact steps to rebrand a fork — edit `config/brand.json`, run the generator, run the smoke test, generate a fresh Sparkle keypair, point `updateFeedURL` at the fork's releases, and re-provision App Store Connect records if shipping iOS.
- It must state plainly what a manifest edit does **not** do: it does not rename Swift modules, Xcode targets, directories, registry package names, the Homebrew cask, or localized prose, and it does not re-key Sparkle. Each carries a one-line reason.
- Add a "Brand identity" section to `CONTRIBUTING.md` linking to `docs/brand-identity.md` and `docs/forking.md`.
- All new documentation is contributor-facing English prose, not shipped UI strings, so `.github/review-bot-rules/full-internationalization.md` does not apply. Say so explicitly in the PR description to pre-empt a bot false positive.

**Acceptance Criteria**
- AC-5.3.a: `docs/forking.md` lists every step including Sparkle re-keying and App Store Connect provisioning.
- AC-5.3.b: It enumerates the non-covered surfaces with a reason each.
- AC-5.3.c: `CONTRIBUTING.md` links to both new documents.
- AC-5.3.d: No shipped UI string was added or changed by this work item.

**Acceptance Tests**
- Test-5.3.a: Unit — grep `docs/forking.md` for `SUPublicEDKey` and App Store Connect.
- Test-5.3.b: Unit — assert a "Not covered" section exists with at least six entries.
- Test-5.3.c: Unit — grep `CONTRIBUTING.md` for both document paths.
- Test-5.3.d: Regression — assert `Resources/Localizable.xcstrings` and `web/messages/en.json` are unmodified by this work item.

**Verification Commands**
```bash
rg -q 'SUPublicEDKey' docs/forking.md   # (new file)
rg -q 'App Store Connect' docs/forking.md   # (new file)
rg -q 'docs/brand-identity.md' CONTRIBUTING.md
git diff --name-only origin/main -- Resources/Localizable.xcstrings web/messages/en.json | wc -l | rg -q '^0$'
```

## Phase 6: Upstream Submission and Fork Ingest

**Purpose:** Cannot start until Phases 1 through 5 are complete and green, because the upstream PR split needs a finished, verified change set to carve into self-contained units — splitting a half-done refactor produces PRs that do not build independently. The fork-side ingest work must also come last, since it is what lets the fork consume the upstreamed result back.

### 6.1 Upstream PR split

**Landing:** upstream-PR

**Implementation Details**
- Cut each upstream unit as a topic branch **from `upstream-main`**, never from `main`, so no fork-local content leaks in. Fetch the mirror with `git fetch origin upstream-main:refs/remotes/origin/upstream-main` — there is no `upstream` remote configured locally.
- Five PRs, each independently buildable and reviewable, in dependency order: (1) inventory tool, taxonomy doc, baseline, ratchet; (2) manifest, schema, generator, drift guard; (3) build-settings migration, Info.plist, equivalence gate; (4) runtime paths and cross-process contracts; (5) ratchet tightening, smoke test, fork docs.
- Every PR follows `.github/pull_request_template.md`: summary, testing notes, the review-trigger comment block, and the checklist. PRs 3 and 4 change build and runtime behaviour surfaces and therefore need the demo-video or equivalent evidence the template asks for — the equivalence-gate output serves as that evidence.
- PR 4 must state in its description that the ~1,200 internal `CMUX_*` names are intentionally untouched, with the reason, so a reviewer does not read the partial migration as an oversight.
- No PR modifies `.github/workflows/` filenames, `ios/scripts/upload-testflight.sh`, or any registry package name.

**Acceptance Criteria**
- AC-6.1.a: Every upstream branch's merge base is `upstream-main`, not `main`.
- AC-6.1.b: Each PR builds and its verification commands pass independently of later PRs.
- AC-6.1.c: No PR diff touches a workflow filename, the TestFlight upload script, or a registry package name.
- AC-6.1.d: Each PR description follows the repository template.

**Acceptance Tests**
- Test-6.1.a: Integration — `git merge-base --is-ancestor origin/upstream-main <branch>` for each branch.
- Test-6.1.b: E2E — check out each branch in isolation and run its verification commands.
- Test-6.1.c: Unit — `git diff --name-only` per branch, assert none of the excluded paths appear.
- Test-6.1.d: Unit — assert each PR body contains the template's section headings.

**Verification Commands**
```bash
git fetch origin upstream-main:refs/remotes/origin/upstream-main
for b in brand-p1 brand-p2 brand-p3 brand-p4 brand-p5; do
  git merge-base --is-ancestor origin/upstream-main "$b" || exit 1
  git diff --name-only origin/upstream-main.."$b" | rg -q '^(\.github/workflows/|ios/scripts/upload-testflight\.sh)' && exit 1
done
```

### 6.2 Fork brand values

**Landing:** fork-only

**Implementation Details**
- On `main` in `stokd-cloud/ghostty-dock`, set `config/brand.json` to the Ghostty Dock values: `productName: "Ghostty Dock"`, `cliBinaryName: "gdock"`, `bundleIdMacOS: "cloud.stokd.ghostty-dock"`, `envPrefix: "GDOCK"`, `configDirName: "ghostty-dock"`, `socketBaseName: "gdock"`, `urlScheme: "gdock"`, and the fork's own `githubRepo` and `updateFeedURL`.
- Populate `legacy.envPrefixes` with `["CMUX"]` and `legacy.configDirNames` with `["cmux"]` so an existing `~/.config/cmux` keeps working. Per the fork's standing rebrand posture, `~/.config/cmux` is never deleted — migration is a non-destructive copy with the original left intact as a fallback.
- Generate a fork-owned Sparkle keypair and set `sparklePublicKey` accordingly. Renaming alone would leave the fork trusting upstream's signing key.
- This is the **entire** fork rebrand of the identity surface: one file plus a regenerate. That single-file property is the PRD's headline claim and this work item is where it is demonstrated.

**Acceptance Criteria**
- AC-6.2.a: The rebrand touches exactly `config/brand.json` plus generated files → the claim holds.
- AC-6.2.b: A built app reports the Ghostty Dock bundle ID and display name.
- AC-6.2.c: An existing `~/.config/cmux/cmux.json` is still read and remains byte-unchanged on disk after the app writes settings.
- AC-6.2.d: `sparklePublicKey` differs from upstream's value → the fork is not trusting upstream's key.

**Acceptance Tests**
- Test-6.2.a: Unit — `git diff --name-only` lists only the manifest and generated files.
- Test-6.2.b: E2E — build, assert bundle ID and display name.
- Test-6.2.c: Regression — seed a legacy config, launch, write settings, assert it is read and its hash is unchanged.
- Test-6.2.d: Unit — compare against the upstream key value, assert different.

**Verification Commands**
```bash
python3 scripts/generate-brand-sources.py   # (new file)
git diff --name-only | rg -v '^(config/brand\.json|config/Brand\.xcconfig|Sources/Generated/|scripts/lib/brand\.sh|web/lib/generated/)' | wc -l | rg -q '^0$'
CMUX_SKIP_ZIG_BUILD=1 ./scripts/reload.sh --tag gdock
```

### 6.3 Upstream-to-main ingest

**Landing:** fork-only

**Implementation Details**
- `.github/workflows/sync-upstream.yml` today only fast-forwards `upstream-main` from `upstream/main` and hard-fails with an issue if it cannot. **Nothing merges `upstream-main` into `main`** — the ingest half of the fork flow is undefined, and the fork silently falls behind at roughly 100 upstream commits per day.
- Create `.github/workflows/ingest-upstream.yml` (new file), scheduled after the existing sync. It creates or updates a branch `ingest/upstream-<date>` from `main`, merges `origin/upstream-main`, and opens a PR to `main`.
- On a clean merge it runs the brand ratchet, the generator drift check, and the unit suite, and labels the PR `ingest:clean`.
- On conflict it does **not** force anything: it pushes the conflicted branch, opens a PR labelled `ingest:conflict`, and comments with the conflicted paths so a human resolves them.
- The workflow must never push to `main` directly and never touch `upstream-main`, preserving the pristine-mirror invariant the sync workflow enforces.
- Because the fork's rebrand is confined to the manifest and generated files, the expected conflict surface is small — which is the whole reason the thin-skin scope was chosen. The ingest PR's conflict count is the ongoing measurement of whether that assumption holds.

**Acceptance Criteria**
- AC-6.3.a: The workflow never pushes to `main` or `upstream-main` → invariants preserved.
- AC-6.3.b: A clean ingest opens a PR labelled `ingest:clean` with the guard checks green.
- AC-6.3.c: A conflicting ingest opens a PR labelled `ingest:conflict` listing the conflicted paths, and does not force-push.
- AC-6.3.d: `actionlint` passes on the new workflow.
- AC-6.3.e: A manual `workflow_dispatch` run completes and produces a PR.

**Acceptance Tests**
- Test-6.3.a: Unit — grep the workflow for `push origin HEAD:main` and `upstream-main`, assert no write to either.
- Test-6.3.b: Integration — dispatch against a clean state, assert the PR and label.
- Test-6.3.c: Regression — dispatch with a seeded conflict, assert the conflict label and no force-push.
- Test-6.3.d: Unit — run `actionlint` over the workflow.
- Test-6.3.e: E2E — one real dispatch producing a real PR.

**Verification Commands**
```bash
test -f .github/workflows/ingest-upstream.yml   # (new file)
! rg -q 'push .*HEAD:main|push .*:upstream-main' .github/workflows/ingest-upstream.yml   # (new file)
actionlint .github/workflows/ingest-upstream.yml   # (new file)
gh workflow run ingest-upstream.yml
```

## 3. Completion Criteria

The project is complete when all of the following hold simultaneously:

- The inventory tool, taxonomy document, and committed baseline exist, and the ratchet runs in `workflow-guard-tests`.
- `config/brand.json` is the only hand-edited source of brand identity, and the generator drift check is green in CI and in the pre-commit hook.
- Every migrated category reports zero occurrences outside generated files and the manifest.
- With default manifest values, the built app's identity surface matches `scripts/brand-identity-golden.txt` byte for byte — the executable form of "the exact same build afterwards".
- `scripts/rebrand-smoke-test.sh` exits 0, proving a throwaway rebrand moves every identity value together with no residue and restores the tree cleanly.
- `./scripts/test-unit.sh` and `./scripts/check-pbxproj.sh` exit 0, and a tagged reload builds and round-trips over its socket.
- Five upstream PRs are open from branches cut off `upstream-main`, each independently buildable.
- The fork's `main` carries Ghostty Dock values in `config/brand.json` and nothing else brand-related.
- `.github/workflows/ingest-upstream.yml` exists and has produced at least one real ingest PR.

## 4. Rollout & Validation

### Rollout Strategy

- **Phase-by-phase, each behind its own gate.** Phases 1 and 2 add only new files and CI checks; they cannot regress the product. Phase 3 is the first to touch the build and is immediately covered by the equivalence gate. Phase 4 is the highest-risk phase and lands only after that gate is in place.
- **The golden file is the rollback trigger.** Any unexplained diff against `scripts/brand-identity-golden.txt` fails the phase; the fix is to correct the migration, never to regenerate the golden to match. Regenerating it is legitimate only when the identity surface is *intended* to change, and that intent must be argued in the PR.
- **Compatibility windows are time-boxed.** The legacy config-path, env-prefix, and keychain-service fallbacks exist so no user loses state at the cutover. Their removal criteria are recorded in `docs/brand-identity.md` rather than left open-ended.
- **Per-phase rollback is a single revert.** Because each phase is a self-contained PR whose consumers are all downstream of it, reverting phase N leaves phases 1 through N-1 functional.
- **CI is currently `workflow_dispatch`-only.** Until it resumes on PRs, every guard added here must be run manually via dispatch on each PR, and the PR description must record the run URL. Do not treat a green local run as CI coverage.

### Post-Launch Validation

- Track the per-category inventory totals over time; the migrated categories must stay at zero and the overall total must not climb.
- Track the conflicted-path count on each `ingest:conflict` PR. A sustained rise means the thin-skin assumption is breaking down and the scope boundary needs revisiting.
- Confirm on the first fork release that Sparkle updates resolve against the fork's own feed and key, and that an existing `~/.config/cmux` installation upgrades without losing settings.
- Confirm that the previously drifted `ai.manaflow.cmux` os_log subsystems either now derive from the manifest or are explicitly recorded as non-migrated — the failure this PRD exists to prevent repeating.
- Watch for a stale `~/Library/Preferences/ai.manaflow.cmuxterm.plist` reference in `homebrew-cmux/Casks/cmux.rb` and `scripts/build-sign-upload.sh`: that zap path already matches no current bundle ID, so the cask's preference cleanup is silently broken today, independent of this work.

## 5. Open Questions

Autonomous decisions taken while authoring, recorded so they can be challenged rather than rediscovered:

- **Decision: scope excludes localized prose** — chose to inventory but not migrate the ~2,842 `Localizable.xcstrings` and ~1,100–1,400 per-locale `web/messages` hits, because `.github/review-bot-rules/full-internationalization.md` requires complete translations for all 20 locales in the same PR, which would dwarf the identity change and make the upstream PRs unreviewable.
- **Decision: scope excludes Swift module, Xcode target, and directory names** — chose to leave them, because renaming them would convert every future upstream ingest into a mass-conflict event, which is the exact cost this PRD is trying to eliminate.
- **Decision: equivalence is asserted over the identity surface, not binary bytes** — chose a normalised identity manifest over a bit-for-bit comparison, because Swift builds embed non-deterministic UUIDs, build paths, and timestamps; promising byte-identical binaries would be an unverifiable claim. The identity manifest is the strongest falsifiable version of the user's "exact same build" requirement.
- **Decision: env-prefix migration is limited to the cross-process contract subset** — chose ~8 names over ~1,200, because only those require multi-binary agreement; migrating the rest would balloon the diff past PR size with no contract benefit.
- **Decision: compatibility via dual-read fallbacks rather than a hard cutover** — chose the pattern commit `d675f0a0e3` already established in this repo for `mux` → `cmux-tui`, because it is precedented here and avoids stranding user state.
- **Decision: `BrandIdentity` is a constants-only `enum`** — chose this over a struct with instances or a settable singleton, so `.github/review-bot-rules/no-ambient-global-state.md` is satisfied by construction.
- **Decision: the ratchet starts as non-increase, then tightens to zero** — chose a two-stage ratchet so Phase 1 can land immediately without blocking the very work items that reduce the counts.

Genuinely open, and none blocking any Phase 1 or Phase 2 work item:

- Is `ai.manaflow.cmuxterm.plist` (referenced in `homebrew-cmux/Casks/cmux.rb` and `scripts/build-sign-upload.sh`) legacy residue or a still-live path? It matches no bundle ID this repo currently produces. Resolve with the upstream maintainers before deciding whether the cask's zap stanza is fixed or removed.
- Which iOS bundle ID is actually live in App Store Connect? `ios/Config/Shared.xcconfig` says `dev.cmux.ios`, `ios/scripts/upload-testflight.sh` defaults to `dev.cmux.app.beta` and `com.cmux.app`. Three conventions coexist and this cannot be settled from the repository alone.
- Will upstream accept the `config/brand.json` location and key naming, or prefer a different path such as `Config/` or a `.xcconfig`-only approach? Worth raising as a draft PR or issue before Phase 2 is fully built out.
- Should `cmuxd` be in scope? `scripts/reload.sh` references a `cmuxd/` directory that does not exist in this checkout and is guarded by a directory test. Confirm whether it is expected to exist before treating the daemon binary name as a live migration target.
