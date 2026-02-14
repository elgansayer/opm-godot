# Agent Task 23: Lightmap Styles (Switchable Lights)

## Objective
Implement Phase 80: BSP lightmap styles. MOHAA maps can have multiple lightmap styles per surface (up to 4), controlled by configstrings. Light switches, flickering lights, and pulsing lights use alternate lightmap styles that the map compiler baked.

## Files to Create (EXCLUSIVE)
- `code/godot/godot_lightmap_styles.cpp` — Lightmap style manager
- `code/godot/godot_lightmap_styles.h` — Public API
- `code/godot/godot_lightmap_styles_accessors.c` — C accessor for configstring light state

## Implementation

### 1. BSP lightmap style data
Each BSP surface has `lightmapStyles[4]` (4 style indices). Style 0 = always on. Styles 1-63 = switchable. Style 255 = unused. The BSP data contains separate lightmap pixels for each active style. The final surface light = sum of all active style contributions.

### 2. C accessor for light state
```c
// Reads configstring CS_LIGHTS + style_index
// Returns current brightness for a given light style (0-255)
int Godot_LightStyle_GetValue(int style_index);
```
The engine updates light styles via `cl.lightstyles[i]` from configstrings. Flicker patterns are strings like "mmnmmommommnonmmonqnmmo" where a='0', z='26'.

### 3. Light style manager
```cpp
void Godot_LightStyles_Init(void);
void Godot_LightStyles_Update(float delta);  // poll current style values
void Godot_LightStyles_Shutdown(void);
float Godot_LightStyles_GetBrightness(int style_index); // 0.0-1.0
```
- Track 64 light styles
- Each frame: read style brightness from engine (via accessor)
- Interpolate between brightness steps for smooth transitions

### 4. Integration with BSP lightmaps
This module provides brightness multipliers. The integration agent applies them:
- For StandardMaterial3D: modulate lightmap texture brightness
- For ShaderMaterial: set `lightstyle_brightness` uniform
- Document the integration point for the integration agent

### 5. Default style patterns
Style 0 = always full brightness (1.0)
Style 1-10 = various flicker patterns (engine controls these)
Style 63 = off by default, toggled by trigger_light entity

## Build Verification
```bash
cd openmohaa && scons platform=linux target=template_debug -j$(nproc) dev_build=yes
```

## Documentation
Append `## Phase 80: Lightmap Styles ✅` to `TASKS.md`.

## DO NOT MODIFY
- `MoHAARunner.cpp` / `MoHAARunner.h`
- `godot_bsp_mesh.cpp` (Agent 3 owns BSP code)
- `godot_shader_material.cpp` (Agent 2 owns shader materials)
