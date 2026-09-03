#!/usr/bin/env bash
# Hermetic tests for the gdock installed-app swap gate (AX-GDOCK-INSTALLED-APP-SWAP-GATE).
#
# Exercises scripts/gdock-run end to end against a fake ghostty-dock worktree with a
# stub reload.sh. No Xcode, no zig, no write to the real /Applications, and no real
# process signalling: open / osascript / ps / kill are routed through env seams.
set -uo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
GDOCK="$REPO_ROOT/scripts/gdock-run"

FAILURES=0
CURRENT_CASE=""

fail() {
  printf '    FAIL (%s): %s\n' "$CURRENT_CASE" "$*" >&2
  FAILURES=$((FAILURES + 1))
}

begin_case() {
  CURRENT_CASE="$1"
  printf '==> %s\n' "$1"
}

assert_exists() { [[ -e "$1" ]] || fail "expected to exist: $1"; }
assert_absent() { [[ ! -e "$1" ]] || fail "expected NOT to exist: $1"; }

assert_eq() {
  # assert_eq <actual> <expected> <what>
  [[ "$1" == "$2" ]] || fail "$3: expected '$2', got '$1'"
}

assert_log_empty() {
  local log="$1" what="$2" contents
  contents="$(tr -d '[:space:]' < "$log" 2>/dev/null || true)"
  [[ -z "$contents" ]] || fail "$what: expected no entries, got: $(tr '\n' ';' < "$log")"
}

assert_log_nonempty() {
  local log="$1" what="$2" contents
  contents="$(tr -d '[:space:]' < "$log" 2>/dev/null || true)"
  [[ -n "$contents" ]] || fail "$what: expected at least one entry, got none"
}

installed_marker() {
  cat "$APPS/gdock.app/Contents/marker" 2>/dev/null || printf '<no-installed-app>'
}

reload_build_count() {
  # Lines are appended by the stub for real builds only (--help probes excluded).
  wc -l < "$RELOAD_CALLS" | tr -d ' '
}

reload_reuse_count() {
  wc -l < "$REUSE_CALLS" | tr -d ' '
}

pending_record() {
  # The pending-install record lives beside the per-mode build state.
  find "$STATE/builds" -name 'pending-install' -type f 2>/dev/null | head -n 1
}

write_reload_stub() {
  cat > "$FW/scripts/reload.sh" <<'STUB'
#!/usr/bin/env bash
# Stub reload.sh: advertises the fork dialect and fabricates an app bundle.
set -euo pipefail

if [[ "${1:-}" == "--help" ]]; then
  echo "usage: reload.sh [--release] [--debug] [--tag <tag>] [--reuse-app <path>] [--launch]"
  exit 0
fi

APP="$GDOCK_TEST_BUILT_APP"
TAG=""
REUSE_APP=""
REUSE_IDENTITY=""
while [[ $# -gt 0 ]]; do
  case "$1" in
    --tag)
      TAG="${2:-}"
      shift 2
      ;;
    --reuse-app)
      REUSE_APP="${2:-}"
      shift 2
      ;;
    --reuse-identity)
      REUSE_IDENTITY="${2:-}"
      shift 2
      ;;
    *)
      shift
      ;;
  esac
done
if [[ -n "$TAG" ]]; then
  APP="$(dirname "$GDOCK_TEST_BUILT_APP")/gdock tagged.app"
fi

rm -rf "$APP"
if [[ -n "$REUSE_APP" ]]; then
  printf '%s\n' "$REUSE_APP" >> "$GDOCK_TEST_REUSE_CALLS"
  printf '%s\n' "$REUSE_IDENTITY" >> "$GDOCK_TEST_REUSE_IDENTITIES"
  if [[ -n "${GDOCK_TEST_REUSE_PAUSE_FLAG:-}" && -e "$GDOCK_TEST_REUSE_PAUSE_FLAG" ]]; then
    : > "$GDOCK_TEST_REUSE_ENTERED"
    while [[ -e "$GDOCK_TEST_REUSE_PAUSE_FLAG" ]]; do
      sleep 0.05
    done
  fi
  if [[ "${GDOCK_TEST_REUSE_REJECT:-0}" != "1" ]]; then
    cp -R "$REUSE_APP" "$APP"
  else
    REUSE_APP=""
  fi
