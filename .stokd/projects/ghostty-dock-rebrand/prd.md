# Ghostty Dock Rebrand

## 0. Source Context

**Derived From:** "i want to start using the version of cmux built from the ghostty-dock repo.. and as a part of that i want to brand it as ghostty dock.. and i want the cli to be gdock so we need to scrub cmux wherever it exists within this project and replace it with either the cli or the new name depending on the context"
**Feature Name:** Ghostty Dock Rebrand (thin-skin)
**PRD Owner:** Brian Stoker
**Last Updated:** 2026-07-26

### Summary

`stokd-cloud/ghostty-dock` is a fork of `manaflow-ai/cmux`. This project rebrands the
user-visible surface of the macOS app to **Ghostty Dock** and the CLI binary to **`gdock`**,
severs the fork's auto-update channel from upstream, and migrates user data
non-destructively — while deliberately leaving internal identifiers (`CMUX_*` environment
variables, `Cmux*`/`CMUX*` Swift symbols, Xcode target names, directory names, keychain
service strings) untouched so that ongoing upstream ingest stays cheap.

The measured basis for that "thin-skin" scope: a full scrub is **80,064 lines across 5,401
files**. Over a 60-day window upstream lands **54.5 commits/day**, and today
`git merge-tree --write-tree main origin/upstream-main` reports **0 conflicts**. Preserving
that clean-merge baseline is a hard constraint of this project, not an aspiration.

## 1. Objectives & Constraints

### Objectives

- **O1 — Stop the fork from silently self-replacing with upstream.** `Resources/Info.plist:245`
  sets `SUFeedURL` to `https://github.com/manaflow-ai/cmux/releases/latest/download/appcast.xml`
  with `SUEnableAutomaticChecks=true` and `SUScheduledCheckInterval=86400`. Any Ghostty Dock
  build installed today is replaced by an upstream `cmux` build within 24 hours. This is the
  single blocking defect against the user's stated goal and is fixed first.
- **O2 — The app presents as "Ghostty Dock" and the CLI is invoked as `gdock`** across app
  display name, menus, About panel, alerts, notifications, CLI `--help`/`--version`, and the
  installed `/usr/local/bin` symlink.
- **O3 — Give Ghostty Dock a distinct runtime identity** (bundle identifier, control socket,
  preferences domain, config directory) so it can be installed and run alongside an existing
  `cmux` without LaunchServices ambiguity or socket collision.
- **O4 — No user data is destroyed.** `~/.config/cmux` is copied, never moved or deleted.
- **O5 — Upstream ingest remains mechanical.** After this project, merging
  `origin/upstream-main` into `main` must remain resolvable by a documented, re-runnable
  procedure rather than by hand-editing thousands of conflicts.

### Constraints

- **C1 — Preserve the 0-conflict merge baseline where free; script it where not.** Rename
  targets were ranked by measured upstream churn (cmux-touching commits/day):
  `Resources/Info.plist` and the 18 `PRODUCT_NAME`/`PRODUCT_BUNDLE_IDENTIFIER` lines in
  `cmux.xcodeproj/project.pbxproj` = **0.0/day**; `*.entitlements` = 0.05; `README*.md` = 0.10–0.13;
  `scripts/reload*.sh` = 0.30; `Resources/Localizable.xcstrings` = 1.72; `CLI/cmux.swift` = 2.85;
  `web/messages/**` = 15–20 aggregate.
- **C2 — `web/**` is OUT OF SCOPE.** 28,014 occurrences, the worst conflict generator in the
  repo, and it is the marketing site for `cmux.com`, a domain this fork does not operate.
- **C3 — `CHANGELOG.md` is OUT OF SCOPE.** It is upstream's historical record; 100% of its
  commits touch a `cmux` line.
- **C4 — No `CMUX_*` environment variable may be renamed.** ~730 distinct names are injected
  into every terminal surface and read by third-party agent hooks and users' shell rc files.
  A rename breaks already-running agent sessions with no migration path.
- **C5 — No keychain service string and no iroh HKDF label may be changed.** The
  `"com.cmuxterm.iroh.*"` services and `"cmux/iroh/…/v1"` strings are cryptographic domain
  separators; changing them invalidates every stored credential and device pairing.
- **C6 — Internal Swift symbols, Xcode target names, scheme names, directory names, and file
  names stay `cmux`.** They are not user-visible and they are where upstream churn concentrates.
- **C7 — Formal TDD (Axiom 5).** Every code-touching work item below adds its test first,
  observes it fail (red), then implements to green. Test files added under `cmuxTests/` MUST be
  wired into `cmux.xcodeproj/project.pbxproj`, or they silently never run.
- **C8 — The `ghostty`, `vendor/bonsplit`, and `homebrew-cmux` submodules are upstream-owned**
  (`manaflow-ai/*`). No commit in this project may modify a submodule's contents.

## 1.5 Required Toolchain

| Tool | Min Version | Install Command | Verify Command |
|------|-------------|-----------------|----------------|
| Xcode | 26 (per `.xcode-version`) | Apple Developer downloads | `xcodebuild -version` |
| Swift | bundled with Xcode 26 | — | `swift --version` |
| Python | 3.9 | preinstalled on macOS 14+ | `python3 --version` |
| Node.js | 18 | `brew install node` | `node --version` |
| Bun | 1.1 | `brew install oven-sh/bun/bun` | `bun --version` |
| Zig | per `scripts/install-zig-ci.sh` | `brew install zig` | `zig version` |
| Sparkle tools | bundled via SPM | — | `swift scripts/derive_sparkle_public_key.swift --help` |
| git | 2.38 (for `merge-tree --write-tree`) | `brew install git` | `git merge-tree --help` |

## 2. Execution Phases

## Phase 1: Sever the Upstream Update Channel

**Purpose:** This phase must come first because it is the only phase whose absence invalidates
every other phase. While `SUFeedURL` points at `manaflow-ai/cmux` with automatic checks enabled,
any rebranded build installed on the user's machine is overwritten by an upstream `cmux` build
within 24 hours — silently discarding all downstream work. No identity, migration, or branding
work may begin until the fork can no longer update itself from upstream.

### 1.1 Repoint the Sparkle feed and disable automatic upstream checks

**Implementation Details**

- **Systems affected:** `Resources/Info.plist`, `cmux.xcodeproj/project.pbxproj`.
- Set `Resources/Info.plist` key `SUEnableAutomaticChecks` (currently `<true/>` at line 243–244)
  to `<false/>`. Automatic checks are re-enabled in work item 5.3 only after a Ghostty Dock feed
  is actually published; shipping with checks enabled against a nonexistent feed produces a
  recurring user-visible error dialog.
- Replace the `SUFeedURL` string at `Resources/Info.plist:246` with
  `https://github.com/stokd-cloud/ghostty-dock/releases/latest/download/appcast.xml`.
- `SUPublicEDKey` at `Resources/Info.plist:252` is `$(SPARKLE_PUBLIC_KEY)` and needs no plist edit.
  Replace the build-setting value at `cmux.xcodeproj/project.pbxproj:9335` (Debug) and `:9382`
  (Release) — currently `avjcgKibf1FTvhIjLBxhd+0HSpsXU4D0IGlVk8cgqRc=`, which is manaflow's
  public key — with the public key of a newly generated stokd-owned EdDSA keypair. The private
  key is stored as the GitHub Actions secret `SPARKLE_PRIVATE_KEY` in `stokd-cloud/ghostty-dock`
  and MUST NOT be committed.
- **Inputs:** a freshly generated Sparkle EdDSA keypair. **Outputs:** an app bundle whose
  `Info.plist` contains no `manaflow-ai` URL and whose `SUPublicEDKey` is stokd-owned.
- **Failure modes:** (a) leaving `SUEnableAutomaticChecks=true` against an unpublished feed →
  repeated update-failure dialogs; (b) changing the feed but not the key → every future update
  fails signature validation with a misleading error; (c) committing the private key → anyone
  can sign malicious updates for this app.

