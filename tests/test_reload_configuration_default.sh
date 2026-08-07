#!/usr/bin/env bash
# Regression test: reload.sh build configuration + app naming.
#
# Naming contract (dogfood / main app):
#   (default)              Release → gdock.app          (main app, no DEV/tag)
#   --tag <t>              Release → gdock <t>.app
#   --debug                Debug   → gdock DBG.app
#   --debug --tag <t>      Debug   → gdock DBG <t>.app
#
# Uses --print-plan, which resolves the configuration/app path and exits before
# xcodebuild runs, so this test never triggers a build.
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
RELOAD="$ROOT_DIR/scripts/reload.sh"
TAG="rel-plan"
FAILED=0

fail() {
  echo "FAIL: $1" >&2
  FAILED=1
}

assert_contains() {
  local haystack="$1" needle="$2" label="$3"
  if [[ "$haystack" != *"$needle"* ]]; then
    fail "$label: expected output to contain '$needle'"
    printf 'actual output:\n%s\n' "$haystack" >&2
  fi
}

assert_not_contains() {
  local haystack="$1" needle="$2" label="$3"
  if [[ "$haystack" == *"$needle"* ]]; then
    fail "$label: expected output NOT to contain '$needle'"
    printf 'actual output:\n%s\n' "$haystack" >&2
  fi
}

# A stub xcodebuild on PATH proves --print-plan never builds.
STUB_DIR="$(mktemp -d)"
trap 'rm -rf "$STUB_DIR"' EXIT
cat > "$STUB_DIR/xcodebuild" <<'EOF'
#!/usr/bin/env bash
echo "STUB_XCODEBUILD_INVOKED" >&2
exit 1
EOF
chmod +x "$STUB_DIR/xcodebuild"

PLAN_OUT=""
PLAN_RC=0
run_plan() {
  PLAN_RC=0
  PLAN_OUT="$(PATH="$STUB_DIR:$PATH" "$RELOAD" "$@" --print-plan 2>&1)" || PLAN_RC=$?
  if [[ "$PLAN_RC" -ne 0 ]]; then
    fail "reload.sh $* --print-plan exited $PLAN_RC"
    printf 'actual output:\n%s\n' "$PLAN_OUT" >&2
  fi
}

# 1. Default (no flags): Release main app named gdock — not DEV, no invented tag.
run_plan
DEFAULT_PLAN="$PLAN_OUT"
assert_contains "$DEFAULT_PLAN" "configuration: Release" "default plan"
assert_contains "$DEFAULT_PLAN" "/Build/Products/Release/" "default plan app path"
assert_contains "$DEFAULT_PLAN" "/gdock.app" "default plan app name"
assert_not_contains "$DEFAULT_PLAN" "/Build/Products/Debug/" "default plan app path"
assert_not_contains "$DEFAULT_PLAN" "gdock DEV" "default plan must not use DEV"
assert_not_contains "$DEFAULT_PLAN" "STUB_XCODEBUILD_INVOKED" "default plan must not build"

# 2. --tag appends the tag on a Release build (no DEV prefix).
run_plan --tag "$TAG"
TAG_PLAN="$PLAN_OUT"
assert_contains "$TAG_PLAN" "configuration: Release" "tagged plan"
assert_contains "$TAG_PLAN" "/gdock ${TAG}.app" "tagged plan app name"
assert_not_contains "$TAG_PLAN" "gdock DEV" "tagged plan must not use DEV"
assert_not_contains "$TAG_PLAN" "STUB_XCODEBUILD_INVOKED" "tagged plan must not build"

# 3. --debug without tag: Debug config, "gdock DBG".
run_plan --debug
DEBUG_PLAN="$PLAN_OUT"
assert_contains "$DEBUG_PLAN" "configuration: Debug" "debug plan"
assert_contains "$DEBUG_PLAN" "/Build/Products/Debug/" "debug plan app path"
assert_contains "$DEBUG_PLAN" "/gdock DBG.app" "debug plan app name"
assert_not_contains "$DEBUG_PLAN" "/Build/Products/Release/" "debug plan app path"
assert_not_contains "$DEBUG_PLAN" "STUB_XCODEBUILD_INVOKED" "debug plan must not build"

# 4. --debug --tag: Debug config, "gdock DBG <tag>".
run_plan --debug --tag "$TAG"
DEBUG_TAG_PLAN="$PLAN_OUT"
assert_contains "$DEBUG_TAG_PLAN" "configuration: Debug" "debug+tag plan"
assert_contains "$DEBUG_TAG_PLAN" "/gdock DBG ${TAG}.app" "debug+tag plan app name"
assert_not_contains "$DEBUG_TAG_PLAN" "STUB_XCODEBUILD_INVOKED" "debug+tag plan must not build"

# 5. Flags are documented in --help.
HELP_OUTPUT="$("$RELOAD" --help 2>&1)"
assert_contains "$HELP_OUTPUT" "--debug" "help output"
assert_contains "$HELP_OUTPUT" "--tag" "help output"

if [[ "$FAILED" -ne 0 ]]; then
  echo "test_reload_configuration_default.sh FAILED" >&2
  exit 1
fi

echo "test_reload_configuration_default.sh PASSED"
