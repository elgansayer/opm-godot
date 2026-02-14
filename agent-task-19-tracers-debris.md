# Agent Task 19: Tracer Rendering & Debris System

## Objective
Implement bullet tracer stretched-quad rendering and breakable object debris with physics-like trajectories.

## Files to Create (EXCLUSIVE)
- `code/godot/godot_tracers.cpp` — Tracer + debris particle system
- `code/godot/godot_tracers.h` — Public API

## Implementation

### 1. Bullet Tracers
```cpp
void Godot_Tracer_Spawn(const godot::Vector3 &start,
                        const godot::Vector3 &end,
                        const godot::Color &colour,
                        float width);       // metres, typically 0.01-0.02
void Godot_Tracer_Update(float delta);
void Godot_Tracer_Clear(void);
```
- Stretched quad between start and end (not billboard — oriented along trajectory)
- Quad normal faces camera (compute from cross product of trajectory × camera_direction)
- Length: actual distance start↔end (typically 5-20m)
- Colour: yellow-white for standard, green for MG42, red for enemy — passed by caller
- Material: additive blending (`BLEND_MODE_ADD`), no depth write
- Lifetime: 0.08-0.15s (fast fade)
- Pool: max 64 active tracers

### 2. Debris System (func_breakable destruction)
```cpp
void Godot_Debris_Spawn(const godot::Vector3 &position,
                        int debris_type,     // 0=wood, 1=glass, 2=stone, 3=metal
                        int count,           // 3-12 pieces
                        float spread);       // initial velocity magnitude
void Godot_Debris_Update(float delta);
void Godot_Debris_Clear(void);
```
- Small box/slab MeshInstance3D pieces (random size 0.02–0.1m)
- Random outward velocity from origin + upward bias + gravity (-9.8 m/s²)
- Spin rotation during flight
- Material per type:
  - Wood: brown, roughness 0.8
  - Glass: transparent, roughness 0.1, metallic 0.2
  - Stone: grey, roughness 0.9
  - Metal: dark grey, metallic 0.7
- Fade out after 2s, recycle to pool
- Pool: max 128 active debris pieces

## Build Verification
```bash
cd openmohaa && scons platform=linux target=template_debug -j$(nproc) dev_build=yes
```

## Documentation
Append `## Phase 228: Tracers & Debris ✅` to `TASKS.md`.

## DO NOT MODIFY
- `MoHAARunner.cpp` / `MoHAARunner.h`
- Any other agent's files
