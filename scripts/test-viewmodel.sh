#!/usr/bin/env bash
# test-viewmodel.sh — Automated viewmodel/NODRAW regression test
#
# Launches Godot with the TestViewmodel scene, captures structured
# diagnostic output from MoHAARunner's [VIEWMODEL-VALIDATE] and
# [FPS-DIAG] logging, and reports pass/fail.
#
# Prerequisites:
#   - Built libopenmohaa.so deployed to project/bin/
#   - Game assets in ~/.local/share/openmohaa/main/ (Pak0-6.pk3)
#   - godot in PATH (Godot 4.2+)
#
# Usage:
#   ./scripts/test-viewmodel.sh [--map=dm/mohdm1] [--duration=45]
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
LOG_FILE="$LOG_DIR/viewmodel-test-$(date +%Y%m%d-%H%M%S).log"
SUMMARY_FILE="$LOG_DIR/viewmodel-test-latest.summary"

# Defaults
MAP="dm/mohdm1"
DURATION=45

# Parse args
for arg in "$@"; do
    case "$arg" in
        --map=*) MAP="${arg#--map=}" ;;
        --duration=*) DURATION="${arg#--duration=}" ;;
        --help|-h)
            echo "Usage: $0 [--map=dm/mohdm1] [--duration=45]"
            exit 0
            ;;
    esac
done

# Setup
mkdir -p "$LOG_DIR"

echo "========================================"
echo " Viewmodel/NODRAW Regression Test"
echo "========================================"
echo "Map:       $MAP"
echo "Duration:  ${DURATION}s"
echo "Log:       $LOG_FILE"
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

# Run the test
echo "Launching Godot with TestViewmodel scene..."
echo ""

# Use timeout to enforce duration limit (add 15s buffer for startup/shutdown)
TIMEOUT_SECS=$((DURATION + 15))

set +e
timeout "$TIMEOUT_SECS" godot --path "$PROJECT_DIR" \
    res://TestViewmodel.tscn \
    -- --map="$MAP" --duration="$DURATION" \
    2>&1 | tee "$LOG_FILE"
GODOT_EXIT=$?
set -e

echo ""
echo "Godot exited with code: $GODOT_EXIT"
echo ""

# Analyse results
FAIL_COUNT=0
WARN_COUNT=0
INFO_COUNT=0
FPS_DIAG_COUNT=0
NODRAW_CHANGES=0

if [[ -f "$LOG_FILE" ]]; then
    FAIL_COUNT=$(grep -c '\[VIEWMODEL-VALIDATE\] FAIL' "$LOG_FILE" 2>/dev/null || echo 0)
    WARN_COUNT=$(grep -c '\[VIEWMODEL-VALIDATE\] WARN' "$LOG_FILE" 2>/dev/null || echo 0)
    INFO_COUNT=$(grep -c '\[VIEWMODEL-VALIDATE\] INFO' "$LOG_FILE" 2>/dev/null || echo 0)
    FPS_DIAG_COUNT=$(grep -c '\[FPS-DIAG\]' "$LOG_FILE" 2>/dev/null || echo 0)
    NODRAW_CHANGES=$(grep -c '\[FPS-DIAG\] CHANGE' "$LOG_FILE" 2>/dev/null || echo 0)
fi

# Write summary
cat > "$SUMMARY_FILE" <<EOF
Viewmodel Test Summary
======================
Date:            $(date)
Map:             $MAP
Duration:        ${DURATION}s
Godot exit code: $GODOT_EXIT

VIEWMODEL-VALIDATE:
  FAIL:  $FAIL_COUNT
  WARN:  $WARN_COUNT
  INFO:  $INFO_COUNT

FPS-DIAG:
  Total lines:    $FPS_DIAG_COUNT
  NODRAW changes: $NODRAW_CHANGES

Overall: $([ "$FAIL_COUNT" -eq 0 ] && [ "$GODOT_EXIT" -eq 0 ] && echo "PASS" || echo "FAIL")
EOF

# Print summary
echo "========================================"
echo " TEST RESULTS"
echo "========================================"
cat "$SUMMARY_FILE"
echo "========================================"
echo ""

# Show FAIL lines if any
if [[ "$FAIL_COUNT" -gt 0 ]]; then
    echo "--- FAIL details ---"
    grep '\[VIEWMODEL-VALIDATE\] FAIL' "$LOG_FILE" | head -20
    echo ""
fi

# Show WARN lines if any
if [[ "$WARN_COUNT" -gt 0 ]]; then
    echo "--- WARN details ---"
    grep '\[VIEWMODEL-VALIDATE\] WARN' "$LOG_FILE" | head -10
    echo ""
fi

# Show FPS-DIAG changes (surface transitions)
if [[ "$NODRAW_CHANGES" -gt 0 ]]; then
    echo "--- Surface state changes ---"
    grep '\[FPS-DIAG\] CHANGE' "$LOG_FILE" | head -20
    echo ""
fi

# Show INFO health summaries
if [[ "$INFO_COUNT" -gt 0 ]]; then
    echo "--- Health summaries (last 10) ---"
    grep '\[VIEWMODEL-VALIDATE\] INFO' "$LOG_FILE" | tail -10
    echo ""
fi

# Symlink latest log
ln -sf "$(basename "$LOG_FILE")" "$LOG_DIR/viewmodel-test-latest.log"

# Exit
if [[ "$FAIL_COUNT" -gt 0 ]] || [[ "$GODOT_EXIT" -ne 0 ]]; then
    echo "RESULT: FAIL ($FAIL_COUNT validation failures, exit code $GODOT_EXIT)"
    echo "Full log: $LOG_FILE"
    exit 1
else
    echo "RESULT: PASS (0 failures, $WARN_COUNT warnings)"
    echo "Full log: $LOG_FILE"
    exit 0
fi
