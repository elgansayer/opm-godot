# Agent Task 21: Shadow Blob Projection (RF_SHADOW)

## Objective
Implement shadow blob decals under entities that have the `RF_SHADOW` (0x0040) render flag. The engine projects a circular shadow downward from the entity origin onto the nearest ground surface.

## Files to Create (EXCLUSIVE)
- `code/godot/godot_shadow.cpp` — Shadow blob projection system
- `code/godot/godot_shadow.h` — Public API

## Implementation

### 1. Public API
```cpp
void Godot_Shadow_Init(godot::Node3D *parent);
void Godot_Shadow_UpdateAll(int entity_count); // call after entity update
void Godot_Shadow_Shutdown(void);
void Godot_Shadow_Clear(void);
```

### 2. Shadow blob rendering
- For each entity with `RF_SHADOW` (0x0040) in `gr_entities[]`:
  1. Perform downward raycast from entity origin (use Godot PhysicsDirectSpaceState3D or BSP trace via accessor)
  2. Place a dark circular decal quad at the hit point, aligned to surface normal
  3. Scale shadow radius based on entity bounding box (typically 0.5-1.5m)
  4. Distance fade: alpha decreases as entity-to-ground distance increases (full at 0m, zero at 5m)

### 3. Shadow decal implementation
- Flat `MeshInstance3D` quad (PlaneMesh, 1×1m, scaled per entity)
- `StandardMaterial3D`: albedo = black, `TRANSPARENCY_ALPHA`, alpha from distance calculation
- `no_depth_test = false`, `render_priority = -1` (render below other surfaces)
- Slight Y offset (+0.01m) to prevent z-fighting with ground
- Billboard disabled (aligned to surface)

### 4. Pool management
- Pool of 128 shadow quads
- Each frame: assign shadows to pool slots for visible RF_SHADOW entities
- Unused slots: `visible = false`

### 5. C accessor for RF_SHADOW detection
Add to `godot_shadow.cpp`:
```cpp
extern "C" {
    int Godot_Shadow_GetEntityFlags(int entity_index);
    void Godot_Shadow_GetEntityOrigin(int entity_index, float *origin);
}
```
These read from `gr_entities[]` — include `godot_renderer.h` in the .cpp file.

## Build Verification
```bash
cd openmohaa && scons platform=linux target=template_debug -j$(nproc) dev_build=yes
```

## Documentation
Append `## Phase 79: Shadow Projection ✅` to `TASKS.md`.

## DO NOT MODIFY
- `MoHAARunner.cpp` / `MoHAARunner.h`
- `godot_renderer.c` (only read data)
- `godot_entity_lighting.cpp` (Agent 4 owns)
