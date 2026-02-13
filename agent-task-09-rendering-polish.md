# Agent Task 09: Rendering Polish, Animation & Debug

## Objective
Implement remaining rendering features and polish: cinematic playback, shadow projection, gamma/overbright, draw distance, anti-aliasing, debug rendering options, animation blending, transparent surface sorting, additive blending, PVS/frustum culling, and final visual audit. This agent handles the "long tail" of rendering correctness.

## Starting Point
Read `.github/copilot-instructions.md`, `openmohaa/AGENTS.md`, and `openmohaa/TASKS.md`. Current rendering: BSP world with lightmaps, skeletal models, polys, swipes, terrain marks, fog, basic shader animation. Missing: cinematics, sorted transparency, animation blending, debug overlays, gamma correction, PVS culling, and various small rendering features.

## Scope — Phases 56, 79–84, 241–260

### Phase 56: Cinematic Playback Stub
- MOHAA uses RoQ video format for intro/cutscenes
- `CIN_PlayCinematic` / `CIN_StopCinematic` are currently stubbed
- Implement at minimum: detect cinematic start, show black screen + "skip" text, handle skip input
- Optional advanced: implement RoQ decoder reading frames from VFS
- The engine calls `SCR_DrawCinematic()` which invokes renderer's `DrawStretchRaw()` with pixel data
- `godot_renderer.c` has a `GR_DrawStretchRaw` stub — extend it to capture raw frame data if implementing decoder
- Display on `cin_layer` / `cin_rect` / `cin_texture` already set up in `MoHAARunner.h`

### Phase 79: Shadow Projection
- MOHAA uses projected shadow blobs (dark circles/ovals under entities)
- Mark fragment system (Phase 17) already handles decals on BSP surfaces
- Add shadow marks under player and NPC entities
- Project downward from entity origin, find ground surface via BSP trace
- Apply dark semi-transparent decal at ground contact point
- Handle shadow for all entity types with `RF_SHADOW` flag

