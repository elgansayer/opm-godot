# Agent Task 20: Surface-Specific Effect Data Tables

## Objective
Create centralised data tables mapping engine surface types to complete effect descriptions (particle parameters, decal textures, sound aliases). This is the lookup database other VFX modules query when they need "what effect does surface X produce?".

## Files to Create (EXCLUSIVE)
- `code/godot/godot_surface_fx_data.cpp` — Surface effect data tables
- `code/godot/godot_surface_fx_data.h` — Struct definitions + query API

## Implementation

### 1. Surface type enum (mirrors engine's surfaceType_t)
```cpp
enum SurfaceFXType {
    SFX_DEFAULT = 0,
    SFX_METAL,
    SFX_WOOD,
    SFX_STONE,
    SFX_DIRT,
    SFX_GRASS,
    SFX_MUD,
    SFX_WATER,
    SFX_GLASS,
    SFX_GRAVEL,
    SFX_SAND,
    SFX_FOLIAGE,
    SFX_SNOW_SURFACE,
    SFX_CARPET,
    SFX_FLESH,
    SFX_COUNT
};
```

### 2. Complete effect descriptor
```cpp
struct SurfaceFXEntry {
    // Impact particles
    int impact_particle_count;       // 5-30
    float impact_velocity_min;       // m/s
    float impact_velocity_max;
    float impact_lifetime;           // seconds
    float impact_size;               // quad size
    float impact_color_r, impact_color_g, impact_color_b, impact_color_a;
    float impact_gravity;            // -9.8 for arcing, 0 for floating

    // Impact decal
    const char *decal_texture;       // VFS path or NULL
    float decal_size_min;            // metres
    float decal_size_max;
    float decal_lifetime;            // 0 = permanent

    // Footstep
    const char *footstep_sound;      // sound alias
    float footstep_volume;           // 0-1

    // Bullet impact sound
    const char *impact_sound;        // sound alias

    // Debris type (for breakable objects)
    int debris_type;                 // matches Godot_Debris_Spawn type enum
};
```

### 3. Query API
```cpp
const SurfaceFXEntry *Godot_SurfaceFX_Get(SurfaceFXType type);
SurfaceFXType Godot_SurfaceFX_FromEngineFlags(int surface_flags);
```

### 4. Populate ALL entries
Fill in realistic values for all 15 surface types based on MOHAA's visual style:
- Metal: bright sparks, metallic ping sound
- Wood: brown splinters, thud sound
- Stone: grey dust + chips, crack sound
- Dirt: brown puff, soft thud
- Grass: green particles + dirt, muffled thud
- Water: white splash droplets, splash sound
- Glass: transparent shards, tinkle sound
- Flesh: red spray, wet impact sound
- etc.

## Build Verification
```bash
cd openmohaa && scons platform=linux target=template_debug -j$(nproc) dev_build=yes
```

## Documentation
Append `## Phase 231: Surface Effect Data Tables ✅` to `TASKS.md`.

## DO NOT MODIFY
- `MoHAARunner.cpp` / `MoHAARunner.h`
- Any VFX agent files (they READ this data, not the reverse)
