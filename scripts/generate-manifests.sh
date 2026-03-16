#!/usr/bin/env bash
# generate-manifests.sh — Generates manifest.json for each MOHAA game directory.
#
# The web VFS preloader uses these manifests to discover and download ALL files
# from the CDN (pk3s, sounds, music, videos, configs — everything the engine needs).
# Without a manifest, the preloader can only probe known pk3 filenames and ALL
# loose files (sounds, music, configs, scripts) will be missing.
#
# Usage:
#   ./scripts/generate-manifests.sh /path/to/mohaa-web-base-all
#   ./scripts/generate-manifests.sh /path/to/mohaa-web-base-all --game-dirs main,mainta
#
# This scans each game directory (main/, mainta/, maintt/) and creates a
# manifest.json listing every file with its relative name, size (bytes),
# and type (file/directory). Excludes:
#   - .wrangler/ cache directories
#   - .pk3.partaa / .pk3.partab split files
#   - save/ directories (player saves — not needed for web)
#   - manifest.json itself (avoid self-reference)

set -euo pipefail

GAME_DIRS="main,mainta,maintt"

if [[ $# -lt 1 ]]; then
    echo "Usage: $0 <base-directory> [--game-dirs main,mainta,maintt]"
    echo "  e.g. $0 /path/to/mohaa-web-base-all"
    exit 1
fi

BASE_DIR="$1"
shift

# Parse optional flags
while [[ $# -gt 0 ]]; do
    case "$1" in
        --game-dirs) GAME_DIRS="$2"; shift 2 ;;
        *) echo "Unknown option: $1" >&2; exit 1 ;;
    esac
done

if [[ ! -d "$BASE_DIR" ]]; then
    echo "Error: '$BASE_DIR' is not a directory"
    exit 1
fi

IFS=',' read -ra DIRS <<< "$GAME_DIRS"

for GAME_DIR in "${DIRS[@]}"; do
    DIR="$BASE_DIR/$GAME_DIR"
    if [[ ! -d "$DIR" ]]; then
        echo "Skipping $GAME_DIR/ (not found)"
        continue
    fi

    echo "Generating $GAME_DIR/manifest.json ..."

    # Find all files, excluding unwanted paths, collect name and size.
    # Uses python3 for reliable JSON generation (handles special chars in filenames).
    python3 -c "
import os, json, sys
base = sys.argv[1]
entries = []
for root, dirs, files in os.walk(base):
    # Skip excluded directories
    dirs[:] = [d for d in dirs if d not in ('.wrangler', 'save')]
    for f in sorted(files):
        if f == 'manifest.json':
            continue
        if f.endswith('.partaa') or f.endswith('.partab'):
            continue
        full = os.path.join(root, f)
        rel = os.path.relpath(full, base).replace(os.sep, '/')
        size = os.path.getsize(full)
        entries.append({'name': rel, 'size': size, 'type': 'file'})
entries.sort(key=lambda e: e['name'])
total_mb = sum(e['size'] for e in entries) / 1048576
with open(os.path.join(base, 'manifest.json'), 'w') as fh:
    json.dump(entries, fh, indent=1)
print(f'  \u2192 {len(entries)} files, {total_mb:.1f} MB total')
" "$DIR"
done

echo "Done. Deploy manifest.json files alongside game assets to your CDN."
