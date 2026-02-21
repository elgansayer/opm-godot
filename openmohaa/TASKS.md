
## Phase 146: Impact Effects Integration ✅

Implemented impact effects (bullet holes, sparks, debris) by hooking into the client game's bullet trace logic and forwarding events to the Godot rendering backend.

- [x] **Task 146.1:** Modified `godot_impact_effects.h` and `.cpp` to expose a C-compatible `Godot_Impact_Spawn_C` function that handles coordinate conversion from id Tech 3 (Z-up inches) to Godot (Y-up meters).
- [x] **Task 146.2:** Extended `refexport_t` in `tr_public.h` with `AddImpact` hook.
- [x] **Task 146.3:** Extended `clientGameImport_t` in `cg_public.h` with `AddImpact` hook.
- [x] **Task 146.4:** Updated `cl_cgame.cpp` to map `cgi->AddImpact` to `re.AddImpact`.
- [x] **Task 146.5:** Implemented `GR_AddImpact` in `godot_renderer.c` to call the C++ impact spawner.
- [x] **Task 146.6:** Hooked `CG_MakeBulletHole` in `cg_parsemsg.cpp` to call `cgi.AddImpact` with surface flags and impact data.
- [x] **Task 146.7:** Integrated impact system lifecycle (Init/Update/Shutdown) into `MoHAARunner.cpp`.

### Key technical details (Phase 146):
- **Coordinate Conversion:** Performed in `Godot_Impact_Spawn_C`: `Godot.x = -id.y * SCALE`, `Godot.y = id.z * SCALE`, `Godot.z = -id.x * SCALE` where `SCALE = 1.0/39.37`.
- **Surface Mapping:** `Godot_Impact_SurfaceFromFlags` maps engine `SURF_*` flags to visual effect templates (metal sparks, wood chips, etc.).
- **Integration Point:** `CG_MakeBulletHole` captures all bullet impacts derived from server messages (`CGM_BULLET_*`). This ensures multiplayer and singleplayer impacts are visualized.
- **Safety:** All changes guarded by `#ifdef GODOT_GDEXTENSION` and module presence checks.

### Files modified (Phase 146):
- `code/godot/godot_impact_effects.h/cpp`
- `code/renderercommon/tr_public.h`
- `code/cgame/cg_public.h`
- `code/client/cl_cgame.cpp`
- `code/godot/godot_renderer.c`
- `code/cgame/cg_parsemsg.cpp`
- `code/godot/MoHAARunner.h/cpp`
