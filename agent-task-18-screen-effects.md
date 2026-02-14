# Agent Task 18: Screen Post-Processing Effects

## Objective
Implement screen-space visual effects: damage flash (red tint on hit), underwater colour tint, flash-bang white-out, and pain flinch view offset. These are driven by cgame state captured via the renderer stub.

## Files to Create (EXCLUSIVE)
- `code/godot/godot_screen_effects.cpp` — Screen effect manager
- `code/godot/godot_screen_effects.h` — Public API

## Implementation

### 1. Public API
```cpp
#ifdef __cplusplus
#include <godot_cpp/classes/canvas_layer.hpp>
#include <godot_cpp/classes/color_rect.hpp>
#include <godot_cpp/classes/camera3d.hpp>

void Godot_ScreenFX_Init(godot::Node *parent);
void Godot_ScreenFX_Update(float delta, godot::Camera3D *camera);
void Godot_ScreenFX_Shutdown(void);

// Trigger effects
void Godot_ScreenFX_DamageFlash(float intensity);     // 0.0-1.0
void Godot_ScreenFX_UnderwaterTint(bool active);
void Godot_ScreenFX_FlashBang(float intensity);
void Godot_ScreenFX_PainFlinch(float pitch_offset);   // radians
#endif
```

### 2. Damage Flash
- `CanvasLayer` (z_index = 100) with fullscreen `ColorRect`
- On trigger: Color(1.0, 0.0, 0.0, intensity * 0.4)
- Fade alpha to 0 over 0.3s
- Multiple hits stack (additive alpha, capped at 0.6)

### 3. Underwater Tint
- When active: persistent `ColorRect` with Color(0.0, 0.1, 0.3, 0.3)
- Slight sine-wave alpha oscillation (0.25–0.35 at 0.5 Hz) for ripple feel
- Toggle cleanly on/off

### 4. Flash-Bang
- On trigger: fullscreen white ColorRect, alpha from intensity
- Fade over 2.0s (slow recovery)
- Stacks with damage flash (separate ColorRect on same CanvasLayer)

### 5. Pain Flinch
- Apply temporary pitch rotation offset to camera
- Recover over 0.2s (smooth interpolation back to 0)
- Does NOT modify camera position, only rotation

### 6. Integration notes
- Engine sets `v_dmg_time`, `v_dmg_pitch`, `v_dmg_roll` in cgame
- These can be read through a C accessor from `cg_view.c` state (or detected via refdef changes)
- Underwater detected via `CG_PointContents()` returning CONTENTS_WATER near camera position
- For now: provide the API and document the integration point. MoHAARunner (integration agent) calls the trigger functions.

## Build Verification
```bash
cd openmohaa && scons platform=linux target=template_debug -j$(nproc) dev_build=yes
```

## Documentation
Append `## Phase 227: Screen Effects ✅` to `TASKS.md`.

## DO NOT MODIFY
- `MoHAARunner.cpp` / `MoHAARunner.h`
- `godot_renderer.c`
