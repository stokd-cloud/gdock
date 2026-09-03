#!/usr/bin/env bash
# Lint: the Stokd Work panel must not depend on the sidebar-dock subsystem or
# on a hardcoded data source (VAL-GATE-002 / VAL-DATA-002).
#
# The rail may host Work; Work may not know the rail exists, and it must reach
# stokd only through the resolved CLI. Fails when any Swift file under
# Sources/Stokd/ mentions the dock subsystem, the dock beta key, or an HTTP
# endpoint.
#
# Usage:
#   ./scripts/lint-stokd-work-dock-independence.sh [--repo-root <path>]
#
# Exit codes:
#   0 — clean
#   1 — at least one forbidden reference
#   2 — invocation error

set -euo pipefail

REPO_ROOT=""
while [ "$#" -gt 0 ]; do
  case "$1" in
    --repo-root)
      REPO_ROOT="$2"
      shift 2
      ;;
    -h|--help)
      sed -n '2,16p' "$0" | sed 's/^# *//'
      exit 0
      ;;
    *)
      echo "Unknown argument: $1" >&2
      exit 2
      ;;
  esac
done

if [ -z "$REPO_ROOT" ]; then
  REPO_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
fi

STOKD_DIR="$REPO_ROOT/Sources/Stokd"
if [ ! -d "$STOKD_DIR" ]; then
  echo "lint-stokd-work-dock-independence: missing $STOKD_DIR" >&2
  exit 2
fi

PATTERN='SidebarDock|sidebar\.beta\.dock\.enabled|localhost|8167|http://|URLSession'
if hits="$(grep -rnE "$PATTERN" "$STOKD_DIR" --include='*.swift' 2>/dev/null)" && [ -n "$hits" ]; then
  echo "lint-stokd-work-dock-independence: forbidden references under Sources/Stokd:" >&2
  echo "$hits" >&2
  exit 1
fi

echo "lint-stokd-work-dock-independence: ok"
