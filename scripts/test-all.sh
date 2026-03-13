#!/usr/bin/env bash
# test-all.sh — Build, deploy, and run ALL automated tests.
#
# Sequence:
#   1. Build libopenmohaa.so + libcgame.so (incremental)
#   2. Deploy to project/bin/ and ~/.local/share/openmohaa/main/
#   3. Run headless smoke test (no display required)
#   4. Run viewmodel/NODRAW regression test (needs display + game assets)
#   5. Run resolution/HUD scaling test (needs display + game assets)
#   6. Print unified summary
#
# Usage:
#   ./scripts/test-all.sh                     # Run all tests
#   ./scripts/test-all.sh --skip-build        # Skip build step
#   ./scripts/test-all.sh --headless-only     # Only headless smoke test
#   ./scripts/test-all.sh --map=dm/mohdm6     # Override test map
#   ./scripts/test-all.sh --no-clean          # Incremental build (default)
#   ./scripts/test-all.sh --clean             # Full clean + rebuild
#
# Prerequisites:
#   - godot in PATH (Godot 4.2+)
#   - scons, gcc/g++, bison, flex, zlib
#   - Game assets in ~/.local/share/openmohaa/main/ (for viewmodel + resolution tests)
#   - A display server for viewmodel + resolution tests (or use xvfb-run)
#
# Exit codes:
#   0  All tests passed
#   1  One or more tests failed
#   2  Build/setup error

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
OPENMOHAA_DIR="$REPO_ROOT/openmohaa"
PROJECT_DIR="$REPO_ROOT/project"
LOG_DIR="$REPO_ROOT/test-results"
SUMMARY_FILE="$LOG_DIR/test-all-latest.summary"

# Defaults
SKIP_BUILD=false
HEADLESS_ONLY=false
DO_CLEAN=false
MAP="dm/mohdm1"
VIEWMODEL_DURATION=45
RESOLUTION_DURATION=180
RESOLUTION_SETTLE=3

# Parse args
for arg in "$@"; do
    case "$arg" in
        --skip-build)     SKIP_BUILD=true ;;
        --headless-only)  HEADLESS_ONLY=true ;;
        --clean)          DO_CLEAN=true ;;
        --no-clean)       DO_CLEAN=false ;;
        --map=*)          MAP="${arg#--map=}" ;;
        --help|-h)
            head -25 "$0" | grep '^#' | sed 's/^# \?//'
            exit 0
            ;;
    esac
done

mkdir -p "$LOG_DIR"

# ─── Colours ───
if [[ -t 1 ]]; then
    RED=$'\033[0;31m'; GREEN=$'\033[0;32m'; YELLOW=$'\033[0;33m'
    BOLD=$'\033[1m'; RESET=$'\033[0m'
else
    RED=''; GREEN=''; YELLOW=''; BOLD=''; RESET=''
fi

TOTAL=0
PASSED=0
FAILED=0
SKIPPED=0
declare -a RESULTS=()

run_test() {
    local name="$1"; shift
    local cmd=("$@")
    TOTAL=$((TOTAL + 1))
    echo ""
    echo "${BOLD}━━━ Test: ${name} ━━━${RESET}"
    echo "Command: ${cmd[*]}"
    echo ""

    local exit_code=0
    "${cmd[@]}" || exit_code=$?

    if [[ $exit_code -eq 0 ]]; then
        PASSED=$((PASSED + 1))
        RESULTS+=("${GREEN}PASS${RESET}  ${name}")
        echo "${GREEN}──── PASS: ${name} ────${RESET}"
    else
        FAILED=$((FAILED + 1))
        RESULTS+=("${RED}FAIL${RESET}  ${name} (exit ${exit_code})")
        echo "${RED}──── FAIL: ${name} (exit ${exit_code}) ────${RESET}"
    fi
    echo ""
}

skip_test() {
    local name="$1"
    local reason="$2"
    TOTAL=$((TOTAL + 1))
    SKIPPED=$((SKIPPED + 1))
    RESULTS+=("${YELLOW}SKIP${RESET}  ${name} — ${reason}")
    echo "${YELLOW}──── SKIP: ${name} — ${reason} ────${RESET}"
}

