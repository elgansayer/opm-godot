#!/usr/bin/env bash
# test-resolution.sh — Automated resolution/mode/quality end-to-end test
#
# Launches Godot with the ResolutionTest scene, cycles through
# resolution × windowed/fullscreen × quality combinations, captures
# screenshots, and validates viewport dimensions + rendering properties.
#
# Prerequisites:
#   - Built libopenmohaa.so deployed to project/bin/
#   - Game assets in ~/.local/share/openmohaa/main/ (Pak0-6.pk3)
#   - godot in PATH (Godot 4.2+)
#   - A display server (cannot run headless — resolution tests need a window)
#
# Usage:
#   ./scripts/test-resolution.sh [--map=dm/mohdm1] [--duration=180] [--settle=3]
#
# Exit codes:
#   0  All checks passed
#   1  Validation failures detected
#   2  Setup/infrastructure error

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
PROJECT_DIR="$REPO_ROOT/project"
LOG_DIR="$REPO_ROOT/test-results"
LOG_FILE="$LOG_DIR/resolution-test-$(date +%Y%m%d-%H%M%S).log"
SUMMARY_FILE="$LOG_DIR/resolution-test-latest.summary"
SCREENSHOT_DIR="$LOG_DIR/resolution-screenshots-$(date +%Y%m%d-%H%M%S)"

# Defaults
MAP="dm/mohdm1"
DURATION=180
SETTLE=3

# Parse args
for arg in "$@"; do
    case "$arg" in
        --map=*) MAP="${arg#--map=}" ;;
        --duration=*) DURATION="${arg#--duration=}" ;;
        --settle=*) SETTLE="${arg#--settle=}" ;;
        --help|-h)
            echo "Usage: $0 [--map=dm/mohdm1] [--duration=180] [--settle=3]"
            exit 0
            ;;
    esac
done

# Setup
mkdir -p "$LOG_DIR"
mkdir -p "$SCREENSHOT_DIR"

echo "========================================"
echo " Resolution/Mode/Quality E2E Test"
echo "========================================"
echo "Map:       $MAP"
echo "Duration:  ${DURATION}s"
echo "Settle:    ${SETTLE}s per test case"
echo "Log:       $LOG_FILE"
echo "Shots:     $SCREENSHOT_DIR"
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

if [[ ! -d "$HOME/.local/share/openmohaa/main" ]]; then
    echo "WARNING: ~/.local/share/openmohaa/main/ not found. Test may fail to load map."
fi

# Headless check — resolution tests need a display
if [[ -z "${DISPLAY:-}" ]] && [[ -z "${WAYLAND_DISPLAY:-}" ]]; then
    echo "ERROR: No display server detected (DISPLAY/WAYLAND_DISPLAY unset)."
    echo "       Resolution tests require a window. Run inside a desktop session or via xvfb-run."
    exit 2
fi

# Run the test
echo "Launching Godot with ResolutionTest scene..."
echo ""

# Generous timeout: startup + map load + (N test cases × settle time) + buffer
TIMEOUT_SECS=$((DURATION + 30))

set +e
timeout "$TIMEOUT_SECS" godot --path "$PROJECT_DIR" \
    res://ResolutionTest.tscn \
    -- --map="$MAP" --duration="$DURATION" --settle="$SETTLE" \
       --outdir="$SCREENSHOT_DIR" \
    2>&1 | tee "$LOG_FILE"
GODOT_EXIT=$?
set -e

echo ""
echo "Godot exited with code: $GODOT_EXIT"
echo ""

# Analyse results
FAIL_COUNT=0
PASS_COUNT=0
WARN_COUNT=0
TOTAL_TESTS=0
SCREENSHOT_COUNT=0

if [[ -f "$LOG_FILE" ]]; then
    FAIL_COUNT=$(grep -c 'ResolutionTest: .*\[FAIL\]' "$LOG_FILE" 2>/dev/null) || FAIL_COUNT=0
    PASS_COUNT=$(grep -c 'ResolutionTest: .*\[PASS\]' "$LOG_FILE" 2>/dev/null) || PASS_COUNT=0
    WARN_COUNT=$(grep -c 'ResolutionTest: .*WARN:' "$LOG_FILE" 2>/dev/null) || WARN_COUNT=0
    TOTAL_TESTS=$((FAIL_COUNT + PASS_COUNT))
