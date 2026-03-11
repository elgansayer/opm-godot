#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd -- "$SCRIPT_DIR/.." && pwd)"
PROJECT_DIR="$REPO_ROOT/project"
WEB_OUTPUT_DEFAULT="$REPO_ROOT/web/mohaa.html"

PLATFORM=""
VARIANT="debug"
PRESET_OVERRIDE=""
OUTPUT_OVERRIDE=""

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
        --preset)
            PRESET_OVERRIDE="$2"
            shift 2
            ;;
        --output)
            OUTPUT_OVERRIDE="$2"
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

if ! command -v godot >/dev/null 2>&1; then
    echo "ERROR: godot not found in PATH" >&2
    exit 1
fi

export_cmd="--export-debug"
if [[ "$VARIANT" == "release" ]]; then
    export_cmd="--export-release"
fi

preset=""
output=""
case "$PLATFORM" in
    web)
        preset="Web"
        output="$WEB_OUTPUT_DEFAULT"
        ;;
    linux)
        preset="Linux"
        output="$PROJECT_DIR/bin/openmohaa.x86_64"
        ;;
    windows)
        preset="Windows Desktop"
        output="$PROJECT_DIR/bin/openmohaa.exe"
        ;;
    macos)
        preset="macOS"
        output="$PROJECT_DIR/bin/openmohaa_macos.zip"
        ;;
    android)
        preset="Android"
        output="$PROJECT_DIR/bin/openmohaa.apk"
        ;;
    ios)
        preset="iOS"
        output="$PROJECT_DIR/bin/openmohaa_ios"
        ;;
    *)
        echo "ERROR: unsupported platform '$PLATFORM'" >&2
        exit 1
        ;;
esac

if [[ -n "$PRESET_OVERRIDE" ]]; then
    preset="$PRESET_OVERRIDE"
fi
if [[ -n "$OUTPUT_OVERRIDE" ]]; then
    output="$OUTPUT_OVERRIDE"
fi

mkdir -p "$(dirname -- "$output")"

PRESETS_FILE="$PROJECT_DIR/export_presets.cfg"
if [[ -f "$PRESETS_FILE" ]]; then
    if ! grep -q "^name=\"$preset\"" "$PRESETS_FILE"; then
        echo "ERROR: Godot export preset '$preset' is not defined in $PRESETS_FILE" >&2
        exit 1
    fi
fi

case "$PLATFORM" in
    web)
        [[ -f "$PROJECT_DIR/bin/libopenmohaa.wasm" ]] || {
            echo "ERROR: Missing web extension artefact: $PROJECT_DIR/bin/libopenmohaa.wasm" >&2
            echo "Run './build.sh web' (or web cmake opm-engine) before export." >&2
            exit 1
        }
        ;;
    linux)
        [[ -f "$PROJECT_DIR/bin/libopenmohaa.so" || -f "$PROJECT_DIR/bin/openmohaa.so" ]] || {
            echo "ERROR: Missing Linux extension artefact in $PROJECT_DIR/bin" >&2
            echo "Run './build.sh linux' before export." >&2
            exit 1
        }
        ;;
    windows)
        [[ -f "$PROJECT_DIR/bin/libopenmohaa.dll" || -f "$PROJECT_DIR/bin/openmohaa.dll" ]] || {
            echo "ERROR: Missing Windows extension artefact in $PROJECT_DIR/bin" >&2
            echo "Run './build.sh windows' before export." >&2
            exit 1
        }
        ;;
    macos)
        [[ -f "$PROJECT_DIR/bin/libopenmohaa.dylib" || -f "$PROJECT_DIR/bin/openmohaa.dylib" ]] || {
            echo "ERROR: Missing macOS extension artefact in $PROJECT_DIR/bin" >&2
            echo "Run './build.sh macos' before export." >&2
            exit 1
        }
        ;;
esac

echo "Godot export"
echo "  platform: $PLATFORM"
echo "  preset:   $preset"
echo "  variant:  $VARIANT"
echo "  output:   $output"

LOG_FILE="$(mktemp -t opm-godot-export.XXXXXX.log)"
trap 'rm -f "$LOG_FILE"' EXIT

if godot --headless --path "$PROJECT_DIR" "$export_cmd" "$preset" "$output" >"$LOG_FILE" 2>&1; then
    # Godot scans GDExtensions during export and can emit known non-fatal
    # preload warnings when host-side runtime libs are not present.
    if [[ "$PLATFORM" == "web" ]]; then
        grep -E -v "Condition \"!FileAccess::exists\(path\)\" is true|at: open_dynamic_library \(drivers/unix/os_unix.cpp:1061\)|GDExtension dynamic library not found: 'res://openmohaa.gdextension'|Error loading extension: 'res://openmohaa.gdextension'|at: open_library \(core/extension/gdextension.cpp:740\)|at: load_extensions \(core/extension/gdextension_manager.cpp:329\)" "$LOG_FILE" || true
    else
        cat "$LOG_FILE"
    fi
else
    cat "$LOG_FILE" >&2
    exit 1
fi

echo "Export complete: $output"
