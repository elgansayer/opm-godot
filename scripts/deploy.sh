#!/usr/bin/env bash
# deploy.sh — Push code to trigger GitHub Actions build + optionally sync CDN
#
# The web build is done by GitHub Actions (build-web.yml), which produces a
# Docker image and pushes it to ghcr.io/elgansayer/mohaa-godot:latest.
# The production server (Portainer) pulls that image and serves the web export.
# Game assets live on a remote CDN — no local assets on the server.
#
# Usage:
#   ./scripts/deploy.sh [OPTIONS]
#
# Options:
#   --cdn-remote REMOTE   Sync game assets to CDN via rclone (e.g. r2:mohaa-cdn)
#   --asset-path PATH     Local path to game assets (required with --cdn-remote)
#   --no-push             Stage changes but don't commit/push
#   --message "MSG"       Custom commit message (default: auto-generated timestamp)
#   --local-build         Also run a local web build before pushing
#   --local-serve         Also start local Docker stack (requires --asset-path)
#   -h, --help            Show this help
#
# Default pipeline (remote-first):
#   1. CDN asset sync (if --cdn-remote) — deploy-cdn.sh (manifest gen + rclone)
#   2. Commit + push to GitHub
#   3. GitHub Actions builds Docker image → ghcr.io/elgansayer/mohaa-godot:latest
#   4. Portainer pulls latest image (configured with CDN_URL env var)
#
# Examples:
#   # Just push code — GitHub Actions builds, Portainer redeploys
#   ./scripts/deploy.sh
#
#   # Sync CDN assets then push
#   ./scripts/deploy.sh --cdn-remote r2:mohaa-cdn --asset-path ~/mohaa-assets
#
#   # Local dev: build locally + serve + push
#   ./scripts/deploy.sh --local-build --local-serve --asset-path ~/mohaa-assets

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
cd "$REPO_ROOT"

# --- Defaults ---
ASSET_PATH=""
CDN_REMOTE=""
NO_PUSH=0
COMMIT_MSG=""
LOCAL_BUILD=0
LOCAL_SERVE=0

# --- Parse flags ---
while [[ $# -gt 0 ]]; do
    case "$1" in
        --asset-path)   ASSET_PATH="$2"; shift 2 ;;
        --cdn-remote)   CDN_REMOTE="$2"; shift 2 ;;
        --no-push)      NO_PUSH=1; shift ;;
        --message)      COMMIT_MSG="$2"; shift 2 ;;
        --local-build)  LOCAL_BUILD=1; shift ;;
        --local-serve)  LOCAL_SERVE=1; shift ;;
        -h|--help)
            sed -n '2,/^set -euo/{ /^set -euo/d; s/^# \?//p; }' "$0"
            exit 0 ;;
        *)
            echo "Unknown option: $1" >&2
            exit 1 ;;
    esac
done

# --- Validation ---
if [[ -n "$CDN_REMOTE" && -z "$ASSET_PATH" ]]; then
    echo "ERROR: --cdn-remote requires --asset-path to know which files to upload." >&2
    exit 1
fi
if [[ "$LOCAL_SERVE" -eq 1 && -z "$ASSET_PATH" ]]; then
    echo "ERROR: --local-serve requires --asset-path for the Docker volume mount." >&2
    exit 1
fi

TIMESTAMP="$(date -u +%Y-%m-%dT%H:%M:%SZ)"
if [[ -z "$COMMIT_MSG" ]]; then
    COMMIT_MSG="release: web export ${TIMESTAMP}"
fi

# Count total steps
TOTAL_STEPS=1  # push is always a step
[[ "$LOCAL_BUILD" -eq 1 ]] && TOTAL_STEPS=$(( TOTAL_STEPS + 1 ))
[[ -n "$CDN_REMOTE" ]] && TOTAL_STEPS=$(( TOTAL_STEPS + 1 ))
[[ "$LOCAL_SERVE" -eq 1 ]] && TOTAL_STEPS=$(( TOTAL_STEPS + 1 ))
CURRENT_STEP=0

# --- Colours ---
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
CYAN='\033[0;36m'
NC='\033[0m'

next_step() { CURRENT_STEP=$(( CURRENT_STEP + 1 )); echo -e "\n${CYAN}=== Step ${CURRENT_STEP}/${TOTAL_STEPS}: $1 ===${NC}"; }
ok()   { echo -e "${GREEN}✓ $1${NC}"; }
warn() { echo -e "${YELLOW}⚠ $1${NC}"; }
fail() { echo -e "${RED}✗ $1${NC}" >&2; exit 1; }

# =========================================================================
# Optional: Local web build (dev only)
# =========================================================================
if [[ "$LOCAL_BUILD" -eq 1 ]]; then
    next_step "Local web build"
    BUILD_ARGS=(--release)
    if [[ -n "$ASSET_PATH" ]]; then
        BUILD_ARGS+=(--asset-path "$ASSET_PATH")
    fi
    "$SCRIPT_DIR/build-web.sh" "${BUILD_ARGS[@]}"
    ok "Web build complete"
fi

# =========================================================================
# Optional: CDN asset sync
# =========================================================================
if [[ -n "$CDN_REMOTE" ]]; then
    next_step "CDN asset sync"
    "$SCRIPT_DIR/deploy-cdn.sh" --source "$ASSET_PATH" --remote "$CDN_REMOTE"
    ok "CDN assets synced to $CDN_REMOTE"
fi

# =========================================================================
# Optional: Local Docker serve (dev only)
# =========================================================================
if [[ "$LOCAL_SERVE" -eq 1 ]]; then
    next_step "Local Docker deploy"
    WEB_DIST="${REPO_ROOT}/dist/web/release"
    if [[ ! -f "$WEB_DIST/mohaa.html" ]]; then
        fail "dist/web/release/mohaa.html not found — run with --local-build first"
    fi
    WEB_DIST="$WEB_DIST" ASSET_PATH="$ASSET_PATH" docker compose -f docker/docker-compose.yml up -d
    ok "Local stack running at http://localhost:8086"
fi

# =========================================================================
# Commit + push (triggers GitHub Actions)
# =========================================================================
next_step "Commit + push"
if [[ "$NO_PUSH" -eq 0 ]]; then
    git add -A
    if git diff --cached --quiet; then
        warn "Nothing changed — skipping commit"
    else
        git commit -m "$COMMIT_MSG"
        git push
        ok "Pushed to origin"
    fi
else
    warn "Skipping push (--no-push)"
fi

# =========================================================================
# Summary
# =========================================================================
echo ""
echo "  Repo:   git@github.com:elgansayer/mohaa-godot.git"
echo "  Image:  ghcr.io/elgansayer/mohaa-godot:latest"
if [[ -n "$CDN_REMOTE" ]]; then
    echo "  CDN:    $CDN_REMOTE"
fi
echo ""
if [[ "$NO_PUSH" -eq 0 ]]; then
    echo "  GitHub Actions will build + push the Docker image to GHCR."
    echo "  Check: https://github.com/elgansayer/mohaa-godot/actions"
    echo ""
    echo "  Once complete, redeploy in Portainer or wait for auto-poll."
    echo "  Ensure CDN_URL is set in the Portainer stack environment."
else
    echo "  Run again without --no-push to commit and deploy."
fi
echo ""
ok "Deploy complete"
