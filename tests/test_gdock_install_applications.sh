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
  echo "usage: reload.sh [--release] [--debug] [--tag <tag>] [--launch]"
  exit 0
fi

echo build >> "$GDOCK_TEST_RELOAD_CALLS"

APP="$GDOCK_TEST_BUILT_APP"
for arg in "$@"; do
  if [[ "$arg" == "--tag" ]]; then
    APP="$(dirname "$GDOCK_TEST_BUILT_APP")/gdock tagged.app"
  fi
done

rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS"
printf '%s\n' "$GDOCK_TEST_BUILD_ID" > "$APP/Contents/marker"
printf '#!/bin/sh\nexit 0\n' > "$APP/Contents/MacOS/gdock"
chmod +x "$APP/Contents/MacOS/gdock"

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
  OPEN_LOG="$TEST/open.log"
  OSASCRIPT_LOG="$TEST/osascript.log"
  KILL_LOG="$TEST/kill.log"
  RUNNING_FLAG="$TEST/installed-app-running"
  BUILT_APP="$FW/DerivedData/Build/Products/Release/gdock.app"
  BUILD_ID="build-1"
  ASSUME_TTY=""

  mkdir -p "$FW/scripts" "$FW/ghostty/include" "$STATE" "$APPS" "$TEST/bin"
  : > "$FW/ghostty/include/ghostty.h"
  : > "$RELOAD_CALLS"
  : > "$OPEN_LOG"
  : > "$OSASCRIPT_LOG"
  : > "$KILL_LOG"

  write_reload_stub
  write_seams

  git -C "$FW" -c init.defaultBranch=main init -q
  git -C "$FW" remote add origin "git@github.com:stokd/gdock.git"
  git -C "$FW" -c user.email=t@example.com -c user.name=t commit -q --allow-empty -m init
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
      GDOCK_TEST_INSTALL_DIR="$APPS" \
      GDOCK_TEST_RELOAD_CALLS="$RELOAD_CALLS" \
      GDOCK_TEST_BUILT_APP="$BUILT_APP" \
      GDOCK_TEST_BUILD_ID="$BUILD_ID" \
      GDOCK_TEST_OPEN_LOG="$OPEN_LOG" \
      GDOCK_TEST_OSASCRIPT_LOG="$OSASCRIPT_LOG" \
      GDOCK_TEST_KILL_LOG="$KILL_LOG" \
      GDOCK_TEST_RUNNING_FLAG="$RUNNING_FLAG" \
      "$GDOCK" "$@"
  )
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

if [[ ! -x "$GDOCK" ]]; then
  echo "FATAL: $GDOCK is missing or not executable" >&2
  exit 1
fi

case_fresh_install
case_replace_when_not_running
case_decline_keeps_installed
case_pending_applied_on_next_run
case_accept_quits_and_replaces
case_non_tty_declines
case_tagged_never_installs

if [[ "$FAILURES" -ne 0 ]]; then
  printf '\n%d assertion failure(s)\n' "$FAILURES" >&2
  exit 1
fi
printf '\nall gdock install-gate cases passed\n'
