#!/usr/bin/env bash
# test-chat.sh — Automated DM chat (messagemode_all) regression test
#
# Launches Godot with the TestChat scene for each game variant (AA/SH/BT),
# captures scene-level ChatTest output and reports pass/fail per variant.
#
# Prerequisites:
#   - Built libopenmohaa.so deployed to project/bin/
#   - Game assets in ~/.local/share/openmohaa/ (main/, mainta/, maintt/)
#   - godot in PATH (Godot 4.2+)
#
# Usage:
#   ./scripts/test-chat.sh                    # Test all variants
#   ./scripts/test-chat.sh --game=aa          # Test AA only
#   ./scripts/test-chat.sh --game=sh          # Test SH only
#   ./scripts/test-chat.sh --game=bt          # Test BT only
#   ./scripts/test-chat.sh --duration=45      # Custom timeout per variant
#
# Exit codes:
#   0  All checks passed
#   1  One or more variants failed
#   2  Setup/infrastructure error

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
PROJECT_DIR="$REPO_ROOT/project"
LOG_DIR="$REPO_ROOT/test-results"
SUMMARY_FILE="$LOG_DIR/chat-test-latest.summary"
TIMESTAMP="$(date +%Y%m%d-%H%M%S)"

# Defaults
GAME_FILTER="all"
DURATION=90
CYCLES=3

# Parse args
for arg in "$@"; do
    case "$arg" in
        --game=*) GAME_FILTER="${arg#--game=}" ;;
        --duration=*) DURATION="${arg#--duration=}" ;;
        --cycles=*) CYCLES="${arg#--cycles=}" ;;
        --help|-h)
            echo "Usage: $0 [--game=aa|sh|bt|all] [--duration=45] [--cycles=5]"
            exit 0
            ;;
    esac
done

# Setup
mkdir -p "$LOG_DIR"

echo "========================================"
echo " DM Chat (messagemode_all) Regression Test"
echo "========================================"
echo "Game filter: $GAME_FILTER"
echo "Duration:    ${DURATION}s per variant"
echo "Cycles:      $CYCLES open/close per variant"
echo ""

# Check prerequisites
if ! command -v godot &>/dev/null; then
    echo "ERROR: 'godot' not found in PATH"
    exit 2
fi

if [[ ! -f "$PROJECT_DIR/bin/libopenmohaa.so" ]]; then
    echo "ERROR: project/bin/libopenmohaa.so not found. Run ./build.sh first."
    exit 2
fi

# Define game variants
# Format: game_id:com_target_game:map:asset_dir
declare -a VARIANTS=()

case "$GAME_FILTER" in
    aa|AA)
        VARIANTS=("AA:0:dm/mohdm1:main")
        ;;
    sh|SH)
        VARIANTS=("SH:1:DM/MP_Bahnhof_DM:mainta")
        ;;
    bt|BT)
        VARIANTS=("BT:2:DM/mp_bahnhof_dm:maintt")
        ;;
    all|ALL)
        VARIANTS=(
            "AA:0:dm/mohdm1:main"
            "SH:1:DM/MP_Bahnhof_DM:mainta"
            "BT:2:DM/mp_bahnhof_dm:maintt"
        )
        ;;
    *)
        echo "ERROR: Unknown game '$GAME_FILTER'. Use aa, sh, bt, or all."
        exit 2
        ;;
esac

# Track overall results
OVERALL_PASS=true
declare -a RESULTS=()

