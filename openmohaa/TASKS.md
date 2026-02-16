
## Phase 146: Impact Effects Integration ✅

Implemented the missing "Impact effects per surface type" (metal sparks, wood splinters, dirt puffs, etc.) by connecting the engine's bullet impact events to the Godot-side impact effect system.

- [x] **Task 146.1:** Extended Renderer API (`refexport_t` in `tr_public.h`) with `AddImpactEffect`, guarded by `GODOT_GDEXTENSION`.
- [x] **Task 146.2:** Implemented `GR_AddImpactEffect` in `godot_renderer.c` which calls a new C-linkage wrapper `Godot_Impact_Spawn_C`.
- [x] **Task 146.3:** Added `Godot_Impact_Spawn_C` to `godot_impact_effects.cpp` to expose the C++ impact spawning logic to C code.
- [x] **Task 146.4:** Extended Client-Game API (`clientGameImport_t` in `cg_public.h`) with `AddImpactEffect`, guarded by `GODOT_GDEXTENSION`.
- [x] **Task 146.5:** Mapped `re.AddImpactEffect` to `cgi.AddImpactEffect` in `cl_cgame.cpp` (`CL_InitCGameDLL`).
- [x] **Task 146.6:** Triggered effects in CGame: Modified `CG_MakeBulletHole` in `cg_parsemsg.cpp` to call `cgi.AddImpactEffect` with the surface flags, impact position, and normal.

### Key technical details (Phase 146):
- **Data Flow:** `cg_parsemsg.cpp` (cgame) -> `cgi.AddImpactEffect` -> `re.AddImpactEffect` (renderer) -> `GR_AddImpactEffect` -> `Godot_Impact_Spawn_C` -> `Godot_Impact_Spawn` (Godot C++).
- **Surface Type:** The engine's `trace.surfaceFlags` are passed all the way to `Godot_Impact_SurfaceFromFlags` which maps `SURF_METAL`, `SURF_WOOD`, etc. to `ImpactSurfaceType`.
- **Visuals:** Uses the existing `godot_impact_effects.cpp` templates to spawn material-specific particles (quads with motion, gravity, fade) and decals.
- **Integration:** This runs *alongside* the legacy `CG_ImpactMark` / `sfxManager` calls, allowing modern GPU particles to augment or eventually replace the legacy effects.

### Files modified (Phase 146):
- `code/renderercommon/tr_public.h`
- `code/godot/godot_renderer.c`
- `code/godot/godot_impact_effects.cpp`
- `code/cgame/cg_public.h`
- `code/client/cl_cgame.cpp`
- `code/cgame/cg_parsemsg.cpp`
