#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd -- "$SCRIPT_DIR/.." && pwd)"
IOS_EXPORT_DIR="${IOS_EXPORT_DIR:-$REPO_ROOT/project/bin/openmohaa_ios}"

if [[ ! -d "$IOS_EXPORT_DIR" ]]; then
    echo "INFO: iOS export directory not found at $IOS_EXPORT_DIR"
    echo "      Build/export first, then sign/provision with Xcode tooling."
    exit 0
fi

if ! command -v xcodebuild >/dev/null 2>&1; then
    echo "INFO: xcodebuild not found; skipping iOS signing/provisioning."
    echo "      Run this on macOS with Xcode installed."
    exit 0
fi

if [[ -z "${IOS_SCHEME:-}" || -z "${IOS_WORKSPACE:-}" ]]; then
    echo "INFO: IOS_SCHEME / IOS_WORKSPACE not set; skipping automated iOS signing."
    echo "      Export these env vars to enable xcodebuild archive/export steps."
    exit 0
fi

echo "Running iOS archive/export using Xcode"

xcodebuild \
    -workspace "$IOS_WORKSPACE" \
    -scheme "$IOS_SCHEME" \
    -configuration Release \
    archive

echo "iOS signing/provisioning command completed"
