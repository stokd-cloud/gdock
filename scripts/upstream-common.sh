#!/bin/sh
# Shared helpers for fork-side upstream:* tooling.
# These scripts live on the fork (main) and only *operate on* the
# pristine upstream-main worktree — they must not write tooling into that tree.

set -eu

# Resolve the pristine pure-upstream worktree path.
# Override with GDOCK_UPSTREAM_WORKTREE if needed.
resolve_upstream_worktree() {
  if [ -n "${GDOCK_UPSTREAM_WORKTREE:-}" ]; then
    printf '%s\n' "$GDOCK_UPSTREAM_WORKTREE"
    return 0
  fi

  # Prefer a worktree whose branch is exactly "upstream-main".
  wt="$(
    git worktree list --porcelain 2>/dev/null | awk '
      $1 == "worktree" { path = $2 }
      $1 == "branch" && $2 == "refs/heads/upstream-main" { print path; exit }
    '
  )"
  if [ -n "${wt:-}" ] && [ -d "$wt" ]; then
    printf '%s\n' "$wt"
    return 0
  fi

  # Convention: sibling directory next to this fork worktree.
  fork_root="$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)"
  sibling="$(CDPATH= cd -- "$fork_root/.." && pwd)/upstream-main"
  if [ -d "$sibling/.git" ] || [ -f "$sibling/.git" ]; then
    printf '%s\n' "$sibling"
    return 0
  fi

  echo "error: could not find upstream-main worktree" >&2
  echo "  set GDOCK_UPSTREAM_WORKTREE=/path/to/upstream-main" >&2
  echo "  or create: git worktree add <path> upstream-main" >&2
  return 1
}

require_clean_upstream_worktree() {
  wt="$1"
  if ! git -C "$wt" rev-parse --is-inside-work-tree >/dev/null 2>&1; then
    echo "error: not a git worktree: $wt" >&2
    return 1
  fi
  branch="$(git -C "$wt" symbolic-ref --quiet --short HEAD 2>/dev/null || true)"
  if [ "$branch" != "upstream-main" ]; then
    echo "error: expected branch upstream-main in $wt (got: ${branch:-detached})" >&2
    return 1
  fi
  if [ -n "$(git -C "$wt" status --porcelain 2>/dev/null)" ]; then
    echo "error: upstream-main worktree is dirty; refuse to touch it:" >&2
    git -C "$wt" status --short >&2
    return 1
  fi
}
