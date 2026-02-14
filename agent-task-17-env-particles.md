# Agent Task 17: Environmental Particles (Dust, Embers, Leaves)

## Objective
Implement ambient environmental particle effects: dust motes in indoor areas, embers near fires, fireflies in night maps, and falling leaves in outdoor forest areas. These are spawned by BSP entity keys (`misc_particle_effects`, `func_emitter`) or hard-coded per-map ambience.

## Files to Create (EXCLUSIVE)
- `code/godot/godot_env_particles.cpp` — Environmental particle manager
- `code/godot/godot_env_particles.h` — Public API

## Implementation

### 1. Particle emitter types
```cpp
enum EnvParticleType {
    ENV_DUST_MOTES = 0,   // Indoor: small white specks, slow drift
    ENV_EMBERS,           // Near fire: orange sparks, upward drift
    ENV_FIREFLIES,        // Night: yellow glow, random wandering
    ENV_FALLING_LEAVES,   // Outdoor: green/brown, slow spiral descent
    ENV_SNOW_DUST,        // Cold areas: white specks, lateral drift
    ENV_COUNT
};
```

### 2. Emitter configuration struct
```cpp
struct EnvEmitterConfig {
    int particle_count;        // per emitter
    float spawn_radius;        // volume radius (metres)
    float particle_lifetime;   // seconds
    float particle_speed;      // m/s
    float particle_size;       // quad size (metres)
    Color colour_start;
    Color colour_end;
    godot::Vector3 drift_dir;  // primary drift direction
    bool use_billboard;
};
```

### 3. Population from BSP entities
```cpp
void Godot_EnvParticles_Init(godot::Node3D *parent);
void Godot_EnvParticles_SpawnEmitter(EnvParticleType type,
                                     const godot::Vector3 &position,
                                     float radius);
void Godot_EnvParticles_Update(float delta,
                               const godot::Vector3 &camera_pos);
void Godot_EnvParticles_Shutdown(void);
void Godot_EnvParticles_Clear(void);
```
- Each emitter: GPUParticles3D node (for high count) or manual MeshInstance3D pool (for low count ≤20)
- Only update/render emitters within 50m of camera (performance)
- Max 32 emitters, max 500 total particles

### 4. Default templates
- Dust motes: 30 particles, 3m radius, 4s life, 0.1 m/s upward drift, 0.005m, white α=0.3
- Embers: 20 particles, 2m radius, 2s life, 1.0 m/s upward, 0.01m, orange→red
- Fireflies: 10 particles, 5m radius, 3s life, random wander 0.5 m/s, 0.02m, yellow glow
- Leaves: 15 particles, 8m radius, 5s life, 0.3 m/s downward + lateral, 0.03m, green/brown

## Build Verification
```bash
cd openmohaa && scons platform=linux target=template_debug -j$(nproc) dev_build=yes
```

## Documentation
Append `## Phase 226: Environmental Particles ✅` to `TASKS.md`.

## DO NOT MODIFY
- `MoHAARunner.cpp` / `MoHAARunner.h`
- `godot_weather.cpp` / `godot_weather.h` (Agent 3 owns weather)
