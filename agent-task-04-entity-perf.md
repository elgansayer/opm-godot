# Agent Task 04: Entity Rendering Performance — LOD, Caching, Lighting

## Objective
Dramatically improve entity rendering performance and quality: skeletal mesh LOD, per-entity mesh caching to eliminate redundant rebuilds, material caching, first-person weapon rendering via SubViewport, and dynamic entity lighting from lightgrid + dynamic lights.

## Starting Point
Read `.github/copilot-instructions.md`, `openmohaa/AGENTS.md`, and `openmohaa/TASKS.md`. Entity rendering currently works but rebuilds `ArrayMesh` every frame for every animated entity. `godot_skel_model.cpp/.h` handles TIKI→ArrayMesh conversion with CPU skinning. `godot_skel_model_accessors.cpp` provides C++ wrappers around engine TIKI data. `MoHAARunner.cpp::update_entities()` is the main entity update loop (~650 lines). An `EntityCacheKey` struct exists in `MoHAARunner.h` (Phase 37) but isn't yet used for actual caching.

## Scope — Phases 59–64, 85

### Phase 59: Entity LOD System
- `skelHeaderGame_t` has `lodIndex[10]` — maps camera distance thresholds to LOD levels
- `pCollapse` / `pCollapseIndex` in `skelHeaderGame_t` define progressive mesh vertex collapse
- Implement distance-based LOD selection: compute distance from camera to entity, select appropriate LOD
- Apply `pCollapse`/`pCollapseIndex` to reduce vertex/triangle count for distant entities
- Read existing LOD data via `godot_skel_model_accessors.cpp` — add new accessor functions as needed

### Phase 60: Per-Entity Mesh Caching
- Currently `update_entities()` calls skeletal mesh building every frame
- Implement a cache keyed on `(hModel, frame0, frame1, frame2, frame3, actionWeight, shaderRGBA)`
- Store built `ArrayMesh` in cache; only rebuild when key changes
- Use `std::unordered_map<EntityMeshCacheKey, Ref<ArrayMesh>>` with time-based eviction
- Benchmark: log frame time before/after with `OS::get_ticks_usec()`

### Phase 61: Material Cache System
- Currently materials are duplicated per entity per frame for tinting/alpha changes
- Cache `StandardMaterial3D` (or `ShaderMaterial` from Agent 2) per unique shader + RGBA combination
- Key: `(shader_handle, rgba[4], blend_mode)` → `Ref<Material>`
- Share materials across entities with identical appearance
- Eviction: LRU or frame-count-based cleanup

### Phase 62: Weapon Rendering via SubViewport
- First-person weapons (`RF_FIRST_PERSON` + `RF_DEPTHHACK`) currently use a depth-test disable hack
- Replace with proper SubViewport rendering:
  1. Create a `SubViewport` with its own `Camera3D` matching the main camera
  2. Render weapon entities into the SubViewport
  3. Composite the SubViewport over the main view using a `TextureRect` on a `CanvasLayer`
- This gives correct self-occlusion for complex weapon models
- Read the `RF_FIRST_PERSON` and `RF_DEPTHHACK` flags from `gr_entities[]` in `godot_renderer.c`

### Phase 63: Lightgrid Entity Lighting
- BSP lightgrid stores ambient + directed light at regular 3D grid positions
- `Godot_BSP_LightForPoint()` already exists (Phase 28) — returns ambient colour
- Sample lightgrid at each entity's world position
- Apply as entity material modulation: `material.albedo_color *= lightgrid_sample`
- Handle `RF_LIGHTING_ORIGIN` flag (use different position for lighting than rendering)

### Phase 64: Dynamic Lights on Entities
- `gr_dlights[64]` captures dynamic lights (muzzle flashes, explosions)
- For each entity, find the N closest dynamic lights
- Compute per-entity light contribution: `sum(dlight.color * attenuation(distance))`
- Apply as additional material modulation or use Godot `OmniLight3D` nodes
- Limit to 4 closest dlights per entity for performance

### Phase 85: Render Performance Audit
- Profile frame times with `OS::get_singleton()->get_ticks_usec()`
- Identify top 5 bottlenecks in entity rendering
- Batch static entities where possible (entities with no animation)
- Log per-frame statistics: mesh cache hits/misses, material cache hits/misses, draw calls
- Document findings and optimisation results

## Files You OWN (create or primarily modify)

