#!/usr/bin/env bash
# CI guard for ./scripts/lint-submodule-gitlinks.sh.
#
# Submodule paths from .gitmodules must stay mode 160000 gitlinks.
# Machine-local worktree sharing-symlinks (absolute 120000 targets such as
# /opt/worktrees/...) must not be committable. Relative skill/AGENTS.md
# 120000 links stay allowed.
#
# Cases:
#   (a) Real repo HEAD must lint clean (fails on origin/main after PR #37
#       until vendor/bonsplit and ghostty are restored to gitlinks).
#   (b) Sandbox: .gitmodules paths as 160000 gitlinks pass.
#   (c) Sandbox: submodule path as absolute 120000 symlink fails.
#   (d) Sandbox: submodule path as relative 120000 symlink fails.
#   (e) Sandbox: relative skill/AGENTS.md 120000 symlink passes.
#   (f) Sandbox: absolute 120000 symlink outside .gitmodules still fails.

set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT_DIR"

LINT="$ROOT_DIR/scripts/lint-submodule-gitlinks.sh"
if [ ! -x "$LINT" ]; then
  echo "test_ci_submodule_gitlinks: lint not executable at $LINT" >&2
  exit 1
fi

fail() {
  echo "test_ci_submodule_gitlinks: $*" >&2
  exit 1
}

SANDBOX_PARENT="$(mktemp -d "${TMPDIR:-/tmp}/cmux-gitlink-lint.XXXXXX")"
trap 'rm -rf "$SANDBOX_PARENT"' EXIT

init_sandbox() {
  local repo="$1"
  mkdir -p "$repo"
  git -C "$repo" init -q
  git -C "$repo" config user.email "gitlink-lint@example.com"
  git -C "$repo" config user.name "gitlink-lint"
  git -C "$repo" config commit.gpgsign false
}

commit_tree() {
  local repo="$1"
  local message="$2"
  local file
  # Do not `git add -A`: it drops index-only 160000 gitlinks whose paths
  # have no worktree directory.
  git -C "$repo" add -- .gitmodules
  while IFS= read -r file; do
    [ -n "$file" ] || continue
    git -C "$repo" add -- "$file"
  done < <(git -C "$repo" ls-files --others --exclude-standard)
  git -C "$repo" commit -q -m "$message"
}

write_gitmodules() {
  local repo="$1"
  cat > "$repo/.gitmodules" <<'EOF'
[submodule "vendor/bonsplit"]
	path = vendor/bonsplit
	url = https://github.com/manaflow-ai/bonsplit.git
[submodule "ghostty"]
	path = ghostty
	url = https://github.com/manaflow-ai/ghostty.git
[submodule "homebrew-cmux"]
	path = homebrew-cmux
	url = https://github.com/manaflow-ai/homebrew-cmux.git
EOF
}

add_gitlink() {
  local repo="$1"
  local path="$2"
  mkdir -p "$(dirname "$repo/$path")"
  git -C "$repo" update-index --add --cacheinfo \
    "160000,1111111111111111111111111111111111111111,$path"
}

expect_fail() {
  local repo="$1"
  local needle="$2"
  local output=""
  local status=0
  set +e
  output="$("$LINT" --repo-root "$repo" 2>&1)"
  status=$?
  set -e
  if [ "$status" -eq 0 ]; then
    fail "expected lint to fail in $repo; output: $output"
  fi
  if ! printf '%s\n' "$output" | grep -q "$needle"; then
    fail "expected lint output to mention '$needle'; got: $output"
  fi
}

expect_ok() {
  local repo="$1"
  "$LINT" --repo-root "$repo" >/dev/null
}

# (b) Gitlinks for every submodule path pass, with a relative 120000 skill link.
REPO_B="$SANDBOX_PARENT/gitlinks-ok"
init_sandbox "$REPO_B"
write_gitmodules "$REPO_B"
add_gitlink "$REPO_B" "vendor/bonsplit"
add_gitlink "$REPO_B" "ghostty"
add_gitlink "$REPO_B" "homebrew-cmux"
mkdir -p "$REPO_B/.claude/skills"
ln -s ../../skills/cmux "$REPO_B/.claude/skills/cmux"
ln -s CLAUDE.md "$REPO_B/AGENTS.md"
commit_tree "$REPO_B" "gitlinks ok"
expect_ok "$REPO_B"

# (c) Absolute sharing-symlink on a submodule path fails.
REPO_C="$SANDBOX_PARENT/absolute-submodule"
init_sandbox "$REPO_C"
write_gitmodules "$REPO_C"
add_gitlink "$REPO_C" "ghostty"
add_gitlink "$REPO_C" "homebrew-cmux"
mkdir -p "$REPO_C/vendor"
ln -s /opt/worktrees/stokd-cloud/gdock/main/vendor/bonsplit "$REPO_C/vendor/bonsplit"
commit_tree "$REPO_C" "absolute bonsplit symlink"
expect_fail "$REPO_C" "vendor/bonsplit"

# (d) Relative symlink on a submodule path still fails (must be a gitlink).
REPO_D="$SANDBOX_PARENT/relative-submodule"
init_sandbox "$REPO_D"
write_gitmodules "$REPO_D"
add_gitlink "$REPO_D" "vendor/bonsplit"
add_gitlink "$REPO_D" "homebrew-cmux"
ln -s ../some-ghostty-checkout "$REPO_D/ghostty"
commit_tree "$REPO_D" "relative ghostty symlink"
expect_fail "$REPO_D" "ghostty"

# (e) Relative skill/AGENTS.md 120000 links pass alongside gitlinks.
# Covered by (b). Keep an explicit extra repo so a regression in (b)'s
# gitlink setup cannot hide a false pass on skill links.
REPO_E="$SANDBOX_PARENT/relative-skills"
init_sandbox "$REPO_E"
write_gitmodules "$REPO_E"
add_gitlink "$REPO_E" "vendor/bonsplit"
add_gitlink "$REPO_E" "ghostty"
add_gitlink "$REPO_E" "homebrew-cmux"
mkdir -p "$REPO_E/skills"
echo "skill" > "$REPO_E/skills/cmux"
mkdir -p "$REPO_E/.agents"
ln -s ../skills "$REPO_E/.agents/skills"
ln -s CLAUDE.md "$REPO_E/AGENTS.md"
echo "# CLAUDE" > "$REPO_E/CLAUDE.md"
commit_tree "$REPO_E" "relative skills"
expect_ok "$REPO_E"

# (f) Absolute 120000 anywhere fails, even if it is not a submodule path.
REPO_F="$SANDBOX_PARENT/absolute-other"
init_sandbox "$REPO_F"
write_gitmodules "$REPO_F"
add_gitlink "$REPO_F" "vendor/bonsplit"
add_gitlink "$REPO_F" "ghostty"
add_gitlink "$REPO_F" "homebrew-cmux"
ln -s /opt/worktrees/stokd-cloud/gdock/main/GhosttyKit.xcframework \
  "$REPO_F/GhosttyKit.xcframework"
commit_tree "$REPO_F" "absolute xcframework symlink"
expect_fail "$REPO_F" "GhosttyKit.xcframework"

# (a) Real repo HEAD must lint clean. Run last so sandbox regressions
# surface even when HEAD is still the PR #37 sharing-symlink tree.
"$LINT" --repo-root "$ROOT_DIR"

echo "test_ci_submodule_gitlinks: ok"
