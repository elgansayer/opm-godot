#!/usr/bin/env bash
# build-desktop.sh — Build OpenMoHAA GDExtension for desktop platforms.
# Outputs to openmohaa/bin/, deploys to project/bin/ for GDExtension staging.
# Does NOT destroy previous builds — incremental by default.
set -euo pipefail

SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd -- "$SCRIPT_DIR/.." && pwd)"
OPENMOHAA_DIR="$REPO_ROOT/openmohaa"
PROJECT_BIN_DIR="$REPO_ROOT/project/bin"
CGAME_DEPLOY_DIR="$REPO_ROOT/project/bin"

# ── CPU detection ─────────────────────────────────────────────────────────
detect_jobs() {
    if command -v nproc >/dev/null 2>&1; then nproc; return; fi
    if command -v getconf >/dev/null 2>&1; then
        local j; j="$(getconf _NPROCESSORS_ONLN 2>/dev/null || true)"
        [[ "$j" =~ ^[0-9]+$ ]] && [[ "$j" -gt 0 ]] && echo "$j" && return
    fi
    if command -v sysctl >/dev/null 2>&1; then
        local j; j="$(sysctl -n hw.ncpu 2>/dev/null || true)"
        [[ "$j" =~ ^[0-9]+$ ]] && [[ "$j" -gt 0 ]] && echo "$j" && return
    fi
    echo 4
}

extract_osxcross_sdk_tags() {
    local bin_dir="$1"
    ls -1 "$bin_dir"/*-apple-*-clang 2>/dev/null \
        | sed -E 's#^.*/(x86_64|arm64)-apple-([^-]+)-clang$#\2#' \
        | sort -u
}

# ── Argument parsing ──────────────────────────────────────────────────────
CLEAN=false
if [[ "${1:-}" == "--clean" ]]; then
    CLEAN=true
    shift
fi

if [[ $# -eq 0 ]]; then
    echo "Usage: build-desktop.sh [--clean] <linux|windows|macos> [scons-args...]" >&2
    exit 1
fi
PLAT="$1"; shift

case "$PLAT" in
    linux|windows|macos) ;;
    *) echo "ERROR: unsupported platform '$PLAT'" >&2; exit 1 ;;
esac

HOST_UNAME="$(uname -s)"
EXTRA_SCONS_ARGS=("$@")
BUILD_TARGET="template_debug"

# Extract target= from extra args so we can use it in messages.
FILTERED_SCONS_ARGS=()
for arg in "${EXTRA_SCONS_ARGS[@]}"; do
    if [[ "$arg" == target=* ]]; then
        BUILD_TARGET="${arg#target=}"
        continue
    fi
    FILTERED_SCONS_ARGS+=("$arg")
done
EXTRA_SCONS_ARGS=("${FILTERED_SCONS_ARGS[@]}")

# ── macOS cross-compile validation ────────────────────────────────────────
if [[ "$PLAT" == "macos" ]] && [[ "$HOST_UNAME" != "Darwin" ]]; then
    if [[ -z "${OSXCROSS_ROOT:-}" ]]; then
        echo "ERROR: macos builds require OSXCROSS_ROOT for cross-compile on Linux." >&2
        exit 1
    fi
    [[ -d "$OSXCROSS_ROOT/target/bin" ]] || { echo "ERROR: OSXCROSS_ROOT target/bin missing" >&2; exit 1; }
    compgen -G "$OSXCROSS_ROOT/target/bin/*-apple-*-clang" >/dev/null || {
        echo "ERROR: no osxcross compiler binaries found" >&2; exit 1
    }

    # Auto-detect osxcross SDK tag if not provided
    OSXCROSS_SDK_ARG=""
    for arg in "${EXTRA_SCONS_ARGS[@]}"; do
        [[ "$arg" == osxcross_sdk=* ]] && { OSXCROSS_SDK_ARG="${arg#osxcross_sdk=}"; break; }
    done
    if [[ -z "$OSXCROSS_SDK_ARG" ]]; then
        mapfile -t sdk_tags < <(extract_osxcross_sdk_tags "$OSXCROSS_ROOT/target/bin")
        [[ "${#sdk_tags[@]}" -eq 0 ]] && { echo "ERROR: failed to infer osxcross SDK tag" >&2; exit 1; }
        OSXCROSS_SDK_ARG="${sdk_tags[0]}"
        EXTRA_SCONS_ARGS+=("osxcross_sdk=$OSXCROSS_SDK_ARG")
        echo "Auto-detected osxcross_sdk=$OSXCROSS_SDK_ARG"
    fi
    if [[ ! -x "$OSXCROSS_ROOT/target/bin/x86_64-apple-$OSXCROSS_SDK_ARG-clang" ]] \
       && [[ ! -x "$OSXCROSS_ROOT/target/bin/arm64-apple-$OSXCROSS_SDK_ARG-clang" ]]; then
        echo "ERROR: osxcross_sdk='$OSXCROSS_SDK_ARG' does not match installed compilers" >&2
        extract_osxcross_sdk_tags "$OSXCROSS_ROOT/target/bin" | sed 's/^/  - /' >&2
        exit 1
    fi