**Acceptance Criteria**

- AC-1.1.a: `Resources/Info.plist` contains no string matching `manaflow-ai` → condition holds by inspection of the plist.
- AC-1.1.b: `SUEnableAutomaticChecks` is `false` and `SUFeedURL` points at `stokd-cloud/ghostty-dock` → condition holds by inspection.
- AC-1.1.c: `grep -c 'avjcgKibf1FTvhIjLBxhd+0HSpsXU4D0IGlVk8cgqRc=' cmux.xcodeproj/project.pbxproj` → prints `0`.
- AC-1.1.d: `/usr/libexec/PlistBuddy -c 'Print :SUFeedURL' Resources/Info.plist` → exit 0 and output contains `stokd-cloud/ghostty-dock`.
- AC-1.1.e: `plutil -lint Resources/Info.plist` → exit 0 (the edit did not corrupt the plist).

**Acceptance Tests**

- Test-1.1.a (Regression): `cmuxTests/GhosttyDockUpdateFeedTests.swift` asserts that the built
  bundle's `SUFeedURL` does not contain `manaflow-ai`. Added and observed RED before the plist
  edit; GREEN after. Must be wired into `project.pbxproj` per C7.
- Test-1.1.b (Unit): same test file asserts `SUPublicEDKey` resolves to a non-empty string that
  is not manaflow's known key.
- Test-1.1.c (Integration): `plutil -lint` + `PlistBuddy` reads confirm plist validity and values.

**Verification Commands**

```bash
set -e
grep -q 'manaflow-ai' Resources/Info.plist && { echo "FAIL: upstream URL still present"; exit 1; } || true
/usr/libexec/PlistBuddy -c 'Print :SUFeedURL' Resources/Info.plist | grep -q 'stokd-cloud/ghostty-dock'
/usr/libexec/PlistBuddy -c 'Print :SUEnableAutomaticChecks' Resources/Info.plist | grep -qi 'false'
plutil -lint Resources/Info.plist
test "$(grep -c 'avjcgKibf1FTvhIjLBxhd+0HSpsXU4D0IGlVk8cgqRc=' cmux.xcodeproj/project.pbxproj)" -eq 0
./scripts/check-pbxproj.sh
```

### 1.2 Decouple version tooling from the upstream appcast

**Implementation Details**

- **Systems affected:** `scripts/bump-version.sh`, `tests/test_ci_sparkle_build_monotonic.sh`,
  `.github/workflows/release.yml`.
- `scripts/bump-version.sh:28` fetches
  `https://github.com/manaflow-ai/cmux/releases/latest/download/appcast.xml` to keep build
  numbers monotonic. Repoint it at the stokd feed. The script already tolerates an unreachable
  feed (it prints "unavailable (continuing with local build baseline)" and continues), so a
  not-yet-published feed is a supported state.
- `tests/test_ci_sparkle_build_monotonic.sh:39` hardcodes the same upstream URL; repoint it.
- `.github/workflows/release.yml:326-333` re-injects `SUFeedURL` via PlistBuddy at release time,
  which would overwrite work item 1.1 at every release. Update it to the stokd feed.
- **Failure modes:** missing the `release.yml` re-injection means the shipped binary silently
  reverts to the upstream feed even though the committed plist is correct — the most dangerous
  failure in this phase, because the repo looks correct while the artifact is not.

**Acceptance Criteria**

- AC-1.2.a: No file under `scripts/`, `tests/`, or `.github/workflows/` references the upstream appcast URL → condition holds by repo-wide grep.
- AC-1.2.b: `grep -rn 'manaflow-ai/cmux/releases' scripts tests .github/workflows | wc -l` → prints `0`.
- AC-1.2.c: `./scripts/release-pretag-guard.sh` → exit 0.
- AC-1.2.d: `bash -n scripts/bump-version.sh && bash -n tests/test_ci_sparkle_build_monotonic.sh` → exit 0.

**Acceptance Tests**

- Test-1.2.a (Regression): `tests/test_ci_no_upstream_appcast.sh` — a new guard asserting zero
  matches for `manaflow-ai/cmux/releases` across `scripts/`, `tests/`, `.github/workflows/`, and
  `Resources/Info.plist`. Observed RED before 1.1/1.2 edits, GREEN after.
- Test-1.2.b (Integration): `./scripts/release-pretag-guard.sh` still passes, proving the
  monotonic-build guard survives the URL change.

**Verification Commands**

```bash
set -e
test "$(grep -rn 'manaflow-ai/cmux/releases' scripts tests .github/workflows Resources/Info.plist | wc -l | tr -d ' ')" -eq 0
bash -n scripts/bump-version.sh
bash -n tests/test_ci_sparkle_build_monotonic.sh
./scripts/release-pretag-guard.sh
./tests/test_ci_no_upstream_appcast.sh
```

## Phase 2: Application and CLI Identity

**Purpose:** Cannot start before Phase 1, because renaming the app while it still auto-updates
from upstream produces a build that reverts to `cmux` within 24 hours, making every acceptance
check in this phase unreproducible on the user's machine. With the update channel severed, this
phase establishes the identity that Phase 3's data migration must target — the new bundle
identifier and config directory must be decided and implemented before anything can migrate
*into* them.

### 2.1 macOS application identity

**Implementation Details**

- **Systems affected:** `cmux.xcodeproj/project.pbxproj` only. `Resources/Info.plist` requires
  **no edit** — `CFBundleDisplayName` and `CFBundleName` are already `$(PRODUCT_NAME)` and
  `CFBundleIdentifier` is already `$(PRODUCT_BUNDLE_IDENTIFIER)`.
- Exactly 18 lines in `project.pbxproj` carry `PRODUCT_NAME` or `PRODUCT_BUNDLE_IDENTIFIER`.
  These lines had **zero churn across 60 days of upstream history**, so editing them costs no
  future merge conflicts. Apply exactly these changes:

| Line | Current | New |
|---|---|---|
| 9330 | `PRODUCT_NAME = "cmux DEV";` | `PRODUCT_NAME = "Ghostty Dock DEV";` |
| 9381 | `PRODUCT_NAME = cmux;` | `PRODUCT_NAME = "Ghostty Dock";` |
| 9329 | `PRODUCT_BUNDLE_IDENTIFIER = com.cmuxterm.app.debug;` | `= cloud.stokd.ghostty-dock.debug;` |
| 9380 | `PRODUCT_BUNDLE_IDENTIFIER = com.cmuxterm.app;` | `= cloud.stokd.ghostty-dock;` |
| 9224, 9437 | `= com.cmuxterm.appuitests;` | `= cloud.stokd.ghostty-dock.uitests;` |
| 9504, 9523 | `= com.cmuxterm.apptests;` | `= cloud.stokd.ghostty-dock.tests;` |
| 9460 | `= com.cmuxterm.app.docktileplugin.debug;` | `= cloud.stokd.ghostty-dock.docktileplugin.debug;` |
| 9485 | `= com.cmuxterm.app.docktileplugin;` | `= cloud.stokd.ghostty-dock.docktileplugin;` |

  The remaining 8 `PRODUCT_NAME = "$(TARGET_NAME)"` lines are internal target names and are left
  untouched per C6. Lines 9401 and 9421 belong to the CLI target and are handled in 2.2.
- Line numbers are provided for orientation only; locate each setting by key + owning target +
  configuration, since upstream ingest may shift line numbers.
- **Failure modes:** editing a `$(TARGET_NAME)` line renames a build product and breaks
  `scripts/check-workspace-package-groups.py`; a stale normalized pbxproj fails
  `scripts/check-pbxproj.sh`.

**Acceptance Criteria**