fi
if [[ -z "$REUSE_APP" ]]; then
  echo build >> "$GDOCK_TEST_RELOAD_CALLS"
  mkdir -p "$APP/Contents/MacOS"
  printf '%s\n' "$GDOCK_TEST_BUILD_ID" > "$APP/Contents/marker"
  printf '#!/bin/sh\nexit 0\n' > "$APP/Contents/MacOS/gdock"
  chmod +x "$APP/Contents/MacOS/gdock"
fi

echo "Build complete."
echo "App path:"
echo "  $APP"
STUB
  chmod +x "$FW/scripts/reload.sh"
}

write_seams() {
  cat > "$TEST/bin/open" <<'SEAM'
#!/usr/bin/env bash
printf '%s\n' "$*" >> "$GDOCK_TEST_OPEN_LOG"
SEAM

  cat > "$TEST/bin/osascript" <<'SEAM'
#!/usr/bin/env bash
printf '%s\n' "$*" >> "$GDOCK_TEST_OSASCRIPT_LOG"
# A real quit ends the process; model that so the pid scan goes quiet.
rm -f "$GDOCK_TEST_RUNNING_FLAG"
# When gdock-build runs inside the installed app, quitting the app SIGHUPs the
# builder. Opt in so the regression case can prove the swap still finishes.
if [[ -n "${GDOCK_TEST_QUIT_KILLS_BUILDER:-}" ]]; then
  kill -HUP "$PPID" 2>/dev/null || true
fi
SEAM

  # Stands in for the process-table scan. Emits "<pid> <executable path>" lines,
  # the same shape as `ps -axo pid=,comm=`.
  cat > "$TEST/bin/ps" <<'SEAM'
#!/usr/bin/env bash
if [[ -f "$GDOCK_TEST_RUNNING_FLAG" ]]; then
  printf '%s %s\n' 4242 "$GDOCK_TEST_INSTALL_DIR/gdock.app/Contents/MacOS/gdock"
fi
printf '%s %s\n' 1 /sbin/launchd
SEAM

  cat > "$TEST/bin/kill" <<'SEAM'
#!/usr/bin/env bash
printf '%s\n' "$*" >> "$GDOCK_TEST_KILL_LOG"
rm -f "$GDOCK_TEST_RUNNING_FLAG"
SEAM

  chmod +x "$TEST/bin/open" "$TEST/bin/osascript" "$TEST/bin/ps" "$TEST/bin/kill"
}

new_env() {
  TEST="$(mktemp -d "${TMPDIR:-/tmp}/gdock-install-test.XXXXXX")"
  FW="$TEST/worktree"
  STATE="$TEST/state"
  APPS="$TEST/Applications"
  RELOAD_CALLS="$TEST/reload-calls"
  REUSE_CALLS="$TEST/reuse-calls"
  REUSE_IDENTITIES="$TEST/reuse-identities"
  OPEN_LOG="$TEST/open.log"
  OSASCRIPT_LOG="$TEST/osascript.log"
  KILL_LOG="$TEST/kill.log"
  RUNNING_FLAG="$TEST/installed-app-running"
  BUILT_APP="$FW/DerivedData/Build/Products/Release/gdock.app"
  BUILD_ID="build-1"
  ASSUME_TTY=""
  QUIT_KILLS_BUILDER=""
  REUSE_REJECT=0
  REUSE_PAUSE_FLAG="$TEST/reuse-pause"
  REUSE_ENTERED="$TEST/reuse-entered"
  SKIP_ZIG_VALUE=1
  INNER_VALUE=0

  mkdir -p "$FW/scripts" "$FW/ghostty/include" "$STATE" "$APPS" "$TEST/bin"
  : > "$FW/ghostty/include/ghostty.h"
  : > "$RELOAD_CALLS"
  : > "$REUSE_CALLS"
  : > "$REUSE_IDENTITIES"
  : > "$OPEN_LOG"
  : > "$OSASCRIPT_LOG"
  : > "$KILL_LOG"

  write_reload_stub
  write_seams

  git -C "$FW" -c init.defaultBranch=main init -q
  git -C "$FW" remote add origin "git@github.com:stokd/gdock.git"
  printf 'DerivedData/\n' > "$FW/.gitignore"
  git -C "$FW" add .gitignore
  git -C "$FW" -c user.email=t@example.com -c user.name=t commit -q -m init
}

cleanup_env() {
  [[ -n "${TEST:-}" && -d "$TEST" ]] && rm -rf "$TEST"
}

