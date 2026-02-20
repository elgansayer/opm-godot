#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
OPENMOHAA_DIR="$SCRIPT_DIR/openmohaa"
PROJECT_BIN_DIR="$SCRIPT_DIR/project/bin"
CGAME_DEPLOY_DIR="$HOME/.local/share/openmohaa/main"

# Build OpenMoHAA GDExtension
cd "$OPENMOHAA_DIR"

# If you edited widely included headers (e.g. qcommon.h), uncomment:
# rm -f .sconsign.dblite

scons platform=linux target=template_debug -j"$(nproc)" dev_build=yes "$@"

# Validate artifacts before deploy
[[ -f bin/libopenmohaa.so ]]
[[ -f bin/libcgame.so ]]

# Deploy artifacts
mkdir -p "$PROJECT_BIN_DIR" "$CGAME_DEPLOY_DIR"
\cp -f bin/libopenmohaa.so "$PROJECT_BIN_DIR/libopenmohaa.so" || exit 1
\cp -f bin/libcgame.so "$CGAME_DEPLOY_DIR/cgame.so" || exit 1
