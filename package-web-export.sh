#!/usr/bin/env bash
# package-web-export.sh — Bundle the web export into a standalone deployment directory
# suitable for Portainer / docker compose.
#
# Usage:
#   ./package-web-export.sh [output-dir]
#   Default output: ../opm-godot-web-export
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
DEFAULT_OUT="$(dirname "$SCRIPT_DIR")/opm-godot-web-export"
OUT="${1:-$DEFAULT_OUT}"

echo "=== Packaging opm-godot web export ==="
echo "Source: $SCRIPT_DIR"
echo "Output: $OUT"

# Verify source files exist
if [[ ! -f "$SCRIPT_DIR/exports/web/mohaa.html" ]]; then
    echo "ERROR: exports/web/mohaa.html not found. Run build-web.sh first." >&2
    exit 1
fi
if [[ ! -d "$SCRIPT_DIR/exports/web/main" ]]; then
    echo "ERROR: exports/web/main/ not found (game assets)." >&2
    exit 1
fi

# Create output directory
mkdir -p "$OUT"

# --- 1. Web export files ---
echo "Copying web export files..."
mkdir -p "$OUT/web"
# Engine/Godot files
for f in mohaa.html mohaa.js mohaa.wasm mohaa.side.wasm mohaa.pck \
         libopenmohaa.wasm mohaa.png mohaa.512x512.png mohaa.180x180.png \
         mohaa.144x144.png mohaa.audio.worklet.js \
         mohaa.audio.position.worklet.js mohaa.offline.html \
         mohaa.manifest.json; do
    if [[ -f "$SCRIPT_DIR/exports/web/$f" ]]; then
        cp -f "$SCRIPT_DIR/exports/web/$f" "$OUT/web/$f"
    fi
done

# Runtime files needed from main/ (all .so runtime modules + cfg)
echo "Copying runtime files (main/)..."
mkdir -p "$OUT/web/main"
# Copy all runtime modules produced by the web export (eg cgame.so, game.so, renderer_opengl1.so)
for f in "$SCRIPT_DIR/exports/web/main/"*.so; do
  [[ -f "$f" ]] && cp -f "$f" "$OUT/web/main/"
done
# Server configs
for f in "$SCRIPT_DIR/exports/web/main/"*.cfg; do
    [[ -f "$f" ]] && cp -f "$f" "$OUT/web/main/"
done

# --- 2. Relay server ---
echo "Copying relay server..."
mkdir -p "$OUT/relay"
cp -f "$SCRIPT_DIR/relay/mohaa_relay.js" "$OUT/relay/"
cp -f "$SCRIPT_DIR/relay/package.json" "$OUT/relay/"
cp -f "$SCRIPT_DIR/relay/package-lock.json" "$OUT/relay/" 2>/dev/null || true
cp -f "$SCRIPT_DIR/relay/Dockerfile" "$OUT/relay/"
cp -f "$SCRIPT_DIR/relay/.dockerignore" "$OUT/relay/"

# --- 3. nginx web server (Docker-served static files) ---
echo "Writing nginx Docker files..."
mkdir -p "$OUT/docker/web"

# Dockerfile — config is COPY-ed in (not mounted), avoids Portainer OCI bind-mount errors
cat > "$OUT/docker/web/Dockerfile" << 'WEBDOCKERFILE'
FROM nginx:alpine
# nginx.conf is baked into the image — no volume mount needed for config
COPY nginx.conf /etc/nginx/conf.d/default.conf
WEBDOCKERFILE

# nginx.conf — serves web/ files + proxies /main/ /mainta/ /maintt/ to asset volume
cat > "$OUT/docker/web/nginx.conf" << 'NGINXCONF'
server {
    listen 80;
    server_name _;

    # Required for SharedArrayBuffer (Emscripten threading + WASM)
    add_header Cross-Origin-Opener-Policy  "same-origin"   always;
    add_header Cross-Origin-Embedder-Policy "require-corp" always;
    add_header Cross-Origin-Resource-Policy "cross-origin" always;
    add_header Cache-Control               "no-store"      always;

    # Game web files (HTML, JS, WASM, compiled .so, .cfg)
    root /srv/web;
    index mohaa.html;

    # For game directories: try web/main/ first (runtime .so/.cfg),
    # then fall back to the asset volume (pk3 archives).
    location ~ ^/(main|mainta|maintt)/.+ {
        try_files $uri @gamedata;
    }

    location @gamedata {
        # ASSET_PATH is mounted at /srv/assets in docker-compose.yml
        root /srv/assets;
        try_files $uri =404;
    }

    location / {
        try_files $uri $uri/ =404;
    }
}
NGINXCONF

