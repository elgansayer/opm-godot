#!/usr/bin/env bash
# package-build.sh — Package dist/<platform>/<variant>/ into a .tar.gz archive.
set -euo pipefail

SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd -- "$SCRIPT_DIR/.." && pwd)"
PLATFORM=""
VARIANT="debug"

while [[ $# -gt 0 ]]; do
    case "$1" in
        --platform) PLATFORM="$2"; shift 2 ;;
        --variant)  VARIANT="$2";  shift 2 ;;
        *) echo "ERROR: unknown argument: $1" >&2; exit 1 ;;
    esac
done

[[ -n "$PLATFORM" ]] || { echo "ERROR: --platform is required" >&2; exit 1; }

DIST_DIR="$REPO_ROOT/dist/$PLATFORM/$VARIANT"
[[ -d "$DIST_DIR" ]] || {
    echo "ERROR: dist directory not found: $DIST_DIR" >&2
    echo "Run the build+export pipeline first." >&2
    exit 1
}

STAMP="$(date -u +%Y%m%d-%H%M%S)"
PKG_NAME="opm-godot-${PLATFORM}-${VARIANT}-${STAMP}.tar.gz"
PKG_DIR="$REPO_ROOT/dist/packages"
mkdir -p "$PKG_DIR"
PKG_PATH="$PKG_DIR/$PKG_NAME"

# Archive the dist/<platform>/<variant>/ directory contents.
tar -czf "$PKG_PATH" -C "$DIST_DIR" .

echo "Package created: $PKG_PATH"
echo "  Contents from: $DIST_DIR"
