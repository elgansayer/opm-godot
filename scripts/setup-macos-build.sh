#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd -- "$SCRIPT_DIR/.." && pwd)"

ok() { echo "[OK] $*"; }
warn() { echo "[WARN] $*"; }
err() { echo "[ERROR] $*"; }

check_cmd() {
    local cmd="$1"
    local hint="$2"
    if command -v "$cmd" >/dev/null 2>&1; then
        ok "Found '$cmd'"
        return 0
    fi
    warn "Missing '$cmd' ($hint)"
    return 1
}

echo "=== macOS build preflight ==="
echo "Repo: $REPO_ROOT"
echo

HOST_UNAME="$(uname -s)"
echo "Host OS: $HOST_UNAME"
echo

MISSING=0
check_cmd python3 "required by SCons" || MISSING=1
check_cmd scons "required to build the GDExtension" || MISSING=1
check_cmd bison "parser generation" || MISSING=1
check_cmd flex "lexer generation" || MISSING=1

if [[ "$HOST_UNAME" == "Darwin" ]]; then
    echo
    echo "Checking native macOS toolchain..."
    if xcode-select -p >/dev/null 2>&1; then
        ok "Xcode Command Line Tools are installed"
    else
        err "Xcode Command Line Tools missing"
        echo "Run: xcode-select --install"
        MISSING=1
    fi

    check_cmd clang "provided by Xcode Command Line Tools" || MISSING=1
    check_cmd clang++ "provided by Xcode Command Line Tools" || MISSING=1

    echo
    if [[ "$MISSING" -eq 0 ]]; then
        ok "Native macOS build prerequisites satisfied"
        echo "Next step: ./build.sh macos"
    else
        err "Native macOS prerequisites are incomplete"
        exit 1
    fi
    exit 0
fi

echo
echo "Checking Linux -> macOS cross-compile prerequisites..."
if [[ -z "${OSXCROSS_ROOT:-}" ]]; then
    err "OSXCROSS_ROOT is not set"
    echo "Set it first, e.g.: export OSXCROSS_ROOT=/opt/osxcross"
    MISSING=1
else
    ok "OSXCROSS_ROOT=$OSXCROSS_ROOT"

    if [[ ! -d "$OSXCROSS_ROOT/target/bin" ]]; then
        err "Missing $OSXCROSS_ROOT/target/bin"
        MISSING=1
    else
        if compgen -G "$OSXCROSS_ROOT/target/bin/*apple-*-clang" >/dev/null; then
            ok "Found osxcross clang toolchain in $OSXCROSS_ROOT/target/bin"
            echo "Detected SDK tags from compiler names:"
            ls -1 "$OSXCROSS_ROOT/target/bin"/*-apple-*-clang 2>/dev/null \
                | sed -E 's#^.*/(x86_64|arm64)-apple-([^-]+)-clang$#\2#' \
                | sort -u \
                | sed 's/^/  - /'
        else
            err "No *apple-*-clang binaries found in $OSXCROSS_ROOT/target/bin"
            MISSING=1
        fi
    fi

    if [[ -d "$OSXCROSS_ROOT/target/SDK" ]]; then
        ok "SDK directory found: $OSXCROSS_ROOT/target/SDK"
    else
        warn "SDK directory not found at $OSXCROSS_ROOT/target/SDK"
        warn "If your SDK is elsewhere, pass macos_sdk_path=... to SCons"
    fi
fi

echo
if [[ "$MISSING" -eq 0 ]]; then
    ok "Cross-compile prerequisites look good"
    echo "Build Intel: ./build.sh macos arch=x86_64"
    echo "Build Apple Silicon: ./build.sh macos arch=arm64"
else
    err "Cross-compile prerequisites are incomplete"
    echo "Note: osxcross SDK provisioning requires manual setup due Apple SDK licensing."
    exit 1
fi
