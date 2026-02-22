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

# Runtime files needed from main/ (cgame + cfg)
echo "Copying runtime files (main/)..."
mkdir -p "$OUT/web/main"
# cgame.so is needed at runtime
if [[ -f "$SCRIPT_DIR/exports/web/main/cgame.so" ]]; then
    cp -f "$SCRIPT_DIR/exports/web/main/cgame.so" "$OUT/web/main/"
fi
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

# --- 3. Nginx config ---
echo "Copying nginx config..."
mkdir -p "$OUT/docker/web"
cp -f "$SCRIPT_DIR/docker/web/default.conf" "$OUT/docker/web/"

# --- 4. docker-compose.yml ---
echo "Writing docker-compose.yml..."
cat > "$OUT/docker-compose.yml" << 'COMPOSE'
services:
  web:
    image: nginx:1.27-alpine
    container_name: opm-godot-web
    ports:
      - "8086:80"
    volumes:
      - ./web:/usr/share/nginx/html:ro
      - ${MOHAA_ASSETS:-${HOME}/mohaa-web-base}:/gamedata:ro
      - ./docker/web/default.conf:/etc/nginx/conf.d/default.conf:ro
    restart: unless-stopped

  relay:
    build: ./relay
    container_name: opm-godot-relay
    # Host networking so UDP broadcast (LAN server scanning) reaches
    # the real LAN interface, not just the Docker bridge.
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

Self-contained web deployment of OpenMoHAA via Godot GDExtension.

## Quick Start

### 1. Add game assets

Copy your MOHAA pk3 files into:

```bash
mkdir -p ~/mohaa-web-base/main ~/mohaa-web-base/mainta ~/mohaa-web-base/maintt

# Allied Assault (required)
cp /path/to/mohaa/main/Pak*.pk3 ~/mohaa-web-base/main/
cp /path/to/mohaa/main/pak6.pk3 ~/mohaa-web-base/main/

# Spearhead (optional)
cp /path/to/mohaa/mainta/*.pk3 ~/mohaa-web-base/mainta/

# Breakthrough (optional)
cp /path/to/mohaa/maintt/*.pk3 ~/mohaa-web-base/maintt/
```

Override with env var if needed:
```bash
MOHAA_ASSETS=/path/to/mohaa-web-base docker compose up -d
```

### 2. Start stack

```bash
docker compose up -d
```

Then open: **http://your-server:8086**

## Services

| Service | Port | Description |
|---------|------|-------------|
| `web` | 8086 | Nginx serving the Godot web export |
| `relay` | 12300 | WebSocket-to-UDP relay for multiplayer |

The web client auto-connects to the relay on the same hostname, port 12300.

## Multiplayer

The relay bridges browser WebSocket connections to native UDP game servers.
LAN server scanning works via UDP broadcast.

To connect to a specific server, use the in-game console:
```
connect <server-ip>
```

## Asset Layout

Nginx serves from two roots:
- `web/` (repo): engine/runtime files (`mohaa.*`, `cgame.so`, cfgs)
- `/gamedata` (host mount): pk3 assets from `~/mohaa-web-base`

The game can load:
- `main/` from `~/mohaa-web-base/main`
- `mainta/` from `~/mohaa-web-base/mainta`
- `maintt/` from `~/mohaa-web-base/maintt`

## Directory Structure

```
├── docker-compose.yml       # Docker Compose config
├── docker/web/default.conf  # Nginx config (COOP/COEP headers)
├── relay/                   # WebSocket-to-UDP relay server
│   ├── Dockerfile
│   ├── package.json
│   └── mohaa_relay.js
└── web/                     # Godot web export (served by nginx)
    ├── mohaa.html           # Entry point
    ├── mohaa.js             # Emscripten runtime
    ├── *.wasm               # Engine binaries
    ├── mohaa.pck            # Godot project package
  └── main/                # Runtime files (cgame.so, cfg)

~/mohaa-web-base/            # External game assets (not in git)
  ├── main/                # AA pk3 files
  ├── mainta/              # SH pk3 files
  └── maintt/              # BT pk3 files
```

## Requirements

- Docker + Docker Compose
- Game assets in `~/mohaa-web-base/{main,mainta,maintt}`

## Portainer Deployment

1. Add this repo as a Git stack in Portainer
2. Set the compose path to `docker-compose.yml`
3. Ensure `~/mohaa-web-base` exists on host with your pk3 files
3. Deploy — both services start automatically
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
echo "  mkdir -p ~/mohaa-web-base/main ~/mohaa-web-base/mainta ~/mohaa-web-base/maintt"
echo "  # copy your pk3 files into ~/mohaa-web-base/..."
echo "  git init"
echo "  git add -A && git commit -m 'Initial web export package'"
echo "  git remote add origin git@github.com:YOUR_USER/opm-godot-web-export.git"
echo "  git push -u origin main"
