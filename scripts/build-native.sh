#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
OPENMOHAA_DIR="$SCRIPT_DIR/openmohaa"
PROJECT_BIN_DIR="$SCRIPT_DIR/project/bin"
CGAME_DEPLOY_DIR="$SCRIPT_DIR/project/bin"

# Build OpenMoHAA GDExtension
cd "$OPENMOHAA_DIR"

# Generate parser/lexer sources if missing (requires bison & flex)
PARSER_DIR="code/parser/generated"
if [[ ! -f "$PARSER_DIR/yyParser.hpp" ]]; then
    mkdir -p "$PARSER_DIR"
    bison --defines="$PARSER_DIR/yyParser.hpp" -o "$PARSER_DIR/yyParser.cpp" code/parser/bison_source.txt
    flex -Cem --nounistd -o "$PARSER_DIR/yyLexer.cpp" --header-file="$PARSER_DIR/yyLexer.h" code/parser/lex_source.txt
fi

# If you edited widely included headers (e.g. qcommon.h), uncomment:
# rm -f .sconsign.dblite

scons platform=linux target=template_debug -j"$(nproc)" "$@"

# Validate artifacts before deploy
[[ -f bin/libopenmohaa.so ]]

# Deploy artifacts
mkdir -p "$PROJECT_BIN_DIR" "$CGAME_DEPLOY_DIR"
\cp -f bin/libopenmohaa.so "$PROJECT_BIN_DIR/libopenmohaa.so" || exit 1

# Deploy cgame.so next to libopenmohaa.so (project/bin/) so the GDExtension
# loader finds it via dladdr without polluting the main/ game directory.
OLD_CGAME="$SCRIPT_DIR/openmohaa/bin/libcgame.so"
if [[ -f bin/libcgame.so ]]; then
    \cp -f bin/libcgame.so "$CGAME_DEPLOY_DIR/cgame.so" || exit 1
elif [[ -f "$OLD_CGAME" ]]; then
    \cp -f "$OLD_CGAME" "$CGAME_DEPLOY_DIR/cgame.so" || exit 1
else
    echo "WARNING: libcgame.so not found; cgame.so not deployed"
fi

# Clean up old cgame.so from main/ if it exists (legacy location)
OLD_MAIN_CGAME="$HOME/.local/share/openmohaa/main/cgame.so"
if [[ -f "$OLD_MAIN_CGAME" ]]; then
    rm -f "$OLD_MAIN_CGAME"
    echo "Removed legacy $OLD_MAIN_CGAME"
fi

