# Collision & Projectile Physics Audit

**Audit date:** 2026-02-14
**Scope:** BSP clip model collision, entity-vs-entity collision, projectile physics,
water physics, fall damage, kill triggers and world damage.

---

## 1. BSP Collision (CM_BoxTrace)

### 1.1 CM_BoxTrace — `code/qcommon/cm_trace.c`

**Status: ✅ Working correctly**

- Initialises `traceWork_t` with start/end positions, box extents, and content mask.
- Increments `cm.checkcount` to avoid re-testing geometry shared between adjacent leaves.
- Routes point queries to `CM_PositionTest()` and swept traces to `CM_TraceThroughTree()`.
- Precomputes `tw.offsets[8]` corner offsets for efficient plane distance calculations.
- Point traces (`tw.isPoint = qtrue`) optimised for zero-extent boxes.
- Sphere/capsule support adjusts plane distances by radius offset.
- No `#ifdef GODOT_GDEXTENSION` guards — compiled identically for Godot and native.

### 1.2 CM_PointContents — `code/qcommon/cm_test.c`

**Status: ✅ Working correctly**

- Walks BSP tree via `CM_PointLeafnum_r()` to locate the containing leaf.
- Iterates leaf brushes, tests AABB overlap then plane-side for each.
- ORs content flags (`CONTENTS_SOLID`, `CONTENTS_WATER`, `CONTENTS_LAVA`, etc.)
  when the point is inside a brush (on the inner side of every plane).
- Uses strict `>` comparison (`d > dist`) — a point exactly on a plane boundary is
  considered inside. An upstream comment ("FIXME test for Cash") notes this was a
  deliberate choice for a specific test case.

### 1.3 Brush Collision — `CM_TraceThroughBrush`

**Status: ✅ Correct**

- Standard plane-sweep: computes parametric enter/exit fractions per plane.
- Records collision plane, surface flags, shader number, and content flags.
- `SURFACE_CLIP_EPSILON (0.125)` prevents degenerate penetration.
- Fence brushes (`CONTENTS_FENCE`) have a separate code path requiring point traces
  plus alpha-mask testing via `CM_TraceThroughFence()`.
- Solid, water, lava, clip brushes all handled via content mask filtering.

### 1.4 Patch Surfaces — `code/qcommon/cm_patch.c`

**Status: ✅ Correct**

- `CM_GeneratePatchCollide()` tessellates Bézier control points into planar facets.
- Each facet is bounded by border planes with inward/outward orientation.
- Bevel planes added at corners to prevent tunnelling through edges.
- Plane deduplication via `CM_FindPlane()` with `PLANE_TRI_EPSILON` tolerance.
- `CM_TraceThroughPatch()` delegates to `CM_TraceThroughPatchCollide()` using the
  same plane-sweep algorithm as brushes.
- No `#ifdef GODOT_GDEXTENSION` guards.

### 1.5 Terrain Collision — `code/qcommon/cm_terrain.c`

**Status: ✅ Working**

- 8×8 heightfield grid stored per terrain patch with two 4D plane equations per square.
- `CM_GenerateTerrainCollide()` pre-stores plane data — no runtime triangle generation.
- `CM_TraceThroughTerrainCollide()` uses the same plane-sweep design as brush traces.
- Integrated into `CM_TraceToLeaf()` after brushes and patches.
- Checkcount mechanism prevents duplicate tests across shared leaves.

**Note:** Terrain traces do not filter on content mask before calling
`CM_TraceThroughTerrain()`, unlike brush traces which check
`!(b->contents & tw->contents)`. This means terrain is always tested regardless
of the caller's content mask. This is consistent with upstream OpenMoHAA behaviour
and not a Godot-specific issue.

---

## 2. Entity Collision

### 2.1 SV_Trace — `code/server/sv_world.c`

**Status: ✅ Correct**