seed_installed() {
  # seed_installed <marker-id>
  local app="$APPS/gdock.app"
  rm -rf "$app"
  mkdir -p "$app/Contents/MacOS"
  printf '%s\n' "$1" > "$app/Contents/marker"
  printf '#!/bin/sh\nexit 0\n' > "$app/Contents/MacOS/gdock"
  chmod +x "$app/Contents/MacOS/gdock"
}

mark_running() { : > "$RUNNING_FLAG"; }
mark_not_running() { rm -f "$RUNNING_FLAG"; }

run_gdock() {
  (
    cd "$FW" || exit 1
    env \
      GDOCK_STATE_DIR="$STATE" \
      GDOCK_INSTALL_DIR="$APPS" \
      GDOCK_OPEN="$TEST/bin/open" \
      GDOCK_OSASCRIPT="$TEST/bin/osascript" \
      GDOCK_PS="$TEST/bin/ps" \
      GDOCK_KILL="$TEST/bin/kill" \
      GDOCK_ASSUME_TTY="$ASSUME_TTY" \
      GDOCK_PROMPT_TIMEOUT=5 \
      GDOCK_INNER="$INNER_VALUE" \
      GDOCK_SKIP_ZIG="$SKIP_ZIG_VALUE" \
      GDOCK_TEST_INSTALL_DIR="$APPS" \
      GDOCK_TEST_RELOAD_CALLS="$RELOAD_CALLS" \
      GDOCK_TEST_REUSE_CALLS="$REUSE_CALLS" \
      GDOCK_TEST_REUSE_IDENTITIES="$REUSE_IDENTITIES" \
      GDOCK_TEST_REUSE_REJECT="$REUSE_REJECT" \
      GDOCK_TEST_REUSE_PAUSE_FLAG="$REUSE_PAUSE_FLAG" \
      GDOCK_TEST_REUSE_ENTERED="$REUSE_ENTERED" \
      GDOCK_TEST_BUILT_APP="$BUILT_APP" \
      GDOCK_TEST_BUILD_ID="$BUILD_ID" \
      GDOCK_TEST_OPEN_LOG="$OPEN_LOG" \
      GDOCK_TEST_OSASCRIPT_LOG="$OSASCRIPT_LOG" \
      GDOCK_TEST_KILL_LOG="$KILL_LOG" \
      GDOCK_TEST_RUNNING_FLAG="$RUNNING_FLAG" \
      GDOCK_TEST_QUIT_KILLS_BUILDER="$QUIT_KILLS_BUILDER" \
      "$GDOCK" "$@"
  )
}

wait_until_installed() {
  # wait_until_installed <marker-id>
  local expected="$1" attempt
  for attempt in {1..100}; do
    [[ "$(installed_marker)" == "$expected" ]] && return 0
    sleep 0.05
  done
  return 1
}

# ---------------------------------------------------------------------------
# Case 1: nothing installed yet -> install, launch, no prompt.
# ---------------------------------------------------------------------------
case_fresh_install() {
  begin_case "case 1: no installed app + successful build installs and launches"
  new_env
  BUILD_ID="build-1"
  mark_not_running

  local out status
  out="$(run_gdock --build 2>&1 < /dev/null)"
  status=$?

  assert_eq "$status" "0" "exit status"
  assert_exists "$APPS/gdock.app"
  assert_eq "$(installed_marker)" "build-1" "installed bundle marker"
  assert_log_nonempty "$OPEN_LOG" "launch"
  grep -q "$APPS/gdock.app" "$OPEN_LOG" || fail "launch did not target the installed app: $(cat "$OPEN_LOG")"
  grep -qiE 'replace|\[y/N\]' <<<"$out" && fail "prompted even though nothing was running"
  assert_absent "$(pending_record 2>/dev/null || true)"
  cleanup_env
}

# ---------------------------------------------------------------------------
# Case 2: installed but not running -> replace silently, launch.
# ---------------------------------------------------------------------------
case_replace_when_not_running() {
  begin_case "case 2: installed + not running + new build replaces and launches"
  new_env
  seed_installed "old-build"
  mark_not_running
  BUILD_ID="build-2"

  local status
  run_gdock --build < /dev/null > "$TEST/out.log" 2>&1
  status=$?

  assert_eq "$status" "0" "exit status"
  assert_eq "$(installed_marker)" "build-2" "installed bundle marker after replace"
  grep -q "$APPS/gdock.app" "$OPEN_LOG" || fail "new installed app was not launched"
  cleanup_env
}