- AC-2.1.a: The Release app target's `PRODUCT_NAME` is `Ghostty Dock` and its `PRODUCT_BUNDLE_IDENTIFIER` is `cloud.stokd.ghostty-dock` → condition holds by inspection.
- AC-2.1.b: `grep -c 'PRODUCT_BUNDLE_IDENTIFIER = com.cmuxterm' cmux.xcodeproj/project.pbxproj` → prints `0`.
- AC-2.1.c: `grep -c 'PRODUCT_NAME = "\$(TARGET_NAME)"' cmux.xcodeproj/project.pbxproj` → prints `8` (unchanged internal targets).
- AC-2.1.d: `./scripts/check-pbxproj.sh` → exit 0.
- AC-2.1.e: A Debug build succeeds and produces a bundle named `Ghostty Dock DEV*.app` → build command exits 0 and the `.app` exists.

**Acceptance Tests**

- Test-2.1.a (Regression): `cmuxTests/GhosttyDockBundleIdentityTests.swift` asserts
  `Bundle.main.bundleIdentifier` has prefix `cloud.stokd.ghostty-dock` and
  `CFBundleDisplayName` starts with `Ghostty Dock`. RED before the pbxproj edit, GREEN after.
  Wired into `project.pbxproj` per C7.
- Test-2.1.b (Integration): `./scripts/check-pbxproj.sh` and
  `python3 scripts/check-workspace-package-groups.py --check` both pass, proving no target name
  was collaterally renamed.
- Test-2.1.c (E2E): a tagged Debug build produces an `.app` whose name begins with `Ghostty Dock`.

**Verification Commands**

```bash
set -e
test "$(grep -c 'PRODUCT_BUNDLE_IDENTIFIER = com.cmuxterm' cmux.xcodeproj/project.pbxproj)" -eq 0
test "$(grep -c 'PRODUCT_NAME = "\$(TARGET_NAME)"' cmux.xcodeproj/project.pbxproj)" -eq 8
./scripts/check-pbxproj.sh
python3 scripts/check-workspace-package-groups.py --check
python3 scripts/check-package-resolved-policy.py
./scripts/lint-pbxproj-test-wiring.sh
./scripts/reload.sh --tag ghostty-dock-rebrand
ls -d "$HOME/Library/Developer/Xcode/DerivedData/cmux-ghostty-dock-rebrand/Build/Products/Debug/Ghostty Dock DEV ghostty-dock-rebrand.app"
```

### 2.2 Rename the CLI binary to `gdock`

**Implementation Details**

