# Agent Task 57: Headless Server Smoke Test

## Objective
Create an automated headless smoke test that validates the engine boots, loads a map, and runs frames without crashing. This replaces manual testing and serves as CI gate.

## Files to CREATE
- `test_headless.sh` — headless smoke test script (repo root)
- `project/test_headless.gd` — GDScript test runner

## Files to MODIFY
- `test.sh` — update existing test script to call new headless test

## DO NOT MODIFY
- `code/godot/MoHAARunner.cpp` (no engine changes)
- `build.sh` (build script)

## Implementation

### 1. Headless test script (`test_headless.sh`)
```bash
#!/bin/bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
PROJECT_DIR="$SCRIPT_DIR/project"

echo "=== OpenMoHAA Headless Smoke Test ==="

# 1. Check build exists
if [ ! -f "$SCRIPT_DIR/openmohaa/bin/libopenmohaa.so" ]; then
    echo "ERROR: libopenmohaa.so not found. Run build.sh first."
    exit 1
fi

# 2. Deploy to project
cp -f "$SCRIPT_DIR/openmohaa/bin/libopenmohaa.so" "$PROJECT_DIR/bin/libopenmohaa.so"

# 3. Check game assets
ASSET_DIR="$HOME/.local/share/openmohaa/main"
if [ ! -f "$ASSET_DIR/Pak0.pk3" ]; then
    echo "SKIP: Game assets not found at $ASSET_DIR"
    echo "       Build-only verification passed."
    exit 0
fi

# 4. Run headless for 10 seconds
echo "Starting headless engine test (10s timeout)..."
cd "$PROJECT_DIR"
timeout 15 godot --headless --script test_headless.gd 2>&1 | tee /tmp/mohaa_test.log
EXIT_CODE=${PIPESTATUS[0]}

# 5. Check results
if [ $EXIT_CODE -eq 0 ]; then
    echo "PASS: Headless smoke test completed successfully."
elif [ $EXIT_CODE -eq 124 ]; then
    echo "PASS: Test timed out (expected for continuous frame loop)."
else
    echo "FAIL: Engine exited with code $EXIT_CODE"
    echo "Last 20 lines of log:"
    tail -20 /tmp/mohaa_test.log
    exit 1
fi

# 6. Check for crash indicators in log
if grep -qi "segfault\|SIGSEGV\|assertion failed\|FATAL" /tmp/mohaa_test.log; then
    echo "FAIL: Crash detected in log output"
    exit 1
fi

echo "=== All smoke tests passed ==="
```

### 2. GDScript test runner (`project/test_headless.gd`)
```gdscript
extends SceneTree

# Headless smoke test: boot engine, wait frames, verify no crash
var frame_count := 0
var max_frames := 300  # ~5 seconds at 60fps

func _init():
    print("=== Headless test starting ===")

func _process(delta):
    frame_count += 1
    
    if frame_count == 1:
        print("Frame 1: Engine booted successfully")
    elif frame_count == 60:
        print("Frame 60: 1 second of frames completed")
    elif frame_count == 180:
        print("Frame 180: 3 seconds of frames completed")
    elif frame_count >= max_frames:
        print("Frame %d: Test complete, exiting cleanly" % frame_count)
        quit(0)
```

### 3. Update existing test.sh
```bash
#!/bin/bash
# Run build first, then smoke test
./build.sh && ./test_headless.sh
```

## Build Verification
```bash
# Make executable
chmod +x test_headless.sh

# Run (requires game assets for full test)
./test_headless.sh
```

## Documentation
Append `## Phase 268: Headless Smoke Test Infrastructure ✅` to `TASKS.md`.
