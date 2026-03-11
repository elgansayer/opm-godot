#!/usr/bin/env bash
# =============================================================================
# build.sh — Single entry point for all build/export/package/test operations.
#
# Output layout:
#   project/bin/                GDExtension staging (libs + companions for dev)
#   dist/<platform>/<variant>/  Final distributable package per platform
#
# Primary workflows:
#   ./build.sh build   --platform linux     Compile engine → project/bin/
#   ./build.sh package --platform linux     Compile + export + archive → dist/
#
# Usage: ./build.sh <target> [flags]
# =============================================================================
set -euo pipefail

REPO="$(cd -- "$(dirname -- "$0")" && pwd)"
DIST_DIR="$REPO/dist"

ensure_cmd() {
    if ! command -v "$1" >/dev/null 2>&1; then
        echo "ERROR: required command not found: $1" >&2
        exit 1
    fi
}

full_clean() {
    echo "Cleaning all build artefacts..."
    rm -rf "$REPO/openmohaa/bin" "$REPO/openmohaa/build" "$REPO/openmohaa/.sconsign.dblite"
    rm -rf "$REPO/project/bin"
    rm -rf "$REPO/dist"
    rm -rf "$REPO/build-cmake"
    echo "Clean done."
}

usage() {
    cat <<'EOF'
Usage: ./build.sh <target> [flags]

Primary:
  build          Compile engine libs → project/bin/ (for development)
  package        Compile + Godot export + archive → dist/<plat>/<var>/

Web:
  web-full       Full web pipeline (engine + export + JS patches)
  web-docker     Build self-contained web Docker image

Deployment:
  serve          Start local Docker web stack from dist/web/<var>/
  deploy         Full release pipeline (web + Docker + git push)

Validation:
  test           Headless smoke test
  test-all       Full test suite
  clean          Remove all build artefacts and dist/

Flags:
  --platform <name>    (linux|windows|macos|web|android|ios)
  --release            Release variant (default: debug)
  --asset-path <path>  Game assets path (web serve/export)
  --arch <arch>        Architecture hint (macOS cross builds)
  --serve              After web-full: also start Docker stack

Examples:
  ./build.sh build --platform linux
  ./build.sh build --platform windows
  ./build.sh package --platform linux
  ./build.sh package --platform windows --release
  ./build.sh web-full --release --serve --asset-path ~/.local/share/openmohaa
  ./build.sh clean
EOF
}