- **Systems affected:** `cmux.xcodeproj/project.pbxproj` (lines 9401, 9421 — the `cmux-cli`
  target's Debug and Release `PRODUCT_NAME = cmux`), `Sources/App/CmuxCLIPathInstaller.swift`.
- Set both `cmux-cli` `PRODUCT_NAME` values to `gdock`. Leave `PRODUCT_MODULE_NAME = cmux_cli`
  and the `CLI/` directory and its `CMUXCLI*` type names untouched per C6.
- `Sources/App/CmuxCLIPathInstaller.swift:55` installs to `/usr/local/bin/cmux`; change the
  destination to `/usr/local/bin/gdock`. Lines 231 and 236 resolve the bundled binary at
  `Contents/Resources/bin/cmux`; both become `bin/gdock` to match the renamed build product.
- **Compatibility:** additionally install a `/usr/local/bin/cmux` symlink pointing at the same
  bundled binary, so existing user scripts and agent hooks that invoke `cmux` keep working. The
  CLI already resolves its own invoked name, so `usage()` output adapts (see 4.3).
- **Failure modes:** renaming `PRODUCT_NAME` without updating the installer's
  `Contents/Resources/bin/...` path yields an installer that silently symlinks to a nonexistent
  file; the user gets `command not found` with no diagnostic.

**Acceptance Criteria**

- AC-2.2.a: Both `cmux-cli` target configurations declare `PRODUCT_NAME = gdock` → condition holds by inspection.
- AC-2.2.b: The built app bundle contains `Contents/Resources/bin/gdock` → the file exists and is executable.
- AC-2.2.c: `"<app>/Contents/Resources/bin/gdock" --version` → exit 0, prints a version string.
- AC-2.2.d: `"<app>/Contents/Resources/bin/gdock" --help` → exit 0 and the output's first usage line names `gdock`, not `cmux`.
- AC-2.2.e: After running the in-app installer, both `/usr/local/bin/gdock` and `/usr/local/bin/cmux` resolve to the bundled binary → `test -x` passes for both.

**Acceptance Tests**

- Test-2.2.a (Unit): `cmuxTests/GhosttyDockCLIInstallerTests.swift` asserts
  `CmuxCLIPathInstaller` default destination is `/usr/local/bin/gdock` and that the bundled
  path component is `bin/gdock`. RED before, GREEN after. Wired per C7.
- Test-2.2.b (E2E): invoke the built `gdock --version` and `gdock --help`; assert exit 0 and
  that the usage header names `gdock`.
- Test-2.2.c (Regression): assert the compatibility `cmux` symlink still resolves, so existing
  agent hooks do not break.

**Verification Commands**

```bash
set -e
test "$(grep -c 'PRODUCT_NAME = gdock;' cmux.xcodeproj/project.pbxproj)" -eq 2
./scripts/reload.sh --tag ghostty-dock-rebrand
APP="$HOME/Library/Developer/Xcode/DerivedData/cmux-ghostty-dock-rebrand/Build/Products/Debug/Ghostty Dock DEV ghostty-dock-rebrand.app"
test -x "$APP/Contents/Resources/bin/gdock"
"$APP/Contents/Resources/bin/gdock" --version
"$APP/Contents/Resources/bin/gdock" --help | head -1 | grep -q 'gdock'
./scripts/test-unit.sh test -only-testing:cmuxTests/GhosttyDockCLIInstallerTests
```

### 2.3 Restore identity coherence across sockets, entitlements, and iOS

**Implementation Details**

- **Systems affected (all consume the bundle identifier, which 2.1 changed):**
  - `Packages/macOS/CmuxSettings/Sources/CmuxSettings/SocketControl/SocketPathMarkerFiles.swift:6-8`
    — `nightlyBundleIdentifier`, `stagingBundleIdentifier`, `defaultBaseDebugBundleIdentifier`.
  - `Packages/macOS/CmuxSettings/Sources/CmuxSettings/SocketControl/SocketControlSettings.swift`
    — bundle-id prefix comparisons at lines 22, 215, 326, 410–411, 423–424.
  - `CLI/CLISocketPathResolver.swift:485,487` — the CLI's mirror of the app's bundle ids.
  - `CLI/CMUXCLI+ThemeSupport.swift:353-373` — reconstructs `com.cmuxterm.app.{debug,nightly,staging}`.
  - `CLI/cmux.swift:3020` — `defaultBrowserSettingsDomain = "com.cmuxterm.app"` (a UserDefaults domain).
  - `Packages/macOS/CmuxUpdater/Sources/CmuxUpdater/UpdateController.swift:385-386` — suppresses
    Sparkle for debug bundle ids.
  - `Packages/macOS/CMUXDebugLog/Sources/CMUXDebugLog/DebugEventLog.swift:471`.
  - `scripts/reload.sh`, `scripts/reloads.sh`, `scripts/verify-app-bundle-channel-metadata.sh`
    — inject/assert `com.cmuxterm.app.{debug,staging,nightly}` and the `cmux DEV`/`cmux STAGING`
    app names.
  - Entitlements literals: `cmux.entitlements:15`, `cmux.release.entitlements:6,11`,
    `cmux.nightly.entitlements:6,11` (`7WLXT3NR37.com.cmuxterm.app*`).
    `Resources/cmux.entitlements` needs **no edit** — it uses
    `$(AppIdentifierPrefix)$(PRODUCT_BUNDLE_IDENTIFIER)`.
  - `web/services/apns/routePolicy.ts:68` — `PROD_BUNDLE_IDS` allowlist. This is the one
    `web/` file in scope, exempted from C2 because it is a server-side functional allowlist,
    not marketing copy; omitting it breaks push notifications.
  - iOS identity: `ios/Config/Shared.xcconfig` (`PRODUCT_NAME`, `PRODUCT_DISPLAY_NAME`,
    `PRODUCT_BUNDLE_IDENTIFIER = dev.cmux.ios`), `ios/Config/Release.xcconfig:7`,
    `ios/Config/Tests.xcconfig:10`.
- **These must all change in the same commit as 2.1.** The app derives its control-socket path
  from its bundle identifier (`SocketPathMarkerFiles.variant(bundleIdentifier:environment:)`),
  and the CLI independently reconstructs the same path. A mismatch means the CLI silently cannot
  find the running app — the app launches, the CLI hangs or reports "not running", and nothing
  logs an error.
- **Deliberately NOT changed:** every `CMUX_*` env var (C4), every keychain service string and
  iroh HKDF label (C5), and OSLog subsystem strings (internal, C6).
- **Failure modes:** partial application → app/CLI socket divergence (silent); missed
  entitlements literal → code-signing failure at release; missed APNs allowlist → push
  notifications silently dropped.

**Acceptance Criteria**

- AC-2.3.a: No Swift or TypeScript source outside test fixtures references `com.cmuxterm.app` as a bundle identifier → condition holds by grep.
- AC-2.3.b: `grep -rn 'com.cmuxterm.app' --include='*.swift' --include='*.ts' Sources Packages CLI web/services | grep -v '/Tests/' | wc -l` → prints `0`.
- AC-2.3.c: `grep -rn '7WLXT3NR37.com.cmuxterm' cmux.entitlements cmux.release.entitlements cmux.nightly.entitlements | wc -l` → prints `0`.
- AC-2.3.d: The CLI reaches the running app: `gdock list-workspaces` against a freshly launched tagged build → exit 0.
- AC-2.3.e: All `CMUX_*` environment variable names are unchanged → `grep -rho 'CMUX_[A-Z0-9_]*' --include='*.swift' Sources Packages CLI | sort -u` produces a list identical to the pre-change baseline captured at phase start.

**Acceptance Tests**

- Test-2.3.a (Unit): `cmuxTests/GhosttyDockSocketIdentityTests.swift` asserts
  `SocketPathMarkerFiles.variant(bundleIdentifier:)` maps the new debug bundle id to the expected
  socket path, and that `CLISocketPathResolver` derives the identical path. RED before, GREEN after.
- Test-2.3.b (Regression): a guard test asserting the `CMUX_*` env-var name set is byte-identical
  to the baseline, enforcing C4.
- Test-2.3.c (E2E): launch the tagged build, run `gdock list-workspaces` through
  `scripts/cmux-debug-cli.sh`, assert exit 0 — proving app↔CLI rendezvous survived the rename.
- Test-2.3.d (Integration): `./scripts/verify-app-bundle-channel-metadata.sh "$APP" stable` passes.

**Verification Commands**

```bash
set -e
test "$(grep -rn 'com\.cmuxterm\.app' --include='*.swift' --include='*.ts' Sources Packages CLI web/services | grep -v '/Tests/' | wc -l | tr -d ' ')" -eq 0
test "$(grep -rn '7WLXT3NR37\.com\.cmuxterm' cmux.entitlements cmux.release.entitlements cmux.nightly.entitlements | wc -l | tr -d ' ')" -eq 0
grep -q 'cloud.stokd.ghostty-dock' Packages/macOS/CmuxSettings/Sources/CmuxSettings/SocketControl/SocketPathMarkerFiles.swift
grep -q 'cloud.stokd.ghostty-dock' CLI/CLISocketPathResolver.swift
./scripts/reload.sh --tag ghostty-dock-rebrand --launch
CMUX_TAG=ghostty-dock-rebrand scripts/cmux-debug-cli.sh list-workspaces
./scripts/test-unit.sh test -only-testing:cmuxTests/GhosttyDockSocketIdentityTests
```

## Phase 3: User Data Continuity

**Purpose:** Cannot start before Phase 2, because the migration must copy *into* a destination
that Phase 2 defines — the new config directory name and the new preferences domain do not exist
until the identity rename lands. Running this phase earlier would migrate data into a directory
the app does not yet read. It must also complete before Phase 4, so that any intermediate build
the user runs during the branding sweep still finds their settings.

### 3.1 Unify the duplicated config-path resolvers

**Implementation Details**

- **Problem:** `~/.config/cmux` is resolved independently in at least 8 executable code sites,
  each hardcoding the literal. A migration written against only one of them is wrong in seven
  places. Verified sites:
  - `Packages/macOS/CmuxSettings/Sources/CmuxSettings/Stores/CmuxConfigLocation.swift:30-31`
    (`userConfigFile`, `legacyFallbackFile`) — the designated single source of truth.
  - `Sources/CmuxConfig.swift:1747` — `defaultGlobalConfigPath()`.
  - `Sources/KeyboardShortcutSettingsFileStore.swift:65,70`.
  - `Sources/VaultAgentRegistry.swift:456`.
  - `Sources/DockSplitStore+Config.swift:242` (`dock.json`).
  - `Sources/ContentView.swift:10101` (`sidebars/` directory).
  - `Sources/DevWindowDisplayDefault.swift:26` (legacy `dev-window-display`).
  - `Sources/CmuxActionTrust.swift:38` — Application Support `cmux` subdirectory.
- **Change:** extend `CmuxConfigLocation` to expose `directory`, `legacyDirectory`,
  `dockFile`, `sidebarsDirectory`, and `legacyDevWindowDisplayFile`, then route every site above
  through it. This is a pure refactor with no behavior change — it is the precondition for 3.2,
  not a user-visible change.
- **Failure modes:** missing a site → that one config file is read from the old path forever,
  producing a partially-migrated state that is very hard to diagnose.

**Acceptance Criteria**

- AC-3.1.a: No executable Swift statement outside `CmuxConfigLocation.swift` contains the literal `.config/cmux` → condition holds by grep excluding comments and tests.
- AC-3.1.b: `grep -rn '"\.config/cmux' --include='*.swift' Sources Packages CLI | grep -v CmuxConfigLocation.swift | grep -v '/Tests/' | wc -l` → prints `0`.
- AC-3.1.c: `./scripts/test-unit.sh test -only-testing:cmuxTests/CmuxConfigTests` → exit 0 (existing config tests still pass, proving the refactor is behavior-preserving).
- AC-3.1.d: The app still reads an existing `~/.config/cmux/cmux.json` unchanged → E2E check exits 0.

**Acceptance Tests**

- Test-3.1.a (Unit): `cmuxTests/GhosttyDockConfigLocationTests.swift` asserts every accessor
  (`userConfigFile`, `dockFile`, `sidebarsDirectory`, …) resolves under an injected temp home.
  RED before the accessors exist, GREEN after.
- Test-3.1.b (Regression): the pre-existing `cmuxTests/CmuxConfigTests` suite must still pass
  unmodified — the guard that this refactor changed no behavior.

**Verification Commands**

```bash
set -e
test "$(grep -rn '"\.config/cmux' --include='*.swift' Sources Packages CLI | grep -v CmuxConfigLocation.swift | grep -v '/Tests/' | wc -l | tr -d ' ')" -eq 0
./scripts/lint-pbxproj-test-wiring.sh
./scripts/test-unit.sh test -only-testing:cmuxTests/CmuxConfigTests
./scripts/test-unit.sh test -only-testing:cmuxTests/GhosttyDockConfigLocationTests
```

### 3.2 Non-destructive config migration to `~/.config/ghostty-dock`

**Implementation Details**

- **Systems affected:** `CmuxConfigLocation` (new `legacyDirectory`), a new
  `Sources/GhosttyDockConfigMigration.swift`, invoked once during app startup in
  `Sources/AppDelegate.swift` before any settings read.
- **Behavior (exactly):** on launch, if `~/.config/ghostty-dock` does **not** exist and
  `~/.config/cmux` **does**, recursively **copy** the legacy directory to the new path. Copy
  `cmux.json`, `settings.json`, `dock.json`, `dev-window-display`, and the `sidebars/` directory.
  **Never delete, move, or modify anything under `~/.config/cmux`** — this is an explicit user
  requirement (O4). Record completion with a versioned watermark in UserDefaults
  (`ghosttyDockConfigMigrationVersion = 1`), modeled on
  `SocketControlPasswordStore.keychainMigrationDefaultsKey`.
- **Precedent to follow:** `Sources/DevWindowDisplayDefault.swift:22-60` already implements a
  one-time, best-effort, non-destructive legacy migration whose doc comment states it "Leaves the
  legacy file untouched". Mirror that structure and idempotence exactly.
- **Filename policy:** the config file inside the new directory keeps the name `cmux.json` for
  this project. Renaming it to `ghostty-dock.json` would require touching ~360 lines of
  user-visible help text and docs across 117 files and is deferred (see §5).
- **Repo-local config:** `CLI/CMUXCLI+Config.swift:534-547` walks up for `.cmux/cmux.json` and
  `./cmux.json`. These live inside users' own git repositories and MUST continue to be read
  forever. Add `.ghostty-dock/` as an *additional* candidate; do not remove the existing ones.
- **Failure modes:** (a) copying on every launch → clobbers newer settings with stale ones; the
  existence check plus watermark prevents this; (b) partial copy on failure → the app must treat
  a failed copy as "no migration" and fall back to reading the legacy path rather than starting
  blank; (c) following symlinks out of the config dir during recursive copy.

**Acceptance Criteria**

- AC-3.2.a: With a populated `~/.config/cmux` and no `~/.config/ghostty-dock`, one launch creates `~/.config/ghostty-dock` containing copies of all listed files → condition holds by directory inspection.
- AC-3.2.b: `~/.config/cmux` and every file under it is byte-identical before and after migration → `diff -r` of a pre-captured snapshot exits 0.
- AC-3.2.c: Running the migration twice is idempotent and does not overwrite changes made to the new directory between runs → second run leaves the new directory's mtime/content unchanged.
- AC-3.2.d: `./scripts/test-unit.sh test -only-testing:cmuxTests/GhosttyDockConfigMigrationTests` → exit 0.
- AC-3.2.e: If `~/.config/cmux` is absent, launch creates a fresh empty config without error → exit 0, no crash.

**Acceptance Tests**

- Test-3.2.a (Unit): migration against an injected temp home containing a populated legacy dir;
  asserts every file is copied. RED before the migration exists, GREEN after.
- Test-3.2.b (Regression): asserts the legacy directory is untouched — enumerates it before and
  after and compares contents and file count. This is the test that enforces O4.
- Test-3.2.c (Unit): idempotence — run migration twice, mutate the new dir between runs, assert
  the mutation survives.
- Test-3.2.d (Unit): absent-legacy-dir case produces a clean empty state, no throw.
- Test-3.2.e (Unit): a legacy dir containing a symlink pointing outside the config tree is not
  followed.

**Verification Commands**

```bash
set -e
./scripts/lint-pbxproj-test-wiring.sh
./scripts/test-unit.sh test -only-testing:cmuxTests/GhosttyDockConfigMigrationTests
grep -q 'legacyDirectory' Packages/macOS/CmuxSettings/Sources/CmuxSettings/Stores/CmuxConfigLocation.swift
test -f Sources/GhosttyDockConfigMigration.swift
grep -qE 'FileManager|copyItem' Sources/GhosttyDockConfigMigration.swift
test "$(grep -c 'removeItem\|moveItem' Sources/GhosttyDockConfigMigration.swift)" -eq 0
```

### 3.3 Preferences domain migration

**Implementation Details**

- **Systems affected:** a new migration step in `Sources/GhosttyDockConfigMigration.swift`,
  plus `CLI/cmux.swift:3020` (`defaultBrowserSettingsDomain`).
- **Problem:** the app reads `UserDefaults.standard`, which is keyed by bundle identifier.
  Phase 2 changed the bundle identifier, so **every existing user setting is silently orphaned** —
  no error, no crash, just defaults everywhere.
- **Change:** on first launch under the new bundle id, open
  `UserDefaults(suiteName: "com.cmuxterm.app")`, copy its entire `dictionaryRepresentation()`
  into `UserDefaults.standard` for keys not already set, and **leave the old domain intact**
  (same non-destructive rule as 3.2). Guard with the same versioned watermark.
- `CLI/cmux.swift:3020` must be updated in the same commit, or the CLI reads a dead domain.
- **Mitigating context:** a meaningful subset of settings is already mirrored into
  `~/.config/cmux/cmux.json`, which 3.2 copies — so 3.2 partially covers this even if 3.3 misses
  a key. That does not make 3.3 optional; window/dock/UI state lives only in defaults.
- **Failure modes:** copying over already-set keys → clobbers post-migration user changes;
  copying Apple-internal keys (`NSWindow*`, `AppleLanguages`) → imports stale window frames.
  Filter to keys matching the app's own known prefixes.

**Acceptance Criteria**

- AC-3.3.a: After migration, a key written to the old domain before the rename is readable via `UserDefaults.standard` → condition holds under an injected suite in tests.
- AC-3.3.b: The old defaults domain still contains all its original keys after migration → assert count and values unchanged.
- AC-3.3.c: Keys already present in the new domain are NOT overwritten → condition holds by test.
- AC-3.3.d: `grep -c 'com.cmuxterm.app' CLI/cmux.swift` → prints `0`.
- AC-3.3.e: `./scripts/test-unit.sh test -only-testing:cmuxTests/GhosttyDockDefaultsMigrationTests` → exit 0.

**Acceptance Tests**

- Test-3.3.a (Unit): seed a source suite, run migration, assert values readable from the
  destination. RED before, GREEN after.
- Test-3.3.b (Regression): assert source suite is unmodified (enforces the non-destructive rule).
- Test-3.3.c (Unit): pre-set a key in the destination, assert migration does not overwrite it.
- Test-3.3.d (Unit): assert Apple-internal keys are excluded by the prefix filter.

**Verification Commands**

```bash
set -e
test "$(grep -c 'com\.cmuxterm\.app' CLI/cmux.swift | tr -d ' ')" -eq 0
./scripts/lint-pbxproj-test-wiring.sh
./scripts/test-unit.sh test -only-testing:cmuxTests/GhosttyDockDefaultsMigrationTests
./scripts/test-unit.sh test -only-testing:cmuxTests/GhosttyDockConfigMigrationTests
```

## Phase 4: User-Visible Brand Strings

**Purpose:** Cannot start before Phase 3, because the brand sweep touches thousands of localized
strings and produces the largest diff in the project; running it before data continuity exists
would leave the user with a Ghostty Dock-branded build that cannot find their settings. It must
also follow Phase 2, since the `apply-brand` tool's rename map encodes the identity decisions
made there. This phase is deliberately last among code phases because it is the only one whose
output must be *re-applied* after every future upstream ingest.

### 4.1 Build the re-runnable brand transformation tool

**Implementation Details**

- **New file:** `scripts/apply-brand.py`. Deterministic, idempotent, re-runnable. Reads a rename
  map and rewrites only the surfaces enumerated below.
- **Why a script and not a one-time sed:** `Resources/Localizable.xcstrings` sees **1.72
  cmux-touching upstream commits/day** and `CLI/cmux.swift` sees **2.85/day**. Hand-maintaining a
  rename in those files means re-resolving conflicts on essentially every ingest. With this tool,
  ingest becomes: merge upstream taking their side for these files, re-run `apply-brand.py`,
  verify with `check-brand.py` (4.2).
- **In-scope surfaces (exact):**
  - `Resources/Localizable.xcstrings` — rewrite **values only**, never keys. 319 distinct keys
    carry `cmux` in their values across 20 locales (`ar, bs, da, de, en, es, fr, it, ja, km, ko,
    nb, pl, pt-BR, ru, th, tr, uk, zh-Hans, zh-Hant`), 2,790 value occurrences total.
  - `Resources/InfoPlist.xcstrings` — 22 value occurrences across 18 locales (permission prompts).
  - `Resources/Info.plist` — the four `NS*UsageDescription` strings and two `UTTypeDescription`
    strings that read "A program running within cmux would like to…".
  - `Resources/cmux.sdef` — `title`/`name`/`description` attributes only. **Never** the 4-char
    `code=` values (`Cmux`, `CmuxNWin`, …) or `cocoa class=` attributes — those are AppleScript
    wire identifiers.
  - Swift `String(localized:defaultValue:)` literals in `Sources/` (176 occurrences) and `CLI/`
    (43 occurrences).
  - `README.md` and the 20 localized `README.*.md`.
  - `docs/**` prose.
  - `scripts/reload.sh`, `scripts/reloads.sh` app-name variables and the downstream scripts that
    match on the literal app name.
- **Explicitly excluded by the tool (it must refuse to touch these):** `web/**` (C2),
  `CHANGELOG.md` (C3), any `CMUX_*` token (C4), any keychain/HKDF string (C5), xcstrings **keys**,
  `.sdef` `code=` attributes, Swift type/function identifiers, filenames, and directory names.
- **Rename map semantics:** `cmux` → `Ghostty Dock` in prose; the quoted CLI token `'cmux'` and
  `cmux <subcommand>` → `gdock`; `cmux.json` → unchanged (see 3.2 filename policy);
  `~/.config/cmux` → `~/.config/ghostty-dock`.
- **Failure modes:** rewriting xcstrings keys → every localized lookup silently falls back to
  English; rewriting `.sdef` `code=` → AppleScript breaks; non-idempotence → "Ghostty Dock"
  becomes "Ghostty Ghostty Dock" on a second run.

**Acceptance Criteria**

- AC-4.1.a: `scripts/apply-brand.py` exists and is executable → `test -x` passes.
- AC-4.1.b: `python3 scripts/apply-brand.py --check` on an already-transformed tree → exit 0 with no proposed changes (idempotence).
- AC-4.1.c: Running the tool twice produces an identical tree → `git diff --exit-code` after the second run exits 0.
- AC-4.1.d: The tool modifies zero files under `web/` and does not modify `CHANGELOG.md` → `git status --porcelain web CHANGELOG.md` prints nothing after a run.
- AC-4.1.e: `grep -c 'CMUX_' <every file the tool wrote>` is unchanged from before the run → env-var count preserved, enforcing C4.
- AC-4.1.f: `python3 -c "import json;json.load(open('Resources/Localizable.xcstrings'))"` → exit 0 (valid JSON after transformation).

**Acceptance Tests**

- Test-4.1.a (Unit): `tests/test_apply_brand_idempotent.py` runs the tool twice over a fixture
  tree and asserts the second run is a no-op. RED before the tool exists, GREEN after.
- Test-4.1.b (Regression): a fixture asserting xcstrings **keys** are never rewritten while
  **values** are.
- Test-4.1.c (Regression): a fixture asserting `.sdef` `code=` attributes and `CMUX_*` tokens
  survive untouched.
- Test-4.1.d (Regression): asserts the tool refuses to write under `web/` or to `CHANGELOG.md`.

**Verification Commands**

```bash
set -e
test -x scripts/apply-brand.py
python3 tests/test_apply_brand_idempotent.py
python3 scripts/apply-brand.py --check
python3 -c "import json;json.load(open('Resources/Localizable.xcstrings'))"
python3 -c "import json;json.load(open('Resources/InfoPlist.xcstrings'))"
plutil -lint Resources/Info.plist
git status --porcelain web CHANGELOG.md | tee /dev/stderr | test "$(wc -l)" -eq 0
```

### 4.2 Add a brand-consistency CI guard

**Implementation Details**

- **New file:** `scripts/check-brand.py`, wired as one step in the `workflow-guard-tests` job of
  `.github/workflows/ci.yml` (job declared at line 84). That job is Linux-only, needs no Xcode,
  and is where every existing string/path/policy guard already lives.
- **What it asserts:** (a) no user-visible brand surface in scope still says `cmux` where the
  rename map says it must say `Ghostty Dock` or `gdock`; (b) no excluded surface was touched —
  the `CMUX_*` env-var name set matches a checked-in baseline, xcstrings key names are unchanged,
  `.sdef` `code=` values are unchanged; (c) locale parity — every message key present in
  `Resources/Localizable.xcstrings` for `en` exists for all 20 locales.
- **(c) closes a pre-existing gap:** there is currently **no executable localization check
  anywhere in this repo**, despite `CLAUDE.md` mandating a locale audit for every user-facing
  change. The only artifact is prose guidance for review bots at
  `.github/review-bot-rules/full-internationalization.md`. Note also that `CLAUDE.md` claims
  only English and Japanese are supported, which is factually wrong — there are 20 locales.
  Correcting that statement is part of this work item.
- **Failure modes:** a guard that passes on an untransformed tree is worthless — it must be
  observed to FAIL before `apply-brand.py` runs, and pass after.

**Acceptance Criteria**

- AC-4.2.a: `python3 scripts/check-brand.py` on the transformed tree → exit 0.
- AC-4.2.b: `python3 scripts/check-brand.py` on a tree with one brand string reverted → exit non-zero, naming the offending file and line.
- AC-4.2.c: `.github/workflows/ci.yml` contains a step invoking `scripts/check-brand.py` inside `workflow-guard-tests` → condition holds by grep.
- AC-4.2.d: The locale-parity assertion fails when a key is deleted from one locale → exit non-zero.
- AC-4.2.e: `CLAUDE.md` no longer claims only English and Japanese are supported → grep for the corrected locale count succeeds.

**Acceptance Tests**

- Test-4.2.a (Regression): run the guard against a deliberately-reverted fixture; assert non-zero
  exit and a useful message. This is the anti-vacuous-pass test — the guard MUST be observed RED.
- Test-4.2.b (Unit): locale-parity check against a fixture missing a key in `ja`.
- Test-4.2.c (Integration): the guard is reachable from CI — `grep` the workflow file.

**Verification Commands**

```bash
set -e
test -x scripts/check-brand.py
python3 scripts/check-brand.py
grep -q 'check-brand.py' .github/workflows/ci.yml
python3 tests/test_check_brand_detects_regression.py
python3 -m py_compile scripts/check-brand.py scripts/apply-brand.py
```

### 4.3 Apply the brand sweep and make CLI help self-naming

**Implementation Details**

- Run `python3 scripts/apply-brand.py` over the in-scope surfaces and commit the result.
- **CLI help hardening:** `CLI/cmux.swift` prints its own name as a literal `cmux` in ~130
  `Commands:` lines plus the `usage()` header at approximately line 35097 and the subcommand
  header near line 16930. Rather than hardcoding `gdock`, derive the displayed tool name once
  from the invoked executable name (the file already has fallbacks at lines 5847 and 9122 that
  default to `"cmux"`), and interpolate it. This makes the compatibility `cmux` symlink from 2.2
  print correct help too, and it removes the highest-churn file in the rename set from the
  conflict surface permanently.
- **Failure modes:** interpolating into the ~130 command lines mechanically is exactly where a
  regex sweep can corrupt example commands; the fixture tests in 4.1 must cover this file.

**Acceptance Criteria**

- AC-4.3.a: `gdock --help` first line names `gdock`; invoking the same binary through the `cmux` compatibility symlink prints `cmux` → both conditions hold by execution.
- AC-4.3.b: The app's About panel, menu bar item, and Quit menu item read "Ghostty Dock" → condition holds by inspection of the transformed `Localizable.xcstrings` values for `about.appName`, `statusMenu.showCmux`, `menu.quitCmux`.
- AC-4.3.c: `python3 scripts/check-brand.py` → exit 0.
- AC-4.3.d: A full Debug build succeeds after the sweep → build exits 0.
- AC-4.3.e: `./scripts/test-unit.sh` (full `cmuxTests` suite) → exit 0, proving the mass string edit broke no test assertion.

**Acceptance Tests**

- Test-4.3.a (E2E): execute the built CLI as `gdock` and via the `cmux` symlink; assert each
  prints its own invoked name.
- Test-4.3.b (Regression): the full `cmuxTests` suite passes — many suites assert on user-visible
  strings, so this is the real integration signal for the sweep.
- Test-4.3.c (Integration): `check-brand.py` passes on the swept tree.

**Verification Commands**

```bash
set -e
python3 scripts/apply-brand.py
python3 scripts/check-brand.py
./scripts/reload.sh --tag ghostty-dock-rebrand
APP="$HOME/Library/Developer/Xcode/DerivedData/cmux-ghostty-dock-rebrand/Build/Products/Debug/Ghostty Dock DEV ghostty-dock-rebrand.app"
"$APP/Contents/Resources/bin/gdock" --help | head -1 | grep -q 'gdock'
./scripts/test-unit.sh
```

## Phase 5: Release Pipeline and Upstream Ingest

**Purpose:** Cannot start before Phase 4, because the release pipeline's asset names and the
brand guard it must enforce are only defined once the sweep has landed. This phase closes the
loop: it makes CI green against the renamed artifacts and — critically — establishes the
documented ingest procedure that keeps the fork mergeable, which is the constraint every earlier
phase was designed around.

### 5.1 Rename release artifacts and repair the release guards

**Implementation Details**

- **Systems affected:** `.github/workflows/release.yml`, `scripts/release_asset_guard.js` and its
  test `scripts/release_asset_guard.test.js`, `scripts/build-sign-upload.sh`,
  `scripts/verify-app-bundle-channel-metadata.sh`, `.github/workflows/nightly.yml`, and the 21
  README download links.
- `release.yml:426` sets `DMG_RELEASE="cmux-macos.dmg"` → `ghostty-dock-macos.dmg`.
- `release.yml:449` runs `mv ./cmux*.dmg "$DMG_RELEASE"`. This glob depends on the app bundle
  still being named `cmux.app`, which Phase 2 changed. It must become a glob matching the new
  bundle name, or the `mv` fails and the release job dies mid-notarization.
- `release.yml` also references `cmux.entitlements`, `cmux.release.entitlements`,
  `cmux.nightly.entitlements`, `cmux-helper.entitlements` by filename, and hardcodes
  `APP_PATH="build-universal/Build/Products/Release/cmux.app"`. Per C6 the entitlements
  *filenames* stay; only `APP_PATH` and the DMG name change.
- `scripts/release_asset_guard.js` hardcodes the immutable asset list including `cmux-macos.dmg`;
  update it and its test together.
- `scripts/verify-app-bundle-channel-metadata.sh:40` asserts `EXPECTED_NAME="cmux NIGHTLY"`.
- **Failure modes:** updating the guard without the workflow (or vice versa) produces a CI job
  that passes while publishing a misnamed asset, breaking Sparkle and Homebrew simultaneously.

**Acceptance Criteria**

- AC-5.1.a: `node scripts/release_asset_guard.test.js` → exit 0.
- AC-5.1.b: `grep -c 'cmux-macos.dmg' .github/workflows/release.yml scripts/release_asset_guard.js` → prints `0` for both files.
- AC-5.1.c: The `mv` glob in `release.yml` matches the Phase 2 bundle name → condition holds by inspection.
- AC-5.1.d: `python3 -c "import yaml,sys;yaml.safe_load(open('.github/workflows/release.yml'))"` → exit 0 (workflow still parses).
- AC-5.1.e: `./scripts/release-pretag-guard.sh` → exit 0.

**Acceptance Tests**

- Test-5.1.a (Regression): `node scripts/release_asset_guard.test.js` with the new asset names.
  RED before the guard is updated, GREEN after.
- Test-5.1.b (Integration): YAML parse of both `release.yml` and `nightly.yml`.
- Test-5.1.c (Regression): a shell test asserting no workflow references the old DMG name.

**Verification Commands**

```bash
set -e
node scripts/release_asset_guard.test.js
test "$(grep -c 'cmux-macos\.dmg' .github/workflows/release.yml | tr -d ' ')" -eq 0
test "$(grep -c 'cmux-macos\.dmg' scripts/release_asset_guard.js | tr -d ' ')" -eq 0
python3 -c "import yaml;yaml.safe_load(open('.github/workflows/release.yml'));yaml.safe_load(open('.github/workflows/nightly.yml'))"
./scripts/release-pretag-guard.sh
bash -n scripts/build-sign-upload.sh
bash -n scripts/verify-app-bundle-channel-metadata.sh
```

### 5.2 Establish the upstream ingest procedure

**Implementation Details**

- **Problem:** `.github/workflows/sync-upstream.yml` fast-forwards the pristine `upstream-main`
  mirror daily, but **nothing merges `upstream-main` into `main`**. The ingest half of the Model B
  flow (`AX-GHOSTTY-DOCK-FORK-UPSTREAM-FLOW`) does not exist. Upstream lands 54.5 commits/day, so
  the fork falls behind immediately — it was already 195 commits behind within two days.
- **New files:** `docs/upstream-ingest.md` and `.github/workflows/ingest-upstream.yml`.
- **Documented procedure:**
  1. `git fetch origin upstream-main`
  2. `git merge-tree --write-tree main origin/upstream-main` to preview conflicts without mutating
     anything (this is how the pre-rebrand 0-conflict baseline was measured).
  3. `git merge origin/upstream-main`, resolving the brand-owned files by taking upstream's side.
  4. `python3 scripts/apply-brand.py` to re-apply the brand transformation.
  5. `python3 scripts/check-brand.py` to verify, then run the build and unit suites.
- **The workflow** runs steps 1–2 on a schedule and opens an issue reporting the conflict count,
  so drift is visible rather than silent. It must NOT auto-merge — merging is a human decision.
- **Never** use `git stash`, `git reset --hard`, or branch switching in this procedure; use
  `git worktree add` (per the repo's git-safety rules).
- **Failure modes:** an ingest that resolves brand files by hand instead of re-running
  `apply-brand.py` reintroduces drift the guard will then reject.

**Acceptance Criteria**

- AC-5.2.a: `docs/upstream-ingest.md` exists and documents all five steps → condition holds by inspection.
- AC-5.2.b: `.github/workflows/ingest-upstream.yml` parses as valid YAML and contains no `git merge` that pushes to `main` → condition holds by inspection.
- AC-5.2.c: `git merge-tree --write-tree main origin/upstream-main` runs successfully and reports a conflict count → exit 0 or documented non-zero, with the count captured.
- AC-5.2.d: The documented procedure, executed end to end against the current `origin/upstream-main`, yields a tree that passes `check-brand.py` and builds → both exit 0.
- AC-5.2.e: `grep -c 'git stash\|reset --hard' docs/upstream-ingest.md .github/workflows/ingest-upstream.yml` → prints `0`.

**Acceptance Tests**

- Test-5.2.a (Integration): YAML parse of the new workflow.
- Test-5.2.b (E2E): perform a real trial ingest in a scratch worktree, run `apply-brand.py` and
  `check-brand.py`, and build. This is the acceptance test for the entire project's central
  constraint (O5) — if a real upstream merge cannot be re-branded mechanically, the thin-skin
  design has failed and must be revisited.
- Test-5.2.c (Regression): assert the forbidden git verbs appear nowhere in the procedure.

**Verification Commands**

```bash
set -e
test -f docs/upstream-ingest.md
python3 -c "import yaml;yaml.safe_load(open('.github/workflows/ingest-upstream.yml'))"
test "$(grep -c 'git stash\|reset --hard' docs/upstream-ingest.md .github/workflows/ingest-upstream.yml | awk -F: '{s+=$2} END {print s}')" -eq 0
git fetch origin upstream-main:refs/remotes/origin/upstream-main
git merge-tree --write-tree main origin/upstream-main >/dev/null
python3 scripts/check-brand.py
```

## 3. Completion Criteria

The project is complete when all of the following hold simultaneously:

- No file in the repository outside the `ghostty`, `vendor/bonsplit`, and `homebrew-cmux`
  submodules references `manaflow-ai/cmux` as an update or release source.
- A Release build of the app presents as **Ghostty Dock**, carries bundle identifier
  `cloud.stokd.ghostty-dock`, and ships a CLI invoked as **`gdock`** with a working `cmux`
  compatibility symlink.
- Launching the app on a machine with an existing `~/.config/cmux` produces a fully populated
  `~/.config/ghostty-dock`, with `~/.config/cmux` byte-for-byte unchanged.
- `python3 scripts/check-brand.py` exits 0, and it has been demonstrated to exit non-zero on a
  deliberately reverted string.
- The full `cmuxTests` suite passes: `./scripts/test-unit.sh` exits 0.
- Every guard in the `workflow-guard-tests` CI job passes, including the new brand guard.
- `node scripts/release_asset_guard.test.js` exits 0 against the renamed artifacts.
- A trial ingest of `origin/upstream-main` completes via the documented procedure and the
  resulting tree both passes `check-brand.py` and builds.
- No `CMUX_*` environment variable, keychain service string, iroh HKDF label, Swift type name,
  Xcode target name, or directory name was renamed.

## 4. Rollout & Validation

### Rollout Strategy

- **Phase 1 ships alone and first.** It is independently valuable: it stops the fork from
  self-replacing even if no other phase ever lands. Verify by installing the build and confirming
  no update is offered within 48 hours.
- **Phases 2–3 ship together as one release.** Splitting them strands user data: Phase 2 changes
  the bundle identifier, which orphans preferences until Phase 3's migration exists. Do not ship
  a build containing Phase 2 without Phase 3.
- **Phase 4 ships behind a normal dogfood cycle.** It is the largest diff and the most likely to
  produce cosmetic regressions in localized UI. Per the repo's dogfood policy, hand off to the
  user after the tagged build succeeds and focused tests pass.
- **Phase 5 ships last** and is verified by an actual trial ingest, not by inspection.
- **Rollback triggers:** (a) the CLI cannot reach the running app after Phase 2 → revert Phase 2
  wholesale, since the socket identity is all-or-nothing; (b) any evidence that `~/.config/cmux`
  was modified → revert Phase 3 immediately and audit; (c) `check-brand.py` cannot be made to
  fail on a reverted string → the guard is vacuous and Phase 4 does not ship until fixed.
- **Rollback mechanism:** each phase is a separate PR to `main`; revert the merge commit. No
  phase performs a destructive or irreversible user-data operation, so rollback is always safe
  with respect to user data.

### Post-Launch Validation

- **Update channel:** confirm over 7 days that the installed build receives no update from
  `manaflow-ai`. This is the primary success signal for O1.
- **Data continuity:** confirm `~/.config/cmux` file count and checksums are unchanged after a
  week of use, and that settings changed in Ghostty Dock persist across relaunch.
- **Coexistence:** confirm Ghostty Dock and a stock `cmux` can run simultaneously without socket
  or LaunchServices collision (validates O3).
- **Agent-session compatibility:** confirm existing agent hooks that read `CMUX_SOCKET_PATH`,
  `CMUX_WORKSPACE_ID`, and `CMUX_SURFACE_ID` still function inside Ghostty Dock terminals
  (validates C4).
- **Ingest health:** track the conflict count reported by the scheduled ingest workflow. If it
  trends above roughly 5 conflicting files per ingest, the rename set is too broad and specific
  surfaces should be removed from `apply-brand.py`'s scope and reverted to upstream wording.
- **Localization:** confirm the new locale-parity guard runs on every PR and that all 20 locales
  remain complete.

## 5. Open Questions

Every ambiguity encountered during research was resolved as a recorded decision. None of the
remaining questions block any Phase 1–2 work item.

- **Decision: thin-skin scope** — chose renaming only user-visible surfaces over a full 80,064-line
  scrub, because 74% of upstream commits touch a `cmux`-bearing line and a full scrub would make
  every future ingest a mass-conflict event. Confirmed with the user before drafting.
- **Decision: exclude `web/**`** — chose to leave the marketing site entirely alone because it is
  the single worst conflict generator (~15–20 conflicting commits/day across 20 locale files) and
  it markets `cmux.com`, a domain this fork does not operate. The one exception is
  `web/services/apns/routePolicy.ts`, included in 2.3 because it is a functional bundle-id
  allowlist whose omission would silently break push notifications.
- **Decision: exclude `CHANGELOG.md`** — chose to preserve upstream's historical record verbatim
  because 100% of its commits touch a `cmux` line and rebranding history has no user value.
- **Decision: change the bundle identifier** — chose `cloud.stokd.ghostty-dock` over keeping
  `com.cmuxterm.app`, because two installed apps sharing a bundle identifier causes LaunchServices
  to misroute launches and URL handling, and because distinct sockets let the user run both during
  the transition. The cost — orphaned preferences — is paid down by work item 3.3.
- **Decision: keep the config filename `cmux.json`** — chose to rename the *directory* but not the
  *file*, because the filename appears in ~360 lines of help text and docs across 117 files, and
  renaming it buys little user-visible branding value. Revisit if the file name proves confusing.
- **Decision: keep the `cmux://` URL scheme and add `gdock://`** — chose to register both rather
  than replace, because `cmux://workspace/...` deep links are copied by users into notes and
  tickets and silently breaking them has no upside.
- **Decision: keep a `/usr/local/bin/cmux` compatibility symlink** — chose compatibility over
  purity, because third-party agent hooks and user scripts invoke `cmux` directly.
- **Decision: derive the CLI's displayed name from argv[0]** — chose interpolation over hardcoding
  `gdock`, because it makes the compatibility symlink print correct help and permanently removes
  the repo's highest-churn rename target (2.85 conflicts/day) from the conflict surface.
- **Decision: do not rename `CMUX_*` env vars, keychain services, or HKDF labels** — chose
  stability, because renaming breaks live agent sessions with no migration path and invalidates
  stored credentials and device pairings.

Genuinely open, and deferred past Phase 2:

- **Q1 — Homebrew distribution.** The `homebrew-cmux` submodule points at
  `manaflow-ai/homebrew-cmux`, which this fork cannot push to. Distributing `gdock` via Homebrew
  requires standing up a `stokd-cloud/homebrew-ghostty-dock` tap. Not needed for local builds, so
  it is out of scope here; revisit when public distribution is actually wanted.
- **Q2 — Application icon.** The icon family is a chevron mark with no rendered "cmux" wordmark,
  so no asset strictly *must* change. Whether to commission a distinct Ghostty Dock mark is a
  design decision with no engineering dependency.
- **Q3 — iOS companion app.** `ios/` has its own identity (`dev.cmux.ios`) and 20 more locales.
  Work item 2.3 renames its identity for coherence, but a full iOS brand sweep is not scoped here
  and should be its own project if the iOS app is to ship under the new brand.
- **Q4 — `skills/cmux-*` directories.** These 17 directories surface in agent skill pickers, so
  their names are arguably user-visible. Renaming them would break every documented
  `skills/cmux-<x>` reference across `CLAUDE.md` and `AGENTS.md`. Deferred as a documentation
  project.
- **Q5 — Stale documentation discovered during research.** `CLAUDE.md` documents
  `cd cmuxd && zig build`, but no `cmuxd/` directory exists in this repo; it also claims only
  English and Japanese are supported when there are 20 locales. Work item 4.2 corrects the locale
  claim. The `cmuxd` correction is unrelated to the rebrand and should be fixed separately.
