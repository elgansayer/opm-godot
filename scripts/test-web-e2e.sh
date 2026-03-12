#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd -- "$SCRIPT_DIR/.." && pwd)"
E2E_DIR="$SCRIPT_DIR/web-e2e"

ASSET_PATH="${ASSET_PATH:-$HOME/.local/share/openmohaa}"
BASE_URL="${BASE_URL:-http://127.0.0.1:8086}"
TARGET_MAP="${TARGET_MAP:-dm/mohdm1}"
COM_TARGET_GAME="${COM_TARGET_GAME:-0}"
E2E_TIMEOUT_MS="${E2E_TIMEOUT_MS:-240000}"

require_cmd() {
    local cmd="$1"
    if ! command -v "$cmd" >/dev/null 2>&1; then
        echo "ERROR: missing required command: $cmd" >&2
        exit 2
    fi
}

detect_browser() {
    local candidate
    for candidate in \
        "${BROWSER_EXECUTABLE:-}" \
        "$(command -v chromium 2>/dev/null || true)" \
        "$(command -v chromium-browser 2>/dev/null || true)" \
        "$(command -v google-chrome 2>/dev/null || true)" \
        "$(command -v google-chrome-stable 2>/dev/null || true)" \
        "$(command -v microsoft-edge 2>/dev/null || true)" \
        "$(command -v microsoft-edge-stable 2>/dev/null || true)"; do
        if [[ -n "$candidate" && -x "$candidate" ]]; then
            if "$candidate" --version >/dev/null 2>&1; then
                echo "$candidate"
                return 0
            fi
        fi
    done
    return 1
}

run_in_docker_playwright() {
    local image="mcr.microsoft.com/playwright:v1.52.0-jammy"
    echo "WebE2E: Running in Docker Playwright image: $image"
    docker run --rm \
        --network host \
        -v "$REPO_ROOT:/work" \
        -w /work/scripts/web-e2e \
        -e BASE_URL="$BASE_URL" \
        -e TARGET_MAP="$TARGET_MAP" \
        -e COM_TARGET_GAME="$COM_TARGET_GAME" \
        -e E2E_TIMEOUT_MS="$E2E_TIMEOUT_MS" \
        "$image" \
        bash -lc "npm install --silent && node run-web-e2e.mjs"
}

echo "WebE2E: Preconditions"
require_cmd node
require_cmd npm
require_cmd docker

SYSTEM_BROWSER="$(detect_browser || true)"
if [[ -n "$SYSTEM_BROWSER" ]]; then
    echo "WebE2E: Using browser: $SYSTEM_BROWSER"
else
    echo "WebE2E: No usable local browser found; Docker fallback will be used"
fi

if [[ ! -f "$E2E_DIR/package.json" ]]; then
    echo "ERROR: missing Playwright package definition at $E2E_DIR/package.json" >&2
    exit 2
fi

echo "WebE2E: Running web preflight"
ASSET_PATH="$ASSET_PATH" "$SCRIPT_DIR/test-web.sh"

echo "WebE2E: Installing npm dependencies (if needed)"
if [[ -n "$SYSTEM_BROWSER" ]]; then
    PLAYWRIGHT_SKIP_BROWSER_DOWNLOAD=1 npm --prefix "$E2E_DIR" install --silent
fi

echo "WebE2E: Running browser E2E"
if [[ -n "$SYSTEM_BROWSER" ]]; then
    BASE_URL="$BASE_URL" \
    TARGET_MAP="$TARGET_MAP" \
    COM_TARGET_GAME="$COM_TARGET_GAME" \
    E2E_TIMEOUT_MS="$E2E_TIMEOUT_MS" \
    BROWSER_EXECUTABLE="$SYSTEM_BROWSER" \
    node "$E2E_DIR/run-web-e2e.mjs"
else
    run_in_docker_playwright
fi

echo "WebE2E: PASS"
