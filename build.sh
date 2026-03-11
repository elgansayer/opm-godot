#!/usr/bin/env bash
# =============================================================================
# build.sh — Single entry point for all build/export/package/test operations.
#
# Output layout:
#   project/bin/              GDExtension staging (libs only, for Godot export)
#   dist/<platform>/<variant>/  Final packaged output per platform & variant
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

run_cmake_target() {
    local preset="$1" target="$2"; shift 2
    ensure_cmd cmake
    cmake --preset "$preset" "$@"
    cmake --build "$REPO/build-cmake/$preset" --target "$target"
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

Engine/Export Targets:
  engine         Build native engine libs for --platform
  export         Godot CLI export for --platform
  build          Engine + export in one step (output: dist/<plat>/<var>/)

Web Targets:
  web-full       Full web pipeline (engine + export + JS patches)
  web-docker     Build self-contained web Docker image

Packaging:
  package        Create .tar.gz archive from dist/<plat>/<var>/
  sign-android   Android APK signing wrapper
  sign-ios       iOS provisioning/archive wrapper

Deployment:
  serve          Start local Docker web stack from dist/web/<var>/
  deploy         Full release pipeline (web + Docker + git push)

Validation:
  matrix         Run full CMake build/export matrix
  test           Headless smoke test
  test-all       Full test suite
  clean          Remove all build artefacts and dist/

Flags:
  --platform <name>    (linux|windows|macos|web|android|ios)
  --release            Release variant (default: debug)
  --asset-path <path>  Game assets path (web serve/export)
  --minimal            Web: skip custom JS runtime patching
  --arch <arch>        Architecture hint (macOS cross builds)
  --serve              After web-full: also start Docker stack

Examples:
  ./build.sh engine --platform linux
  ./build.sh build --platform linux --release
  ./build.sh web-full --release --serve --asset-path ~/.local/share/openmohaa
  ./build.sh serve --release --asset-path ~/.local/share/openmohaa
  ./build.sh package --platform linux --release
  ./build.sh matrix --debug-only
  ./build.sh clean
EOF
}

[[ $# -eq 0 ]] && { usage; exit 1; }

TARGET="$1"; shift

VARIANT="debug"
PLATFORM=""
ASSET_PATH_OVERRIDE=""
ARCH_OVERRIDE=""
WEB_MINIMAL=0
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
        --minimal)    WEB_MINIMAL=1; shift ;;
        --arch)       [[ $# -lt 2 ]] && { echo "ERROR: --arch needs a value" >&2; exit 1; }
                      ARCH_OVERRIDE="$2"; shift 2 ;;
        --serve)      WEB_SERVE=1; shift ;;
        *)            PASSTHROUGH_ARGS+=("$1"); shift ;;
    esac
done

cmake_overrides=()
cmake_overrides+=("-DOPM_BUILD_VARIANT=$VARIANT")
[[ -n "$ASSET_PATH_OVERRIDE" ]] && cmake_overrides+=("-DOPM_ASSET_PATH=$ASSET_PATH_OVERRIDE")
[[ -n "$ARCH_OVERRIDE" ]] && cmake_overrides+=("-DOPM_ARCH=$ARCH_OVERRIDE")
[[ "$WEB_MINIMAL" -eq 1 ]] && cmake_overrides+=("-DOPM_WEB_MINIMAL=ON")

require_platform() {
    [[ -n "$PLATFORM" ]] || { echo "ERROR: --platform is required for '$TARGET'" >&2; exit 1; }
}

case "$TARGET" in
    clean)
        full_clean
        ;;

    engine)
        require_platform
        run_cmake_target "$PLATFORM-$VARIANT" "opm-engine" "${cmake_overrides[@]}"
        ;;

    export)
        require_platform
        run_cmake_target "$PLATFORM-$VARIANT" "opm-export" "${cmake_overrides[@]}"
        ;;

    build)
        require_platform
        run_cmake_target "$PLATFORM-$VARIANT" "opm-engine" "${cmake_overrides[@]}"
        run_cmake_target "$PLATFORM-$VARIANT" "opm-export" "${cmake_overrides[@]}"
        echo ""
        echo "Build + export complete: dist/$PLATFORM/$VARIANT/"
        ;;

    web-full)
        WEB_ARGS=()
        [[ "$VARIANT" == "release" ]] && WEB_ARGS+=("--release") || WEB_ARGS+=("--debug")
        [[ "$WEB_MINIMAL" -eq 1 ]] && WEB_ARGS+=("--minimal")
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
            docker compose up -d --force-recreate
        echo "Stack running at http://localhost:8086"
        ;;

    package)
        require_platform
        "$REPO/scripts/package-build.sh" --platform "$PLATFORM" --variant "$VARIANT"
        ;;

    sign-android)
        run_cmake_target "android-$VARIANT" "opm-sign-android" "${cmake_overrides[@]}"
        ;;

    sign-ios)
        run_cmake_target "ios-$VARIANT" "opm-sign-ios" "${cmake_overrides[@]}"
        ;;

    matrix)
        exec "$REPO/scripts/test-build-matrix.sh" "${PASSTHROUGH_ARGS[@]}"
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
