#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd -- "$SCRIPT_DIR/.." && pwd)"
APK_PATH="${APK_PATH:-$REPO_ROOT/project/bin/openmohaa.apk}"

if [[ ! -f "$APK_PATH" ]]; then
    echo "INFO: Android artifact not found at $APK_PATH"
    echo "      Build/export first, then sign with your release keystore."
    exit 0
fi

if ! command -v apksigner >/dev/null 2>&1; then
    echo "INFO: apksigner not found; skipping Android signing."
    echo "      Install Android build-tools and run apksigner manually."
    exit 0
fi

if [[ -z "${ANDROID_KEYSTORE:-}" || -z "${ANDROID_KEY_ALIAS:-}" ]]; then
    echo "INFO: ANDROID_KEYSTORE / ANDROID_KEY_ALIAS not set; skipping signing."
    echo "      Export these env vars to enable automated signing."
    exit 0
fi

SIGNED_APK="${SIGNED_APK:-${APK_PATH%.apk}-signed.apk}"

apksigner sign \
    --ks "$ANDROID_KEYSTORE" \
    --ks-key-alias "$ANDROID_KEY_ALIAS" \
    --out "$SIGNED_APK" \
    "$APK_PATH"

echo "Android signing complete: $SIGNED_APK"
