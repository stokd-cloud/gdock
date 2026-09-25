#!/usr/bin/env bash
# Lint: submodule paths from .gitmodules must be mode 160000 gitlinks.
# Committed symlinks (mode 120000) may be relative (skills, AGENTS.md) but
# must never be absolute — those are machine-local worktree sharing links
# that dirty every real submodule checkout and get re-committed by git add.
#
# Usage:
#   ./scripts/lint-submodule-gitlinks.sh [--repo-root <path>] [--tree <treeish>]
#
# Exit codes:
#   0 — clean
#   1 — at least one forbidden gitlink/symlink
#   2 — invocation error

set -euo pipefail

REPO_ROOT=""
TREEISH="HEAD"

while [ "$#" -gt 0 ]; do
  case "$1" in
    --repo-root)
      REPO_ROOT="$2"
      shift 2
      ;;
    --tree)
      TREEISH="$2"
      shift 2
      ;;
    -h|--help)
      sed -n '2,14p' "$0" | sed 's/^# *//'
      exit 0
      ;;
    *)
      echo "lint-submodule-gitlinks: unknown argument: $1" >&2
      exit 2
      ;;
  esac
done

if [ -z "$REPO_ROOT" ]; then
  REPO_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
fi

cd "$REPO_ROOT"

if ! git rev-parse --is-inside-work-tree >/dev/null 2>&1; then
  echo "lint-submodule-gitlinks: not a git repository: $REPO_ROOT" >&2
  exit 2
fi

if ! git cat-file -e "$TREEISH^{tree}" 2>/dev/null; then
  echo "lint-submodule-gitlinks: unknown tree: $TREEISH" >&2
  exit 2
fi

if ! git cat-file -e "$TREEISH:.gitmodules" 2>/dev/null; then
  echo "lint-submodule-gitlinks: missing .gitmodules at $TREEISH" >&2
  exit 1
fi

fail=0

while IFS= read -r path; do
  [ -n "$path" ] || continue
  line="$(git ls-tree "$TREEISH" -- "$path" || true)"
  if [ -z "$line" ]; then
    echo "lint-submodule-gitlinks: $path is listed in .gitmodules but missing from $TREEISH" >&2
    fail=1
    continue
  fi
  mode="${line%% *}"
  if [ "$mode" != "160000" ]; then
    echo "lint-submodule-gitlinks: $path must be a 160000 gitlink, got $mode" >&2
    if [ "$mode" = "120000" ]; then
      target="$(git cat-file -p "$TREEISH:$path" || true)"
      echo "  symlink target: $target" >&2
    fi
    fail=1
  fi
done < <(git cat-file -p "$TREEISH:.gitmodules" | sed -n 's/^[[:space:]]*path[[:space:]]*=[[:space:]]*//p')

while IFS=$'\t' read -r meta path; do
  [ -n "${path:-}" ] || continue
  mode="${meta%% *}"
  [ "$mode" = "120000" ] || continue
  target="$(git cat-file -p "$TREEISH:$path")"
  case "$target" in
    /*)
      echo "lint-submodule-gitlinks: $path is an absolute symlink ($target); machine-local sharing links must not be committed" >&2
      fail=1
      ;;
  esac
done < <(git ls-tree -r "$TREEISH")

if [ "$fail" -ne 0 ]; then
  exit 1
fi

echo "lint-submodule-gitlinks: ok"