# ---------------------------------------------------------------------------
# Case 3: installed and running, answer "n" -> untouched, pending recorded.
# ---------------------------------------------------------------------------
case_decline_keeps_installed() {
  begin_case "case 3: installed + running + answer n leaves it alone and records pending"
  new_env
  seed_installed "old-build"
  mark_running
  BUILD_ID="build-3"
  ASSUME_TTY=1

  local status pending
  printf 'n\n' | run_gdock --build > "$TEST/out.log" 2>&1
  status=$?

  assert_eq "$status" "0" "exit status"
  assert_eq "$(installed_marker)" "old-build" "installed bundle must be unchanged"
  assert_log_empty "$OSASCRIPT_LOG" "quit via osascript"
  assert_log_empty "$KILL_LOG" "kill by pid"
  pending="$(pending_record)"
  [[ -n "$pending" ]] || fail "no pending-install record was written"
  if [[ -n "$pending" ]]; then
    grep -q "$BUILT_APP" "$pending" || fail "pending record does not reference the built bundle"
  fi
  cleanup_env
}

# ---------------------------------------------------------------------------
# Case 4: rerun after a decline, app now closed -> install pending, no rebuild.
# ---------------------------------------------------------------------------
case_pending_applied_on_next_run() {
  begin_case "case 4: pending install is applied on the next run without rebuilding"
  new_env
  seed_installed "old-build"
  mark_running
  BUILD_ID="build-4"
  ASSUME_TTY=1

  printf 'n\n' | run_gdock --build > "$TEST/out1.log" 2>&1
  local builds_after_decline
  builds_after_decline="$(reload_build_count)"
  [[ -n "$(pending_record)" ]] || fail "precondition: decline should have recorded a pending install"

  # The user quits the app, then runs gdock again with no source changes.
  mark_not_running
  ASSUME_TTY=""
  local status
  run_gdock < /dev/null > "$TEST/out2.log" 2>&1
  status=$?

  assert_eq "$status" "0" "exit status"
  assert_eq "$(installed_marker)" "build-4" "pending build should now be installed"
  assert_eq "$(reload_build_count)" "$builds_after_decline" "reload.sh must not run again"
  assert_absent "$(pending_record 2>/dev/null || true)"
  grep -q "$APPS/gdock.app" "$OPEN_LOG" || fail "installed app was not launched"
  cleanup_env
}

# ---------------------------------------------------------------------------
# Case 5: installed and running, answer "y" -> quit, replace, launch.
# ---------------------------------------------------------------------------
case_accept_quits_and_replaces() {
  begin_case "case 5: installed + running + answer y quits, replaces, and launches"
  new_env
  seed_installed "old-build"
  mark_running
  BUILD_ID="build-5"
  ASSUME_TTY=1

  local status
  printf 'y\n' | run_gdock --build > "$TEST/out.log" 2>&1
  status=$?

  assert_eq "$status" "0" "exit status"
  if ! grep -qi 'quit' "$OSASCRIPT_LOG" 2>/dev/null && ! [[ -s "$KILL_LOG" ]]; then
    fail "running app was never asked to quit (osascript and kill logs are both empty)"
  fi
  assert_eq "$(installed_marker)" "build-5" "installed bundle marker after accepted replace"
  grep -q "$APPS/gdock.app" "$OPEN_LOG" || fail "new installed app was not launched"
  assert_absent "$(pending_record 2>/dev/null || true)"
  cleanup_env
}

# ---------------------------------------------------------------------------
# Case 5b: answering y must finish the swap even if quitting the app SIGHUPs
# the gdock-build process (the in-app terminal case).
# ---------------------------------------------------------------------------
case_accept_survives_builder_hup() {
  begin_case "case 5b: y still replaces and launches after quit SIGHUPs the builder"
  new_env
  seed_installed "old-build"
  mark_running
  BUILD_ID="build-5b"
  ASSUME_TTY=1
  QUIT_KILLS_BUILDER=1

  printf 'y\n' | run_gdock --build > "$TEST/out.log" 2>&1 || true

  if ! wait_until_installed "build-5b"; then
    fail "installed bundle marker after builder HUP: expected 'build-5b', got '$(installed_marker)'"
  fi
  local attempt
  for attempt in {1..100}; do
    grep -q "$APPS/gdock.app" "$OPEN_LOG" 2>/dev/null && break
    sleep 0.05
  done
  grep -q "$APPS/gdock.app" "$OPEN_LOG" || fail "new installed app was not launched after builder HUP"
  if ! grep -qi 'quit' "$OSASCRIPT_LOG" 2>/dev/null && ! [[ -s "$KILL_LOG" ]]; then
    fail "running app was never asked to quit (osascript and kill logs are both empty)"
  fi
  cleanup_env
}

