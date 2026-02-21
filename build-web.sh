#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_BIN_DIR="$SCRIPT_DIR/project/bin"
PROJECT_DIR="$SCRIPT_DIR/project"
EXPORT_DIR="$SCRIPT_DIR/exports/web"
EXPORT_HTML="$EXPORT_DIR/mohaa.html"
PROJECT_GDEXT="$PROJECT_DIR/openmohaa.gdextension"
GAME_FILES_DIR="${GAME_FILES_DIR:-$HOME/.local/share/openmohaa/main}"

if [[ -f "$SCRIPT_DIR/openmohaa/SConstruct" ]]; then
    OPENMOHAA_DIR="$SCRIPT_DIR/openmohaa"
elif [[ -f "$SCRIPT_DIR/openmohaa/openmohaa/SConstruct" ]]; then
    OPENMOHAA_DIR="$SCRIPT_DIR/openmohaa/openmohaa"
else
    echo "ERROR: Could not find OpenMoHAA SConstruct under $SCRIPT_DIR/openmohaa" >&2
    exit 1
fi

EMSDK_DIR="${EMSDK_DIR:-/home/elgan/emsdk}"
BUILD_TARGET="template_debug"
CHECK_ONLY=0
EXPORT_AFTER_BUILD=1
COPY_GAME_FILES=1
EXTRA_SCONS_ARGS=()

