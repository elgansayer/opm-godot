#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd -- "$SCRIPT_DIR/.." && pwd)"
OPENMOHAA_DIR="$REPO_ROOT/openmohaa"
PROJECT_BIN_DIR="$REPO_ROOT/project/bin"
CGAME_DEPLOY_DIR="$REPO_ROOT/project/bin"

detect_jobs() {
    # Prefer native tool on each host OS, then fall back safely.
    if command -v nproc >/dev/null 2>&1; then
        nproc
        return
    fi

    if command -v getconf >/dev/null 2>&1; then
        local jobs
        jobs="$(getconf _NPROCESSORS_ONLN 2>/dev/null || true)"
        if [[ -n "${jobs:-}" ]] && [[ "$jobs" =~ ^[0-9]+$ ]] && [[ "$jobs" -gt 0 ]]; then
            echo "$jobs"
            return
        fi
    fi

    if command -v sysctl >/dev/null 2>&1; then
        local jobs
        jobs="$(sysctl -n hw.ncpu 2>/dev/null || true)"
        if [[ -n "${jobs:-}" ]] && [[ "$jobs" =~ ^[0-9]+$ ]] && [[ "$jobs" -gt 0 ]]; then
            echo "$jobs"
            return
        fi
    fi

    # Conservative fallback when CPU count detection is unavailable.
    echo 4
}

extract_osxcross_sdk_tags() {
    local bin_dir="$1"
    ls -1 "$bin_dir"/*-apple-*-clang 2>/dev/null \
        | sed -E 's#^.*/(x86_64|arm64)-apple-([^-]+)-clang$#\2#' \
        | sort -u
}

if [[ $# -eq 0 ]]; then
    echo "ERROR: platform target required (linux|windows|macos)" >&2
    exit 1
fi
PLAT="$1"
shift

case "$PLAT" in
    linux|windows|macos)
        ;;
    *)
        echo "ERROR: unsupported platform '$PLAT' (expected linux|windows|macos)" >&2
        exit 1
        ;;
esac

HOST_UNAME="$(uname -s)"
EXTRA_SCONS_ARGS=("$@")
BUILD_TARGET="template_debug"

# Allow callers (CMake/build.sh) to override target=template_release cleanly.
FILTERED_SCONS_ARGS=()
for arg in "${EXTRA_SCONS_ARGS[@]}"; do
    if [[ "$arg" == target=* ]]; then
        BUILD_TARGET="${arg#target=}"
        continue
    fi
    FILTERED_SCONS_ARGS+=("$arg")
done
EXTRA_SCONS_ARGS=("${FILTERED_SCONS_ARGS[@]}")
if [[ "$PLAT" == "macos" ]] && [[ "$HOST_UNAME" != "Darwin" ]]; then
    # godot-cpp/tools/macos.py only enables non-Darwin macOS builds via OSXCROSS_ROOT.
    if [[ -z "${OSXCROSS_ROOT:-}" ]]; then
        echo "ERROR: macos builds require a macOS host toolchain (or explicit osxcross setup)." >&2
        echo "Run this target on macOS, or export OSXCROSS_ROOT for osxcross cross-compile." >&2
        exit 1
    fi

    if [[ ! -d "$OSXCROSS_ROOT/target/bin" ]]; then
        echo "ERROR: OSXCROSS_ROOT is set but toolchain bin dir is missing:" >&2
        echo "  $OSXCROSS_ROOT/target/bin" >&2
        exit 1
    fi

    if ! compgen -G "$OSXCROSS_ROOT/target/bin/*-apple-*-clang" >/dev/null; then
        echo "ERROR: no osxcross compiler binaries found under:" >&2
        echo "  $OSXCROSS_ROOT/target/bin" >&2
        exit 1
    fi

    OSXCROSS_SDK_ARG=""
    for arg in "${EXTRA_SCONS_ARGS[@]}"; do
        if [[ "$arg" == osxcross_sdk=* ]]; then
            OSXCROSS_SDK_ARG="${arg#osxcross_sdk=}"
            break
        fi
    done

    if [[ -z "$OSXCROSS_SDK_ARG" ]]; then
        mapfile -t sdk_tags < <(extract_osxcross_sdk_tags "$OSXCROSS_ROOT/target/bin")
        if [[ "${#sdk_tags[@]}" -eq 0 ]]; then
            echo "ERROR: failed to infer osxcross SDK tag from compiler names." >&2
            exit 1
        fi

        OSXCROSS_SDK_ARG="${sdk_tags[0]}"
        if [[ "${#sdk_tags[@]}" -gt 1 ]]; then
            echo "WARNING: multiple osxcross SDK tags detected: ${sdk_tags[*]}" >&2
            echo "WARNING: defaulting to '$OSXCROSS_SDK_ARG'; pass osxcross_sdk=<tag> to override." >&2
        fi

        EXTRA_SCONS_ARGS+=("osxcross_sdk=$OSXCROSS_SDK_ARG")
        echo "Using auto-detected osxcross_sdk=$OSXCROSS_SDK_ARG"
    fi

    if [[ ! -x "$OSXCROSS_ROOT/target/bin/x86_64-apple-$OSXCROSS_SDK_ARG-clang" ]] \
       && [[ ! -x "$OSXCROSS_ROOT/target/bin/arm64-apple-$OSXCROSS_SDK_ARG-clang" ]]; then
        echo "ERROR: osxcross_sdk='$OSXCROSS_SDK_ARG' does not match installed compiler prefixes." >&2
        echo "Available SDK tags:" >&2
        extract_osxcross_sdk_tags "$OSXCROSS_ROOT/target/bin" | sed 's/^/  - /' >&2
        exit 1
    fi
