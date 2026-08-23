#!/usr/bin/env bash
# install-gdock-build.sh — install this repo's scripts/gdock-run as the host launcher.
#
# scripts/gdock-run is the source of truth for gdock-build. The host copy at
# ~/.local/bin/gdock-build is generated; never hand-edit it. Re-run this script
# after changing scripts/gdock-run.
#
# Idempotent: a second run with no source change makes no filesystem writes.
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
SOURCE="$REPO_ROOT/scripts/gdock-run"
DEST_DIR="${GDOCK_BIN_DIR:-$HOME/.local/bin}"
DEST="$DEST_DIR/gdock-build"
SHIM="$DEST_DIR/gdock-run"

usage() {
  cat <<'USAGE'
install-gdock-build.sh — install scripts/gdock-run to ~/.local/bin/gdock-build

  install-gdock-build.sh           Install (no-op when already current).
  install-gdock-build.sh --check   Report whether the host copy is current; do not write.
  install-gdock-build.sh --help

Environment:
  GDOCK_BIN_DIR   Destination directory (default: $HOME/.local/bin).
USAGE
}

CHECK_ONLY=0
while [[ $# -gt 0 ]]; do
  case "$1" in
    -h|--help) usage; exit 0 ;;
    --check) CHECK_ONLY=1; shift ;;
    *) echo "install-gdock-build.sh: unknown argument: $1" >&2; usage >&2; exit 2 ;;
  esac
done

if [[ ! -f "$SOURCE" ]]; then
  echo "install-gdock-build.sh: missing source: $SOURCE" >&2
  exit 1
fi
if ! bash -n "$SOURCE"; then
  echo "install-gdock-build.sh: refusing to install a script that fails bash -n" >&2
  exit 1
fi

if [[ -f "$DEST" ]] && cmp -s "$SOURCE" "$DEST"; then
  echo "gdock-build is already current: $DEST"
  [[ -x "$DEST" ]] || chmod 755 "$DEST"
  exit 0
fi

if [[ "$CHECK_ONLY" -eq 1 ]]; then
  echo "gdock-build is STALE: $DEST" >&2
  echo "run: scripts/install-gdock-build.sh" >&2
  exit 1
fi

mkdir -p "$DEST_DIR"
if [[ -f "$DEST" ]]; then
  backup="$DEST.bak.$(date -u +%Y%m%d%H%M%S)"
  cp -p "$DEST" "$backup"
  echo "previous host copy saved: $backup"
fi

# Staged rename so a concurrent gdock-build never reads a half-written script.
staging="$DEST.install-$$"
cp "$SOURCE" "$staging"
chmod 755 "$staging"
mv "$staging" "$DEST"
echo "installed: $DEST"

# Compatibility shim: gdock-run resolves to the same launcher.
if [[ ! -e "$SHIM" ]] || ! grep -q 'gdock-build' "$SHIM" 2>/dev/null; then
  cat > "$SHIM" <<'SHIMBODY'
#!/usr/bin/env bash
# Compatibility shim: gdock-run → gdock-build (same CLI).
exec "$(dirname "$0")/gdock-build" "$@"
SHIMBODY
  chmod 755 "$SHIM"
  echo "installed shim: $SHIM"
fi

case ":$PATH:" in
  *":$DEST_DIR:"*) ;;
  *) echo "note: $DEST_DIR is not on your PATH" >&2 ;;
esac