# ---------------------------------------------------------------------------
# Case 6: running, stdin is not a tty -> behave as a decline, never hang.
# ---------------------------------------------------------------------------
case_non_tty_declines() {
  begin_case "case 6: installed + running + no tty declines without prompting"
  new_env
  seed_installed "old-build"
  mark_running
  BUILD_ID="build-6"
  ASSUME_TTY=""

  local status
  run_gdock --build < /dev/null > "$TEST/out.log" 2>&1
  status=$?

  assert_eq "$status" "0" "exit status"
  assert_eq "$(installed_marker)" "old-build" "installed bundle must be unchanged"
  assert_log_empty "$KILL_LOG" "kill by pid"
  [[ -n "$(pending_record)" ]] || fail "no pending-install record was written"
  cleanup_env
}

# ---------------------------------------------------------------------------
# Case 7: tagged builds never touch the install dir.
# ---------------------------------------------------------------------------
case_tagged_never_installs() {
  begin_case "case 7: tagged build leaves the install dir untouched"
  new_env
  mark_not_running
  BUILD_ID="build-7"

  run_gdock --build --tag foo < /dev/null > "$TEST/out.log" 2>&1

  assert_absent "$APPS/gdock.app"
  cleanup_env
}

# ---------------------------------------------------------------------------
# Case 8: an unchanged first Release tag clones the main artifact without a
# second compile, then the tagged cache handles subsequent unchanged runs.
# ---------------------------------------------------------------------------
case_unchanged_release_retags_main_artifact() {
  begin_case "case 8: unchanged first Release tag reuses the main build artifact"
  new_env
  mark_not_running
  BUILD_ID="main-build"

  run_gdock --build --no-launch < /dev/null > "$TEST/main.log" 2>&1
  assert_eq "$(reload_build_count)" "1" "main Release compile count"
  assert_eq "$(reload_reuse_count)" "0" "main Release reuse count"

  local donor_marker tagged_app status expected_identity installed_snapshot
  donor_marker="$(cat "$BUILT_APP/Contents/marker" 2>/dev/null || true)"
  tagged_app="$(dirname "$BUILT_APP")/gdock tagged.app"
  expected_identity="sha256:$(shasum -a 256 "$BUILT_APP/Contents/MacOS/gdock" | awk '{ print $1 }')"
  installed_snapshot="$TEST/installed-snapshot.app"
  cp -R "$APPS/gdock.app" "$installed_snapshot"
  mark_running
  : > "$OSASCRIPT_LOG"
  : > "$KILL_LOG"
  BUILD_ID="tag-build-must-not-run"
  run_gdock --tag latest --no-launch < /dev/null > "$TEST/tag1.log" 2>&1
  status=$?

  assert_eq "$status" "0" "first tagged exit status"
  assert_eq "$(reload_build_count)" "1" "first tag must not compile"
  assert_eq "$(reload_reuse_count)" "1" "first tag must clone once"
  assert_exists "$tagged_app"
  assert_eq "$(cat "$tagged_app/Contents/marker" 2>/dev/null || true)" "main-build" "tagged artifact payload"
  assert_eq "$(cat "$BUILT_APP/Contents/marker" 2>/dev/null || true)" "$donor_marker" "donor must remain unchanged"
  grep -Fxq "$BUILT_APP" "$REUSE_CALLS" || fail "reuse did not name the main Release donor"
  assert_eq "$(head -n 1 "$REUSE_IDENTITIES")" "$expected_identity" "reuse donor identity"
  diff -qr "$installed_snapshot" "$APPS/gdock.app" >/dev/null 2>&1 || fail "tagged reuse modified the installed app"
  assert_log_empty "$OSASCRIPT_LOG" "tagged reuse quit via osascript"
  assert_log_empty "$KILL_LOG" "tagged reuse kill by pid"

  run_gdock --tag latest --no-launch < /dev/null > "$TEST/tag2.log" 2>&1
  status=$?
  assert_eq "$status" "0" "second tagged exit status"
  assert_eq "$(reload_build_count)" "1" "second unchanged tag must not compile"
  assert_eq "$(reload_reuse_count)" "1" "second unchanged tag must not restage"
  assert_eq "$(cat "$tagged_app/Contents/marker" 2>/dev/null || true)" "main-build" "second tagged payload"

  BUILD_ID="forced-tag-build"
  run_gdock --build --tag latest --no-launch < /dev/null > "$TEST/tag-forced.log" 2>&1
  assert_eq "$(reload_build_count)" "2" "forced tag must compile"
  assert_eq "$(reload_reuse_count)" "1" "forced tag must bypass artifact reuse"
  assert_eq "$(cat "$tagged_app/Contents/marker" 2>/dev/null || true)" "forced-tag-build" "forced tag payload"
  cleanup_env
}

