# Agent Task 06: Visual Effects & Particles

## Objective
Implement the full MOHAA visual effects pipeline: particle system for smoke/fire/sparks/blood/debris, impact effects per surface type, explosion effects, muzzle flash, tracers, shell casings, screen effects (damage flash, underwater), and environmental particles. These effects are driven by cgame code that submits data through the renderer's entity/poly buffers.

## Starting Point
Read `.github/copilot-instructions.md`, `openmohaa/AGENTS.md`, and `openmohaa/TASKS.md`. The cgame module (`code/cgame/`) runs as `cgame.so` loaded via `dlopen`. It submits visual effects through the renderer API: `GR_AddRefEntityToScene` (entities), `GR_AddPolyToScene` (polys), and direct 2D commands. `godot_renderer.c` captures all of these into buffers. `MoHAARunner.cpp` reads these buffers each frame.

Current state: basic entity rendering, poly rendering, and swipe trails work. But the visual fidelity is minimal — particles appear as solid-coloured quads, there's no surface-type-specific impact handling, no screen effects, and no efficient particle batching.

## Scope — Phases 221–240

### Phase 221: Particle System Foundation
- Create a particle manager that converts cgame particle submissions into Godot particles
- cgame submits particles as refEntity_t (type `RT_SPRITE`) with position, radius, shader
- These arrive in `gr_entities[]` — identify sprite entities and route to particle system
- Use `GPUParticles3D` for high-count effects, `MeshInstance3D` quads for low-count
- Handle particle lifetime, fade-out, and cleanup

### Phase 222: Impact Effects
- Bullet impacts produce: decal (mark fragment), particle burst, sound
- Surface type is encoded in the trace result's `surfaceFlags` (metal, wood, stone, dirt, etc.)
- Create per-surface-type effect templates:
  - Metal: orange sparks, ricochet
  - Wood: splinters, dust
  - Stone/Concrete: chip fragments, dust puff
  - Dirt/Sand: dust cloud
  - Water: splash, ripple
  - Glass: shatter
  - Flesh: blood spray
- Map shader `surfaceparm` flags to effect types
- Provide `Godot_VFX_SpawnImpact(position, normal, surface_type)` API

### Phase 223: Explosion Effects
- Grenade, torpedo, satchel charge, artillery explosions
- Expanding fireball: sprite sequence or shader-animated sphere
- Smoke trail: rising from explosion point
- Debris chunks: RT_MODEL entities with physics-like motion
- Camera shake: apply shake offset to camera (expose shake API for integration)

### Phase 224: Muzzle Flash
- First-person and third-person weapon muzzle flash
- Flash sprite at barrel position (arrives as RT_SPRITE entity at weapon tag position)
- Short-lived OmniLight3D at flash position for dynamic illumination
- Shell casing ejection model at ejection port tag

### Phase 225: Blood & Gore Effects
- Hit confirmation blood spray (particles moving away from impact)
- Blood decals on nearby surfaces (mark fragments)
- Blood pooling on ground (optional)
- Death animation blood effects

### Phase 226: Environmental Particles
- Dust motes in sunbeams (volumetric light shafts — simplified as particles)
- Fireflies, embers from fires
- Falling leaves
- Map-specific ambient particles from entity configuration
- These may come as `misc_particle_effects` or `func_emitter` entities

### Phase 227: Screen Effects
- **Damage flash:** red tint overlay when player takes damage
  - Read damage state from client game state via accessor
  - Apply as a `ColorRect` on HUD CanvasLayer with fading alpha
- **Underwater:** blue/green tint + optional distortion
  - Detect underwater state from `PM_WATERTYPE` / viewcontents
- **Flash-bang / stun:** white screen flash with fade
- **Pain flinch:** momentary view offset on damage (done in camera update)

### Phase 228: Tracers
- Bullet tracers for automatic weapons (every Nth shot)
- Render as stretched quad between start and end positions
- Tracer colour varies by weapon type (orange, green for MG42, etc.)
- Short lifetime (~0.1s), move along bullet trajectory

### Phase 229: Shell Casings
- Brass/clip models ejected from weapons
- Simple physics: parabolic arc, bounce once on ground, fade out
- Use pooled MeshInstance3D nodes
- Different models per weapon type (pistol brass, rifle brass, shotgun shell)

### Phase 230: Debris System
- `func_breakable` entities produce debris on destruction
- Rubble, glass shards, wood splinters
- Simple downward arc physics
- Fade and cleanup after 2–3 seconds

### Phases 231–240: Surface-Specific Effect Templates
For each surface type, define a complete effect profile:
- Particle count, velocity, lifetime, colour, size
- Decal texture, decal size, decal lifetime
- Sound alias to play on impact
- Store as data tables for easy tuning

## Files You OWN (create or primarily modify)

