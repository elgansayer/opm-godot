#!/usr/bin/env bash
# test-connect.sh — Automated server connection e2e test
#
# Connects to live MOHAA servers and verifies that the engine can complete
# the full connect flow: challenge → gamestate → map download → map_loaded signal.
#
# Prerequisites:
#   - Built libopenmohaa.so deployed to project/bin/
#   - Game assets in ~/.local/share/openmohaa/ (main/)
#   - godot in PATH (Godot 4.2+)
#
# Usage:
#   ./scripts/test-connect.sh                           # Test default servers
#   ./scripts/test-connect.sh --server=78.108.16.74:12203  # Single server
#   ./scripts/test-connect.sh --game=aa --timeout=45       # Custom timeout
#   ./scripts/test-connect.sh --all                        # Test all known servers
#
# Exit codes:
#   0  At least one connection succeeded
#   1  All connections failed
#   2  Setup/infrastructure error

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
PROJECT_DIR="$REPO_ROOT/project"
LOG_DIR="$REPO_ROOT/test-results"
SUMMARY_FILE="$LOG_DIR/connect-test-latest.summary"
TIMESTAMP="$(date +%Y%m%d-%H%M%S)"

# Defaults
GAME_FILTER="aa"
TIMEOUT=30
SETTLE=5
SERVERS=()
TEST_ALL=false

# Known public MOHAA servers (curated list, most likely to be online)
declare -A SERVER_TABLE=(
    ["mr_robot"]="78.108.16.74:12203"
    ["luv_freezetag"]="217.182.199.4:12203"
    ["mls_stoner"]="108.181.98.42:12203"
    ["anubis_ffa"]="163.172.51.159:12203"
    ["uws_freezetag"]="45.79.133.140:12203"
    ["ab_sniper"]="141.94.205.35:12203"
    ["misfits_rifle"]="108.61.125.119:12203"
    ["nl_cable"]="62.194.57.8:12203"
    ["egy_stalingrad"]="62.194.57.8:12206"
    ["cs_stalingrad"]="179.61.251.35:12203"
    ["gf_obj"]="185.206.151.180:12203"
    ["tfc_sniper"]="173.249.214.104:12203"
)

# Parse args
for arg in "$@"; do
    case "$arg" in
        --server=*) SERVERS+=("${arg#--server=}") ;;
        --game=*)   GAME_FILTER="${arg#--game=}" ;;
        --timeout=*) TIMEOUT="${arg#--timeout=}" ;;
        --settle=*)  SETTLE="${arg#--settle=}" ;;
        --all)       TEST_ALL=true ;;
        --help|-h)
            echo "Usage: $0 [--server=IP:PORT] [--game=aa|sh|bt] [--timeout=30] [--settle=5] [--all]"
            echo ""
            echo "Known servers:"
            for key in "${!SERVER_TABLE[@]}"; do
                printf "  %-20s %s\n" "$key" "${SERVER_TABLE[$key]}"
            done
            exit 0
            ;;
    esac
done

# Setup
mkdir -p "$LOG_DIR"

echo "========================================"
echo " Server Connection E2E Test"
echo "========================================"

# Check prerequisites
if ! command -v godot &>/dev/null; then
    echo "ERROR: 'godot' not found in PATH" >&2
    exit 2
fi

if [[ ! -f "$PROJECT_DIR/bin/libopenmohaa.so" ]]; then
    echo "ERROR: project/bin/libopenmohaa.so not found. Run ./build.sh build first." >&2
    exit 2
fi

# Resolve game variant
case "$GAME_FILTER" in
    aa|AA|0) GAME_ID=0 ;;
    sh|SH|1) GAME_ID=1 ;;
    bt|BT|2) GAME_ID=2 ;;
    *)
        echo "ERROR: Unknown game '$GAME_FILTER'. Use aa, sh, bt." >&2
        exit 2
        ;;
esac

# Build server list
if [[ ${#SERVERS[@]} -eq 0 ]]; then
    if [[ "$TEST_ALL" == "true" ]]; then
        for key in "${!SERVER_TABLE[@]}"; do
            SERVERS+=("${SERVER_TABLE[$key]}")
        done
    else
        # Default: test 2 servers that are most likely online (high player counts)
        SERVERS=(
            "78.108.16.74:12203"    # MR ROBOT TDM (9 players)
            "217.182.199.4:12203"   # LuV Freeze-Tag (28 players)
        )
    fi
fi

echo "Game:      $GAME_FILTER (com_target_game=$GAME_ID)"
echo "Timeout:   ${TIMEOUT}s per server"
echo "Settle:    ${SETTLE}s after map load"
echo "Servers:   ${#SERVERS[@]}"
for srv in "${SERVERS[@]}"; do
    echo "  - $srv"
done
echo ""

# Build godot args
GODOT_ARGS=(--headless res://TestConnect.tscn --)
GODOT_ARGS+=(--game="$GAME_ID" --timeout="$TIMEOUT" --settle="$SETTLE")
for srv in "${SERVERS[@]}"; do
    GODOT_ARGS+=(--server="$srv")
done

LOG_FILE="$LOG_DIR/connect-test-$TIMESTAMP.log"

echo "Launching Godot with: ${GODOT_ARGS[*]}"
echo ""

cd "$PROJECT_DIR"

# Run with timeout: total = (timeout + settle + 5s overhead) * num_servers + 30s init
TOTAL_TIMEOUT=$(( (TIMEOUT + SETTLE + 5) * ${#SERVERS[@]} + 30 ))
set +e
timeout "${TOTAL_TIMEOUT}s" godot "${GODOT_ARGS[@]}" 2>&1 | tee "$LOG_FILE"
EXIT_CODE=${PIPESTATUS[0]}
set -e

echo ""
echo "========================================"
echo " Test Output Analysis"
echo "========================================"

# Parse results from log
PASS_COUNT=$(grep -c "^ConnectTest: PASS" "$LOG_FILE" 2>/dev/null) || PASS_COUNT=0
FAIL_COUNT=$(grep -c "^ConnectTest: FAIL" "$LOG_FILE" 2>/dev/null) || FAIL_COUNT=0

echo "Passed: $PASS_COUNT"
echo "Failed: $FAIL_COUNT"

# Extract individual results
echo ""
grep -E "^ConnectTest: (PASS|FAIL|OVERALL|PARTIAL)" "$LOG_FILE" 2>/dev/null || true

# Write summary
{
    echo "connect-test $TIMESTAMP"
    echo "game=$GAME_FILTER servers=${#SERVERS[@]}"
    echo "pass=$PASS_COUNT fail=$FAIL_COUNT"
    echo "exit=$EXIT_CODE"
    if [[ $PASS_COUNT -gt 0 ]]; then
        echo "result=PASS"
    else
        echo "result=FAIL"
    fi
} > "$SUMMARY_FILE"

echo ""
if [[ $PASS_COUNT -gt 0 ]]; then
    echo "RESULT: PASS ($PASS_COUNT/${#SERVERS[@]} servers connected)"
    exit 0
elif [[ $EXIT_CODE -eq 124 ]]; then
    echo "RESULT: FAIL (timeout — godot exceeded ${TOTAL_TIMEOUT}s)"
    exit 1
else
    echo "RESULT: FAIL (no servers connected)"
    exit 1
fi