# ---------------------------------------------------------------------------
# Case 10: concurrent first runs serialize donor reuse and publish one coherent
# tagged cache record.
# ---------------------------------------------------------------------------
case_concurrent_release_reuse() {
  begin_case "case 10: concurrent first tag runs reuse and publish exactly once"
  new_env
  mark_not_running
  BUILD_ID="main-build"
  run_gdock --build --no-launch < /dev/null > "$TEST/main.log" 2>&1

  INNER_VALUE=1
  : > "$REUSE_PAUSE_FLAG"
  run_gdock --tag concurrent --no-launch < /dev/null > "$TEST/concurrent-1.log" 2>&1 &
  local first_pid=$!
  local attempt
  for attempt in {1..100}; do
    [[ -e "$REUSE_ENTERED" ]] && break
    sleep 0.05
  done
  [[ -e "$REUSE_ENTERED" ]] || fail "first concurrent reuse never reached the pause point"

  run_gdock --tag concurrent --no-launch < /dev/null > "$TEST/concurrent-2.log" 2>&1 &
  local second_pid=$!
  for attempt in {1..100}; do
    grep -q 'waiting for another release artifact operation' "$TEST/concurrent-2.log" 2>/dev/null && break
    sleep 0.05
  done
  grep -q 'waiting for another release artifact operation' "$TEST/concurrent-2.log" 2>/dev/null \
    || fail "second concurrent run never contended for the release lock"
  rm -f "$REUSE_PAUSE_FLAG"

  local first_status=0 second_status=0
  wait "$first_pid" || first_status=$?
  wait "$second_pid" || second_status=$?
  assert_eq "$first_status" "0" "first concurrent exit status"
  assert_eq "$second_status" "0" "second concurrent exit status"
  assert_eq "$(reload_build_count)" "1" "concurrent tags must not add a compile"
  assert_eq "$(reload_reuse_count)" "1" "concurrent tags must restage exactly once"

  local tagged_app
  tagged_app="$(dirname "$BUILT_APP")/gdock tagged.app"
  assert_eq "$(cat "$tagged_app/Contents/marker" 2>/dev/null || true)" "main-build" "concurrent tagged payload"
  run_gdock --tag concurrent --no-launch < /dev/null > "$TEST/concurrent-3.log" 2>&1
  assert_eq "$?" "0" "third unchanged concurrent-tag exit status"
  assert_eq "$(reload_build_count)" "1" "third unchanged run must not compile"
  assert_eq "$(reload_reuse_count)" "1" "third unchanged run must not restage"
  cleanup_env
}

# ---------------------------------------------------------------------------
# Case 11: a source edit during packaging invalidates the clone and triggers a
# full tagged build for the new fingerprint.
# ---------------------------------------------------------------------------
case_source_change_during_reuse() {
  begin_case "case 11: source change during reuse falls back to a fresh build"
  new_env
  mark_not_running
  BUILD_ID="main-build"
  run_gdock --build --no-launch < /dev/null > "$TEST/main.log" 2>&1

  INNER_VALUE=1
  BUILD_ID="source-race-build"
  : > "$REUSE_PAUSE_FLAG"
  run_gdock --tag source-race --no-launch < /dev/null > "$TEST/source-race.log" 2>&1 &
  local build_pid=$!
  local attempt
  for attempt in {1..100}; do
    [[ -e "$REUSE_ENTERED" ]] && break
    sleep 0.05
  done
  [[ -e "$REUSE_ENTERED" ]] || fail "source-race reuse never reached the pause point"
  printf 'changed during reuse\n' > "$FW/source-during-reuse"
  rm -f "$REUSE_PAUSE_FLAG"

  local build_status=0
  wait "$build_pid" || build_status=$?
  assert_eq "$build_status" "0" "source-race exit status"
  assert_eq "$(reload_build_count)" "2" "source race must trigger one fresh compile"
  assert_eq "$(reload_reuse_count)" "1" "source race must attempt reuse once"
  local tagged_app
  tagged_app="$(dirname "$BUILT_APP")/gdock tagged.app"
  assert_eq "$(cat "$tagged_app/Contents/marker" 2>/dev/null || true)" "source-race-build" "source-race payload"
  cleanup_env
}

