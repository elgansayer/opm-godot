#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd -- "$SCRIPT_DIR/.." && pwd)"
OUT_DIR="$REPO_ROOT/dist"
PLATFORM=""
VARIANT="debug"

while [[ $# -gt 0 ]]; do
    case "$1" in
        --platform)
            PLATFORM="$2"
            shift 2
            ;;
        --variant)
            VARIANT="$2"
            shift 2
            ;;
        *)
            echo "ERROR: unknown argument: $1" >&2
            exit 1
            ;;
    esac
done

if [[ -z "$PLATFORM" ]]; then
    echo "ERROR: --platform is required" >&2
    exit 1
fi

mkdir -p "$OUT_DIR"
STAMP="$(date -u +%Y%m%d-%H%M%S)"
PKG_NAME="opm-godot-${PLATFORM}-${VARIANT}-${STAMP}.tar.gz"
PKG_PATH="$OUT_DIR/$PKG_NAME"

staging_dir="$(mktemp -d)"
trap 'rm -rf "$staging_dir"' EXIT

mkdir -p "$staging_dir/project/bin" "$staging_dir/web" "$staging_dir/scripts"

if [[ -d "$REPO_ROOT/project/bin" ]]; then
    rsync -a --include='*/' --include='*.so' --include='*.dll' --include='*.dylib' --include='*.wasm' --include='*.exe' --exclude='*' \
        "$REPO_ROOT/project/bin/" "$staging_dir/project/bin/" || true
fi

if [[ -d "$REPO_ROOT/web" ]]; then
    rsync -a \
        --include='mohaa.html' \
        --include='mohaa.js' \
        --include='mohaa.wasm' \
        --include='mohaa.pck' \
        --include='mohaa.manifest.json' \
        --include='mohaa.audio.worklet.js' \
        --include='mohaa.audio.position.worklet.js' \
        --exclude='*' \
        "$REPO_ROOT/web/" "$staging_dir/web/" || true
fi

cp -f "$REPO_ROOT/README.md" "$staging_dir/README.md"
cp -f "$REPO_ROOT/scripts/export-godot.sh" "$staging_dir/scripts/export-godot.sh"
cp -f "$REPO_ROOT/scripts/sign-android.sh" "$staging_dir/scripts/sign-android.sh"
cp -f "$REPO_ROOT/scripts/sign-ios.sh" "$staging_dir/scripts/sign-ios.sh"

tar -czf "$PKG_PATH" -C "$staging_dir" .

echo "Package created: $PKG_PATH"