run_variant() {
    local LABEL="$1"
    local TARGET_GAME="$2"
    local MAP="$3"
    local ASSET_DIR="$4"
    local LOG_FILE="$LOG_DIR/chat-test-${LABEL,,}-${TIMESTAMP}.log"

    echo ""
    echo "----------------------------------------"
    echo " Testing $LABEL (com_target_game=$TARGET_GAME, map=$MAP)"
    echo "----------------------------------------"

    # Check assets exist
    local ASSET_PATH="$HOME/.local/share/openmohaa/$ASSET_DIR"
    if [[ ! -d "$ASSET_PATH" ]]; then
        echo "WARNING: $ASSET_PATH not found. Test may fail to load map."
    else
        local PAK_COUNT
        PAK_COUNT=$(find "$ASSET_PATH" -maxdepth 1 -iname '*.pk3' | wc -l)
        echo "Assets: $ASSET_PATH ($PAK_COUNT .pk3 files)"
    fi

    echo "Log: $LOG_FILE"
    echo ""

    # Run the test with timeout
    local TIMEOUT_SECS=$((DURATION + 20))

    set +e
    timeout "$TIMEOUT_SECS" godot --path "$PROJECT_DIR" \
        res://TestChat.tscn \
        -- --game="$TARGET_GAME" --map="$MAP" \
           --duration="$DURATION" --cycles="$CYCLES" \
        2>&1 | tee "$LOG_FILE"
    local GODOT_EXIT=$?
    set -e

    echo ""
    echo "Godot exited with code: $GODOT_EXIT"

    # Analyse results
    local FAIL_COUNT=0
    local PASS_COUNT=0
    local INFO_COUNT=0
    local RESULT_FAIL=0
    local RESULT_PASS=0
    local CRASH_DETECTED=0

    if [[ -f "$LOG_FILE" ]]; then
        FAIL_COUNT=$(grep -c 'ChatTest: .*FAIL' "$LOG_FILE" 2>/dev/null) || FAIL_COUNT=0
        PASS_COUNT=$(grep -c 'ChatTest: .*PASS' "$LOG_FILE" 2>/dev/null) || PASS_COUNT=0
        INFO_COUNT=$(grep -c 'ChatTest: .*INFO' "$LOG_FILE" 2>/dev/null) || INFO_COUNT=0
        RESULT_FAIL=$(grep -c 'ChatTest: Result: *FAIL' "$LOG_FILE" 2>/dev/null) || RESULT_FAIL=0
        RESULT_PASS=$(grep -c 'ChatTest: Result: *PASS' "$LOG_FILE" 2>/dev/null) || RESULT_PASS=0

        # Check for crash indicators
        if grep -qE 'free\(\): invalid|SIGSEGV|SIGABRT|Segmentation fault|heap-buffer-overflow|double free' "$LOG_FILE" 2>/dev/null; then
            CRASH_DETECTED=1
        fi
    fi

    # Determine variant result
    local VARIANT_PASS=true
    local VARIANT_STATUS="PASS"

    if [[ "$FAIL_COUNT" -gt 0 ]] || [[ "$RESULT_FAIL" -gt 0 ]]; then
        VARIANT_PASS=false
        VARIANT_STATUS="FAIL ($FAIL_COUNT failures)"
    fi

    if [[ "$GODOT_EXIT" -ne 0 ]]; then
        VARIANT_PASS=false
        VARIANT_STATUS="FAIL (exit code $GODOT_EXIT)"
    fi

    if [[ "$CRASH_DETECTED" -eq 1 ]]; then
        VARIANT_PASS=false
        VARIANT_STATUS="FAIL (crash detected)"
    fi

    if ! $VARIANT_PASS; then
        OVERALL_PASS=false
    fi

    RESULTS+=("$LABEL: $VARIANT_STATUS (pass=$PASS_COUNT fail=$FAIL_COUNT info=$INFO_COUNT)")

    echo ""
    echo "$LABEL result: $VARIANT_STATUS"

    # Show FAIL lines if any
    if [[ "$FAIL_COUNT" -gt 0 ]]; then
        echo "--- $LABEL FAIL details ---"
        grep 'ChatTest: .*FAIL' "$LOG_FILE" | head -20
        echo ""
    fi

    # Show PASS lines (useful for diagnosis)
    if [[ "$PASS_COUNT" -gt 0 ]]; then
        echo "--- $LABEL PASS summary (last 10) ---"
        grep 'ChatTest: .*PASS' "$LOG_FILE" | tail -10
        echo ""
    fi

    # Symlink latest log for this variant
    ln -sf "$(basename "$LOG_FILE")" "$LOG_DIR/chat-test-${LABEL,,}-latest.log"
}

# Run each variant
for variant in "${VARIANTS[@]}"; do
    IFS=: read -r LABEL TARGET_GAME MAP ASSET_DIR <<< "$variant"
    run_variant "$LABEL" "$TARGET_GAME" "$MAP" "$ASSET_DIR"
done

# Write overall summary
{
    echo "DM Chat Test Summary"
    echo "===================="
    echo "Date:     $(date)"
    echo "Duration: ${DURATION}s per variant"
    echo "Cycles:   $CYCLES per variant"
    echo ""
    for result in "${RESULTS[@]}"; do
        echo "  $result"
    done
    echo ""
    echo "Overall: $($OVERALL_PASS && echo "PASS" || echo "FAIL")"
} | tee "$SUMMARY_FILE"

echo ""
echo "========================================"
echo " OVERALL RESULTS"
echo "========================================"
for result in "${RESULTS[@]}"; do
    echo "  $result"
done
echo ""

if $OVERALL_PASS; then
    echo "RESULT: ALL PASS"
    exit 0
else
    echo "RESULT: FAIL (see per-variant details above)"
    exit 1
fi
