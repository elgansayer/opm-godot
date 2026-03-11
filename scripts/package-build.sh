#!/usr/bin/env bash
# package-build.sh — Build engine, run Godot export, stage companions,
# and create a distributable .tar.gz archive.
#
# Output:  dist/<platform>/<variant>/          — exported + companion files
#          dist/packages/opm-godot-<plat>-<var>-<stamp>.tar.gz
#
# Usage:
#   ./scripts/package-build.sh --platform linux [--variant release] [--arch x86_64]
set -euo pipefail

SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd -- "$SCRIPT_DIR/.." && pwd)"

PLATFORM=""
VARIANT="debug"
ARCH=""
ASSET_PATH=""

while [[ $# -gt 0 ]]; do
    case "$1" in
        --platform)    PLATFORM="$2";    shift 2 ;;
        --variant)     VARIANT="$2";     shift 2 ;;
        --arch)        ARCH="$2";        shift 2 ;;
        --asset-path)  ASSET_PATH="$2";  shift 2 ;;
        *) echo "ERROR: unknown argument: $1" >&2; exit 1 ;;
    esac
done

[[ -n "$PLATFORM" ]] || { echo "ERROR: --platform is required" >&2; exit 1; }

SCONS_TARGET="template_debug"
[[ "$VARIANT" == "release" ]] && SCONS_TARGET="template_release"

# ── Step 1: Build engine → project/bin/ ───────────────────────────────────
echo "=== Step 1/3: Build engine ($PLATFORM/$VARIANT) ==="

case "$PLATFORM" in
    linux|windows|macos)
        BUILD_ARGS=("$PLATFORM" "target=$SCONS_TARGET")
        [[ -n "$ARCH" ]] && BUILD_ARGS+=("arch=$ARCH")
        "$SCRIPT_DIR/build-desktop.sh" "${BUILD_ARGS[@]}"
        ;;
    web)
        WEB_ARGS=("--build-only")
        [[ "$VARIANT" == "release" ]] && WEB_ARGS+=("--release") || WEB_ARGS+=("--debug")
        "$SCRIPT_DIR/build-web.sh" "${WEB_ARGS[@]}"
        # Web export is handled by build-web.sh full pipeline; fall through
        # to run the full web pipeline if not build-only.
        ;;
    android)
        cd "$REPO_ROOT/openmohaa"
        JOBS="$(nproc 2>/dev/null || echo 4)"
        scons platform=android target="$SCONS_TARGET" -j"$JOBS" \
            dev_build=yes disable_exceptions=no \
            ${ARCH:+arch=$ARCH}
        mkdir -p "$REPO_ROOT/project/bin"
        cp -f bin/libopenmohaa*.so "$REPO_ROOT/project/bin/" 2>/dev/null || true
        cp -f bin/libcgame*.so "$REPO_ROOT/project/bin/" 2>/dev/null || true
        cp -f bin/cgame*.so "$REPO_ROOT/project/bin/" 2>/dev/null || true
        cd "$REPO_ROOT"
        ;;
    *)
        echo "ERROR: unsupported platform: $PLATFORM" >&2; exit 1
        ;;
esac

# ── Step 2: Godot export + companion staging ──────────────────────────────
echo ""
echo "=== Step 2/3: Godot export + companion staging ==="

if [[ "$PLATFORM" == "web" ]]; then
    # Web uses its own full pipeline (build-web.sh handles export + JS patches)
    WEB_FULL_ARGS=()
    [[ "$VARIANT" == "release" ]] && WEB_FULL_ARGS+=("--release") || WEB_FULL_ARGS+=("--debug")
    [[ -n "$ASSET_PATH" ]] && WEB_FULL_ARGS+=("--asset-path" "$ASSET_PATH")
    "$SCRIPT_DIR/build-web.sh" "${WEB_FULL_ARGS[@]}"
else
    "$SCRIPT_DIR/export-godot.sh" --platform "$PLATFORM" --variant "$VARIANT"
fi

# ── Step 3: Create archive ────────────────────────────────────────────────
DIST_DIR="$REPO_ROOT/dist/$PLATFORM/$VARIANT"
[[ -d "$DIST_DIR" ]] || {
    echo "ERROR: dist directory not found after export: $DIST_DIR" >&2; exit 1
}

echo ""
echo "=== Step 3/3: Create archive ==="

STAMP="$(date -u +%Y%m%d-%H%M%S)"
PKG_NAME="opm-godot-${PLATFORM}-${VARIANT}-${STAMP}.tar.gz"
PKG_DIR="$REPO_ROOT/dist/packages"
mkdir -p "$PKG_DIR"
PKG_PATH="$PKG_DIR/$PKG_NAME"

tar -czf "$PKG_PATH" -C "$DIST_DIR" .

echo ""
echo "Package created: $PKG_PATH"
echo "  Contents from: $DIST_DIR"
echo ""
echo "Distribution contents:"
ls -lh "$DIST_DIR/"