### New files to create
| File | Purpose |
|------|---------|
| `code/godot/godot_mesh_cache.cpp` | Entity mesh caching — keyed ArrayMesh storage with eviction |
| `code/godot/godot_mesh_cache.h` | Cache API: `Godot_MeshCache_Get()`, `Godot_MeshCache_Put()`, `Godot_MeshCache_Flush()` |
| `code/godot/godot_entity_lighting.cpp` | Lightgrid sampling + dlight accumulation for entities |
| `code/godot/godot_entity_lighting.h` | Lighting API: `Godot_EntityLight_Sample()`, `Godot_EntityLight_Dlights()` |
| `code/godot/godot_weapon_viewport.cpp` | SubViewport weapon rendering manager |
| `code/godot/godot_weapon_viewport.h` | Weapon viewport API |

### Existing files you may modify
| File | What to change |
|------|----------------|
| `code/godot/godot_skel_model.cpp` | Add LOD vertex collapse implementation. **Add new functions — do not restructure existing `build_skel_mesh()`.** |
| `code/godot/godot_skel_model.h` | Add LOD-related function declarations |
| `code/godot/godot_skel_model_accessors.cpp` | Add accessors for LOD data (`lodIndex`, `pCollapse`, `pCollapseIndex`) |

## Files You Must NOT Touch
- `MoHAARunner.cpp` / `MoHAARunner.h` — do NOT modify. Document integration points.
- `godot_renderer.c` — do not modify. READ `gr_entities[]` and `gr_dlights[]` via existing accessors.
- `godot_shader_props.cpp/.h` — owned by Agent 2.
- `godot_bsp_mesh.cpp/.h` — owned by Agent 3.
- `godot_sound.c` — owned by Agent 1.
- `SConstruct` — auto-discovers new files.

## Architecture Notes

### Mesh Cache Key Design
```cpp
struct EntityMeshCacheKey {
    int hModel;
    // Animation state — 4 frame info slots
    struct FrameInfo {
        int index;
        float weight;
        float time;
    } frames[4];
    // LOD level
    int lodLevel;

    bool operator==(const EntityMeshCacheKey &o) const;
};

// Custom hash for unordered_map
struct EntityMeshCacheHash {
    size_t operator()(const EntityMeshCacheKey &k) const;
};
```

### Material Cache Key
```cpp
struct MaterialCacheKey {
    int shader_handle;
    uint8_t rgba[4];
    int blend_mode;
    bool operator==(const MaterialCacheKey &o) const;
};
```

### Weapon SubViewport Setup
```
Main scene tree:
  MoHAARunner (Node)
    game_world (Node3D)
      camera (Camera3D)           ← main camera
      entity_root (Node3D)        ← world entities
    weapon_viewport (SubViewport) ← NEW: weapon rendering
      weapon_camera (Camera3D)    ← copies main camera transform
      weapon_root (Node3D)        ← RF_FIRST_PERSON entities go here
    weapon_overlay (CanvasLayer)  ← NEW: composites weapon_viewport
      weapon_rect (TextureRect)   ← ViewportTexture from weapon_viewport
```

### Lightgrid Sampling
The existing `Godot_BSP_LightForPoint(float x, float y, float z, float *r, float *g, float *b)` takes id Tech 3 coordinates and returns ambient RGB. Your entity lighting module should:
1. Convert entity position from Godot coords back to id Tech 3 coords
2. Call `Godot_BSP_LightForPoint()`
3. Return the colour as a Godot `Color` for material modulation

## Integration Points
Document in TASKS.md **"MoHAARunner Integration Required"** sections:
1. In `update_entities()`: replace direct mesh building with `Godot_MeshCache_Get()` + `Godot_MeshCache_Put()`
2. In `update_entities()`: call `Godot_EntityLight_Sample()` for each entity's material colour
3. In `setup_3d_scene()`: create weapon SubViewport + overlay
4. In `update_entities()`: route `RF_FIRST_PERSON` entities to weapon viewport instead of main scene
5. In `_process()`: copy main camera transform to weapon camera each frame
6. Provide performance logging that can be toggled with a cvar or method

## Build & Test
```bash
cd openmohaa && rm -f .sconsign.dblite && scons platform=linux target=template_debug -j$(nproc) dev_build=yes
```

## Documentation
Add Phase entries (59–64, 85) to `openmohaa/TASKS.md`.

## Merge Awareness
- You exclusively own `godot_skel_model.cpp/.h` and `godot_skel_model_accessors.cpp`.
- Agent 2 (Shaders) provides material creation — your material cache should work with both `StandardMaterial3D` and `ShaderMaterial`.
- Agent 3 (BSP) owns `godot_bsp_mesh.cpp` which has `Godot_BSP_LightForPoint()` — you call it, don't modify it.
- Agent 10 (Integration) wires your caching/lighting into `MoHAARunner.cpp::update_entities()`.
- No other agent touches your files.
