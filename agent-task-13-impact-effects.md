# Agent Task 13: Impact Effects by Surface Type

## Objective
Create impact effect templates that spawn the correct particle burst, decal, and sound when a projectile/bullet hits a surface. The engine already classifies surfaces (metal, wood, stone, dirt, grass, water, glass, flesh) — this agent translates those into Godot-rendered particle effects.

## Context
The cgame code (`cg_marks.cpp`, `cg_effects.cpp`) submits impact polys and sprites via `RE_AddPolyToScene` and `RE_AddRefEntityToScene`. These arrive in `gr_polys[]` and `gr_entities[]`. This agent creates data tables mapping surface type → visual effect parameters, and a spawn function that creates the particles.

## Files to Create (EXCLUSIVE)
- `code/godot/godot_impact_effects.cpp` — Impact effect spawner + per-surface templates
- `code/godot/godot_impact_effects.h` — Public API

## Dependencies
- Requires Agent 12 (VFX Foundation) to provide `Godot_VFX_Init()` parent node
- If Agent 12 not merged, create a standalone `Node3D` parent and document the integration point

## Implementation Steps

### 1. Surface type enum (match engine's `surfaceType_t`)
```cpp
enum ImpactSurfaceType {
    IMPACT_DEFAULT = 0,
    IMPACT_METAL,
    IMPACT_WOOD,
    IMPACT_STONE,
    IMPACT_DIRT,
    IMPACT_GRASS,
    IMPACT_WATER,
    IMPACT_GLASS,
    IMPACT_FLESH,
    IMPACT_COUNT
};
```

### 2. Per-surface effect template struct
```cpp
struct ImpactTemplate {
    int particle_count;          // 5-30
    float particle_velocity;     // m/s
    float particle_lifetime;     // seconds
    Color particle_colour;       // start colour
    float particle_size;         // quad size in metres
    const char *decal_texture;   // e.g. "textures/decals/bullethole_metal"
    float decal_size;            // metres
    float decal_lifetime;        // seconds (0 = permanent)
};
```

### 3. Populate templates for all surface types
- Metal: 15 bright-orange sparks, fast velocity (8 m/s), short life (0.3s), small decal
- Wood: 10 brown splinters, medium velocity (4 m/s), 0.5s life, wood chip decal
- Stone: 12 grey chips, medium velocity (5 m/s), 0.4s, stone chip decal
- Dirt: 8 brown puffs, slow velocity (2 m/s), 0.6s, dirt mark decal
- Water: 20 white droplets, upward spread (3 m/s), 0.8s, no decal
- Glass: 15 white/transparent shards, fast (6 m/s), 0.4s, crack decal
- Flesh: 10 red particles, medium (3 m/s), 0.5s, blood splat decal

### 4. `Godot_Impact_Spawn()` function
```cpp
void Godot_Impact_Spawn(ImpactSurfaceType type,
                        const godot::Vector3 &position,
                        const godot::Vector3 &normal);
```
- Creates N `MeshInstance3D` quads at position, velocity randomised within a cone around normal
- Each particle: billboard material, alpha fade over lifetime
- Pool/recycle old particles (max 256 active impact particles)
- Decal: small MeshInstance3D aligned to surface normal

### 5. `Godot_Impact_Update(float delta)`
- Animate particle positions (velocity + gravity)
- Fade alpha over lifetime
- Remove expired particles (recycle to pool)

## Coordinate Convention
All positions and normals in Godot coordinates (converted before calling this API).

## Build Verification
```bash
cd openmohaa && scons platform=linux target=template_debug -j$(nproc) dev_build=yes
```

## Documentation
Append `## Phase 222: Impact Effects ✅` to `TASKS.md`.

## DO NOT MODIFY
- `MoHAARunner.cpp` / `MoHAARunner.h`
- `godot_vfx.cpp` / `godot_vfx.h` (Agent 12 owns those)
- `godot_renderer.c`, `godot_sound.c`