fi

# Count screenshots
if [[ -d "$SCREENSHOT_DIR" ]]; then
    SCREENSHOT_COUNT=$(find "$SCREENSHOT_DIR" -name '*.png' 2>/dev/null | wc -l)
fi

# Write summary
cat > "$SUMMARY_FILE" <<EOF
Resolution Test Summary
=======================
Date:            $(date)
Map:             $MAP
Duration limit:  ${DURATION}s
Settle time:     ${SETTLE}s
Godot exit code: $GODOT_EXIT

Test Results:
  Total:       $TOTAL_TESTS
  Passed:      $PASS_COUNT
  Failed:      $FAIL_COUNT
  Warnings:    $WARN_COUNT
  Screenshots: $SCREENSHOT_COUNT

Overall: $([ "$FAIL_COUNT" -eq 0 ] && [ "$GODOT_EXIT" -eq 0 ] && echo "PASS" || echo "FAIL")

Screenshots: $SCREENSHOT_DIR
Log: $LOG_FILE
EOF

# Copy GDScript-generated summary if present
if [[ -f "$SCREENSHOT_DIR/summary.txt" ]]; then
    echo "" >> "$SUMMARY_FILE"
    echo "--- GDScript Test Details ---" >> "$SUMMARY_FILE"
    cat "$SCREENSHOT_DIR/summary.txt" >> "$SUMMARY_FILE"
fi

# Print summary
echo "========================================"
echo " TEST RESULTS"
echo "========================================"
cat "$SUMMARY_FILE"
echo "========================================"
echo ""

# Show FAIL details
if [[ "$FAIL_COUNT" -gt 0 ]]; then
    echo "--- FAIL details ---"
    awk '/ResolutionTest: .*\[FAIL\]/ { print; if (++n == 20) exit }' "$LOG_FILE"
    echo ""
    awk '/ResolutionTest: .*FAIL:/ { print; if (++n == 20) exit }' "$LOG_FILE"
    echo ""
fi

# Show WARN details
if [[ "$WARN_COUNT" -gt 0 ]]; then
    echo "--- WARN details ---"
    awk '/ResolutionTest: .*WARN:/ { print; if (++n == 10) exit }' "$LOG_FILE"
    echo ""
fi

# List screenshots
if [[ "$SCREENSHOT_COUNT" -gt 0 ]]; then
    echo "--- Screenshots captured ---"
    find "$SCREENSHOT_DIR" -name '*.png' -exec ls -lh {} \; | sort
    echo ""

    # Check for dimension variety
    UNIQUE_SIZES=$(find "$SCREENSHOT_DIR" -name '*.png' -exec identify -format '%wx%h\n' {} \; 2>/dev/null | sort -u | wc -l) || UNIQUE_SIZES=0
    if [[ "$UNIQUE_SIZES" -gt 1 ]]; then
        echo "Screenshot sizes: $UNIQUE_SIZES unique dimensions (good — resolution changes worked)"
    elif [[ "$UNIQUE_SIZES" -eq 1 ]]; then
        echo "WARNING: All screenshots are the same size — resolution changes may not be effective"
    fi
    echo ""
fi

# Symlink latest log
ln -sf "$(basename "$LOG_FILE")" "$LOG_DIR/resolution-test-latest.log"

# Exit
if [[ "$FAIL_COUNT" -gt 0 ]] || [[ "$GODOT_EXIT" -ne 0 ]]; then
    echo "RESULT: FAIL ($FAIL_COUNT test failures, exit code $GODOT_EXIT)"
    echo "Full log: $LOG_FILE"
    exit 1
else
    echo "RESULT: PASS ($PASS_COUNT tests passed, $WARN_COUNT warnings)"
    echo "Full log: $LOG_FILE"
    exit 0
fi
