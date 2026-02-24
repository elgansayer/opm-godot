#!/usr/bin/env bash
# package-web-export.sh — Bundle the web export into a standalone deployment directory
# suitable for Portainer / docker compose.
#
# Usage:
#   ./package-web-export.sh [--push] [output-dir]
#
#   --push   After packaging, commit and push the output repo to GitHub.
#            GitHub Actions will then build & push the Docker image to GHCR.
#            Portainer pulls the pre-built image — no local build needed.
#
#   Default output: ../opm-godot-web-export
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
DEFAULT_OUT="$(dirname "$SCRIPT_DIR")/opm-godot-web-export"
PUSH=0

# Parse flags before the optional positional output-dir argument.
args=()
for arg in "$@"; do
    case "$arg" in
        --push) PUSH=1 ;;
        *)      args+=("$arg") ;;
    esac
done
OUT="${args[0]:-$DEFAULT_OUT}"

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

# Clean up stale generated directories so old files never linger in the repo.
# The .git dir is preserved; nothing else in docker/ is hand-authored.
rm -rf "$OUT/docker"

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

# Dockerfile — uses repo root as build context so both nginx.conf and web/ are
# baked into the image.
cat > "$OUT/docker/web/Dockerfile" << 'WEBDOCKERFILE'
FROM nginx:alpine
# Bake nginx config into the image
COPY docker/web/nginx.conf /etc/nginx/conf.d/default.conf
# Bake entrypoint
COPY docker/web/entrypoint.sh /entrypoint.sh
RUN chmod +x /entrypoint.sh
# Bake all web export files (HTML/JS/WASM/PCK/runtime .so) into the image.
COPY web /srv/web
ENTRYPOINT ["/entrypoint.sh"]
WEBDOCKERFILE

# entrypoint.sh — generates assets_manifest.json and injects CDN_URL
cat > "$OUT/docker/web/entrypoint.sh" << 'ENTRYPOINT'
#!/bin/sh
set -e

MANIFEST="/srv/web/assets_manifest.json"
echo "[OpenMoHAA] Generating asset manifest..."
echo "[" > "$MANIFEST"

# Find all pk3, so, and cfg files in /srv/assets
# We use a temporary file to handle the comma separation
TMP_LIST=$(mktemp)
find /srv/assets -type f \( -name "*.pk3" -o -name "*.so" -o -name "*.cfg" \) | sort > "$TMP_LIST"

COUNT=0
TOTAL=$(wc -l < "$TMP_LIST")
while IFS= read -r f; do
    COUNT=$((COUNT + 1))
    # Get path relative to /srv/assets
    REL=${f#/srv/assets/}
    if [ "$COUNT" -eq "$TOTAL" ]; then
        echo "  \"$REL\"" >> "$MANIFEST"
    else
        echo "  \"$REL\"," >> "$MANIFEST"
    fi
done < "$TMP_LIST"
rm "$TMP_LIST"

echo "]" >> "$MANIFEST"
echo "[OpenMoHAA] Manifest generated: $TOTAL files"

# Inject CDN_URL into mohaa.html if provided
if [ -n "$CDN_URL" ]; then
    echo "[OpenMoHAA] Injecting CDN_URL: $CDN_URL"
    # Ensure it ends with slash for the JS logic
    CDNLINK="$CDN_URL"
    case "$CDNLINK" in */) ;; *) CDNLINK="$CDNLINK/";; esac
    
    # Inject into GODOT_CONFIG in mohaa.html
    sed -i "s|\"serviceWorker\":\"\"|\"serviceWorker\":\"\",\"CDN_URL\":\"$CDNLINK\"|g" /srv/web/mohaa.html
fi

exec nginx -g 'daemon off;'
ENTRYPOINT
chmod +x "$OUT/docker/web/entrypoint.sh"

# nginx.conf — serves web/ files + game assets from volume with autoindex for preloader
cat > "$OUT/docker/web/nginx.conf" << 'NGINXCONF'
# Correct MIME type for WebAssembly (not in nginx:alpine defaults)
types {
    application/wasm          wasm;
    application/octet-stream  pck so pk3;
    application/json          json;
}