fi

JOBS="$(detect_jobs)"

# Build OpenMoHAA GDExtension
cd "$OPENMOHAA_DIR"

# Always clean prior binaries so stale .so files cannot survive
rm -rf bin/ build/ .sconsign.dblite
rm -f "$PROJECT_BIN_DIR/libopenmohaa"* "$CGAME_DEPLOY_DIR/cgame"*

# Generate parser/lexer sources if missing (requires bison & flex)
PARSER_DIR="code/parser/generated"
if [[ ! -f "$PARSER_DIR/yyParser.hpp" ]]; then
    mkdir -p "$PARSER_DIR"
    bison --defines="$PARSER_DIR/yyParser.hpp" -o "$PARSER_DIR/yyParser.cpp" code/parser/bison_source.txt
    flex -Cem --nounistd -o "$PARSER_DIR/yyLexer.cpp" --header-file="$PARSER_DIR/yyLexer.h" code/parser/lex_source.txt
fi

scons platform="$PLAT" target="$BUILD_TARGET" -j"$JOBS" "${EXTRA_SCONS_ARGS[@]}"

# Determine artifact extensions based on platform
EXT=".so"
if [[ "$PLAT" == "windows" ]]; then
    EXT=".dll"
elif [[ "$PLAT" == "macos" ]]; then
    EXT=".dylib"
fi

# Validate artifacts before deploy
[[ -f "bin/libopenmohaa$EXT" ]] || [[ -f "bin/openmohaa$EXT" ]]

# Deploy artifacts
mkdir -p "$PROJECT_BIN_DIR" "$CGAME_DEPLOY_DIR"

if [[ -f "bin/libopenmohaa$EXT" ]]; then
    \cp -f "bin/libopenmohaa$EXT" "$PROJECT_BIN_DIR/libopenmohaa$EXT" || exit 1
elif [[ -f "bin/openmohaa$EXT" ]]; then
    \cp -f "bin/openmohaa$EXT" "$PROJECT_BIN_DIR/openmohaa$EXT" || exit 1
fi


# Deploy cgame next to main extension so GDExtension loader finds it
OLD_CGAME="$REPO_ROOT/openmohaa/bin/libcgame$EXT"
if [[ -f "bin/libcgame$EXT" ]]; then
    \cp -f "bin/libcgame$EXT" "$CGAME_DEPLOY_DIR/cgame$EXT" || exit 1
elif [[ -f "bin/cgame$EXT" ]]; then
    \cp -f "bin/cgame$EXT" "$CGAME_DEPLOY_DIR/cgame$EXT" || exit 1
elif [[ -f "$OLD_CGAME" ]]; then
    \cp -f "$OLD_CGAME" "$CGAME_DEPLOY_DIR/cgame$EXT" || exit 1
else
    echo "WARNING: libcgame$EXT not found; cgame$EXT not deployed"
fi

# Clean up old cgame.so from main/ if it exists (legacy location)
OLD_MAIN_CGAME="$HOME/.local/share/openmohaa/main/cgame.so"
if [[ -f "$OLD_MAIN_CGAME" ]]; then
    rm -f "$OLD_MAIN_CGAME"
    echo "Removed legacy $OLD_MAIN_CGAME"
fi