fi

# ── Build ─────────────────────────────────────────────────────────────────
JOBS="$(detect_jobs)"
cd "$OPENMOHAA_DIR"

# Only clean when explicitly requested — incremental by default.
if $CLEAN; then
    echo "Cleaning previous build artefacts..."
    rm -rf bin/ build/ .sconsign.dblite
    rm -f "$PROJECT_BIN_DIR/libopenmohaa"* "$CGAME_DEPLOY_DIR/cgame"*
fi

# Generate parser/lexer sources if missing
PARSER_DIR="code/parser/generated"
if [[ ! -f "$PARSER_DIR/yyParser.hpp" ]]; then
    mkdir -p "$PARSER_DIR"
    bison --defines="$PARSER_DIR/yyParser.hpp" -o "$PARSER_DIR/yyParser.cpp" code/parser/bison_source.txt
    flex -Cem --nounistd -o "$PARSER_DIR/yyLexer.cpp" --header-file="$PARSER_DIR/yyLexer.h" code/parser/lex_source.txt
fi

echo "Building $PLAT/$BUILD_TARGET with $JOBS jobs..."
scons platform="$PLAT" target="$BUILD_TARGET" -j"$JOBS" "${EXTRA_SCONS_ARGS[@]}"

# ── Deploy to project/bin/ (GDExtension staging) ─────────────────────────
EXT=".so"
case "$PLAT" in
    windows) EXT=".dll" ;;
    macos)   EXT=".dylib" ;;
esac

# Validate at least one main library exists
[[ -f "bin/libopenmohaa$EXT" ]] || [[ -f "bin/openmohaa$EXT" ]] || {
    echo "ERROR: build produced no library artefact in openmohaa/bin/" >&2; exit 1
}

mkdir -p "$PROJECT_BIN_DIR" "$CGAME_DEPLOY_DIR"

# Main library
if [[ -f "bin/libopenmohaa$EXT" ]]; then
    \cp -f "bin/libopenmohaa$EXT" "$PROJECT_BIN_DIR/libopenmohaa$EXT"
elif [[ -f "bin/openmohaa$EXT" ]]; then
    \cp -f "bin/openmohaa$EXT" "$PROJECT_BIN_DIR/openmohaa$EXT"
fi

# cgame
if [[ -f "bin/libcgame$EXT" ]]; then
    \cp -f "bin/libcgame$EXT" "$CGAME_DEPLOY_DIR/cgame$EXT"
elif [[ -f "bin/cgame$EXT" ]]; then
    \cp -f "bin/cgame$EXT" "$CGAME_DEPLOY_DIR/cgame$EXT"
else
    echo "WARNING: cgame$EXT not found; not deployed"
fi

# Clean up legacy cgame location
OLD_MAIN_CGAME="$HOME/.local/share/openmohaa/main/cgame.so"
[[ -f "$OLD_MAIN_CGAME" ]] && rm -f "$OLD_MAIN_CGAME" && echo "Removed legacy $OLD_MAIN_CGAME"

echo "Desktop engine build complete: $PLAT/$BUILD_TARGET"
echo "  Libraries staged in: $PROJECT_BIN_DIR"
