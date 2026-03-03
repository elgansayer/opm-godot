#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd -- "$SCRIPT_DIR/.." && pwd)"
OPENMOHAA_DIR="$REPO_ROOT/openmohaa"
PROJECT_BIN_DIR="$REPO_ROOT/project/bin"
CGAME_DEPLOY_DIR="$REPO_ROOT/project/bin"

if [[ $# -eq 0 ]]; then
    echo "ERROR: platform target required (linux|windows|macos)" >&2
    exit 1
fi
PLAT="$1"
shift

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

scons platform="$PLAT" target=template_debug -j"$(nproc)" "$@"

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