# --- 4. docker-compose.yml ---
echo "Writing docker-compose.yml..."
cat > "$OUT/docker-compose.yml" << 'COMPOSE'
# =============================================================================
# OPM-Godot Web Export — Portainer / docker compose stack
# =============================================================================
# Deploy this stack in Portainer by pointing it at this Git repo.
#
# Set ONE environment variable in Portainer (or a .env file):
#   ASSET_PATH  — absolute path on the host to your game assets directory.
#                 Must contain main/, mainta/, maintt/ sub-directories with pk3s.
#                 Example:  ASSET_PATH=/home/elgan/mohaa-web-base
#
# The web service serves game files on port 8086 (mapped to your Apache VHost).
# The relay service bridges browser WebSockets to UDP game servers (port 12300).
# =============================================================================

services:
  web:
    build: ./docker/web
    container_name: opm-godot-web
    ports:
      # Apache VHost for game.moh-central.net (port 80) reverse-proxies to :8086.
      # Docker binds host port 8086 → container port 80.
      - "8086:80"
    volumes:
      # Static game files (HTML/JS/WASM/runtime .so) from this repo
      - ./web:/srv/web:ro
      # Game asset pk3 archives from the host — set ASSET_PATH in Portainer env vars
      - ${ASSET_PATH:-/opt/mohaa-assets}:/srv/assets:ro
    restart: unless-stopped

  relay:
    build: ./relay
    container_name: opm-godot-relay
    # Host networking: relay binds on host port 12300 directly.
    # Browsers connect via ws://your-host:12300/
    network_mode: host
    restart: unless-stopped
COMPOSE

# --- 5. .gitignore ---
cat > "$OUT/.gitignore" << 'GITIGNORE'
# Game assets (copyrighted — not distributed via git)
gamedata/
*.pk3

# Node
relay/node_modules/

# Logs
web/main/qconsole.log

# OS
.DS_Store
Thumbs.db
GITIGNORE

# --- 6. README ---
cat > "$OUT/README.md" << 'README'
# OPM-Godot Web Export

Web deployment of OpenMoHAA via Godot GDExtension.

The Docker stack serves the game via **nginx on port 8086** and runs the
WebSocket relay for multiplayer. No separate web server config required —
just point your Apache `ProxyPass` (or equivalent) at `localhost:8086`.

## Setup

### 1. Add game assets to the server

```bash
mkdir -p ~/mohaa-web-base/main ~/mohaa-web-base/mainta ~/mohaa-web-base/maintt
cp /path/to/mohaa/main/Pak*.pk3     ~/mohaa-web-base/main/
# Spearhead (optional):
cp /path/to/mohaa/mainta/*.pk3      ~/mohaa-web-base/mainta/
# Breakthrough (optional):
cp /path/to/mohaa/maintt/*.pk3      ~/mohaa-web-base/maintt/
```

### 2. Deploy via Portainer

1. Add this repo as a **Git stack** in Portainer
2. Set compose file path: `docker-compose.yml`
3. Set **one environment variable** in Portainer:
   ```
   ASSET_PATH=/home/elgan/mohaa-web-base
   ```
   (Adjust to wherever your pk3 archives live on the server.)
4. Deploy — Portainer builds the images and starts both containers.

### 3. Apache VHost (one-time, already done)

Your VHost for `game.moh-central.net` listens on port 80 and proxies to the
Docker container on port 8086:

```apache
<VirtualHost *:80>
    ServerName game.moh-central.net
    ProxyPreserveHost On
    ProxyPass        / http://localhost:8086/
    ProxyPassReverse / http://localhost:8086/
</VirtualHost>
```

The COOP/COEP/CORP headers required for SharedArrayBuffer are set by nginx
automatically — no `Header always set` directives needed in Apache.

## Services

| Service | Port | Description |
|---------|------|-------------|
| `web`   | 8086 | nginx — serves game HTML/JS/WASM + pk3 assets (Apache proxies :80→:8086) |
| `relay` | 12300 | WebSocket-to-UDP relay for multiplayer |

Browsers connect to the relay directly: `ws://your-host:12300/`

## Directory Structure

```
├── docker-compose.yml        # web (nginx:8086) + relay (port 12300)
├── docker/
│   └── web/
│       ├── Dockerfile        # FROM nginx:alpine — config baked in
│       └── nginx.conf        # COOP/COEP headers + asset routing
├── relay/                    # WebSocket-to-UDP relay
└── web/                      # Godot export files
    ├── mohaa.html
    ├── mohaa.js / *.wasm / *.pck
    └── main/                 # Runtime modules (cgame.so, etc.)
```

Game assets (pk3 files) are **not** stored in git — mount them via `ASSET_PATH`.
README

# --- Summary ---
echo ""
echo "=== Package complete ==="
du -sh "$OUT"
echo ""
echo "Contents:"
du -sh "$OUT"/*
echo ""
echo "Next steps:"
echo "  cd $OUT"
echo "  # Copy pk3 assets to server, then set ASSET_PATH in Portainer env vars"
echo "  git add -A && git commit -m 'Update web export'"
echo "  git push"
echo "  # In Portainer: pull latest → redeploy stack"
