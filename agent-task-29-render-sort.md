# Agent Task 29: Transparent Surface Sort Order

## Objective
Implement Phases 251-254: correct back-to-front rendering order for transparent surfaces. idTech 3 sorts transparent surfaces by shader sort key, then by distance from camera. Without this, transparent surfaces render in wrong order causing visual artifacts.

## Files to Create (EXCLUSIVE)
- `code/godot/godot_render_sort.cpp` — Transparent surface sort system
- `code/godot/godot_render_sort.h` — Public API

## Implementation

### 1. Sort key system
The engine assigns `sort` values to shaders:
- 0: portal
- 2: opaque (default)
- 6: decal
- 8: see-through (fences, grates)
- 9: banner (flags, cloth)
- 12: underwater
- 14: blend0 (standard alpha blend)
- 15: blend1
- 16: additive (GL_ONE GL_ONE)

### 2. Public API
```cpp
struct SortableEntity {
    int entity_index;          // index in gr_entities[]
    float sort_key;            // shader sort value
    float camera_distance;     // squared distance from camera
    bool is_additive;          // BLEND_MODE_ADD detected
};

void Godot_RenderSort_Init(void);

// Sort entities for correct rendering order
void Godot_RenderSort_SortEntities(SortableEntity *entities,
                                   int count,
                                   const godot::Vector3 &camera_pos);

// Apply sort order to MeshInstance3D render priority
void Godot_RenderSort_ApplyPriority(godot::MeshInstance3D *mesh,
                                     float sort_key,
                                     float camera_distance);

void Godot_RenderSort_Shutdown(void);
```

### 3. Sorting algorithm
1. Group by opaque vs transparent (sort_key > 2 = transparent)
2. Opaque: render front-to-back (for early-z optimisation) — `render_priority = 0`
3. Transparent: render back-to-front (for correct blending) — `render_priority` computed from distance
4. Within same sort key: sort by distance from camera
5. Additive (sort_key 16): render after all other transparents

### 4. Godot render priority mapping
Godot's `render_priority` is an int (-128 to 127):
- Opaque surfaces: priority 0
- Transparent surfaces: map distance to priority range (1-100)
  - Furthest = lowest priority (renders first)
  - Nearest = highest priority (renders last)
- Additive: priority 101-127

### 5. Per-frame update
- Each frame: recalculate distances from camera for all transparent entities
- Update `render_priority` on MaterialOverride or BaseMaterial
- Only sort entities with `TRANSPARENCY_ALPHA` or `TRANSPARENCY_ALPHA_DEPTH_PRE_PASS`

### 6. Integration point
Document how MoHAARunner's `update_entities()` should call this:
1. After building entity list, call `Godot_RenderSort_SortEntities()`
2. For each entity, call `Godot_RenderSort_ApplyPriority(mesh, sort_key, distance)`

## Build Verification
```bash
cd openmohaa && scons platform=linux target=template_debug -j$(nproc) dev_build=yes
```

## Documentation
Append `## Phase 251: Transparent Sort Order ✅` to `TASKS.md`.

## DO NOT MODIFY
- `MoHAARunner.cpp` / `MoHAARunner.h`
- `godot_shader_material.cpp` (Agent 2 owns)
