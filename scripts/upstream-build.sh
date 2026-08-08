#!/bin/sh
# Build pure upstream cmux from the pristine upstream-main worktree.
# Invoked from the fork via: pnpm run upstream:build
# Does not modify fork main sources; builds only inside upstream-main.
set -eu

SCRIPT_DIR="$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)"
# shellcheck source=scripts/upstream-common.sh
. "$SCRIPT_DIR/upstream-common.sh"

WT="$(resolve_upstream_worktree)"
require_clean_upstream_worktree "$WT"

TAG="${GDOCK_UPSTREAM_BUILD_TAG:-upstream-main}"
# Skip zig/GhosttyKit rebuild unless explicitly requested (GDOCK_SKIP_ZIG=0).
export CMUX_SKIP_ZIG_BUILD="${CMUX_SKIP_ZIG_BUILD:-${GDOCK_SKIP_ZIG:-1}}"

echo "==> upstream:build"
echo "    worktree: $WT"
echo "    branch:   $(git -C "$WT" rev-parse --abbrev-ref HEAD)"
echo "    HEAD:     $(git -C "$WT" rev-parse --short HEAD) $(git -C "$WT" log -1 --oneline --no-decorate)"
echo "    tag:      $TAG"
echo "    CMUX_SKIP_ZIG_BUILD=$CMUX_SKIP_ZIG_BUILD"

if [ ! -x "$WT/scripts/reload.sh" ]; then
  echo "error: missing $WT/scripts/reload.sh" >&2
  exit 1
fi

if [ ! -f "$WT/ghostty/include/ghostty.h" ]; then
  echo "error: ghostty submodule not checked out in $WT" >&2
  echo "  run: pnpm run upstream:update   # initializes submodules" >&2
  exit 1
fi

# Build only (no --launch). User can open App path; or set GDOCK_UPSTREAM_LAUNCH=1.
cd "$WT"
if [ "${GDOCK_UPSTREAM_LAUNCH:-0}" = "1" ]; then
  exec ./scripts/reload.sh --tag "$TAG" --launch
else
  exec ./scripts/reload.sh --tag "$TAG"
fi
