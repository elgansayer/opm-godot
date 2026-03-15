#!/usr/bin/env bash
# test-web-connect.sh — Web E2E connect test against real MOHAA servers via relay.
#
# Usage:
#   ./scripts/test-web-connect.sh [--server=IP:PORT] [--all] [--timeout=60] [--settle=3]
#
# Requires: Docker stack running (./build.sh serve), Chromium/Chrome, npm.
set -euo pipefail

SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd -- "$SCRIPT_DIR/.." && pwd)"
E2E_DIR="$SCRIPT_DIR/web-e2e"

BASE_URL="${BASE_URL:-http://127.0.0.1:8086}"
CONNECT_TIMEOUT_MS=60000
SETTLE_MS=3000
SERVERS=""

# Server table — same as desktop test-connect.sh
declare -A SERVER_TABLE=(
    [tfc_sniper]="173.249.214.104:12203"
    [gf_obj]="185.206.151.180:12203"
    [misfits_rifle]="108.61.125.119:12203"
    [cs_stalingrad]="179.61.251.35:12203"
    [uws_freezetag]="45.79.133.140:12203"
    [mls_stoner]="108.181.98.42:12203"
    [ab_sniper]="141.94.205.35:12203"
    [nl_cable]="62.194.57.8:12203"
    [egy_stalingrad]="62.194.57.8:12206"
    [anubis_ffa]="163.172.51.159:12203"
    [mr_robot_tdm]="78.108.16.74:12203"
    [luv_freezetag]="217.182.199.4:12203"
)

# Default quick-test servers (known reliable)
DEFAULT_SERVERS="78.108.16.74:12203,217.182.199.4:12203,108.181.98.42:12203"

USE_ALL=0

while [[ $# -gt 0 ]]; do
    case "$1" in
        --server=*) SERVERS="${1#--server=}"; shift ;;
        --timeout=*) CONNECT_TIMEOUT_MS=$(( ${1#--timeout=} * 1000 )); shift ;;
        --settle=*) SETTLE_MS=$(( ${1#--settle=} * 1000 )); shift ;;
        --all) USE_ALL=1; shift ;;
        --base-url=*) BASE_URL="${1#--base-url=}"; shift ;;
        *) echo "ERROR: Unknown arg: $1" >&2; exit 1 ;;
    esac
done

if [[ "$USE_ALL" -eq 1 ]]; then
    SERVERS=""
    for key in "${!SERVER_TABLE[@]}"; do
        [[ -n "$SERVERS" ]] && SERVERS+=","
        SERVERS+="${SERVER_TABLE[$key]}"
    done
fi

[[ -z "$SERVERS" ]] && SERVERS="$DEFAULT_SERVERS"

# Check Docker stack is running
if ! curl -sf "$BASE_URL/health" >/dev/null 2>&1; then
    echo "ERROR: Docker stack not reachable at $BASE_URL/health" >&2
    echo "  Start it with: ./build.sh serve --release --asset-path ~/.local/share/openmohaa" >&2
    exit 2
fi
echo "Docker stack healthy at $BASE_URL"

# Detect browser
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
            echo "$candidate"
            return 0
        fi
    done
    return 1
}

SYSTEM_BROWSER="$(detect_browser || true)"
if [[ -z "$SYSTEM_BROWSER" ]]; then
    echo "ERROR: No Chromium/Chrome browser found. Install chromium or google-chrome." >&2
    exit 2
fi
echo "Using browser: $SYSTEM_BROWSER"

# Install npm deps
cd "$E2E_DIR"
PLAYWRIGHT_SKIP_BROWSER_DOWNLOAD=1 npm install --silent 2>/dev/null

echo ""
echo "========================================"
echo " Web Connect E2E Test"
echo "========================================"
echo "Servers: $SERVERS"
echo "Timeout: $((CONNECT_TIMEOUT_MS / 1000))s per server"
echo ""

BASE_URL="$BASE_URL" \
SERVERS="$SERVERS" \
CONNECT_TIMEOUT_MS="$CONNECT_TIMEOUT_MS" \
SETTLE_MS="$SETTLE_MS" \
BROWSER_EXECUTABLE="$SYSTEM_BROWSER" \
node run-web-connect-e2e.mjs

EXIT_CODE=$?
exit $EXIT_CODE