- First traces against the world BSP via `CM_BoxTrace()` (model index 0).
- If not fully blocked, traces against entities via `SV_ClipMoveToEntities()`.
- Entity clipping:
  - Skips `SOLID_NOT` and `SOLID_TRIGGER` entities.
  - Skips self/owner to prevent self-collision.
  - Respects content mask filtering.
  - For BSP sub-models (`ent->r.bmodel`): uses `CM_InlineModel()`.
  - For bounding-box entities: uses `CM_TempBoxModel()` with entity contents.
- No `#ifdef GODOT_GDEXTENSION` guards.

### 2.2 Entity Clip Models

**Status: ✅ Correct**

- `SV_ClipHandleForEntity()` distinguishes BSP models from bounding boxes.
- `SV_LinkEntity()` expands `absmin`/`absmax` by 1 unit epsilon on all sides to
  prevent floating-point precision issues at edges.
- Entities linked into world-sector BSP tree for spatial queries
  (`SV_AreaEntities()`).

### 2.3 Pusher Entities — `code/fgame/g_phys.cpp`

**Status: ✅ Functional**

- `G_Push()` moves doors/elevators and pushes overlapping entities.
- Saves original positions, moves pusher, tests each entity in the swept volume
  with `G_TestEntityPosition()`.
- If any entity is blocked, all moved entities are rolled back to original positions.
- `G_Physics_Pusher()` dispatches to `G_Push()` and posts `EV_Blocked` events.
- Ground entity tracking (`check->groundentity == pusher->edict`) determines whether
  entities ride pushers.
- Trigger touches (`G_TouchTriggers()`) called after successful pushes.

### 2.4 Content Masks

**Status: ✅ Correct**

- `G_Trace()` in `g_utils.cpp` delegates to `gi.trace()` → `SV_Trace()` → `CM_BoxTrace()`.
- Per-entity `clipmask` with fallback to `MASK_SOLID`.
- `CONTENTS_BODY`, `CONTENTS_SOLID`, `CONTENTS_PLAYERCLIP`, `MASK_PROJECTILE` all
  used correctly throughout the codebase.
- No `#ifdef GODOT_GDEXTENSION` guards in collision code.

---

## 3. Projectile Physics

### 3.1 Grenade — `code/fgame/weaputils.cpp`

**Status: ✅ Correct**

- Spawned via `ProjectileAttack()` with `MOVETYPE_BOUNCE` and `SOLID_BBOX`.
- Velocity set from weapon direction × speed + optional owner velocity.
- Gravity applied by the engine's `MOVETYPE_BOUNCE` physics (uses `sv_gravity` cvar).
- Angular velocity (`avelocity`) gives visual spin until stabilised.
- `Projectile::Touch()` handles bounce with surface-aware sounds:
  mud, metal/grill, rock/wood/glass, water.
- `P_BOUNCE_TOUCH` flag controls whether the projectile bounces or detonates on contact.
- Optional die-in-water behaviour (`m_bDieInWater`).
- Bounce dampening is engine-controlled (not per-projectile configurable) — consistent
  with upstream.

### 3.2 Rocket — `code/fgame/weaputils.cpp`

**Status: ✅ Correct**

- Same `ProjectileAttack()` path but without `P_BOUNCE_TOUCH` flag.
- Straight-line travel at configured speed.
- Detonates on first impact: `Projectile::Touch()` applies damage to hit entity
  then calls `RadiusDamage()` for splash.
- `RadiusDamage()` (line ~3009) implements linear damage falloff with distance,
  entity size compensation, self-damage reduction (×0.9), and sight-trace to
  prevent damage through walls.

### 3.3 Bullet Traces — `code/fgame/weaputils.cpp`

**Status: ✅ Correct**

- `BulletAttack()` uses instant-hit `G_Trace()` line traces.
- Spread calculated via `grandom()` applied to forward direction.
- Material penetration with configurable through-wood and through-metal factors.
- Maximum 5 penetrations per bullet.
- Damage reduction per penetration: `newdamage -= damageMultiplier * 2 * damage`.
- Surface-specific tracer and impact effects via `CGM_BULLET_*` network messages.