### New files to create
| File | Purpose |
|------|---------|
| `code/godot/godot_vfx.cpp` | Main VFX manager — particle spawning, effect templates, pools |
| `code/godot/godot_vfx.h` | VFX API: `Godot_VFX_Init()`, `Godot_VFX_Update()`, `Godot_VFX_SpawnImpact()`, etc. |
| `code/godot/godot_particles.cpp` | Particle pool management — GPUParticles3D / MeshInstance3D pools |
| `code/godot/godot_particles.h` | Particle pool API |
| `code/godot/godot_screen_effects.cpp` | Screen overlay effects — damage flash, underwater, screen shake |
| `code/godot/godot_screen_effects.h` | Screen effects API |
| `code/godot/godot_vfx_accessors.c` | C accessors for cgame effect state (damage, underwater, surface flags) |

### Existing files you may modify
**None.** This is a purely additive agent — all work goes into new files.

## Files You Must NOT Touch
- `MoHAARunner.cpp` / `MoHAARunner.h` — do NOT modify.
- `godot_renderer.c` — READ entity/poly buffers only.
- `godot_sound.c` — owned by Agent 1.
- `godot_shader_props.cpp/.h` — owned by Agent 2.
- `godot_bsp_mesh.cpp/.h` — owned by Agent 3.
- `godot_skel_model*.cpp` — owned by Agent 4.
- `godot_client_accessors.cpp` — owned by Agent 5.
- `SConstruct` — auto-discovers new files.
- `stubs.cpp` — document needed stubs, don't modify.

## Architecture Notes

### Effect Spawning Pattern
```cpp
// Called from MoHAARunner::update_entities() when a sprite entity is detected:
void Godot_VFX_ProcessSpriteEntity(
    float pos[3],         // Godot-space position
    float radius,         // sprite radius
    int shader_handle,    // identifies effect type
    uint8_t rgba[4]       // colour modulation
);

// Called when impact is detected (from cgame mark fragment + effect):
void Godot_VFX_SpawnImpact(
    float pos[3],         // Godot-space
    float normal[3],      // surface normal
    int surface_flags,    // from BSP trace: SURF_METAL, SURF_WOOD, etc.
    int weapon_type       // for weapon-specific effects
);
```

### Particle Pool Design
```
Pool of N GPUParticles3D nodes (created at init, hidden until needed):
  - Each has configurable: amount, lifetime, velocity, color, size
  - On spawn: set position, configure parameters, set emitting=true
  - On completion: set emitting=false, return to pool
  - One-shot mode: emitting=true, one_shot=true, auto-recycle

For low-count effects (tracers, shell casings):
  - Pool of MeshInstance3D nodes with simple mesh
  - Manual position update per frame
  - Timer-based cleanup
```

### Screen Effect Layers
```
CanvasLayer (z_index=100):  ← higher than HUD
  ColorRect (fullscreen):   ← damage flash (Color(1,0,0,alpha), alpha fades)
  ColorRect (fullscreen):   ← underwater tint (Color(0,0.2,0.4,0.3))
  TextureRect (fullscreen): ← flash-bang (white, alpha fades)
```

### Surface Type Flags (from Quake 3 / MOHAA)
```c
#define SURF_NODAMAGE    0x1
#define SURF_SLICK       0x2
#define SURF_SKY         0x4
#define SURF_LADDER      0x8
#define SURF_NOIMPACT    0x10
#define SURF_NOMARKS     0x20
#define SURF_FLESH       0x40
#define SURF_METAL       0x1000
#define SURF_WOOD        0x2000
#define SURF_GRASS       0x4000
#define SURF_GRAVEL      0x8000
#define SURF_GLASS       0x10000
// etc. — check code/qcommon/surfaceflags.h
```

## Integration Points
Document in TASKS.md **"MoHAARunner Integration Required"** sections:
1. `Godot_VFX_Init(Node3D *parent)` — called once in `setup_3d_scene()`
2. `Godot_VFX_Update(float delta)` — called each frame in `_process()`
3. In `update_entities()`: route `RT_SPRITE` entities through `Godot_VFX_ProcessSpriteEntity()`
4. `Godot_ScreenEffects_Init(CanvasLayer *hud)` — create screen effect overlays
5. `Godot_ScreenEffects_Update(float delta)` — fade/update screen effects each frame
6. Camera shake: `Godot_VFX_GetCameraShake(float *pitch, float *yaw, float *roll)` — apply in `update_camera()`

## Build & Test
```bash
cd openmohaa && rm -f .sconsign.dblite && scons platform=linux target=template_debug -j$(nproc) dev_build=yes
```

## Documentation
Add Phase entries (221–240) to `openmohaa/TASKS.md`.

## Merge Awareness
- All your files are NEW — zero merge conflict risk with other agents.
- You READ `godot_renderer.c` buffer data via existing C accessor functions — don't modify the capture side.
- Agent 1 (Audio) handles impact sounds — your impact effects should document which sound alias to play so the integration agent can wire both together.
- Agent 4 (Entity) handles entity rendering — your sprite/particle processing is complementary (it handles `RT_MODEL`, you handle `RT_SPRITE`/effects).
- Agent 10 (Integration) wires your VFX calls into `MoHAARunner.cpp`.
