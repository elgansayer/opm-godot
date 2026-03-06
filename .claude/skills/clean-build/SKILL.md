# /clean-build — Deep clean and rebuild

Force a full clean of all build artifacts and SCons cache, then rebuild. Use this when builds behave unexpectedly or after editing widely-included headers like `qcommon.h`.

## Steps

1. Show what will be cleaned:
   ```bash
   ls -lah openmohaa/.sconsign.dblite 2>/dev/null
   ls openmohaa/bin/ 2>/dev/null
   ls project/bin/libopenmohaa.* project/bin/cgame.* 2>/dev/null
   ```
2. Run the clean:
   ```bash
   ./build.sh clean
   ```
3. Ask which platform to rebuild for (linux, windows, macos, web, all)
4. Run the build:
   ```bash
   ./build.sh <platform>
   ```
5. Verify the output artifacts exist in `project/bin/`

## When to use

- After editing widely-included headers (e.g., `qcommon.h`) — SCons sometimes misses transitive dependencies
- When getting strange linker errors or stale object files
- After updating submodules
