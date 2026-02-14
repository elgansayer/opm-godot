# Agent Task 42: Collision & Projectile Physics Audit

## Objective
Audit BSP clip model collision, entity-vs-entity collision, projectile physics (grenades, rockets, bullets), water physics, and fall damage.

## Files to Audit
- `code/qcommon/cm_trace.c` — BSP collision traces
- `code/qcommon/cm_patch.c` — Patch collision
- `code/fgame/g_phys.cpp` — Entity physics
- `code/fgame/g_utils.cpp` — G_Trace, G_PointContents
- `code/fgame/weaputils.cpp` — Projectile spawning and physics
- `code/fgame/grenadehint.cpp` — Grenade AI hints
- `code/fgame/bg_pmove.cpp` — Water/fall damage sections

## Files to Create (EXCLUSIVE)
- `code/godot/godot_physics_audit.md` — Audit results documentation

## Audit Checklist

### 1. BSP collision (CM_BoxTrace)
- [ ] `CM_BoxTrace()` works correctly — traces a box through BSP world
- [ ] `CM_PointContents()` — returns content flags for a point
- [ ] Brush collision: solid, water, lava, clip brushes
- [ ] Patch surfaces: collision hulls generated from Bézier patches
- [ ] Terrain collision: heightfield traces

### 2. Entity collision
- [ ] `SV_Trace()` wraps CM_BoxTrace with entity clipping
- [ ] Entity clip models (bounding boxes)
- [ ] Pusher entities: doors pushing players, elevators carrying players
- [ ] Trigger touches detected correctly  
- [ ] `CONTENTS_BODY`, `CONTENTS_SOLID`, `CONTENTS_PLAYERCLIP` masks

### 3. Projectile physics
- [ ] Grenade: parabolic arc (initial velocity + gravity), bounce off walls
- [ ] Rocket: straight-line travel with speed, explode on impact
- [ ] Bullet traces: instant hit via `G_Trace`
- [ ] Per-weapon projectile definitions from TIKI files
- [ ] Projectile-entity collision → damage + effects

### 4. Water physics
- [ ] `PM_WaterMove()` — swimming velocity and resistance
- [ ] Water level detection (0=none, 1=feet, 2=waist, 3=submerged)
- [ ] Drowning damage when submerged too long
- [ ] Transition sounds (enter/exit water)

### 5. Fall damage
- [ ] `PM_CrashLand()` — fall damage calculation
- [ ] Fall height threshold (minimum height for damage)
- [ ] Damage scaling with fall distance
- [ ] Landing sound selection
- [ ] Death from extreme falls

### 6. Kill triggers and world damage
- [ ] `trigger_hurt` — constant damage inside volume
- [ ] Lava/slime content damage
- [ ] Out-of-world kill plane (`void`)

## Build Verification
```bash
cd openmohaa && scons platform=linux target=template_debug -j$(nproc) dev_build=yes
```

## Documentation
Append `## Phase 116-120: Collision & Physics Audit ✅` to `TASKS.md`.

## DO NOT MODIFY
- `MoHAARunner.cpp` / `MoHAARunner.h`