# ─── Step 0: Prerequisites ───
echo "${BOLD}══════════════════════════════════════${RESET}"
echo "${BOLD} mohaa-godot — Full Test Suite${RESET}"
echo "${BOLD}══════════════════════════════════════${RESET}"
echo "Repo:     $REPO_ROOT"
echo "Map:      $MAP"
echo "Date:     $(date)"
echo ""

if ! command -v godot &>/dev/null; then
    echo "ERROR: 'godot' not found in PATH" >&2
    exit 2
fi

if ! command -v scons &>/dev/null && [[ "$SKIP_BUILD" = false ]]; then
    echo "ERROR: 'scons' not found in PATH (needed for build)" >&2
    exit 2
fi

HAS_DISPLAY=false
if [[ -n "${DISPLAY:-}" ]] || [[ -n "${WAYLAND_DISPLAY:-}" ]]; then
    HAS_DISPLAY=true
fi

HAS_GAME_ASSETS=false
if [[ -d "$HOME/.local/share/openmohaa/main" ]]; then
    # Quick check for at least one pk3
    if ls "$HOME/.local/share/openmohaa/main/"*.pk3 >/dev/null 2>&1; then
        HAS_GAME_ASSETS=true
    fi
fi

HAS_SH_ASSETS=false
if [[ -d "$HOME/.local/share/openmohaa/mainta" ]]; then
    if ls "$HOME/.local/share/openmohaa/mainta/"*.pk3 >/dev/null 2>&1; then
        HAS_SH_ASSETS=true
    fi
fi

HAS_BT_ASSETS=false
if [[ -d "$HOME/.local/share/openmohaa/maintt" ]]; then
    if ls "$HOME/.local/share/openmohaa/maintt/"*.pk3 >/dev/null 2>&1; then
        HAS_BT_ASSETS=true
    fi
fi

HAS_DOCKER=false
if command -v docker &>/dev/null; then
    HAS_DOCKER=true
fi

HAS_NODE=false
if command -v node &>/dev/null && command -v npm &>/dev/null; then
    HAS_NODE=true
fi

echo "Display:  $(if $HAS_DISPLAY; then echo "yes"; else echo "no (viewmodel/resolution tests will be skipped)"; fi)"
echo "Assets:   $(if $HAS_GAME_ASSETS; then echo "yes (MOHAA)"; else echo "no (MOHAA assets missing)"; fi)"
echo "SH assets:$(if $HAS_SH_ASSETS; then echo " yes (Spearhead mainta/)"; else echo " no (Spearhead E2E will be skipped)"; fi)"
echo "BT assets:$(if $HAS_BT_ASSETS; then echo " yes (Breakthrough maintt/)"; else echo " no (Breakthrough E2E will be skipped)"; fi)"
echo "Docker:   $(if $HAS_DOCKER; then echo "yes"; else echo "no (web preflight will be skipped)"; fi)"
echo "Node:     $(if $HAS_NODE; then echo "yes"; else echo "no (web browser E2E will be skipped)"; fi)"
echo ""

# ─── Step 1: Build ───
if [[ "$SKIP_BUILD" = false ]]; then
    echo "${BOLD}━━━ Build ━━━${RESET}"
    if [[ "$DO_CLEAN" = true ]]; then
        echo "Cleaning build artefacts..."
        rm -rf "$OPENMOHAA_DIR/bin" "$OPENMOHAA_DIR/build" "$OPENMOHAA_DIR/.sconsign.dblite"
    fi

    echo "Building GDExtension (incremental)..."
    cd "$OPENMOHAA_DIR"

    # Generate parser sources if needed
    PARSER_DIR="code/parser/generated"
    if [[ ! -f "$PARSER_DIR/yyParser.hpp" ]]; then
        if command -v bison &>/dev/null && command -v flex &>/dev/null; then
            mkdir -p "$PARSER_DIR"
            bison --defines="$PARSER_DIR/yyParser.hpp" -o "$PARSER_DIR/yyParser.cpp" code/parser/bison_source.txt
            flex -Cem --nounistd -o "$PARSER_DIR/yyLexer.cpp" --header-file="$PARSER_DIR/yyLexer.h" code/parser/lex_source.txt
        fi
    fi

    JOBS=$(nproc 2>/dev/null || echo 4)
    if ! scons platform=linux target=template_debug -j"$JOBS" dev_build=yes 2>&1 | tee "$LOG_DIR/build.log"; then
        echo "${RED}BUILD FAILED${RESET}" >&2
        exit 2
    fi
    cd "$REPO_ROOT"

    echo "Build complete."