[[ $# -eq 0 ]] && { usage; exit 1; }

TARGET="$1"; shift

VARIANT="debug"
PLATFORM=""
ASSET_PATH_OVERRIDE=""
ARCH_OVERRIDE=""
WEB_SERVE=0
PASSTHROUGH_ARGS=()

while [[ $# -gt 0 ]]; do
    case "$1" in
        --release)    VARIANT="release"; shift ;;
        --debug)      VARIANT="debug"; shift ;;
        --platform)   [[ $# -lt 2 ]] && { echo "ERROR: --platform needs a value" >&2; exit 1; }
                      PLATFORM="$2"; shift 2 ;;
        --asset-path) [[ $# -lt 2 ]] && { echo "ERROR: --asset-path needs a path" >&2; exit 1; }
                      ASSET_PATH_OVERRIDE="$2"; shift 2 ;;
        --arch)       [[ $# -lt 2 ]] && { echo "ERROR: --arch needs a value" >&2; exit 1; }
                      ARCH_OVERRIDE="$2"; shift 2 ;;
        --serve)      WEB_SERVE=1; shift ;;
        *)            PASSTHROUGH_ARGS+=("$1"); shift ;;
    esac
done

require_platform() {
    [[ -n "$PLATFORM" ]] || { echo "ERROR: --platform is required for '$TARGET'" >&2; exit 1; }
}

# Resolve SCons target name from variant
scons_target() {
    if [[ "$VARIANT" == "release" ]]; then
        echo "target=template_release"
    else
        echo "target=template_debug"
    fi
}

# Build desktop engine args for build-desktop.sh
desktop_scons_args() {
    local args=()
    args+=("$(scons_target)")
    [[ -n "$ARCH_OVERRIDE" ]] && args+=("arch=$ARCH_OVERRIDE")
    for a in "${PASSTHROUGH_ARGS[@]+"${PASSTHROUGH_ARGS[@]}"}"; do
        args+=("$a")
    done
    echo "${args[@]}"
}

case "$TARGET" in
    clean)
        full_clean
        ;;

    build)
        # Compile engine → project/bin/ (development workflow).
        require_platform
        case "$PLATFORM" in
            linux|windows|macos)
                "$REPO/scripts/build-desktop.sh" "$PLATFORM" $(desktop_scons_args)
                ;;
            web)
                WEB_ARGS=("--build-only")
                [[ "$VARIANT" == "release" ]] && WEB_ARGS+=("--release") || WEB_ARGS+=("--debug")
                "$REPO/scripts/build-web.sh" "${WEB_ARGS[@]}"
                ;;
            android)
                cd "$REPO/openmohaa"
                scons platform=android $(scons_target) -j"$(nproc 2>/dev/null || echo 4)" \
                    dev_build=yes disable_exceptions=no \
                    ${ARCH_OVERRIDE:+arch=$ARCH_OVERRIDE} \
                    "${PASSTHROUGH_ARGS[@]+"${PASSTHROUGH_ARGS[@]}"}"
                mkdir -p "$REPO/project/bin"
                cp -f bin/libopenmohaa*.so "$REPO/project/bin/" 2>/dev/null || true
                cp -f bin/libcgame*.so "$REPO/project/bin/" 2>/dev/null || true
                ;;
            *)
                echo "ERROR: unsupported platform for build: $PLATFORM" >&2; exit 1
                ;;
        esac
        echo ""
        echo "Build complete: project/bin/"
        ls -lh "$REPO/project/bin/" 2>/dev/null || true
        ;;

    package)
        # Compile engine + Godot export + companion staging + tar.gz archive.
        require_platform
        "$REPO/scripts/package-build.sh" --platform "$PLATFORM" --variant "$VARIANT" \
            ${ARCH_OVERRIDE:+--arch "$ARCH_OVERRIDE"} \
            ${ASSET_PATH_OVERRIDE:+--asset-path "$ASSET_PATH_OVERRIDE"}
        ;;

    web-full)
        WEB_ARGS=()
        [[ "$VARIANT" == "release" ]] && WEB_ARGS+=("--release") || WEB_ARGS+=("--debug")
        [[ -n "$ASSET_PATH_OVERRIDE" ]] && WEB_ARGS+=("--asset-path" "$ASSET_PATH_OVERRIDE")
        [[ "$WEB_SERVE" -eq 1 ]] && WEB_ARGS+=("--serve")
        "$REPO/scripts/build-web.sh" "${WEB_ARGS[@]}"
        ;;

    web-docker)
        "$REPO/scripts/build-web-docker.sh" --variant "$VARIANT"
        ;;

    serve)
        [[ -n "$ASSET_PATH_OVERRIDE" ]] || { echo "ERROR: --asset-path is required for 'serve'" >&2; exit 1; }
        WEB_DIST="$DIST_DIR/web/$VARIANT"
        [[ -f "$WEB_DIST/mohaa.html" ]] || { echo "ERROR: No web build at $WEB_DIST/ — run 'web-full' first" >&2; exit 1; }
        cd "$REPO"
        ASSET_PATH="$ASSET_PATH_OVERRIDE" WEB_DIST="$WEB_DIST" CDN_URL="${CDN_URL:-/assets}" \
            docker compose -f docker/docker-compose.yml up -d --force-recreate
        echo "Stack running at http://localhost:8086"
        ;;

    deploy)
        exec "$REPO/scripts/deploy.sh" "${PASSTHROUGH_ARGS[@]}"
        ;;

    test)
        exec "$REPO/scripts/test.sh" "${PASSTHROUGH_ARGS[@]}"
        ;;

    test-all)
        exec "$REPO/scripts/test-all.sh" "${PASSTHROUGH_ARGS[@]}"
        ;;

    -h|--help)
        usage; exit 0
        ;;

    *)
        echo "Unknown target: $TARGET" >&2
        usage; exit 1
        ;;
esac
