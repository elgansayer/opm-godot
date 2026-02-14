# Agent Task 25: Draw Distance & Far Plane (cg_farplane)

## Objective
Implement Phase 83: map engine draw distance cvars to Godot Camera3D near/far planes. MOHAA uses `r_znear`, `r_zfar`, `cg_farplane`, and `cg_farplane_color` to control view distance and fog-out.

## Files to Create (EXCLUSIVE)
- `code/godot/godot_draw_distance.cpp` — Draw distance manager
- `code/godot/godot_draw_distance.h` — Public API
- `code/godot/godot_draw_distance_accessors.c` — C accessor for distance cvars

## Implementation

### 1. C accessor
```c
float Godot_DrawDistance_GetZNear(void);        // r_znear, default 4.0 (inches)
float Godot_DrawDistance_GetZFar(void);         // r_zfar, default 0 (auto)
float Godot_DrawDistance_GetFarplane(void);     // cg_farplane, 0=disabled
void  Godot_DrawDistance_GetFarplaneColor(float *r, float *g, float *b); // cg_farplane_color
int   Godot_DrawDistance_GetFarplaneCull(void); // farplane_cull, 1=cull beyond farplane
```

### 2. Draw distance manager
```cpp
void Godot_DrawDistance_Init(void);
void Godot_DrawDistance_Update(godot::Camera3D *camera,
                              godot::Environment *env);
```

### 3. Camera near/far
- `r_znear`: convert from inches to metres (÷39.37), set `camera->set_near()`
- `r_zfar`: if >0, convert and set `camera->set_far()`; if 0, use default 1000m
- `cg_farplane`: if >0, overrides r_zfar — set camera far plane to this distance (inches→metres)

### 4. Far plane fog
- When `cg_farplane > 0`:
  - Enable Environment fog
  - Set fog colour from `cg_farplane_color` (normalize from 0-1 range)
  - Set fog density so it reaches full opacity at the far plane distance
  - `env->set_fog_enabled(true)`
  - `env->set_fog_light_color(Color(r, g, b))`
  - `env->set_fog_density(calculated_density)`

### 5. Far plane culling
- When `farplane_cull = 1`: entities beyond the far plane distance should not be rendered
- Document this as an integration point: MoHAARunner should check distance before spawning entity MeshInstance3D nodes

### 6. Update frequency
- Poll cvars once per second (delta accumulator), not every frame

## Build Verification
```bash
cd openmohaa && scons platform=linux target=template_debug -j$(nproc) dev_build=yes
```

## Documentation
Append `## Phase 83: Draw Distance ✅` to `TASKS.md`.

## DO NOT MODIFY
- `MoHAARunner.cpp` / `MoHAARunner.h`
- `godot_weather.cpp` (Agent 3 owns weather fog)
