#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd -- "$SCRIPT_DIR/.." && pwd)"
ASSET_PATH="${ASSET_PATH:-$HOME/.local/share/openmohaa}"
BASE_URL="${BASE_URL:-http://127.0.0.1:8086}"
WEB_VARIANT="${WEB_VARIANT:-release}"

require_cmd() {
    local cmd="$1"
    if ! command -v "$cmd" >/dev/null 2>&1; then
        echo "ERROR: missing required command: $cmd" >&2
        exit 2
    fi
}

http_status() {
    local url="$1"
    local out
    out="$(curl -s --retry 20 --retry-all-errors --retry-connrefused --retry-delay 1 --max-time 10 -o /dev/null -w "%{http_code}" "$url" || true)"
    if [[ -z "$out" ]]; then
        out="000"
    fi
    echo "$out"
}

assert_status_200() {
    local url="$1"
    local code
    code="$(http_status "$url")"
    if [[ "$code" != "200" ]]; then
        echo "FAIL: expected 200 for $url, got $code" >&2
        exit 1
    fi
}

echo "[web-test] Preconditions"
require_cmd curl
require_cmd docker
require_cmd python3

if [[ ! -d "$ASSET_PATH/main" ]]; then
    echo "ERROR: ASSET_PATH '$ASSET_PATH' missing main/" >&2
    exit 2
fi

# Check pak availability case-insensitively so users with Pak*.pk3 naming are supported.
for n in 0 1 2 3 4 5 6; do
    if ! find "$ASSET_PATH/main" -maxdepth 1 -type f -iname "pak${n}.pk3" | grep -q .; then
        echo "ERROR: missing required pak${n}.pk3 in $ASSET_PATH/main" >&2
        exit 2
    fi
done

echo "[web-test] Building and starting web stack"
cd "$REPO_ROOT"
./scripts/build-web.sh --serve-only --asset-path "$ASSET_PATH" --"$WEB_VARIANT" >/tmp/opm-web-serve.log 2>&1 || {
    cat /tmp/opm-web-serve.log >&2
    exit 1
}

echo "[web-test] Validating HTTP endpoints"
# Give nginx a moment to finish start-up after compose returns.
assert_status_200 "$BASE_URL/mohaa.html"
assert_status_200 "$BASE_URL/mohaa.js"
assert_status_200 "$BASE_URL/main/cgame.so"

headers="$(curl -s --retry 20 --retry-all-errors --retry-connrefused --retry-delay 1 --max-time 10 -I "$BASE_URL/mohaa.html" || true)"
if [[ -z "$headers" ]]; then
    echo "FAIL: unable to fetch response headers from $BASE_URL/mohaa.html" >&2
    exit 1
fi
if ! grep -qi '^Cross-Origin-Opener-Policy: same-origin' <<<"$headers"; then
    echo "FAIL: missing COOP header" >&2
    exit 1
fi
if ! grep -qi '^Cross-Origin-Embedder-Policy: require-corp' <<<"$headers"; then
    echo "FAIL: missing COEP header" >&2
    exit 1
fi

echo "[web-test] Validating JSON asset directory listing"
json_payload="$(curl -s --retry 20 --retry-all-errors --retry-connrefused --retry-delay 1 --max-time 10 -H 'Accept: application/json' "$BASE_URL/assets/main/" || true)"
if [[ -z "$json_payload" ]]; then
    echo "FAIL: empty JSON payload from /assets/main/" >&2
    exit 1
fi

python3 - <<'PY' "$json_payload"
import json
import sys

payload = sys.argv[1]
try:
    data = json.loads(payload)
except Exception as exc:
    print(f"FAIL: /assets/main/ is not valid JSON: {exc}", file=sys.stderr)
    sys.exit(1)

if not isinstance(data, list):
    print("FAIL: /assets/main/ JSON is not a list", file=sys.stderr)
    sys.exit(1)

names = {str(item.get('name', '')).lower() for item in data if isinstance(item, dict)}
required = {f"pak{i}.pk3" for i in range(7)}
missing = sorted(required - names)
if missing:
    print("FAIL: /assets/main/ listing missing required pak files: " + ", ".join(missing), file=sys.stderr)
    sys.exit(1)

print("OK: /assets/main/ JSON listing includes pak0..pak6")
PY

echo "[web-test] PASS: web stack preflight checks succeeded"
