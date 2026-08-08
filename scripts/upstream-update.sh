#!/bin/sh
# Fast-forward the pristine upstream-main worktree to manaflow-ai/cmux main.
# Invoked from the fork via: pnpm run upstream:update
set -eu

SCRIPT_DIR="$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)"
# shellcheck source=scripts/upstream-common.sh
. "$SCRIPT_DIR/upstream-common.sh"

WT="$(resolve_upstream_worktree)"
require_clean_upstream_worktree "$WT"

echo "==> upstream:update"
echo "    worktree: $WT"
echo "    branch:   $(git -C "$WT" rev-parse --abbrev-ref HEAD)"
echo "    HEAD:     $(git -C "$WT" rev-parse --short HEAD) $(git -C "$WT" log -1 --oneline --no-decorate)"

if ! git -C "$WT" remote get-url upstream >/dev/null 2>&1; then
  echo "error: remote 'upstream' is not configured in $WT" >&2
  echo "  expected: git remote add upstream https://github.com/manaflow-ai/cmux.git" >&2
  exit 1
fi

echo "==> fetch upstream"
git -C "$WT" fetch upstream main

before="$(git -C "$WT" rev-parse HEAD)"
target="$(git -C "$WT" rev-parse upstream/main)"

if [ "$before" = "$target" ]; then
  echo "==> already at upstream/main ($(git -C "$WT" rev-parse --short HEAD))"
else
  echo "==> fast-forward $before -> $target"
  git -C "$WT" merge --ff-only upstream/main
fi

echo "==> submodule update --init --recursive"
git -C "$WT" submodule update --init --recursive

echo "==> upstream:update complete"
echo "    HEAD: $(git -C "$WT" rev-parse --short HEAD) $(git -C "$WT" log -1 --oneline --no-decorate)"
echo "    match upstream/main: $(git -C "$WT" rev-parse HEAD) == $(git -C "$WT" rev-parse upstream/main)"