# ---------------------------------------------------------------------------
# Case 9: changed sources and Debug builds never reuse the main Release donor.
# ---------------------------------------------------------------------------
case_release_reuse_guardrails() {
  begin_case "case 9: changed sources and Debug bypass Release artifact reuse"
  new_env
  mark_not_running
  BUILD_ID="main-build"
  run_gdock --build --no-launch < /dev/null > "$TEST/main.log" 2>&1

  printf 'changed\n' > "$FW/source-change"
  BUILD_ID="changed-tag-build"
  run_gdock --tag changed --no-launch < /dev/null > "$TEST/changed.log" 2>&1
  assert_eq "$(reload_build_count)" "2" "changed sources must compile"
  assert_eq "$(reload_reuse_count)" "0" "changed sources must not reuse"
  cleanup_env

  new_env
  mark_not_running
  BUILD_ID="main-build"
  run_gdock --build --no-launch < /dev/null > "$TEST/main.log" 2>&1
  BUILD_ID="debug-tag-build"
  run_gdock --debug --tag debug --no-launch < /dev/null > "$TEST/debug.log" 2>&1
  assert_eq "$(reload_build_count)" "2" "Debug tag must compile"
  assert_eq "$(reload_reuse_count)" "0" "Debug tag must not reuse Release"
  cleanup_env

  new_env
  mark_not_running
  BUILD_ID="main-build"
  run_gdock --build --no-launch < /dev/null > "$TEST/main.log" 2>&1
  chmod -x "$BUILT_APP/Contents/MacOS/gdock"
  BUILD_ID="malformed-donor-tag-build"
  run_gdock --tag malformed --no-launch < /dev/null > "$TEST/malformed.log" 2>&1
  assert_eq "$(reload_build_count)" "2" "malformed donor must compile"
  assert_eq "$(reload_reuse_count)" "0" "malformed donor must not reuse"
  cleanup_env

  new_env
  mark_not_running
  BUILD_ID="main-build"
  run_gdock --build --no-launch < /dev/null > "$TEST/main.log" 2>&1
  BUILD_ID="fallback-tag-build"
  REUSE_REJECT=1
  run_gdock --tag fallback --no-launch < /dev/null > "$TEST/fallback.log" 2>&1
  local fallback_status=$?
  local fallback_app
  fallback_app="$(dirname "$BUILT_APP")/gdock tagged.app"
  assert_eq "$fallback_status" "0" "reload donor rejection fallback exit status"
  assert_eq "$(reload_build_count)" "2" "reload donor rejection must fall back to compile"
  assert_eq "$(reload_reuse_count)" "1" "reload donor rejection must first attempt reuse"
  [[ -n "$(tr -d '[:space:]' < "$REUSE_IDENTITIES" 2>/dev/null || true)" ]] || fail "reuse request omitted the recorded donor identity"
  assert_eq "$(cat "$fallback_app/Contents/marker" 2>/dev/null || true)" "fallback-tag-build" "fallback payload"
  cleanup_env

  new_env
  mark_not_running
  BUILD_ID="main-build"
  run_gdock --build --no-launch < /dev/null > "$TEST/main.log" 2>&1
  SKIP_ZIG_VALUE=0
  BUILD_ID="real-helper-tag-build"
  run_gdock --tag real-helper --no-launch < /dev/null > "$TEST/profile.log" 2>&1
  assert_eq "$(reload_build_count)" "2" "different zig-helper profile must compile"
  assert_eq "$(reload_reuse_count)" "0" "different zig-helper profile must not reuse"
  cleanup_env

  new_env
  mark_not_running
  BUILD_ID="main-build"
  run_gdock --build --no-launch < /dev/null > "$TEST/main.log" 2>&1
  printf '\n# replaced outside launcher\n' >> "$BUILT_APP/Contents/MacOS/gdock"
  BUILD_ID="identity-mismatch-tag-build"
  run_gdock --tag identity-mismatch --no-launch < /dev/null > "$TEST/identity.log" 2>&1
  assert_eq "$(reload_build_count)" "2" "changed donor identity must compile"
  assert_eq "$(reload_reuse_count)" "0" "changed donor identity must not reuse"
  cleanup_env

  new_env
  mark_not_running
  BUILD_ID="main-build"
  run_gdock --build --no-launch < /dev/null > "$TEST/main.log" 2>&1
  local main_manifest
  main_manifest="$(find "$STATE/builds" -name manifest -type f -print -quit)"
  [[ -n "$main_manifest" && -f "$main_manifest" ]] || fail "main build did not publish an atomic manifest"
  sed 's#^root=.*#root=/different/worktree#' "$main_manifest" > "$main_manifest.tmp"
  mv "$main_manifest.tmp" "$main_manifest"
  BUILD_ID="different-root-tag-build"
  run_gdock --tag different-root --no-launch < /dev/null > "$TEST/root.log" 2>&1
  assert_eq "$(reload_build_count)" "2" "different worktree root must compile"
  assert_eq "$(reload_reuse_count)" "0" "different worktree root must not reuse"
  cleanup_env

  new_env
  mark_not_running
  BUILD_ID="main-build"
  run_gdock --build --no-launch < /dev/null > "$TEST/main.log" 2>&1
  run_gdock --tag cached-root --no-launch < /dev/null > "$TEST/cached-root-1.log" 2>&1
  local tagged_manifest
  tagged_manifest="$(find "$STATE/builds" -name manifest -type f -exec grep -l '^mode=release:cached-root$' {} \; | head -n 1)"
  [[ -n "$tagged_manifest" && -f "$tagged_manifest" ]] || fail "tagged build did not publish an atomic manifest"
  sed 's#^root=.*#root=/different/worktree#' "$tagged_manifest" > "$tagged_manifest.tmp"
  mv "$tagged_manifest.tmp" "$tagged_manifest"
  BUILD_ID="cached-root-compile-must-not-run"
  run_gdock --tag cached-root --no-launch < /dev/null > "$TEST/cached-root-2.log" 2>&1
  assert_eq "$(reload_build_count)" "1" "different cached root must not require a compile when the main donor is valid"
  assert_eq "$(reload_reuse_count)" "2" "different cached root must restage from the same-root main donor"
  assert_eq "$(cat "$(dirname "$BUILT_APP")/gdock tagged.app/Contents/marker" 2>/dev/null || true)" "main-build" "different cached root payload"
  cleanup_env

  new_env
  mark_not_running
  BUILD_ID="main-build"
  run_gdock --build --no-launch < /dev/null > "$TEST/main.log" 2>&1
  main_manifest="$(find "$STATE/builds" -name manifest -type f -print -quit)"
  [[ -n "$main_manifest" && -f "$main_manifest" ]] || fail "main build did not publish an atomic manifest"
  mv "$main_manifest" "$main_manifest.legacy"
  BUILD_ID="legacy-state-tag-build"
  run_gdock --tag legacy-state --no-launch < /dev/null > "$TEST/legacy.log" 2>&1
  assert_eq "$(reload_build_count)" "2" "legacy main state must compile"
  assert_eq "$(reload_reuse_count)" "0" "legacy main state must not reuse"
  cleanup_env
}

# ---------------------------------------------------------------------------

if [[ ! -x "$GDOCK" ]]; then
  echo "FATAL: $GDOCK is missing or not executable" >&2
  exit 1
fi

case_fresh_install
case_replace_when_not_running
case_decline_keeps_installed
case_pending_applied_on_next_run
case_accept_quits_and_replaces
case_accept_survives_builder_hup
case_non_tty_declines
case_tagged_never_installs
case_unchanged_release_retags_main_artifact
case_release_reuse_guardrails
case_concurrent_release_reuse
case_source_change_during_reuse

if [[ "$FAILURES" -ne 0 ]]; then
  printf '\n%d assertion failure(s)\n' "$FAILURES" >&2
  exit 1
fi
printf '\nall gdock install-gate cases passed\n'
