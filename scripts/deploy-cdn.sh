#!/usr/bin/env bash
# deploy-cdn.sh — Generate manifests and sync game assets to a remote CDN.
#
# Uses rclone for upload, which supports Cloudflare R2, AWS S3, Google Cloud
# Storage, Azure Blob, and 40+ other backends. Configure your remote first:
#   rclone config   (interactive setup)
#
# Usage:
#   ./scripts/deploy-cdn.sh --source /path/to/game/assets --remote r2:mohaa-assets
#
# Options:
#   --source PATH        Local directory containing main/, mainta/, maintt/ (required)
#   --remote REMOTE      rclone remote destination, e.g. r2:bucket-name (required)
#   --dry-run            Preview changes without uploading
#   --skip-manifests     Don't regenerate manifest.json files
#   --game-dirs DIRS     Comma-separated game dirs (default: main,mainta,maintt)
#   --transfers N        Parallel upload threads (default: 16)
#   -h, --help           Show this help
#
# Examples:
#   # Cloudflare R2
#   ./scripts/deploy-cdn.sh --source ~/mohaa-assets --remote r2:mohaa-cdn
#
#   # AWS S3
#   ./scripts/deploy-cdn.sh --source ~/mohaa-assets --remote s3:mohaa-bucket
#
#   # Preview what would be uploaded
#   ./scripts/deploy-cdn.sh --source ~/mohaa-assets --remote r2:mohaa-cdn --dry-run
#
#   # Only upload main/ (skip expansion packs)
#   ./scripts/deploy-cdn.sh --source ~/mohaa-assets --remote r2:mohaa-cdn --game-dirs main
#
# Prerequisites:
#   - rclone (https://rclone.org/install/)
#   - python3 (for manifest generation)
#   - A configured rclone remote (run: rclone config)

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"

# --- Defaults ---
SOURCE=""
REMOTE=""
DRY_RUN=0
SKIP_MANIFESTS=0
GAME_DIRS="main,mainta,maintt"
TRANSFERS=16

# --- Colours ---
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
CYAN='\033[0;36m'
NC='\033[0m'

step() { echo -e "\n${CYAN}=== $1 ===${NC}"; }
ok()   { echo -e "${GREEN}✓ $1${NC}"; }
warn() { echo -e "${YELLOW}⚠ $1${NC}"; }
fail() { echo -e "${RED}✗ $1${NC}" >&2; exit 1; }

# --- Parse flags ---
while [[ $# -gt 0 ]]; do
    case "$1" in
        --source)          SOURCE="$2"; shift 2 ;;
        --remote)          REMOTE="$2"; shift 2 ;;
        --dry-run)         DRY_RUN=1; shift ;;
        --skip-manifests)  SKIP_MANIFESTS=1; shift ;;
        --game-dirs)       GAME_DIRS="$2"; shift 2 ;;
        --transfers)       TRANSFERS="$2"; shift 2 ;;
        -h|--help)
            sed -n '2,/^set -euo/{ /^set -euo/d; s/^# \?//p; }' "$0"
            exit 0 ;;
        *)
            echo "Unknown option: $1" >&2
            exit 1 ;;
    esac
done

# --- Validation ---
[[ -z "$SOURCE" ]] && fail "--source is required (path to game assets directory)"
[[ -z "$REMOTE" ]] && fail "--remote is required (rclone remote, e.g. r2:mohaa-cdn)"
[[ ! -d "$SOURCE" ]] && fail "Source directory not found: $SOURCE"
command -v rclone >/dev/null 2>&1 || fail "rclone not found. Install it: https://rclone.org/install/"
command -v python3 >/dev/null 2>&1 || fail "python3 not found (needed for manifest generation)"

# Parse game dirs into array
IFS=',' read -ra DIRS <<< "$GAME_DIRS"

# Verify at least one game directory exists
FOUND_ANY=0
for gd in "${DIRS[@]}"; do
    if [[ -d "$SOURCE/$gd" ]]; then
        FOUND_ANY=1
    fi
