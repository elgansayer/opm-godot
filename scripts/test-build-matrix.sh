#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd -- "$SCRIPT_DIR/.." && pwd)"

if ! command -v cmake >/dev/null 2>&1; then
    echo "ERROR: cmake not found in PATH" >&2
    exit 1
fi

VARIANTS=(debug release)
RUN_WEB_FULL=0

while [[ $# -gt 0 ]]; do
    case "$1" in
        --debug-only)
            VARIANTS=(debug)
            shift
            ;;
        --release-only)
            VARIANTS=(release)
            shift
            ;;
        --with-web-full)
            RUN_WEB_FULL=1
            shift
            ;;
        *)
            echo "ERROR: unknown argument: $1" >&2
            echo "Usage: scripts/test-build-matrix.sh [--debug-only|--release-only] [--with-web-full]" >&2
            exit 1
            ;;
    esac
done

run_step() {
    local label="$1"
    local cmd="$2"

    echo ""
    echo "==> $label"
    if (cd "$REPO_ROOT" && eval "$cmd"); then
        echo "PASS: $label"
        RESULTS+=("PASS | $label")
    else
        echo "FAIL: $label"
        RESULTS+=("FAIL | $label")
        FAIL_COUNT=$((FAIL_COUNT + 1))
    fi
}

RESULTS=()
FAIL_COUNT=0

for variant in "${VARIANTS[@]}"; do
    for platform in linux windows macos web android ios; do
        preset="${platform}-${variant}"
        run_step "configure ${preset}" "cmake --preset ${preset} -DOPM_BUILD_VARIANT=${variant}"

        # Engine target is wired for linux/windows/macos/web; android/ios are placeholder no-ops for now.
        run_step "engine ${preset}" "cmake --build build-cmake/${preset} --target opm-engine"

        # Export target is always wired.
        run_step "export ${preset}" "cmake --build build-cmake/${preset} --target opm-export"

        if [[ "$platform" == "web" && "$RUN_WEB_FULL" -eq 1 ]]; then
            run_step "web full export ${preset}" "cmake --build build-cmake/${preset} --target opm-web-export"
        fi
    done
done

echo ""
echo "==== Build Matrix Summary ===="
printf '%s\n' "${RESULTS[@]}"
echo "Failures: $FAIL_COUNT"

if [[ "$FAIL_COUNT" -ne 0 ]]; then
    exit 1
fi
