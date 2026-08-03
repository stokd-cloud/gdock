#!/usr/bin/env bash
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"
matches="$(grep -rn 'manaflow-ai/cmux/releases' scripts tests .github/workflows Resources/Info.plist   --exclude='test_ci_no_upstream_appcast.sh' 2>/dev/null || true)"
if [[ -n "$matches" ]]; then
  echo "FAIL: upstream appcast references remain:"
  echo "$matches"
  exit 1
fi
echo "OK: no manaflow-ai/cmux/releases references in release tooling"