done
[[ "$FOUND_ANY" -eq 0 ]] && fail "No game directories found in $SOURCE (checked: ${GAME_DIRS})"

if [[ "$DRY_RUN" -eq 1 ]]; then
    warn "DRY RUN — no files will be uploaded"
fi

# =========================================================================
# Step 1: Generate manifests
# =========================================================================
if [[ "$SKIP_MANIFESTS" -eq 0 ]]; then
    step "Step 1/2: Generating manifests"

    for gd in "${DIRS[@]}"; do
        DIR="$SOURCE/$gd"
        if [[ ! -d "$DIR" ]]; then
            warn "Skipping $gd/ (not found)"
            continue
        fi

        echo "  Generating $gd/manifest.json ..."
        python3 -c "
import os, json, sys
base = sys.argv[1]
entries = []
for root, dirs, files in os.walk(base):
    dirs[:] = [d for d in dirs if d not in ('.wrangler', 'save')]
    for f in sorted(files):
        if f == 'manifest.json':
            continue
        if f.endswith('.partaa') or f.endswith('.partab'):
            continue
        full = os.path.join(root, f)
        rel = os.path.relpath(full, base)
        size = os.path.getsize(full)
        entries.append({'name': rel, 'size': size, 'type': 'file'})
entries.sort(key=lambda e: e['name'])
total_mb = sum(e['size'] for e in entries) / 1048576
with open(os.path.join(base, 'manifest.json'), 'w') as fh:
    json.dump(entries, fh, indent=1)
print(f'    -> {len(entries)} files, {total_mb:.1f} MB total')
" "$DIR"
    done
    ok "Manifests generated"
else
    step "Step 1/2: Skipping manifest generation (--skip-manifests)"
fi

# =========================================================================
# Step 2: Sync to CDN via rclone
# =========================================================================
step "Step 2/2: Syncing to CDN"

TOTAL_FILES=0
TOTAL_BYTES=0

for gd in "${DIRS[@]}"; do
    DIR="$SOURCE/$gd"
    if [[ ! -d "$DIR" ]]; then
        continue
    fi

    DEST="$REMOTE/$gd"
    echo -e "  ${CYAN}$gd/${NC} → $DEST"

    # Count files for progress reporting
    FILE_COUNT=$(find "$DIR" -type f \
        -not -path '*/.wrangler/*' \
        -not -path '*/save/*' \
        -not -name '*.partaa' \
        -not -name '*.partab' | wc -l)
    DIR_SIZE=$(du -sb "$DIR" 2>/dev/null | awk '{print $1}')
    DIR_SIZE_MB=$(( DIR_SIZE / 1048576 ))
    echo "    $FILE_COUNT files, ~${DIR_SIZE_MB} MB"

    TOTAL_FILES=$(( TOTAL_FILES + FILE_COUNT ))
    TOTAL_BYTES=$(( TOTAL_BYTES + DIR_SIZE ))

    # Build rclone args
    RCLONE_ARGS=(
        sync
        "$DIR"
        "$DEST"
        --transfers "$TRANSFERS"
        --checkers 32
        --progress
        --exclude '.wrangler/**'
        --exclude 'save/**'
        --exclude '*.partaa'
        --exclude '*.partab'
    )

    if [[ "$DRY_RUN" -eq 1 ]]; then
        RCLONE_ARGS+=(--dry-run)
    fi

    rclone "${RCLONE_ARGS[@]}"
    ok "$gd/ synced"
done

# =========================================================================
# Summary
# =========================================================================
TOTAL_MB=$(( TOTAL_BYTES / 1048576 ))
echo ""
echo -e "  ${GREEN}CDN sync complete${NC}"
echo "  Remote:     $REMOTE"
echo "  Game dirs:  ${GAME_DIRS}"
echo "  Files:      $TOTAL_FILES"
echo "  Size:       ~${TOTAL_MB} MB"
if [[ "$DRY_RUN" -eq 1 ]]; then
    echo ""
    warn "This was a dry run. Re-run without --dry-run to upload."
fi
echo ""
ok "CDN deployment complete"