fi

# ─── Step 2: Deploy ───
echo "${BOLD}━━━ Deploy ━━━${RESET}"
mkdir -p "$PROJECT_DIR/bin"

if [[ -f "$OPENMOHAA_DIR/bin/libopenmohaa.so" ]]; then
    cp -f "$OPENMOHAA_DIR/bin/libopenmohaa.so" "$PROJECT_DIR/bin/libopenmohaa.so"
    echo "Deployed libopenmohaa.so → project/bin/"
else
    echo "ERROR: libopenmohaa.so not found in openmohaa/bin/" >&2
    exit 2
fi

if [[ -f "$OPENMOHAA_DIR/bin/libcgame.so" ]]; then
    mkdir -p "$HOME/.local/share/openmohaa/main"
    cp -f "$OPENMOHAA_DIR/bin/libcgame.so" "$HOME/.local/share/openmohaa/main/cgame.so"
    echo "Deployed libcgame.so → ~/.local/share/openmohaa/main/cgame.so"
fi
echo ""

# ─── Step 3: Run tests ───

# Test 1: Compilation check (already passed if we got here)
if [[ "$SKIP_BUILD" = false ]]; then
    # Build passed, record it
    TOTAL=$((TOTAL + 1)); PASSED=$((PASSED + 1))
    RESULTS+=("${GREEN}PASS${RESET}  Compilation (scons build)")
    echo "${GREEN}──── PASS: Compilation (scons build) ────${RESET}"
fi

# Test 2: Headless smoke test
run_test "Headless smoke test" \
    godot --path "$PROJECT_DIR" --headless --quit-after 8000

# Test 3: Web stack preflight
if [[ "$HAS_DOCKER" = false ]]; then
    skip_test "Web stack preflight" "Docker not available"
elif [[ "$HAS_GAME_ASSETS" = false ]]; then
    skip_test "Web stack preflight" "No game assets"
else
    run_test "Web stack preflight" \
        "$SCRIPT_DIR/test-web.sh"
fi

# Test 4: Web browser E2E
if [[ "$HAS_DOCKER" = false ]]; then
    skip_test "Web browser E2E" "Docker not available"
elif [[ "$HAS_NODE" = false ]]; then
    skip_test "Web browser E2E" "Node/npm not available"
elif [[ "$HAS_GAME_ASSETS" = false ]]; then
    skip_test "Web browser E2E" "No game assets"
else
    run_test "Web browser E2E" \
        "$SCRIPT_DIR/test-web-e2e.sh"
fi

# Test 4a: Web browser E2E — Spearhead
if [[ "$HAS_DOCKER" = false ]]; then
    skip_test "Web E2E — Spearhead" "Docker not available"
elif [[ "$HAS_NODE" = false ]]; then
    skip_test "Web E2E — Spearhead" "Node/npm not available"
elif [[ "$HAS_SH_ASSETS" = false ]]; then
    skip_test "Web E2E — Spearhead" "No Spearhead assets (mainta/)"
else
    run_test "Web E2E — Spearhead" \
        env COM_TARGET_GAME=1 TARGET_MAP=DM/MP_Bahnhof_DM \
        "$SCRIPT_DIR/test-web-e2e.sh"
fi

# Test 4b: Web browser E2E — Breakthrough
if [[ "$HAS_DOCKER" = false ]]; then
    skip_test "Web E2E — Breakthrough" "Docker not available"
