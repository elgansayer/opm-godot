# Next Steps for OpenMoHAA GDExtension Debugging

## Immediate Tasks
1. **Resolve `FallingRock` Undefined Symbol**
   - Check if the declaration exists in `misc.cpp`. The symbol `_ZNK11FallingRock9classinfoEv` corresponds to `FallingRock::classinfo() const`, which should be declared using `CLASS_DECLARATION(Entity, FallingRock, ...)`. Ensure it is not commented out or guarded by an inactive macro.

2. **Verify Monolith Symbol Visibility**
   - Confirm that all game entities are being linked correctly in the monolithic build (`server`, `fgame`, `qcommon`, etc.). If `misc.cpp` compiles but the symbol is still missing, check if the methods for `FallingRock` are implemented.

3. **Godot Runtime Loop Verification**
   - Once the library loads successfully, re-run the Godot headless test:
     ```bash
     /home/elgan/.local/bin/godot --headless --path /home/elgan/dev/opm-godot/project --verbose --quit-after 100
     ```
   - Look for debug prints indicating successful initialization and integration.

4. **Headless Server Integration**
   - Implement the actual call to OpenMoHAA server frame logic inside `MoHAARunner::_process`. This will involve calling `Com_Frame` or an equivalent entry point to drive the game engine.
