# Agent Task 15: Muzzle Flash & Shell Casing Effects

## Objective
Implement muzzle flash sprites with short-lived dynamic lights, and ejected shell casing models with physics-like trajectories.

## Files to Create (EXCLUSIVE)
- `code/godot/godot_weapon_effects.cpp` — Muzzle flash + shell casing system
- `code/godot/godot_weapon_effects.h` — Public API

## Implementation

### 1. Muzzle Flash
```cpp
void Godot_MuzzleFlash_Spawn(const godot::Vector3 &position,
                             const godot::Vector3 &direction,
                             float intensity);
void Godot_MuzzleFlash_Update(float delta);
```
- Billboard quad at muzzle position, facing camera
- Bright yellow-white texture (or solid colour), additive blending
- OmniLight3D: warm yellow, range ~3m, energy from `intensity`, 0.05s lifetime
- Pool: max 8 simultaneous flashes (weapons fire fast)
- Fade out over 0.05–0.1 seconds

### 2. Shell Casings
```cpp
void Godot_ShellCasing_Eject(const godot::Vector3 &position,
                             const godot::Vector3 &velocity,
                             int casing_type); // 0=pistol, 1=rifle, 2=shotgun
void Godot_ShellCasing_Update(float delta);
void Godot_ShellCasing_Clear(void);
```
- Small brass-coloured cylinder MeshInstance3D (0.01×0.005m for pistol, larger for rifle/shotgun)
- Parabolic arc: initial velocity (rightward + upward), gravity -9.8 m/s²
- Spin rotation during flight (random axis, ~720°/s)
- Bounce once off ground (reflect velocity × 0.3), then settle
- Fade out after 2s, recycle to pool
- Pool: max 32 active casings

### 3. Casing materials
- StandardMaterial3D, metallic=0.8, roughness=0.3, albedo=Color(0.72, 0.56, 0.3)
- Reuse single material for all casings of same type

## Build Verification
```bash
cd openmohaa && scons platform=linux target=template_debug -j$(nproc) dev_build=yes
```

## Documentation
Append `## Phase 224: Muzzle Flash & Shell Casings ✅` to `TASKS.md`.

## DO NOT MODIFY
- `MoHAARunner.cpp` / `MoHAARunner.h`
- Any other agent's files
