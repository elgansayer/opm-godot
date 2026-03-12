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

run_skip() {
    local label="$1"
    local reason="$2"
    echo ""
    echo "==> $label"
    echo "SKIP: $label ($reason)"
    RESULTS+=("SKIP | $label | $reason")
}

has_export_preset() {
    local preset_name="$1"
    local presets_file="$REPO_ROOT/project/export_presets.cfg"
    [[ -f "$presets_file" ]] && grep -q "^name=\"${preset_name}\"" "$presets_file"
}

export_preset_for_platform() {
    case "$1" in
        web) echo "Web" ;;
        linux) echo "Linux" ;;
        windows) echo "Windows Desktop" ;;
        macos) echo "macOS" ;;
        android) echo "Android" ;;
        ios) echo "iOS" ;;
        *) echo "" ;;
    esac
}

RESULTS=()
FAIL_COUNT=0

for variant in "${VARIANTS[@]}"; do
    for platform in linux windows macos web android ios; do
        preset="${platform}-${variant}"
        engine_skipped=0
        run_step "configure ${preset}" "cmake --preset ${preset} -DMOHAA_BUILD_VARIANT=${variant}"

        # Engine target is wired for linux/windows/macos/web; android/ios are placeholder no-ops for now.
        if [[ "$platform" == "macos" && "$(uname -s)" != "Darwin" && -z "${OSXCROSS_ROOT:-}" ]]; then
            run_skip "engine ${preset}" "OSXCROSS_ROOT not set on non-macOS host"
            engine_skipped=1
        else
            run_step "engine ${preset}" "cmake --build build-cmake/${preset} --target mohaa-engine"
        fi

        # Export target is always wired.
        export_preset_name="$(export_preset_for_platform "$platform")"
        if [[ "$engine_skipped" -eq 1 ]]; then
            run_skip "export ${preset}" "engine step skipped"
        elif [[ -z "$export_preset_name" ]] || ! has_export_preset "$export_preset_name"; then
            run_skip "export ${preset}" "no '$export_preset_name' preset in project/export_presets.cfg"
        else
            run_step "export ${preset}" "cmake --build build-cmake/${preset} --target mohaa-export"
        fi

        if [[ "$platform" == "web" && "$RUN_WEB_FULL" -eq 1 ]]; then
            run_step "web full export ${preset}" "cmake --build build-cmake/${preset} --target mohaa-web-export"
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