### Phase 80: Lightmap Styles
- Some BSP versions support multiple lightmap styles per surface
- Switchable lights use style indices to toggle between light states
- Check if MOHAA BSPs use this feature (Quake 3 BSPs generally don't, but MOHAA is extended)
- If used: implement lightmap style switching via configstring or entity state

### Phase 81: Gamma / Overbright Correction
- Match MOHAA's gamma ramp: `r_gamma` cvar (default 1.0)
- Lightmaps are overbright: multiplied by 2 or 4 depending on `r_overbrightBits`
- Currently lightmaps use a fixed 2× multiply — verify this matches upstream
- Apply gamma correction via Godot's `Environment` tonemap settings
- Expose `r_gamma` as a Godot-side adjustment

### Phase 82: Anti-Aliasing & Texture Quality
- Map engine rendering cvars to Godot equivalents:
  - `r_picmip` → texture mipmap bias
  - `r_texturemode` → texture filtering (bilinear, trilinear, anisotropic)
  - `r_ext_texture_filter_anisotropic` → anisotropic level
- MSAA via Godot's `Viewport.msaa` property
- Expose quality settings through accessors

### Phase 83: Draw Distance / Far Plane
- `r_znear`, `r_zfar`, `farplane_cull` cvars
- Set Camera3D `near` and `far` from engine cvars
- `cg_farplane` and `cg_farplane_color` — per-map far plane with fog blending
- Already partially handled in `update_camera()` — verify correctness

### Phase 84: Debug Rendering Options
- `r_showtris` — wireframe overlay on world geometry
- `r_shownormals` — display surface normal vectors as lines
- `r_lockpvs` — freeze PVS cluster for debugging
- `r_speeds` — render statistics overlay (entity count, poly count, surface count, draw calls)
- Implement as toggleable overlays using Godot's debug draw or LineRenderer
- Read cvar state via C accessors

### Phases 241–250: Animation Polish
- **241:** Smooth animation blending between states (walk→run, idle→fire)
  - MOHAA uses bone weight blending between animation channels
  - `refEntity_t.frameInfo[4]` already captures multiple animation layers
  - Ensure blending weights (`actionWeight`) are applied correctly in `build_skel_mesh()`
- **242:** Animation event sounds (footsteps synced to walk cycle, gear rattling)
  - TIKI files define animation events (sound, effect triggers at specific frames)
  - Parse TIKI animation events and fire them at correct times
- **243:** Third-person weapon model animations (fire, reload, melee)
  - Weapon model attached to hand bone — verify attachment point transforms
- **244:** First-person reload animations
  - First-person weapon viewmodel animations (hand + weapon)
  - Verify frame indices map to correct animation sequences
- **245:** Death animation selection by damage type/direction
  - Different death animations for front/back/left/right/headshot
  - Selected by cgame based on damage direction
- **246:** Pain flinch animations (hit reactions while alive)
- **247:** Jump/land animations and transition states
- **248:** Prone transition animations (stand→prone, prone→stand)
- **249:** Ladder climbing animation
- **250:** Swimming animation

### Phases 251–260: Rendering Refinement
- **251:** Correct draw order for transparent surfaces
  - Sort transparent surfaces back-to-front from camera
  - Group by shader, then sort within shader group by distance
- **252:** Alpha-sorted entity rendering
  - Entities with alpha < 1.0 should render after opaque entities
  - Sort alpha entities by distance from camera
- **253:** Additive blending effects
  - Explosions, flares, energy effects use additive blending
  - Detect `blendFunc GL_ONE GL_ONE` (or similar) from shader properties
  - Apply via `StandardMaterial3D.blend_mode = BLEND_MODE_ADD`
- **254:** Fog interaction with transparent surfaces
  - Transparent surfaces should still be affected by fog
  - Apply fog colour blending in transparent material shaders
- **255:** Skybox rotation for time-of-day maps (if any MOHAA maps use this)
- **256:** Verify lightmap gamma across all stock maps
- **257:** BSP PVS culling
  - `Godot_BSP_InPVS()` currently returns `true` always
  - Implement actual PVS (Potentially Visible Set) lookup from BSP visdata
  - Cull BSP surfaces not in current PVS cluster
  - Significant performance improvement for indoor maps
- **258:** Frustum culling for entities and effects
  - Before processing each entity, check if its bounding box is in camera frustum
  - Use Godot's `Camera3D.is_position_in_frustum()` or manual frustum plane check
- **259:** Occlusion culling (optional)
  - Use Godot's built-in occlusion culling if beneficial
  - Mark large BSP brushes as occluders
- **260:** Final visual audit
  - Compare rendering output against upstream OpenMoHAA screenshots
  - Document remaining visual differences

## Files You OWN (create or primarily modify)

### New files to create
| File | Purpose |
|------|---------|
| `code/godot/godot_debug_render.cpp` | Debug overlays — wireframe, normals, stats, PVS visualisation |
| `code/godot/godot_debug_render.h` | Debug render API |
| `code/godot/godot_animation_events.cpp` | TIKI animation event parser + trigger system |
| `code/godot/godot_animation_events.h` | Animation event API |
| `code/godot/godot_shadow.cpp` | Shadow blob projection for entities |
| `code/godot/godot_shadow.h` | Shadow API |
| `code/godot/godot_render_sort.cpp` | Transparent surface and entity sorting |
| `code/godot/godot_render_sort.h` | Sort API |
| `code/godot/godot_pvs.cpp` | PVS cluster lookup and surface culling |
| `code/godot/godot_pvs.h` | PVS API |
| `code/godot/godot_render_accessors.c` | C accessors for render cvars (r_gamma, r_showtris, etc.) |

### Existing files you may modify
| File | What to change |
|------|----------------|
| `code/godot/godot_renderer.c` | Extend `GR_DrawStretchRaw` for cinematic frame capture. Add debug stat counters. **Only modify clearly marked sections.** |
| `code/godot/stubs.cpp` | Add cinematic function stubs if `CIN_*` functions are missing. **Only append new stubs.** |

## Files You Must NOT Touch
- `MoHAARunner.cpp` / `MoHAARunner.h` — do NOT modify. Document integration points.
- `godot_sound.c` — owned by Agent 1.
- `godot_shader_props.cpp/.h` — owned by Agent 2 (READ for blend mode detection).
- `godot_bsp_mesh.cpp/.h` — owned by Agent 3 (READ for fog volumes, surface data).
- `godot_skel_model*.cpp` — owned by Agent 4 (READ for animation data).
- `godot_client_accessors.cpp` — owned by Agent 5.
- `SConstruct` — auto-discovers new files.

## Architecture Notes

### PVS Implementation
```cpp
// PVS cluster lookup from BSP visdata
int Godot_PVS_GetCluster(float pos[3]);  // returns cluster index for position
bool Godot_PVS_ClusterVisible(int viewCluster, int testCluster);  // PVS check
void Godot_PVS_MarkVisible(int viewCluster, bool *surfaceVisible, int numSurfaces);
```

BSP visdata format: `int numClusters`, `int clusterBytes`, then `numClusters` rows of `clusterBytes` bits. Bit N of row C is set if cluster N is visible from cluster C.

### Transparent Sort Order
```
1. Render all opaque BSP surfaces (front-to-back for depth buffer fill)
2. Render all opaque entities
3. Sort transparent surfaces + entities by distance (back-to-front)
4. Render transparent in sorted order
5. Render additive blend (order-independent)
```

### Debug Rendering
```cpp
void Godot_Debug_Init(Node3D *root);
void Godot_Debug_Update(float delta);
void Godot_Debug_DrawWireframe(bool enable);    // r_showtris
void Godot_Debug_DrawNormals(bool enable);      // r_shownormals
void Godot_Debug_DrawStats(CanvasLayer *hud);   // r_speeds
void Godot_Debug_DrawPVS(int cluster);          // r_lockpvs
```

### Shadow Projection
```
For each entity with RF_SHADOW:
  1. Cast ray downward from entity origin: Godot_BSP_Trace(origin, origin - (0, 1000, 0))
  2. If hit ground: place shadow blob decal at hit point
  3. Shadow decal = dark circle texture, alpha-blended, aligned to surface normal
  4. Scale shadow based on entity-to-ground distance
```

## Integration Points
Document in TASKS.md **"MoHAARunner Integration Required"** sections:
1. `Godot_PVS_MarkVisible()` should be called in `check_world_load()` to pre-compute visibility
2. `Godot_PVS_GetCluster()` + cull should be called before BSP surface rendering
3. `Godot_Debug_Update()` should be called in `_process()`
4. `Godot_Shadow_Update()` should be called after `update_entities()`
5. `Godot_RenderSort_SortTransparent()` should be called before rendering transparent objects
6. Gamma/tonemap settings should be applied to `WorldEnvironment` in `setup_3d_scene()`
7. Animation events: `Godot_AnimEvent_Check(hModel, frame)` after entity animation update

## Build & Test
```bash
cd openmohaa && rm -f .sconsign.dblite && scons platform=linux target=template_debug -j$(nproc) dev_build=yes
```

## Documentation
Add Phase entries (56, 79–84, 241–260) to `openmohaa/TASKS.md`.

## Merge Awareness
- You own `godot_renderer.c` modifications (cinematic capture, debug counters) and `stubs.cpp` (new stubs only).
- Agent 2 (Shaders) owns shader parsing — you READ blend mode data for transparency sorting.
- Agent 3 (BSP) owns `godot_bsp_mesh.cpp` — you READ BSP data for PVS, but add PVS logic in your own new file.
- Agent 4 (Entity) owns skeletal model code — you READ animation data for animation events.
- Agent 6 (VFX) creates complementary effect spawning — your shadow/sort code is independent.
- **Shared file risk:** `godot_renderer.c` — you add cinematic capture + debug counters. Keep changes in clearly delineated `/* === AGENT 9: Cinematic Capture === */` sections. No other agent modifies this file.
- **Shared file risk:** `stubs.cpp` — you append new stubs only. No other agent modifies this file.
