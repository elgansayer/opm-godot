# /submodule-update — Update and sync git submodules

Update `godot-cpp` and `openmohaa` submodules to their latest upstream commits.

## Steps

1. Show current submodule status:
   ```bash
   git submodule status
   ```
2. Verify each submodule is on the correct branch:
   - `godot-cpp` should be on branch `4.2`
   - `openmohaa` should be on branch `godot`
3. If a submodule is on the wrong branch, warn the user and offer to fix it
4. Pull latest changes:
   ```bash
   git submodule update --remote --recursive
   ```
5. Show what changed (new commits pulled):
   ```bash
   git diff --submodule
   ```
6. Ask if the user wants to commit the submodule update:
   ```bash
   git add godot-cpp openmohaa
   git commit -m "chore: update submodules to latest"
   ```

## Notes

- After updating `openmohaa`, consider running `/clean-build` since SCons may miss transitive header dependencies
- The `openmohaa` submodule points to the `openmohaa-godot` fork, not upstream openmohaa