### 3.4 Per-Weapon Projectile Definitions

**Status: ✅ Correct**

- Weapon parameters loaded from TIKI files via `SpawnArgs` at projectile spawn time.
- Configurable properties: speed, minspeed, damage, knockback, dlight, meansofdeath,
  life/minlife, avelocity, addvelocity, addownervelocity, gravity.
- Charge-based weapons scale speed and life by charge fraction (`P_CHARGE_LIFE`,
  `P_CHARGE_SPEED`).

### 3.5 Projectile–Entity Collision → Damage + Effects

**Status: ✅ Correct**

- `Projectile::Touch()` applies `other->Damage()` with inflictor, attacker, raw damage,
  hit location, velocity direction, surface normal, knockback, and means-of-death.
- Team checking via `CheckTeams()` prevents friendly fire on disconnect/respawn.
- Vehicle vulnerability system checks `GetProjectileHitsRemaining()`.
- Single-player stat tracking (`m_iNumHits`, `m_iNumTorsoShots`).

---

## 4. Water Physics

### 4.1 PM_WaterMove — `code/fgame/bg_pmove.cpp`

**Status: ✅ Correct**

- Swimming velocity scaled by water level:
  - `waterlevel == 1` (feet): 80% speed cap.
  - `waterlevel >= 2` (waist/submerged): 50% speed cap.
- Water friction: `pm_waterfriction = 2.0f` (vs ground 6.0f).
- Slime applies 5× friction multiplier per water level.
- Water acceleration: `pm_wateraccelerate = 8.0f`.

### 4.2 Water Level Detection

**Status: ✅ Correct**

- `PM_SetWaterLevel()` samples at three heights using `pointcontents()`:
  - Level 0: not in water.
  - Level 1: feet submerged.
  - Level 2: waist submerged.
  - Level 3: fully submerged (head underwater).
- Water type stored in `pm->watertype` (water, lava, slime).

### 4.3 Drowning Damage — `code/fgame/g_active.cpp`

**Status: ✅ Correct**

- `P_WorldEffects()` handles drowning when `waterlevel == 3`.
- Players have an `airOutTime` timer; when expired while submerged, drowning damage
  starts at 2 HP/second and scales up by +2 per tick, capped at 15 HP/tick.
- Damage applied as `MOD_WATER` with `DAMAGE_NO_ARMOR`.
- Drowning sound: `*drown.wav` on first tick, gurgle sounds on subsequent ticks.
- Recovery: `airOutTime` resets to `level.time + 12000` (12 seconds) when head is
  above water.

### 4.4 Transition Sounds

**Status: ✅ Correct**

- `PM_CheckWaterSounds()` fires events on water state transitions:
  - Enter water: `EV_WATER_TOUCH`.
  - Leave water: `EV_WATER_LEAVE`.
  - Head goes under (2→3): `EV_WATER_UNDER`.
  - Head emerges (3→2): `EV_WATER_CLEAR`.

---

## 5. Fall Damage

### 5.1 PM_CrashLand — `code/fgame/bg_pmove.cpp`

**Status: ✅ Correct**

- Physics-based delta calculation using kinematic equations:
  `delta = (vel - sqrt(b² - 4ac))² × 0.0001`
  where `a = -gravity/2, b = velocity, c = -distance`.
- `SURF_NODAMAGE` surface flag suppresses all fall damage and sounds (for bounce pads).

### 5.2 Fall Height Threshold

**Status: ✅ Correct**

- `delta < 1`: no damage or sound event.
- `delta > 20`: first damage tier (`EV_FALL_SHORT`).

### 5.3 Damage Scaling

**Status: ✅ Correct**