while [[ $# -gt 0 ]]; do
    case "$1" in
        --release)
            BUILD_TARGET="template_release"
            shift
            ;;
        --debug)
            BUILD_TARGET="template_debug"
            shift
            ;;
        --check)
            CHECK_ONLY=1
            shift
            ;;
        --no-export)
            EXPORT_AFTER_BUILD=0
            shift
            ;;
        --no-game-files)
            COPY_GAME_FILES=0
            shift
            ;;
        --emsdk)
            if [[ $# -lt 2 ]]; then
                echo "ERROR: --emsdk requires a path" >&2
                exit 1
            fi
            EMSDK_DIR="$2"
            shift 2
            ;;
        --game-files)
            if [[ $# -lt 2 ]]; then
                echo "ERROR: --game-files requires a path" >&2
                exit 1
            fi
            GAME_FILES_DIR="$2"
            COPY_GAME_FILES=1
            shift 2
            ;;
        *)
            EXTRA_SCONS_ARGS+=("$1")
            shift
            ;;
    esac
done

EMSDK_ENV_SH="$EMSDK_DIR/emsdk_env.sh"
if [[ ! -f "$EMSDK_ENV_SH" ]]; then
    echo "ERROR: Emscripten SDK env script not found at: $EMSDK_ENV_SH" >&2
    exit 1
fi

set +u
# shellcheck disable=SC1090
source "$EMSDK_ENV_SH" >/dev/null
set -u

if ! command -v emcc >/dev/null 2>&1; then
    echo "ERROR: emcc not found in PATH after sourcing $EMSDK_ENV_SH" >&2
    exit 1
fi

if ! command -v scons >/dev/null 2>&1; then
    echo "ERROR: scons not found in PATH" >&2
    exit 1
fi

if ! command -v godot >/dev/null 2>&1; then
    echo "ERROR: godot not found in PATH" >&2
    exit 1
fi

if [[ "$CHECK_ONLY" -eq 1 ]]; then
    echo "Toolchain check OK"
    echo "  EMSDK_DIR: $EMSDK_DIR"
    echo "  emcc: $(command -v emcc)"
    echo "  em++: $(command -v em++ || true)"
    echo "  scons: $(command -v scons)"
    echo "  godot: $(command -v godot)"
    exit 0
fi

sync_gdextension_web_entries() {
    local debug_threads=""
    local debug_nothreads=""
    local release_threads=""
    local release_nothreads=""
    local artifact
    local name

    for artifact in "$@"; do
        name="$(basename "$artifact")"
        if [[ "$name" == *"template_debug"*"nothreads"* ]]; then
            debug_nothreads="$name"
        elif [[ "$name" == *"template_debug"* ]]; then
            debug_threads="$name"
        elif [[ "$name" == *"template_release"*"nothreads"* ]]; then
            release_nothreads="$name"
        elif [[ "$name" == *"template_release"* ]]; then
            release_threads="$name"
        fi
    done

    if [[ -z "$debug_threads" && -n "$debug_nothreads" ]]; then
        debug_threads="$debug_nothreads"
    fi
    if [[ -z "$debug_nothreads" && -n "$debug_threads" ]]; then
        debug_nothreads="$debug_threads"
    fi
    if [[ -z "$release_threads" && -n "$release_nothreads" ]]; then
        release_threads="$release_nothreads"
    fi
    if [[ -z "$release_nothreads" && -n "$release_threads" ]]; then
        release_nothreads="$release_threads"
    fi

    if [[ ! -f "$PROJECT_GDEXT" ]]; then
        echo "ERROR: Missing $PROJECT_GDEXT" >&2
        exit 1
    fi

    awk '!/^web\.(debug|release)(\.threads)?\.wasm32\s*=/' "$PROJECT_GDEXT" > "$PROJECT_GDEXT.tmp"

    {
        if [[ -n "$debug_threads" ]]; then
            echo "web.debug.threads.wasm32 = \"res://bin/$debug_threads\""
        fi
        if [[ -n "$debug_nothreads" ]]; then
            echo "web.debug.wasm32 = \"res://bin/$debug_nothreads\""
        fi
        if [[ -n "$release_threads" ]]; then
            echo "web.release.threads.wasm32 = \"res://bin/$release_threads\""
        fi
        if [[ -n "$release_nothreads" ]]; then
            echo "web.release.wasm32 = \"res://bin/$release_nothreads\""
        fi
    } >> "$PROJECT_GDEXT.tmp"

    mv "$PROJECT_GDEXT.tmp" "$PROJECT_GDEXT"
}

cd "$OPENMOHAA_DIR"

PARSER_DIR="code/parser/generated"
if [[ ! -f "$PARSER_DIR/yyParser.hpp" ]]; then
    mkdir -p "$PARSER_DIR"
    bison --defines="$PARSER_DIR/yyParser.hpp" -o "$PARSER_DIR/yyParser.cpp" code/parser/bison_source.txt
    flex -Cem --nounistd -o "$PARSER_DIR/yyLexer.cpp" --header-file="$PARSER_DIR/yyLexer.h" code/parser/lex_source.txt
fi

scons platform=web target="$BUILD_TARGET" -j"$(nproc)" "${EXTRA_SCONS_ARGS[@]}"

mapfile -t WASM_ARTIFACTS < <(find bin -maxdepth 1 -type f -name "*openmohaa*.wasm" | sort)
if [[ ${#WASM_ARTIFACTS[@]} -eq 0 ]]; then
    echo "ERROR: Build completed but no wasm artifacts were found in $(pwd)/bin" >&2
    exit 1
fi

mkdir -p "$PROJECT_BIN_DIR"
for artifact in "${WASM_ARTIFACTS[@]}"; do
    cp -f "$artifact" "$PROJECT_BIN_DIR/$(basename "$artifact")"
    echo "Deployed: $(basename "$artifact") -> $PROJECT_BIN_DIR"
done

sync_gdextension_web_entries "${WASM_ARTIFACTS[@]}"

if [[ "$COPY_GAME_FILES" -eq 1 ]]; then
    if [[ -d "$GAME_FILES_DIR" ]]; then
        mkdir -p "$EXPORT_DIR/main"
        rsync -a --delete "$GAME_FILES_DIR/" "$EXPORT_DIR/main/"
        echo "Copied game files: $GAME_FILES_DIR -> $EXPORT_DIR/main"
    else
        echo "WARNING: Game files directory not found: $GAME_FILES_DIR"
    fi
fi

if [[ "$EXPORT_AFTER_BUILD" -eq 1 ]]; then
    mkdir -p "$EXPORT_DIR"
    if [[ "$BUILD_TARGET" == "template_release" ]]; then
        godot --headless --path "$PROJECT_DIR" --export-release Web "$EXPORT_HTML"
    else
        godot --headless --path "$PROJECT_DIR" --export-debug Web "$EXPORT_HTML"
    fi
fi

echo "Web build complete (target=$BUILD_TARGET)."
echo "Export output: $EXPORT_HTML"
