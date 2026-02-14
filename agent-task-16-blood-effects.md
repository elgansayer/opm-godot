# Agent Task 16: Blood & Gore Particle Effects

## Objective
Implement blood spray particles on hit, blood decal placement, and optional persistent blood pools.

## Files to Create (EXCLUSIVE)
- `code/godot/godot_blood_effects.cpp` — Blood particle system
- `code/godot/godot_blood_effects.h` — Public API

## Implementation

### 1. Blood Spray
```cpp
void Godot_Blood_SpawnSpray(const godot::Vector3 &position,
                            const godot::Vector3 &direction,
                            float intensity);  // 0.0-1.0 (headshot=1.0)
void Godot_Blood_Update(float delta);
void Godot_Blood_Clear(void);
```
- 8–20 dark-red particles (count scales with intensity)
- Billboard quads, 0.02–0.06m
- Velocity: spray along `direction` with random spread cone (±30°)
- Gravity: -9.8 m/s² (particles arc downward)
- Lifetime: 0.5–1.0s with alpha fade
- Colour: dark red Color(0.5, 0.0, 0.0) → Color(0.3, 0.0, 0.0) over lifetime
- Pool: max 128 active blood particles

### 2. Blood Decals
```cpp
void Godot_Blood_SpawnDecal(const godot::Vector3 &position,
                            const godot::Vector3 &normal,
                            float size);  // 0.1-0.5 metres
```
- Flat quad aligned to surface normal
- Dark red texture with alpha (or solid colour with noise)
- Stays visible for 30s then fades over 5s
- Max 64 active blood decals (oldest recycled first)
- Slight random rotation for variety

### 3. Material setup
- Blood particles: `StandardMaterial3D`, `TRANSPARENCY_ALPHA`, `BILLBOARD_ENABLED`
- Blood decals: `StandardMaterial3D`, `TRANSPARENCY_ALPHA`, no billboard, albedo=dark red

## Build Verification
```bash
cd openmohaa && scons platform=linux target=template_debug -j$(nproc) dev_build=yes
```

## Documentation
Append `## Phase 225: Blood Effects ✅` to `TASKS.md`.

## DO NOT MODIFY
- `MoHAARunner.cpp` / `MoHAARunner.h`
- Any other agent's files
