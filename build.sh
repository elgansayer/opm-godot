#!/usr/bin/env bash
set -euo pipefail

REPO="$(cd -- "$(dirname -- "$0")" && pwd)"

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
    echo "Desktop Targets:"
    echo "  linux     Build Godot GDExtension for Linux"
    echo "  windows   Build Godot GDExtension for Windows"
    echo "  macos     Build Godot GDExtension for macOS"
    echo "  all       Build all desktop platforms"
    echo ""
    echo "Web Targets:"
    echo "  web       Build Godot HTML5 export (pass --release for optimized build)"
    echo "  deploy    Deploy Web build + push to GitHub/Portainer (formerly 'release')"
    echo ""
    echo "Other:"
    echo "  clean     Remove all build artefacts and deployed binaries"
    echo "  test      Run a basic headless smoke test"
    echo "  test-all  Build, deploy, run ALL tests (smoke + viewmodel + resolution)"
    echo ""
    echo "Example:"
    echo "  ./build.sh linux"
    echo "  ./build.sh web --release"
}

if [[ $# -eq 0 ]]; then
    usage
    exit 1
fi

TARGET="$1"
shift

case "$TARGET" in
    clean)
        full_clean
        ;;
    linux|windows|macos)
        full_clean
        exec "$(dirname "$0")/scripts/build-desktop.sh" "$TARGET" "$@"
        ;;
    all)
        full_clean
        echo "Building all desktop target platforms..."
        "$(dirname "$0")/scripts/build-desktop.sh" linux "$@"
        "$(dirname "$0")/scripts/build-desktop.sh" windows "$@"
        "$(dirname "$0")/scripts/build-desktop.sh" macos "$@"
        ;;
    web)
        full_clean
        exec "$(dirname "$0")/scripts/build-web.sh" "$@"
        ;;
    deploy)
        exec "$(dirname "$0")/scripts/deploy.sh" "$@"
        ;;
    test)
        exec "$(dirname "$0")/scripts/test.sh" "$@"
        ;;
    test-all)
        exec "$(dirname "$0")/scripts/test-all.sh" "$@"
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
