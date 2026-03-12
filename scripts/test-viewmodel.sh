#!/usr/bin/env bash
# test-viewmodel.sh — Automated viewmodel/NODRAW regression test
#
# Launches Godot with the TestViewmodel scene and reports pass/fail
# based on the scene's own ViewmodelTest: result output.
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
TEST_FAIL_LINES=0
TEST_PASS_LINES=0
TEST_RESULT_FAIL=0
TEST_RESULT_PASS=0

if [[ -f "$LOG_FILE" ]]; then
    # Note: use VAR=$(...) || VAR=0 pattern, NOT $( ... || echo 0).
    # grep -c outputs "0" with exit code 1 on no match; || echo 0 would
    # append another "0", giving "0\n0" which breaks arithmetic.
    TEST_FAIL_LINES=$(grep -c 'ViewmodelTest: .*FAIL' "$LOG_FILE" 2>/dev/null) || TEST_FAIL_LINES=0
    TEST_PASS_LINES=$(grep -c 'ViewmodelTest: .*PASS' "$LOG_FILE" 2>/dev/null) || TEST_PASS_LINES=0
    TEST_RESULT_FAIL=$(grep -c 'ViewmodelTest: Result: *FAIL' "$LOG_FILE" 2>/dev/null) || TEST_RESULT_FAIL=0
    TEST_RESULT_PASS=$(grep -c 'ViewmodelTest: Result: *PASS' "$LOG_FILE" 2>/dev/null) || TEST_RESULT_PASS=0
fi

# Write summary
cat > "$SUMMARY_FILE" <<EOF
Viewmodel Test Summary
======================
Date:            $(date)
Map:             $MAP
Duration:        ${DURATION}s
Godot exit code: $GODOT_EXIT

Test log markers:
    ViewmodelTest: FAIL lines:   $TEST_FAIL_LINES
    ViewmodelTest: PASS lines:   $TEST_PASS_LINES
    Result FAIL markers: $TEST_RESULT_FAIL
    Result PASS markers: $TEST_RESULT_PASS

Overall: $([ "$TEST_RESULT_FAIL" -eq 0 ] && [ "$GODOT_EXIT" -eq 0 ] && echo "PASS" || echo "FAIL")
EOF

# Print summary
echo "========================================"
echo " TEST RESULTS"
echo "========================================"
cat "$SUMMARY_FILE"
echo "========================================"
echo ""

# Show FAIL lines if any
if [[ "$TEST_FAIL_LINES" -gt 0 ]]; then
    echo "--- FAIL details ---"
    awk '/ViewmodelTest: .*FAIL/ { print; if (++n == 20) exit }' "$LOG_FILE"
    echo ""
fi

# Show PASS lines if any
if [[ "$TEST_PASS_LINES" -gt 0 ]]; then
    echo "--- PASS details (last 10) ---"
    grep 'ViewmodelTest: .*PASS' "$LOG_FILE" | tail -10
    echo ""
fi

# Symlink latest log
ln -sf "$(basename "$LOG_FILE")" "$LOG_DIR/viewmodel-test-latest.log"

# Exit
if [[ "$TEST_RESULT_FAIL" -gt 0 ]] || [[ "$GODOT_EXIT" -ne 0 ]]; then
    echo "RESULT: FAIL (scene reported fail or exit code $GODOT_EXIT)"
    echo "Full log: $LOG_FILE"
    exit 1
else
    echo "RESULT: PASS"
    echo "Full log: $LOG_FILE"
    exit 0
fi