| Delta   | Event            | Severity       |
|---------|------------------|----------------|
| > 100   | `EV_FALL_FATAL`  | Instant death  |
| > 80    | `EV_FALL_FAR`    | Severe damage  |
| > 40    | `EV_FALL_MEDIUM` | Moderate damage|
| > 20    | `EV_FALL_SHORT`  | Minor damage   |
| < 1     | (none)           | No effect      |

Water reduces fall damage:
- `waterlevel == 2` (waist): 75% reduction (×0.25).
- `waterlevel == 1` (feet): 50% reduction (×0.5).

### 5.4 Landing Sound Selection

**Status: ✅ Correct**

- Landing events (`EV_FALL_*`) trigger surface-appropriate sounds on the client side.
- Terminal velocity event (`EV_TERMINAL_VELOCITY`) fired when falling speed exceeds 1200 ups.

### 5.5 Death from Extreme Falls

**Status: ✅ Correct**

- `EV_FALL_FATAL` (delta > 100) deals lethal damage, handled by the game damage system.

---

## 6. Kill Triggers and World Damage

### 6.1 trigger_hurt — `code/fgame/trigger.cpp`

**Status: ✅ Correct**

- Default damage: 10 HP per trigger activation.
- Default damage type: `MOD_CRUSH`.
- Damage applied with `DAMAGE_NO_ARMOR | DAMAGE_NO_SKILL` flags (bypasses armour).
- Skips dead entities and godmode players.
- Spawn flags: `NOT_PLAYERS` (2), `MONSTERS` (4), `PROJECTILES` (8).

### 6.2 Lava/Slime Content Damage — `code/fgame/g_active.cpp`

**Status: ✅ Correct**

- `P_WorldEffects()` applies per-frame environmental damage:
  - Lava: 30 × waterlevel damage as `MOD_LAVA`.
  - Slime: 10 × waterlevel damage as `MOD_SLIME`.
- Damage throttled by `pain_debounce_time`.

### 6.3 Out-of-World Kill Plane

**Status: ✅ Map-dependent**

- No hardcoded void kill at a specific Z coordinate.
- Out-of-world kills are implemented via `trigger_hurt` volumes placed by map authors
  at map boundaries (standard id Tech 3 practice).
- Entity bounding is enforced by map geometry and clip brushes.

---

## 7. Godot GDExtension Compatibility

**No `#ifdef GODOT_GDEXTENSION` guards** exist in any of the audited collision or
physics files:

| File | Guards |
|------|--------|
| `cm_trace.c` | None |
| `cm_patch.c` | None |
| `cm_terrain.c` | None |
| `cm_test.c` | None |
| `sv_world.c` | None |
| `g_phys.cpp` | None |
| `g_utils.cpp` | None |
| `weaputils.cpp` | None |
| `grenadehint.cpp` | None |
| `bg_pmove.cpp` | None |
| `g_active.cpp` | None |
| `trigger.cpp` | None |

The collision and physics systems are compiled identically for both Godot and native
builds. All engine function pointers (`gi.trace`, `gi.pointcontents`, etc.) are set
up during `G_InitGame()` which runs before any physics code executes. No
Godot-specific modifications are required for these subsystems.

---

## 8. Summary

All six audit areas are **functionally correct** and **fully compatible** with the
Godot GDExtension build:

| Area | Status | Notes |
|------|--------|-------|
| BSP collision (CM_BoxTrace) | ✅ | Brushes, patches, terrain all correct |
| Entity collision (SV_Trace) | ✅ | Entity clipping, pushers, triggers correct |
| Projectile physics | ✅ | Grenades, rockets, bullets all correct |
| Water physics | ✅ | Swimming, drowning, transitions correct |
| Fall damage | ✅ | Thresholds, scaling, water reduction correct |
| Kill triggers / world damage | ✅ | trigger_hurt, lava, slime, drowning correct |

No code changes are required. The collision and physics systems operate entirely
through server-side game logic and engine internals that are unaffected by the
Godot rendering/audio/input layer.
