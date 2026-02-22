#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
OPENMOHAA_DIR="$SCRIPT_DIR/openmohaa"
PROJECT_BIN_DIR="$SCRIPT_DIR/project/bin"
CGAME_DEPLOY_DIR="$HOME/.local/share/openmohaa/main"

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

# cgame.so is not built by SCons; use the pre-built copy from the old build dir
OLD_CGAME="$SCRIPT_DIR/openmohaa/bin/libcgame.so"
if [[ -f bin/libcgame.so ]]; then
    \cp -f bin/libcgame.so "$CGAME_DEPLOY_DIR/cgame.so" || exit 1
elif [[ -f "$OLD_CGAME" ]]; then
    \cp -f "$OLD_CGAME" "$CGAME_DEPLOY_DIR/cgame.so" || exit 1
else
    echo "WARNING: libcgame.so not found; cgame.so not deployed"
fi

# Deploy server.cfg to engine config path (fs_homepath/main/) so +exec server.cfg works
SERVER_CFG_SRC="$SCRIPT_DIR/exports/web/main/server.cfg"
SERVER_CFG_DST="$HOME/.config/openmohaa/main/server.cfg"
if [[ -f "$SERVER_CFG_SRC" ]]; then
    mkdir -p "$(dirname "$SERVER_CFG_DST")"
    \cp -f "$SERVER_CFG_SRC" "$SERVER_CFG_DST"
    echo "Deployed server.cfg -> $SERVER_CFG_DST"
fi
