#!/usr/bin/env bash
# release.sh — Full build → package → deploy → push pipeline
#
# Usage:
#   ./release.sh --asset-path /path/to/game/assets [OPTIONS]
#
# Options:
#   --asset-path PATH   Path to game assets directory (required for serve)
#   --skip-build        Skip the full web build (reuse existing exports/web/)
#   --skip-serve        Don't start local Docker stack after packaging
#   --no-push           Package but don't commit/push to either repo
#   --message "MSG"     Custom commit message (default: auto-generated timestamp)
#
# Pipeline:
#   1. Full web build               — build-web.sh (SCons + Godot export + JS patches)
#   2. Local deploy (optional)      — Docker compose up (nginx + relay)
#   3. Package for Portainer        — package-web-export.sh → ../opm-godot-web-export/
#   4. Commit + push main repo      — opm-godot
#   5. Commit + push export repo    — opm-godot-web-export
#   6. GitHub Actions               — builds Docker image → ghcr.io/mohcentral/opm-godot-web-export:latest
#   7. Portainer                    — pulls latest image on next poll/manual redeploy
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
cd "$SCRIPT_DIR"

# --- Defaults ---
ASSET_PATH=""
SKIP_BUILD=0
SKIP_SERVE=0
NO_PUSH=0
COMMIT_MSG=""

# --- Parse flags ---
while [[ $# -gt 0 ]]; do
    case "$1" in
        --asset-path)   ASSET_PATH="$2"; shift 2 ;;
        --skip-build)   SKIP_BUILD=1; shift ;;
        --skip-serve)   SKIP_SERVE=1; shift ;;
        --no-push)      NO_PUSH=1; shift ;;
        --message)      COMMIT_MSG="$2"; shift 2 ;;
        -h|--help)
            head -17 "$0" | tail -16
            exit 0 ;;
        *)
            echo "Unknown option: $1" >&2
            exit 1 ;;
    esac
done

# --- Validation ---
if [[ -z "$ASSET_PATH" && "$SKIP_SERVE" -eq 0 ]]; then
    echo "ERROR: --asset-path is required (or use --skip-serve to skip local deploy)." >&2
    echo "Usage: $0 --asset-path /path/to/game/assets" >&2
    exit 1
fi

TIMESTAMP="$(date -u +%Y-%m-%dT%H:%M:%SZ)"
if [[ -z "$COMMIT_MSG" ]]; then
    COMMIT_MSG="release: web export ${TIMESTAMP}"
fi

# --- Colours ---
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
CYAN='\033[0;36m'
NC='\033[0m'

step() { echo -e "\n${CYAN}=== $1 ===${NC}"; }
ok()   { echo -e "${GREEN}✓ $1${NC}"; }
warn() { echo -e "${YELLOW}⚠ $1${NC}"; }
fail() { echo -e "${RED}✗ $1${NC}" >&2; exit 1; }

# =========================================================================
# Step 1: Full web build
# =========================================================================
if [[ "$SKIP_BUILD" -eq 0 ]]; then
    step "Step 1/5: Full web build"
    BUILD_ARGS=(--release)
    if [[ -n "$ASSET_PATH" ]]; then
        BUILD_ARGS+=(--asset-path "$ASSET_PATH")
    fi
    ./build-web.sh "${BUILD_ARGS[@]}"
    ok "Web build complete"
else
    step "Step 1/5: Skipping build (--skip-build)"
    if [[ ! -f exports/web/mohaa.html ]]; then
        fail "exports/web/mohaa.html not found — run without --skip-build first"
    fi
    # Still apply patches (in case build-web.sh was updated)
    if [[ -n "$ASSET_PATH" ]]; then
        ./build-web.sh --patch-only --asset-path "$ASSET_PATH"
    else
        ./build-web.sh --patch-only
    fi
    ok "Patches re-applied"
fi

# =========================================================================
# Step 2: Local deploy (Docker compose)
# =========================================================================
if [[ "$SKIP_SERVE" -eq 0 ]]; then
    step "Step 2/5: Local deploy"
    ./build-web.sh --serve --asset-path "$ASSET_PATH"
    ok "Local stack running at http://localhost:8086"
else
    step "Step 2/5: Skipping local deploy (--skip-serve)"
fi

# =========================================================================
# Step 3: Package for Portainer
# =========================================================================
step "Step 3/5: Packaging for Portainer"
if [[ "$NO_PUSH" -eq 0 ]]; then
    ./package-web-export.sh --push
else
    ./package-web-export.sh
fi
ok "Package complete"

# =========================================================================
# Step 4: Commit + push main repo (opm-godot)
# =========================================================================
step "Step 4/5: Commit + push opm-godot"
if [[ "$NO_PUSH" -eq 0 ]]; then
    git add -A
    if git diff --cached --quiet; then
        warn "Nothing changed in opm-godot — skipping commit"
    else
        git commit -m "$COMMIT_MSG"
        git push
        ok "Pushed opm-godot to origin"
    fi
else
    warn "Skipping push (--no-push)"
fi

# =========================================================================
# Step 5: Summary
# =========================================================================
step "Step 5/5: Summary"
echo ""
echo "  Main repo:    git@github.com:elgansayer/opm-godot.git"
echo "  Export repo:   git@github.com:MOHCentral/opm-godot-web-export.git"
echo "  Docker image:  ghcr.io/mohcentral/opm-godot-web-export:latest"
echo ""
if [[ "$NO_PUSH" -eq 0 ]]; then
    echo "  GitHub Actions will build + push the Docker image to GHCR."
    echo "  Check: https://github.com/MOHCentral/opm-godot-web-export/actions"
    echo ""
    echo "  Once complete (~2 min), redeploy in Portainer or wait for auto-poll."
else
    echo "  Run again without --no-push to commit and deploy."
fi
echo ""
ok "Release pipeline complete"
