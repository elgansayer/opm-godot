#!/usr/bin/env bash
# export-godot.sh — Run Godot CLI export for any platform.
# Output defaults to dist/<platform>/<variant>/ unless --output overrides.
set -euo pipefail

SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd -- "$SCRIPT_DIR/.." && pwd)"
PROJECT_DIR="$REPO_ROOT/project"

PLATFORM=""
VARIANT="debug"
PRESET_OVERRIDE=""
OUTPUT_OVERRIDE=""

while [[ $# -gt 0 ]]; do
    case "$1" in
        --platform) PLATFORM="$2"; shift 2 ;;
        --variant)  VARIANT="$2";  shift 2 ;;
        --preset)   PRESET_OVERRIDE="$2"; shift 2 ;;
        --output)   OUTPUT_OVERRIDE="$2"; shift 2 ;;
        *) echo "ERROR: unknown argument: $1" >&2; exit 1 ;;
    esac
done

[[ -n "$PLATFORM" ]] || { echo "ERROR: --platform is required" >&2; exit 1; }
command -v godot >/dev/null 2>&1 || { echo "ERROR: godot not found in PATH" >&2; exit 1; }

export_cmd="--export-debug"
[[ "$VARIANT" == "release" ]] && export_cmd="--export-release"

# ── Preset and default output path ────────────────────────────────────────
DIST_DIR="$REPO_ROOT/dist/$PLATFORM/$VARIANT"
preset=""
output=""

case "$PLATFORM" in
    web)     preset="Web";              output="$DIST_DIR/mohaa.html" ;;
    linux)   preset="Linux";            output="$DIST_DIR/openmohaa.x86_64" ;;
    windows) preset="Windows Desktop";  output="$DIST_DIR/openmohaa.exe" ;;
    macos)   preset="macOS";            output="$DIST_DIR/openmohaa.app" ;;
    android) preset="Android";          output="$DIST_DIR/openmohaa.apk" ;;
    ios)     preset="iOS";              output="$DIST_DIR/openmohaa.ipa" ;;
    *) echo "ERROR: unsupported platform '$PLATFORM'" >&2; exit 1 ;;
esac

[[ -n "$PRESET_OVERRIDE" ]] && preset="$PRESET_OVERRIDE"
[[ -n "$OUTPUT_OVERRIDE" ]] && output="$OUTPUT_OVERRIDE"
mkdir -p "$(dirname -- "$output")"

# ── Validate preset exists ────────────────────────────────────────────────
PRESETS_FILE="$PROJECT_DIR/export_presets.cfg"
if [[ -f "$PRESETS_FILE" ]]; then
    grep -q "^name=\"$preset\"" "$PRESETS_FILE" || {
        echo "ERROR: Godot export preset '$preset' not defined in $PRESETS_FILE" >&2
        exit 1
    }
fi

# ── Validate engine artefacts ─────────────────────────────────────────────
case "$PLATFORM" in
    web)
        [[ -f "$PROJECT_DIR/bin/libopenmohaa.wasm" ]] || {
            echo "ERROR: Missing web extension: $PROJECT_DIR/bin/libopenmohaa.wasm" >&2
            echo "Run './build.sh build --platform web' before export." >&2; exit 1
        } ;;
    linux)
        [[ -f "$PROJECT_DIR/bin/libopenmohaa.so" || -f "$PROJECT_DIR/bin/openmohaa.so" ]] || {
            echo "ERROR: Missing Linux extension in $PROJECT_DIR/bin" >&2; exit 1
        } ;;
    windows)
        [[ -f "$PROJECT_DIR/bin/libopenmohaa.dll" || -f "$PROJECT_DIR/bin/openmohaa.dll" ]] || {
            echo "ERROR: Missing Windows extension in $PROJECT_DIR/bin" >&2; exit 1
        } ;;
    macos)
        [[ -f "$PROJECT_DIR/bin/libopenmohaa.dylib" || -f "$PROJECT_DIR/bin/openmohaa.dylib" ]] || {
            echo "ERROR: Missing macOS extension in $PROJECT_DIR/bin" >&2; exit 1
        } ;;
    android)
        ls "$PROJECT_DIR/bin"/libopenmohaa*.so >/dev/null 2>&1 || {
            echo "ERROR: Missing Android extension in $PROJECT_DIR/bin" >&2; exit 1
        } ;;
esac

echo "Godot export"
echo "  platform: $PLATFORM"
echo "  preset:   $preset"
echo "  variant:  $VARIANT"
echo "  output:   $output"

LOG_FILE="$(mktemp -t mohaa-godot-export.XXXXXX.log)"
trap 'rm -f "$LOG_FILE"' EXIT

GODOT_ARGS=(--headless --path "$PROJECT_DIR" "$export_cmd" "$preset" "$output")

if godot "${GODOT_ARGS[@]}" >"$LOG_FILE" 2>&1; then
    # Filter known non-fatal GDExtension preload warnings for web exports
    if [[ "$PLATFORM" == "web" ]]; then
        grep -E -v "Condition \"!FileAccess::exists\(path\)\" is true|at: open_dynamic_library|GDExtension dynamic library not found|Error loading extension|at: open_library|at: load_extensions" "$LOG_FILE" || true
    else
        cat "$LOG_FILE"
    fi
else
    cat "$LOG_FILE" >&2
    exit 1
fi

# ── Post-export: stage companion binaries not handled by Godot export ─────
# Godot export only bundles files it knows about (GDExtension .dll/.so,
# project resources). Runtime-loaded libraries (cgame) and MinGW runtime
# DLLs must be copied alongside the exported executable manually.
OUTPUT_DIR="$(dirname -- "$output")"
PROJECT_BIN="$PROJECT_DIR/bin"

stage_companion() {
    local src="$1" dst="$2"
    if [[ -f "$src" ]]; then
        \cp -f "$src" "$dst"
        echo "Staged companion: $(basename "$dst")"
    fi
}

case "$PLATFORM" in
    windows)
        for companion in cgame.dll libgcc_s_seh-1.dll libstdc++-6.dll libwinpthread-1.dll; do
            stage_companion "$PROJECT_BIN/$companion" "$OUTPUT_DIR/$companion"
        done
        ;;
    linux)
        stage_companion "$PROJECT_BIN/cgame.so" "$OUTPUT_DIR/cgame.so"
        ;;
    macos)
        stage_companion "$PROJECT_BIN/cgame.dylib" "$OUTPUT_DIR/cgame.dylib"
        ;;
    android)
        # Android: cgame is an .so loaded via dlopen at runtime
        for f in "$PROJECT_BIN"/libcgame*.so "$PROJECT_BIN"/cgame*.so; do
            [[ -f "$f" ]] && stage_companion "$f" "$OUTPUT_DIR/$(basename "$f")"
        done
        ;;
    # Web: cgame is handled by build-web.sh pipeline (baked into WASM export)
esac

echo "Export complete: $output"