server {
    listen 80;
    server_name _;

    # Efficient large-file delivery (mohaa.side.wasm is ~39 MB)
    sendfile    on;
    tcp_nopush  on;
    tcp_nodelay on;

    # Gzip for text/code artifacts
    gzip on;
    gzip_types application/javascript application/wasm application/json text/css text/html;
    gzip_min_length 1000;

    # Required for SharedArrayBuffer (Emscripten threading + WASM)
    add_header Cross-Origin-Opener-Policy  "same-origin"   always;
    add_header Cross-Origin-Embedder-Policy "require-corp" always;
    add_header Cross-Origin-Resource-Policy "cross-origin" always;

    # --- WASM cgame.so: exact match from baked-in web root (not game assets volume) ---
    # Without this, the /main/ regex below would serve the Linux ELF binary from assets.
    location = /main/cgame.so {
        root /srv/web;
        default_type application/wasm;
        add_header Cross-Origin-Opener-Policy  "same-origin"   always;
        add_header Cross-Origin-Embedder-Policy "require-corp" always;
        add_header Cross-Origin-Resource-Policy "cross-origin"  always;
        add_header Cache-Control "no-store" always;
    }

    # --- Game asset directories: autoindex JSON for the VFS preloader ---
    # The JS preloader walks /main/ recursively via fetch() and expects JSON directory listings.
    # Files come from the ASSET_PATH volume mounted at /srv/assets.
    location ~ ^/main(/|$)(.*)$ {
        alias /srv/assets/main/$2;
        index off;
        autoindex on;
        autoindex_format json;
        add_header Cross-Origin-Opener-Policy  "same-origin"   always;
        add_header Cross-Origin-Embedder-Policy "require-corp" always;
        add_header Cross-Origin-Resource-Policy "cross-origin"  always;
        add_header Cache-Control "no-store" always;
    }

    # Expansion packs (same pattern)
    location ~ ^/mainta(/|$)(.*)$ {
        alias /srv/assets/mainta/$2;
        index off;
        autoindex on;
        autoindex_format json;
        add_header Cross-Origin-Opener-Policy  "same-origin"   always;
        add_header Cross-Origin-Embedder-Policy "require-corp" always;
        add_header Cross-Origin-Resource-Policy "cross-origin"  always;
        add_header Cache-Control "no-store" always;
    }

    location ~ ^/maintt(/|$)(.*)$ {
        alias /srv/assets/maintt/$2;
        index off;
        autoindex on;
        autoindex_format json;
        add_header Cross-Origin-Opener-Policy  "same-origin"   always;
        add_header Cross-Origin-Embedder-Policy "require-corp" always;
        add_header Cross-Origin-Resource-Policy "cross-origin"  always;
        add_header Cache-Control "no-store" always;
    }

    # No-cache for entrypoints so updates propagate immediately
    location ~* \.(html|js|json)$ {
        add_header Cache-Control "no-store, no-cache, must-revalidate" always;
        add_header Cross-Origin-Opener-Policy  "same-origin" always;
        add_header Cross-Origin-Embedder-Policy "require-corp" always;
        root /srv/web;
    }

    # Long-lived cache for binary assets served from baked-in web root
    location ~* \.(wasm|pck)$ {
        add_header Cache-Control "public, max-age=31536000, immutable" always;
        add_header Cross-Origin-Resource-Policy "cross-origin" always;
        root /srv/web;
    }

    # Game web files (HTML, JS, WASM)
    root /srv/web;
    index mohaa.html;

    location / {
        try_files $uri $uri/ /mohaa.html;
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
# The web service serves the game on port 8086 (Apache proxies :80 → :8086).
# The relay service bridges browser WebSockets to UDP game servers (port 12300).
#
# The web image is built and pushed to GHCR by GitHub Actions on every push to
# main.  Portainer just pulls the pre-built image — no local build required.
# =============================================================================

services:
  web:
    image: ghcr.io/mohcentral/opm-godot-web-export:latest
    container_name: opm-godot-web
    ports:
      # Apache VHost for game.moh-central.net (port 80) reverse-proxies to :8086.
      # Docker binds host port 8086 → container port 80.
      - "8086:80"
    environment:
      # Optional CDN URL (e.g. https://cdn.example.com/assets)
      - CDN_URL=${CDN_URL:-}
    volumes:
      # Game asset pk3 archives from the host — set ASSET_PATH in Portainer env vars.
      # Static web files (HTML/JS/WASM) are baked into the GHCR image, not mounted.
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

if [[ "$PUSH" -eq 1 ]]; then
    echo "=== Pushing to GitHub ==="
    cd "$OUT"
    git add -A
    if git diff --cached --quiet; then
        echo "Nothing changed — skipping commit."
    else
        TIMESTAMP="$(date -u +%Y-%m-%dT%H:%M:%SZ)"
        git commit -m "chore: update web export ${TIMESTAMP}"
        git push
        echo "Pushed. GitHub Actions will build and push the Docker image to GHCR."
        echo "Once the workflow completes (~2 min), redeploy in Portainer."
    fi
else
    echo "Next steps:"
    echo "  cd $OUT"
    echo "  git add -A && git commit -m 'Update web export' && git push"
    echo "  # GitHub Actions builds + pushes ghcr.io/mohcentral/opm-godot-web-export:latest"
    echo "  # Then in Portainer: pull latest image → redeploy stack"
    echo ""
    echo "  Or run:  ./package-web-export.sh --push"
fi
