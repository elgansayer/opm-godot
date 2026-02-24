#!/bin/sh
# Runs automatically via the official nginx docker-entrypoint.d/ hook before nginx starts.
# Creates a symlink so that GET /main/ serves the gamedata directory via nginx autoindex.
# Supports both structured (/gamedata/main/) and flat (/gamedata/*.pk3) layouts.
set -e

HTML_ROOT="/usr/share/nginx/html"
GAMEDATA="/gamedata"
LINK="$HTML_ROOT/main"

if [ ! -d "$GAMEDATA" ]; then
    echo "[40-gamedata-link] /gamedata not mounted; skipping symlink"
    exit 0
fi

# Remove stale link/dir from a previous container run.
if [ -L "$LINK" ] || [ -e "$LINK" ]; then
    rm -rf "$LINK"
fi

if [ -d "$GAMEDATA/main" ]; then
    # Structured layout: /gamedata/main/pak0.pk3 ...
    ln -s "$GAMEDATA/main" "$LINK"
    echo "[40-gamedata-link] Linked $LINK -> $GAMEDATA/main (structured)"
else
    # Flat layout: /gamedata/pak0.pk3 ...
    ln -s "$GAMEDATA" "$LINK"
    echo "[40-gamedata-link] Linked $LINK -> $GAMEDATA (flat)"
fi
