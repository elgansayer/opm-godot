#!/usr/bin/env bash
set -euo pipefail

REPO="$(cd -- "$(dirname -- "$0")" && pwd)"

ensure_cmd() {
    local cmd="$1"
    if ! command -v "$cmd" >/dev/null 2>&1; then
        echo "ERROR: required command not found: $cmd" >&2
        exit 1
    fi
}

run_cmake_target() {
    local preset="$1"
    local target="$2"
    shift 2

    ensure_cmd cmake
    cmake --preset "$preset" "$@"
    cmake --build "$REPO/build-cmake/$preset" --target "$target"
}

full_clean() {
    echo "Cleaning all build artefacts..."
    rm -rf "$REPO/openmohaa/bin" "$REPO/openmohaa/build" "$REPO/openmohaa/.sconsign.dblite"
    rm -f  "$REPO/project/bin/libopenmohaa.so" "$REPO/project/bin/libopenmohaa.dll" "$REPO/project/bin/libopenmohaa.dylib"
    rm -f  "$REPO/project/bin/cgame.so" "$REPO/project/bin/cgame.dll" "$REPO/project/bin/cgame.dylib"
    echo "Clean done."
}

function usage() {
    echo "Usage: ./build.sh <target> [args...]"
    echo ""
    echo "CMake-Orchestrated Targets:"
    echo "  linux       Build engine/native artefacts for Linux"
    echo "  windows     Build engine/native artefacts for Windows"
    echo "  macos       Build engine/native artefacts for macOS"
    echo "  web         Build web engine wasm artefacts only"
    echo "  web-export  Full web pipeline (engine + export + runtime integration)"
    echo "  export      Run Godot CLI export only (requires --platform <name>)"
    echo "  package     Create distributable archive from current outputs"
    echo "  sign-android  Run Android signing wrapper"
    echo "  sign-ios      Run iOS signing wrapper"
    echo "  matrix      Run full CMake build/export matrix validation"
    echo "  all         Build linux/windows/macos engine targets"
    echo ""
    echo "Deploy/Test Targets:"
    echo "  deploy    Deploy Web build + push to GitHub/Portainer (formerly 'release')"
    echo "  clean     Remove all build artefacts and deployed binaries"
    echo "  test      Run a basic headless smoke test"
    echo "  test-all  Build, deploy, run ALL tests (smoke + viewmodel + resolution)"
    echo ""
    echo "Flags:"
    echo "  --release               Use release variant (default: debug)"
    echo "  --asset-path <path>     Forwarded to web CMake preset as OPM_ASSET_PATH"
    echo "  --minimal               For web-export: skip custom runtime patching"
    echo "  --arch <arch>           Forwarded as OPM_ARCH (useful for macOS cross builds)"
    echo "  --platform <name>       Required for 'export' target"
    echo ""
    echo "Example:"
    echo "  ./build.sh linux"
    echo "  ./build.sh web --release"
    echo "  ./build.sh export --platform android --release"
}

if [[ $# -eq 0 ]]; then
    usage
    exit 1
fi

TARGET="$1"
shift

VARIANT="debug"
ASSET_PATH_OVERRIDE=""
ARCH_OVERRIDE=""
EXPORT_PLATFORM=""
PASSTHROUGH_ARGS=()
WEB_MINIMAL=0

while [[ $# -gt 0 ]]; do
    case "$1" in
        --release)
            VARIANT="release"
            shift
            ;;
        --debug)
            VARIANT="debug"
            shift
            ;;
        --asset-path)
            if [[ $# -lt 2 ]]; then
                echo "ERROR: --asset-path requires a path" >&2
                exit 1
            fi
            ASSET_PATH_OVERRIDE="$2"
            shift 2
            ;;
        --minimal)
            WEB_MINIMAL=1
            shift
            ;;
        --arch)
            if [[ $# -lt 2 ]]; then
                echo "ERROR: --arch requires a value" >&2
                exit 1
            fi
            ARCH_OVERRIDE="$2"
            shift 2
            ;;
        --platform)
            if [[ $# -lt 2 ]]; then
                echo "ERROR: --platform requires a value" >&2
                exit 1
            fi
            EXPORT_PLATFORM="$2"
            shift 2
            ;;
        *)
            PASSTHROUGH_ARGS+=("$1")
            shift
            ;;
    esac
done

cmake_overrides=()
cmake_overrides+=("-DOPM_BUILD_VARIANT=$VARIANT")
if [[ -n "$ASSET_PATH_OVERRIDE" ]]; then
    cmake_overrides+=("-DOPM_ASSET_PATH=$ASSET_PATH_OVERRIDE")
fi
if [[ -n "$ARCH_OVERRIDE" ]]; then
    cmake_overrides+=("-DOPM_ARCH=$ARCH_OVERRIDE")
fi
if [[ "$WEB_MINIMAL" -eq 1 ]]; then
    cmake_overrides+=("-DOPM_WEB_MINIMAL=ON")
fi

case "$TARGET" in
    clean)
        full_clean
        ;;
    linux|windows|macos|web)
        full_clean
        run_cmake_target "$TARGET-$VARIANT" "opm-engine" "${cmake_overrides[@]}"
        ;;
    web-export)
        full_clean
        run_cmake_target "web-$VARIANT" "opm-web-export" "${cmake_overrides[@]}"
        ;;
    export)
        if [[ -z "$EXPORT_PLATFORM" ]]; then
            echo "ERROR: export target requires --platform" >&2
            exit 1
        fi
        run_cmake_target "$EXPORT_PLATFORM-$VARIANT" "opm-export" "${cmake_overrides[@]}"
        ;;
    package)
        run_cmake_target "linux-$VARIANT" "opm-package" "${cmake_overrides[@]}"
        ;;
    sign-android)
        run_cmake_target "android-$VARIANT" "opm-sign-android" "${cmake_overrides[@]}"
        ;;
    sign-ios)
        run_cmake_target "ios-$VARIANT" "opm-sign-ios" "${cmake_overrides[@]}"
        ;;
    matrix)
        exec "$(dirname "$0")/scripts/test-build-matrix.sh" "${PASSTHROUGH_ARGS[@]}"
        ;;
    all)
        full_clean
        echo "Building all desktop target platforms..."
        run_cmake_target "linux-$VARIANT" "opm-engine" "${cmake_overrides[@]}"
        run_cmake_target "windows-$VARIANT" "opm-engine" "${cmake_overrides[@]}"
        run_cmake_target "macos-$VARIANT" "opm-engine" "${cmake_overrides[@]}"
        ;;
    deploy)
        exec "$(dirname "$0")/scripts/deploy.sh" "${PASSTHROUGH_ARGS[@]}"
        ;;
    test)
        exec "$(dirname "$0")/scripts/test.sh" "${PASSTHROUGH_ARGS[@]}"
        ;;
    test-all)
        exec "$(dirname "$0")/scripts/test-all.sh" "${PASSTHROUGH_ARGS[@]}"
        ;;
    -h|--help)
        usage
        exit 0
        ;;
    *)
        echo "Unknown target: $TARGET" >&2
        usage
        exit 1
        ;;
esac
