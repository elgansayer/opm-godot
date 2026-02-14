# Agent Task 12: VFX Manager Foundation & RT_SPRITE Pipeline

## Objective
Create the base VFX manager that converts `RT_SPRITE` entities from the engine's entity buffer into Godot particle/billboard quads. This is the foundation all other VFX agents build on.

## Context
The engine submits sprite entities via `GR_AddRefEntityToScene()` into `gr_entities[]` (captured by `godot_renderer.c`). Sprites have `reType == RT_SPRITE` and carry origin, rotation, radius, and shader handle. Currently `MoHAARunner::update_entities()` skips or renders them as placeholder cubes. This agent creates a proper sprite rendering pipeline.

## Files to Create (EXCLUSIVE — no other agent touches these)
- `code/godot/godot_vfx.cpp` — VFX manager: sprite pool, lifecycle, update
- `code/godot/godot_vfx.h` — Public API declarations
- `code/godot/godot_vfx_accessors.c` — C accessor to read RT_SPRITE entities from gr_entities[]

## Implementation Steps

### 1. `godot_vfx_accessors.c`
```c
// C accessor (can include renderer internals)
#include "godot_renderer.h"

int Godot_VFX_GetSpriteCount(void);
void Godot_VFX_GetSprite(int idx, float *origin, float *radius,
                         int *shaderHandle, float *rotation,
                         unsigned char *rgba);
```
- Iterate `gr_entities[0..gr_numentities-1]`, filter `reType == RT_SPRITE`
- Copy origin (3 floats), radius, shaderNum, rotation, shaderRGBA[4]

### 2. `godot_vfx.h`
```cpp
#ifndef GODOT_VFX_H
#define GODOT_VFX_H
#ifdef __cplusplus
#include <godot_cpp/classes/node3d.hpp>
void Godot_VFX_Init(godot::Node3D *parent);
void Godot_VFX_Update(float delta);
void Godot_VFX_Shutdown(void);
void Godot_VFX_Clear(void);  // on map change
#endif
#ifdef __cplusplus
extern "C" {
#endif
int Godot_VFX_GetSpriteCount(void);
void Godot_VFX_GetSprite(int idx, float *origin, float *radius,
                         int *shaderHandle, float *rotation,
                         unsigned char *rgba);
#ifdef __cplusplus
}
#endif
#endif
```

### 3. `godot_vfx.cpp`
- Pool of up to 512 `MeshInstance3D` billboard quads (camera-facing)
- Each frame: read sprites via accessor → assign to pool slots
- Billboard orientation: use `StandardMaterial3D::BILLBOARD_ENABLED`
- Transparency: `TRANSPARENCY_ALPHA`, apply `shaderRGBA` as albedo colour
- Radius → quad scale
- Shader texture → load via `Godot_VFS_ReadFile` + `Image::load_from_file` (reuse existing texture loading pattern from MoHAARunner)
- Shader name lookup via `Godot_Renderer_GetShaderName(handle)`
- Unused pool slots set `visible = false`
- `Godot_VFX_Clear()` hides all, called on map change

### 4. Coordinate conversion
- id Tech 3: X=Forward, Y=Left, Z=Up (inches)
- Godot: X=Right, Y=Up, -Z=Forward (metres)
- Scale: `origin / 39.37`, axes: `godot.x = -id.y, godot.y = id.z, godot.z = -id.x`

## Build Verification
```bash
cd openmohaa && scons platform=linux target=template_debug -j$(nproc) dev_build=yes
```
Both `bin/libopenmohaa.so` and `bin/libcgame.so` must link without errors.

## Documentation
Append a `## Phase 221: VFX Manager Foundation ✅` section to `TASKS.md` with task list and file inventory.

## DO NOT MODIFY
- `MoHAARunner.cpp` / `MoHAARunner.h` (owned by integration agents)
- `godot_renderer.c` (only read its data via accessor)
- Any files owned by other agents
