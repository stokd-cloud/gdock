#!/usr/bin/env bash
# Regression test: the dev CLI shim's last-resort fallback resolves the CLI
# inside the installed /Applications bundle across the cmux -> gdock rename.
#
# The shim is what a bare `cmux` hits in an installed-app terminal (agent
# restore, hooks) once none of the dev pointers above it are set. It previously
# hardcoded /Applications/cmux.app/Contents/Resources/bin/gdock — the old bundle
# name paired with the new binary name — which exists under neither install, so
# the shim always fell through to its error branch.
#
# No Xcode, no zig, no build: the script is sourced for its helpers only.
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
RELOAD="$ROOT_DIR/scripts/reload.sh"
TMP_DIR="$(mktemp -d "${TMPDIR:-/tmp}/reload-shim-fallback.XXXXXX")"
FAILURES=0

cleanup() { rm -rf "$TMP_DIR"; }
trap cleanup EXIT

fail() {
  echo "FAIL: $*" >&2
  FAILURES=$((FAILURES + 1))
}

pass() { echo "ok: $*"; }

# Sourcing must define the helpers without executing the build flow.
# shellcheck source=scripts/reload.sh
source "$RELOAD"

# --- the mispairing must not reappear -------------------------------------
# Guards the exact regression: a bundle name paired with the other era's binary.
if grep -q "cmux\.app/Contents/Resources/bin/gdock" "$RELOAD"; then
  fail "reload.sh still pairs cmux.app with the gdock binary"
else
  pass "no cmux.app/bin/gdock mispairing in reload.sh"
fi

# --- candidates are correctly paired, preferred name first ----------------
# Read into an array without mapfile: macOS still ships bash 3.2.
CANDIDATES=()
while IFS= read -r line; do
  [[ -n "$line" ]] || continue
  CANDIDATES+=("$line")
done < <(installed_app_cli_candidates)

if [[ "${#CANDIDATES[@]}" -lt 2 ]]; then
  fail "expected at least 2 installed-CLI candidates, got ${#CANDIDATES[@]}"
else
  pass "emits ${#CANDIDATES[@]} installed-CLI candidates"
fi

if [[ "${CANDIDATES[0]}" == "/Applications/gdock.app/Contents/Resources/bin/gdock" ]]; then
  pass "prefers the current gdock.app bundle"
else
  fail "first candidate should be gdock.app/bin/gdock, got '${CANDIDATES[0]}'"
fi

for candidate in "${CANDIDATES[@]}"; do
  bundle="${candidate#/Applications/}"
  bundle="${bundle%%.app/*}"
  binary="${candidate##*/}"
  if [[ "$bundle" == "$binary" ]]; then
    pass "candidate correctly paired: $bundle.app -> bin/$binary"
  else
    fail "candidate mispairs bundle '$bundle' with binary '$binary': $candidate"
  fi
done

# --- the generated shim resolves a real installed CLI ----------------------
# Build a fake install for each candidate in turn and prove the shim execs it.
# CMUX_BUNDLED_CLI_PATH / the cli-path pointer are deliberately absent, which is
# what an installed-app terminal looks like.
for candidate in "${CANDIDATES[@]}"; do
  bundle_name="${candidate#/Applications/}"
  bundle_name="${bundle_name%%.app/*}"
  fake_root="$TMP_DIR/install-$bundle_name"
  fake_cli="$fake_root$candidate"
  mkdir -p "$(dirname "$fake_cli")"
  cat > "$fake_cli" <<'FAKECLI'
#!/usr/bin/env bash
echo "installed-cli-reached $*"
FAKECLI
  chmod +x "$fake_cli"

  shim="$TMP_DIR/shim-$bundle_name"
  # Point the shim at this fake install by rewriting the /Applications prefix,
  # so the test never depends on — or writes to — the real /Applications.
  candidates_under_fake=""
  for c in "${CANDIDATES[@]}"; do
    candidates_under_fake+="$fake_root$c"$'\n'
  done

  write_dev_cli_shim "$shim" "$candidates_under_fake" "$TMP_DIR/absent-cli-path"

  if [[ ! -x "$shim" ]]; then
    fail "shim was not written for $bundle_name"
    continue
  fi

  set +e
  output="$(env -u CMUX_BUNDLED_CLI_PATH -u CMUX_SOCKET_PATH -u CMUX_SOCKET \
    "$shim" some-arg 2>&1)"
  rc=$?
  set -e

  if [[ $rc -ne 0 ]]; then
    fail "shim exited $rc for $bundle_name install (output: $output)"
  elif [[ "$output" != "installed-cli-reached some-arg" ]]; then
    fail "shim did not reach the installed CLI for $bundle_name (output: $output)"
  else
    pass "shim resolves the installed CLI for $bundle_name.app"
  fi
done

# --- the shim scan never targets an app's own bin dir ----------------------
for name in "${INSTALLED_APP_CLI_NAMES[@]}"; do
  if is_installed_app_cli_dir "/Applications/${name}.app/Contents/Resources/bin"; then
    pass "recognizes ${name}.app bin dir as off-limits for the shim target"
  else
    fail "did not recognize ${name}.app bin dir as an installed-app CLI dir"
  fi
done

if is_installed_app_cli_dir "$HOME/.local/bin"; then
  fail "an ordinary PATH entry was treated as an installed-app CLI dir"
else
  pass "ordinary PATH entries remain valid shim targets"
fi

if [[ "$FAILURES" -gt 0 ]]; then
  echo "$FAILURES check(s) failed" >&2
  exit 1
fi
echo "all checks passed"
