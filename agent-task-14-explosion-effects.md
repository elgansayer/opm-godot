# Agent Task 14: Explosion & Camera Shake Effects

## Objective
Implement explosion visual effects (expanding fireball, smoke ring, debris chunks) and a camera shake API that other systems can trigger.

## Files to Create (EXCLUSIVE)
- `code/godot/godot_explosion_effects.cpp` — Explosion particle system + camera shake
- `code/godot/godot_explosion_effects.h` — Public API

## Implementation

### 1. Camera Shake API
```cpp
void Godot_CameraShake_Trigger(float intensity, float duration, float falloff_distance,
                               const godot::Vector3 &source_pos);
void Godot_CameraShake_Update(float delta, godot::Camera3D *camera);
void Godot_CameraShake_Clear(void);
```
- Intensity decays over duration (linear/exponential)
- Attenuation by distance from source_pos to camera
- Apply as random offset to camera transform (restored next frame)
- Multiple shakes stack additively (cap total offset to ±0.15m)

### 2. Explosion Effect
```cpp
void Godot_Explosion_Spawn(const godot::Vector3 &position, float radius, float intensity);
void Godot_Explosion_Update(float delta);
void Godot_Explosion_Clear(void);
```
- Phase 1 (0–0.2s): Expanding bright-orange fireball sphere (scale from 0 → radius)
- Phase 2 (0.1–0.8s): Dark smoke ring expanding outward, alpha fading
- Phase 3 (0–0.5s): 5-10 debris chunks flying outward in random directions with gravity
- Short-lived OmniLight3D (orange, 0.3s, intensity from parameter)
- Camera shake triggered automatically via the shake API
- Pool: max 16 simultaneous explosions

### 3. Debris chunks
- Small box MeshInstance3D (0.05–0.15m), dark grey/brown
- Parabolic arc (initial upward + outward velocity + gravity)
- Fade alpha over 1–2s, then recycle

## Build Verification
```bash
cd openmohaa && scons platform=linux target=template_debug -j$(nproc) dev_build=yes
```

## Documentation
Append `## Phase 223: Explosion Effects ✅` to `TASKS.md`.

## DO NOT MODIFY
- `MoHAARunner.cpp` / `MoHAARunner.h`
- Any other agent's files