elif [[ "$HAS_NODE" = false ]]; then
    skip_test "Web E2E — Breakthrough" "Node/npm not available"
elif [[ "$HAS_BT_ASSETS" = false ]]; then
    skip_test "Web E2E — Breakthrough" "No Breakthrough assets (maintt/)"
else
    run_test "Web E2E — Breakthrough" \
        env COM_TARGET_GAME=2 TARGET_MAP=DM/mp_bahnhof_dm \
        "$SCRIPT_DIR/test-web-e2e.sh"
fi

# Test 4c: Web E2E — Map transition (dm/mohdm1 -> dm/mohdm2)
if [[ "$HAS_DOCKER" = false ]]; then
    skip_test "Web E2E — Map transition" "Docker not available"
elif [[ "$HAS_NODE" = false ]]; then
    skip_test "Web E2E — Map transition" "Node/npm not available"
elif [[ "$HAS_GAME_ASSETS" = false ]]; then
    skip_test "Web E2E — Map transition" "No game assets"
else
    run_test "Web E2E — Map transition" \
        "$SCRIPT_DIR/test-map-transition-e2e.sh"
fi

# Test 5: Viewmodel/NODRAW regression
if [[ "$HEADLESS_ONLY" = true ]]; then
    skip_test "Viewmodel/NODRAW regression" "--headless-only flag"
elif [[ "$HAS_DISPLAY" = false ]]; then
    skip_test "Viewmodel/NODRAW regression" "No display server"
elif [[ "$HAS_GAME_ASSETS" = false ]]; then
    skip_test "Viewmodel/NODRAW regression" "No game assets"
else
    run_test "Viewmodel/NODRAW regression" \
        "$SCRIPT_DIR/test-viewmodel.sh" --map="$MAP" --duration="$VIEWMODEL_DURATION"
fi

# Test 6: Resolution/HUD scaling
if [[ "$HEADLESS_ONLY" = true ]]; then
    skip_test "Resolution/HUD scaling" "--headless-only flag"
elif [[ "$HAS_DISPLAY" = false ]]; then
    skip_test "Resolution/HUD scaling" "No display server"
elif [[ "$HAS_GAME_ASSETS" = false ]]; then
    skip_test "Resolution/HUD scaling" "No game assets"
else
    run_test "Resolution/HUD scaling" \
        "$SCRIPT_DIR/test-resolution.sh" --map="$MAP" --duration="$RESOLUTION_DURATION" --settle="$RESOLUTION_SETTLE"
fi

# ─── Summary ───
echo ""
echo "${BOLD}══════════════════════════════════════${RESET}"
echo "${BOLD} TEST SUMMARY${RESET}"
echo "${BOLD}══════════════════════════════════════${RESET}"
for r in "${RESULTS[@]}"; do
    echo "  $r"
done
echo ""
echo "Total: ${TOTAL}  Passed: ${GREEN}${PASSED}${RESET}  Failed: ${RED}${FAILED}${RESET}  Skipped: ${YELLOW}${SKIPPED}${RESET}"
echo ""

# Write plain-text summary
{
    echo "Test Suite Summary"
    echo "=================="
    echo "Date: $(date)"
    echo "Map:  $MAP"
    echo ""
    for r in "${RESULTS[@]}"; do
        # Strip ANSI codes for file output
        echo "$r" | sed 's/\x1b\[[0-9;]*m//g'
    done
    echo ""
    echo "Total: $TOTAL  Passed: $PASSED  Failed: $FAILED  Skipped: $SKIPPED"
    echo ""
    if [[ $FAILED -gt 0 ]]; then
        echo "OVERALL: FAIL"
    else
        echo "OVERALL: PASS"
    fi
} > "$SUMMARY_FILE"

echo "Summary written to: $SUMMARY_FILE"
echo ""

if [[ $FAILED -gt 0 ]]; then
    echo "${RED}OVERALL: FAIL${RESET}"
    exit 1
else
    echo "${GREEN}OVERALL: PASS${RESET}"
    exit 0
fi
