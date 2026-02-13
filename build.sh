#!/usr/bin/env bash
set -euo pipefail

# Build OpenMoHAA GDExtension
cd "$(dirname "$0")/openmohaa"

# If you edited widely included headers (e.g. qcommon.h), uncomment:
# rm -f .sconsign.dblite

scons platform=linux target=template_debug -j"$(nproc)" dev_build=yes

# Deploy artifacts
cp -f bin/libopenmohaa.so ../project/bin/libopenmohaa.so
cp -f bin/libcgame.so "$HOME/.local/share/openmohaa/main/cgame.so"
