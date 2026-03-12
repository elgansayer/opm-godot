#!/usr/bin/env bash
# build-web-docker.sh — Build a self-contained Docker image from dist/web/<variant>/.
# Usage: build-web-docker.sh [--variant debug|release] [--tag <image:tag>]
set -euo pipefail

SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd -- "$SCRIPT_DIR/.." && pwd)"

VARIANT="debug"
TAG=""

while [[ $# -gt 0 ]]; do
    case "$1" in
        --variant) VARIANT="$2"; shift 2 ;;
        --tag)     TAG="$2";     shift 2 ;;
        *) echo "ERROR: unknown argument: $1" >&2; exit 1 ;;
    esac
done

WEB_DIST="$REPO_ROOT/dist/web/$VARIANT"
[[ -d "$WEB_DIST" ]] || {
    echo "ERROR: Web export not found: $WEB_DIST" >&2
    echo "Run './build.sh web-full $VARIANT' first." >&2
    exit 1
}
[[ -f "$WEB_DIST/mohaa.html" ]] || {
    echo "ERROR: mohaa.html not found in $WEB_DIST — incomplete export" >&2
    exit 1
}

# Default tag
[[ -z "$TAG" ]] && TAG="mohaa-godot-web:$VARIANT"

echo "Building Docker image from: $WEB_DIST"
echo "  Tag: $TAG"

# Build a simple nginx:alpine image with the web export baked in.
# Game assets are NOT included — they must be mounted at /srv/assets at runtime.
docker build -t "$TAG" -f - "$REPO_ROOT" <<DOCKERFILE
FROM nginx:alpine
COPY docker/web/nginx.conf /etc/nginx/conf.d/default.conf
COPY dist/web/$VARIANT/ /srv/web/
EXPOSE 80
DOCKERFILE

echo "Docker image built: $TAG"
echo ""
echo "Run it with:"
echo "  docker run -d -p 8086:80 -v /path/to/game-assets:/srv/assets:ro $TAG"
