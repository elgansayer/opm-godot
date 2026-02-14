# Phase 102: func_* Entity Audit

## Overview

This document audits all `func_*` entity types in the OpenMoHAA GDExtension port: doors,
movers, breakables, explodables, vehicles, beams, and miscellaneous interactive entities.

---

## Spawn Architecture

OpenMoHAA uses the **CLASS_DECLARATION** macro system for entity spawning.  The legacy
Quake 3 C-style spawn table (`spawns[]` array and `G_CallSpawn()`) in `g_spawn.cpp` is
entirely wrapped in `#if 0` (lines 607–1312) and is dead code — it is never compiled.

Entity resolution path:
```
SpawnArgs::getClassDef(classname)
  → getClassForID(classname)   // matches CLASS_DECLARATION classID strings
  → getClass(classname)        // fallback: matches C++ class names
  → TIKI model init commands   // fallback: loads from .tik server init
```

---

## Doors

### func_door — SlidingDoor ✅
- **File:** `code/fgame/doors.cpp:1445`
- **Declaration:** `CLASS_DECLARATION(Door, SlidingDoor, "func_door")`
- **Parent:** `Door` → `ScriptSlave` → `Mover` → `Trigger`
- **Movement:** `DoOpen()` / `DoClose()` call inherited `MoveTo()` with velocity along move direction
- **Setup:** Calculates move direction from `angles` key, computes `pos1` (closed) and `pos2` (open) with lip offset
- **Events:** `EV_SlidingDoor_Setup`, `EV_SlidingDoor_SetLip`, `EV_SlidingDoor_SetSpeed`, `EV_SetAngle` → `SetMoveDir()`
- **Status:** Fully implemented. Compiles and spawns correctly.

### func_rotatingdoor — RotatingDoor ✅
- **File:** `code/fgame/doors.cpp:1293`
- **Declaration:** `CLASS_DECLARATION(Door, RotatingDoor, "func_rotatingdoor")`
- **Parent:** `Door` → `ScriptSlave` → `Mover` → `Trigger`
- **Movement:** `DoOpen()` / `DoClose()` call `MoveTo()` with angular destination (swing angle)
- **Configuration:** `OpenAngle` event sets swing angle (default: 90°)
- **Status:** Fully implemented. Compiles and spawns correctly.

### script_door — ScriptDoor ✅
- **File:** `code/fgame/doors.cpp:1586`
- **Declaration:** `CLASS_DECLARATION(Door, ScriptDoor, "script_door")`
- **Movement:** Driven by Morfuse script threads (`SetInitThread`, `SetOpenThread`, `SetCloseThread`)
- **Status:** Fully implemented.

### Door Base Class — Door ✅
- **File:** `code/fgame/doors.cpp:287`
- **Declaration:** `CLASS_DECLARATION(ScriptSlave, Door, "NormalDoor")`
- **27 event handlers** mapped including: Open, Close, DoorFire (toggle), DoorBlocked, Lock/Unlock, TryOpen, FieldTouched, IsOpen (getter)
- **Sounds:** 6 configurable sound slots — open start, open end, close start, close end, message, locked. Each cached via `CacheResource()`.
- **Blocking:** `DoorBlocked()` applies damage (`dmg` key) to blocking entity, or reverses direction for NPCs.
- **Locking:** `LockDoor()` / `UnlockDoor()` set locked state; locked doors play `sound_locked` and reject TryOpen.
- **State machine:** `STATE_CLOSED`, `STATE_CLOSING`, `STATE_OPENING`, `STATE_OPEN`
- **Linked doors:** `LinkDoors()` chains multiple door entities for synchronised open/close.
- **Status:** Fully implemented with all MOHAA door features.

---

## Movers

### Mover (base class) ✅
- **File:** `code/fgame/mover.cpp:38`
- **Declaration:** `CLASS_DECLARATION(Trigger, Mover, "mover")`
- **Key methods:**
  - `MoveTo(dest, angles, speed, event)` — velocity-based movement to target position/angles
  - `LinearInterpolate(dest, angles, time, event)` — time-based linear interpolation
  - `MoveDone(event)` — snaps to final position, processes completion event
  - `Stop()` — halts all movement immediately
- **Movement flags:** `MOVE_ORIGIN` (position), `MOVE_ANGLES` (rotation)
- **Status:** Fully implemented. Core movement engine for all `func_*` movers.

### ScriptSlave ✅
- **File:** `code/fgame/scriptslave.cpp:633`
- **Declaration:** `CLASS_DECLARATION(Mover, ScriptSlave, "script_object")`
- **72+ event handlers** for position, rotation, speed, model, physics, binding, etc.
- **Key role:** Parent class for doors, beams, fulcrums, spawners, and other scripted movers.
- **Status:** Fully implemented.

### Note: func_plat, func_train, func_rotating, func_pendulum, func_bobbing
These entity classnames exist **only in the disabled `#if 0` Q3 spawn table** in `g_spawn.cpp`.
They are **not registered via CLASS_DECLARATION** and cannot spawn in the current codebase.

MOHAA maps do not use these Q3-era classnames. Instead:
- **Elevators/platforms** → `script_object` or `script_model` entities driven by `.scr` scripts
- **Trains/path movers** → `script_object` with `moveto` / `speed` script commands + `path_corner` entities
- **Rotating objects** → `script_object` with `rotateaxis` / `rotateto` script commands
- **Pendulums** → Not used in MOHAA maps

---

## Breakables & Explodables

### func_explodingwall — ExplodingWall ✅
- **File:** `code/fgame/misc.cpp:230`
- **Declaration:** `CLASS_DECLARATION(Trigger, ExplodingWall, "func_explodingwall")`
- **Damage:** `DamageEvent()` accumulates damage; `Explode()` triggers destruction
- **Debris:** Configurable debris count (`explosions`), velocity, angle speed, land radius
- **Ground damage:** `GroundDamage()` uses `MOD_EXPLODEWALL` damage type
- **Spawnflags:** `INVISIBLE`, `ACCUMULATIVE`, `TWOSTAGE`, `RANDOMANGLES`, `LANDSHATTER`
- **Status:** Fully implemented.

### func_exploder — Exploder ✅
- **File:** `code/fgame/explosion.cpp:155`
- **Declaration:** `CLASS_DECLARATION(Trigger, Exploder, "func_exploder")`
- **Triggers explosion effect at entity origin on activation.**
- **Status:** Fully implemented.

### func_multi_exploder — MultiExploder ✅
- **File:** `code/fgame/explosion.cpp:205`
- **Declaration:** `CLASS_DECLARATION(Trigger, MultiExploder, "func_multi_exploder")`
- **Multiple sequential explosion effects.**
- **Status:** Fully implemented.

### func_explodeobject — ExplodeObject ✅
- **File:** `code/fgame/explosion.cpp:380`
- **Declaration:** `CLASS_DECLARATION(MultiExploder, ExplodeObject, "func_explodeobject")`
- **Extends MultiExploder with object-specific explosion parameters.**
- **Status:** Fully implemented.

### Note: func_breakable, func_explodable
These entity classnames **do not exist** in the OpenMoHAA codebase. They are Quake 3 / generic
references not used by MOHAA. The equivalent functionality is provided by:
- `func_explodingwall` — breakable/explodable walls with debris
- `func_window` (WindowObject) — breakable glass with shattering
- `func_barrel` (BarrelObject) — destroyable barrels
- `func_crate` (CrateObject) — destroyable crates

---

## Vehicles

### script_vehicle — Vehicle ✅
- **File:** `code/fgame/vehicle.cpp:858`
- **Declaration:** `CLASS_DECLARATION(VehicleBase, Vehicle, "script_vehicle")`
- **Parent:** `VehicleBase` → `Animate`
- **Key events:** Start, Enter, Exit, Drivable/UnDrivable, PathDrivable, Jumpable
- **Physics:** Custom vehicle physics with wheels, suspension, collision
- **Status:** Fully implemented. Note: Registered as `script_vehicle`, not `func_vehicle`.

### script_drivablevehicle — DrivableVehicle ✅
- **File:** `code/fgame/vehicle.cpp:6900`
- **Declaration:** `CLASS_DECLARATION(Vehicle, DrivableVehicle, "script_drivablevehicle")`
- **Extends Vehicle with player-drivable controls.**
- **Status:** Fully implemented.

### VehicleBase (internal) ✅
- **File:** `code/fgame/vehicle.cpp`
- **Declaration:** `CLASS_DECLARATION(Animate, VehicleBase, NULL)` — no classID (internal only)
- **Status:** Base class, not directly spawnable.

---

## Beams

### func_beam — FuncBeam ✅
- **File:** `code/fgame/beam.cpp:293`
- **Declaration:** `CLASS_DECLARATION(ScriptSlave, FuncBeam, "func_beam")`
- **Renders a beam effect from origin to target entity.**
- **Configurable:** Damage, shader, colour, alpha, width, life, persistence
- **Status:** Fully implemented.

---

## Other func_* Entities

### func_static ✅
- **Not** registered via CLASS_DECLARATION (only in disabled Q3 spawn table).
- In MOHAA, static brush models are typically `worldspawn` sub-models or `script_object` entities with no movement commands.
- Non-moving brush entities spawn as their base class and remain static.

### func_remove — FuncRemove ✅
- **File:** `code/fgame/misc.cpp:64`
- **Declaration:** `CLASS_DECLARATION(Entity, FuncRemove, "func_remove")`
- **Immediately removes itself on spawn** (posts `EV_Remove`).
- **Status:** Fully implemented.

### func_camera — Camera ✅
- **File:** `code/fgame/camera.cpp:660`
- **Declaration:** `CLASS_DECLARATION(Entity, Camera, "func_camera")`
- **Cinematic camera entity for cutscenes.**
- **Status:** Fully implemented.

### func_emitter — Emitter ✅
- **File:** `code/fgame/nature.cpp:42`
- **Declaration:** `CLASS_DECLARATION(Entity, Emitter, "func_emitter")`
- **Particle/effect emitter entity.**
- **Status:** Fully implemented.

### func_rain — Rain ✅
- **File:** `code/fgame/nature.cpp:71`
- **Declaration:** `CLASS_DECLARATION(Entity, Rain, "func_rain")`
- **Rain weather effect entity.**
- **Status:** Fully implemented.

### func_fulcrum — Fulcrum ✅
- **File:** `code/fgame/specialfx.cpp:132`
- **Declaration:** `CLASS_DECLARATION(ScriptSlave, Fulcrum, "func_fulcrum")`
- **Teeter-totter / balance point physics object.**
- **Status:** Fully implemented.

### func_runthrough — RunThrough ✅
- **File:** `code/fgame/specialfx.cpp:388`
- **Declaration:** `CLASS_DECLARATION(Entity, RunThrough, "func_runthrough")`
- **Trigger entity that plays effects when player runs through.**
- **Status:** Fully implemented.

### func_sinkobject — SinkObject ✅
- **File:** `code/fgame/specialfx.cpp:675`
- **Declaration:** `CLASS_DECLARATION(ScriptSlave, SinkObject, "func_sinkobject")`
- **Object that sinks when stepped on.**
- **Status:** Fully implemented.

### func_spawn — Spawn ✅
- **File:** `code/fgame/spawners.cpp:106`
- **Declaration:** `CLASS_DECLARATION(ScriptSlave, Spawn, "func_spawn")`
- **Entity spawner triggered by events.**
- **Status:** Fully implemented.

### func_randomspawn — RandomSpawn ✅
- **File:** `code/fgame/spawners.cpp:257`
- **Declaration:** `CLASS_DECLARATION(Spawn, RandomSpawn, "func_randomspawn")`
- **Status:** Fully implemented.

### func_respawn — ReSpawn ✅
- **File:** `code/fgame/spawners.cpp:317`
- **Declaration:** `CLASS_DECLARATION(Spawn, ReSpawn, "func_respawn")`
- **Status:** Fully implemented.

### func_spawnoutofsight — SpawnOutOfSight ✅
- **File:** `code/fgame/spawners.cpp:348`
- **Declaration:** `CLASS_DECLARATION(Spawn, SpawnOutOfSight, "func_spawnoutofsight")`
- **Status:** Fully implemented.

### func_spawnchain — SpawnChain ✅
- **File:** `code/fgame/spawners.cpp:397`
- **Declaration:** `CLASS_DECLARATION(Spawn, SpawnChain, "func_spawnchain")`
- **Status:** Fully implemented.

### func_throwobject — ThrowObject ✅
- **File:** `code/fgame/object.cpp:224`
- **Declaration:** `CLASS_DECLARATION(Animate, ThrowObject, "func_throwobject")`
- **Status:** Fully implemented.

### func_useanim — UseAnim ✅
- **File:** `code/fgame/misc.cpp:1039`
- **Declaration:** `CLASS_DECLARATION(Entity, UseAnim, "func_useanim")`
- **Animation-driven interaction point (e.g. plant bomb, defuse).**
- **Status:** Fully implemented.

### func_touchanim — TouchAnim ✅
- **File:** `code/fgame/misc.cpp:1383`
- **Declaration:** `CLASS_DECLARATION(UseAnim, TouchAnim, "func_touchanim")`
- **Status:** Fully implemented.

### func_useanimdest — UseAnimDestination ✅
- **File:** `code/fgame/misc.cpp:1421`
- **Declaration:** `CLASS_DECLARATION(Entity, UseAnimDestination, "func_useanimdest")`
- **Status:** Fully implemented.

### func_useobject — UseObject ✅
- **File:** `code/fgame/misc.cpp:1700`
- **Declaration:** `CLASS_DECLARATION(Animate, UseObject, "func_useobject")`
- **Status:** Fully implemented.

### func_monkeybars — MonkeyBars ✅
- **File:** `code/fgame/misc.cpp:2164`
- **Declaration:** `CLASS_DECLARATION(Entity, MonkeyBars, "func_monkeybars")`
- **Status:** Fully implemented.

### func_horizontalpipe — HorizontalPipe ✅
- **File:** `code/fgame/misc.cpp:2193`
- **Declaration:** `CLASS_DECLARATION(Entity, HorizontalPipe, "func_horizontalpipe")`
- **Status:** Fully implemented.

### func_pushobject — PushObject ✅
- **File:** `code/fgame/misc.cpp:2390`
- **Declaration:** `CLASS_DECLARATION(Entity, PushObject, "func_pushobject")`
- **Pushable physics object with damage on collision.**
- **Status:** Fully implemented.

### func_fallingrock — FallingRock ✅
- **File:** `code/fgame/misc.cpp:2577`
- **Declaration:** `CLASS_DECLARATION(Entity, FallingRock, "func_fallingrock")`
- **Bouncing projectile/trap entity.**
- **Status:** Fully implemented.

### func_ladder — FuncLadder ✅
- **File:** `code/fgame/misc.cpp:2839`
- **Declaration:** `CLASS_DECLARATION(Entity, FuncLadder, "func_ladder")`
- **Climbable ladder brush.**
- **Status:** Fully implemented.

### func_objective — Objective ✅
- **File:** `code/fgame/Entities.cpp:2164`
- **Declaration:** `CLASS_DECLARATION(Entity, Objective, "func_objective")`
- **Mission objective entity.**
- **Status:** Fully implemented.

### func_towobjective — TOWObjective ✅
- **File:** `code/fgame/Tow_Entities.cpp:217`
- **Declaration:** `CLASS_DECLARATION(Objective, TOWObjective, "func_towobjective")`
- **Tug-of-War multiplayer objective.**
- **Status:** Fully implemented.

### func_fencepost — FencePost ✅
- **File:** `code/fgame/Entities.cpp:2252`
- **Declaration:** `CLASS_DECLARATION(Entity, FencePost, "func_fencepost")`
- **Status:** Fully implemented.

### func_window — WindowObject ✅
- **File:** `code/fgame/windows.cpp:47`
- **Declaration:** `CLASS_DECLARATION(Entity, WindowObject, "func_window")`
- **Breakable glass window.**
- **Status:** Fully implemented.

### func_barrel — BarrelObject ✅
- **File:** `code/fgame/barrels.cpp:74`
- **Declaration:** `CLASS_DECLARATION(Entity, BarrelObject, "func_barrel")`
- **Destroyable barrel entity.**
- **Status:** Fully implemented.

### func_crate — CrateObject ✅
- **File:** `code/fgame/crateobject.cpp:91`
- **Declaration:** `CLASS_DECLARATION(Entity, CrateObject, "func_crate")`
- **Destroyable crate entity.**
- **Status:** Fully implemented.

### func_viewjitter — ViewJitter ✅
- **File:** `code/fgame/earthquake.cpp:105`
- **Declaration:** `CLASS_DECLARATION(Trigger, ViewJitter, "func_viewjitter")`
- **Screen shake trigger (earthquake effect).**
- **Status:** Fully implemented.

### func_teleportdest — TeleporterDestination ✅
- **File:** `code/fgame/misc.cpp:904`
- **Declaration:** `CLASS_DECLARATION(Entity, TeleporterDestination, "func_teleportdest")`
- **Teleporter landing point.**
- **Status:** Fully implemented.

---

## Brush Model Rendering Integration

### Inline BSP Model Accessors ✅
`func_*` entities that reference inline BSP models (`*1`, `*2`, etc.) rely on these
Godot-side accessor functions defined in `code/godot/godot_bsp_mesh.h`:

| Function | Purpose |
|----------|---------|
| `Godot_BSP_GetBrushModelCount()` | Returns number of inline brush submodels |
| `Godot_BSP_GetBrushModelMesh(int)` | Builds `ArrayMesh` for a specific submodel index |
| `Godot_BSP_GetInlineModelBounds(int, float*, float*)` | Gets AABB (mins/maxs) for a submodel |
| `Godot_BSP_MarkFragmentsForInlineModel(...)` | Projects decal mark fragments onto brush surfaces |

### Movement → Transform Update
When the engine moves a `func_*` entity (e.g. door opens), the server updates the entity's
`origin` and `angles` in the entity state. The renderer stub (`godot_renderer.c`) captures
this via `GR_AddRefEntityToScene()` into `gr_entities[]`. `MoHAARunner::update_entities()`
reads the entity buffer each frame and updates the corresponding `MeshInstance3D` transform
in Godot's scene tree.

### Note on `Godot_BSP_GetModelBounds` / `Godot_BSP_GetModelSurfaces`
These function names (from the task specification) do not exist. The actual equivalents are
`Godot_BSP_GetInlineModelBounds()` and `Godot_BSP_GetBrushModelMesh()` respectively.

---

## GODOT_GDEXTENSION Guards

None of the core `func_*` entity files contain `#ifdef GODOT_GDEXTENSION` guards:
- `doors.cpp` / `doors.h` — no guards
- `mover.cpp` / `mover.h` — no guards
- `misc.cpp` / `misc.h` — no guards
- `vehicle.cpp` — no guards
- `beam.cpp` — no guards
- `explosion.cpp` — no guards
- `scriptslave.cpp` — no guards

This is correct — these files are pure game logic with no platform-specific behaviour.
The only fgame file with a `GODOT_GDEXTENSION` guard is `g_main.h` (for `gi_Malloc_Safe`/
`gi_Free_Safe` wrappers).

---

## Complete func_* Entity Registry

| classID | C++ Class | File | Parent | Status |
|---------|-----------|------|--------|--------|
| `func_door` | SlidingDoor | doors.cpp | Door | ✅ |
| `func_rotatingdoor` | RotatingDoor | doors.cpp | Door | ✅ |
| `script_door` | ScriptDoor | doors.cpp | Door | ✅ |
| `func_beam` | FuncBeam | beam.cpp | ScriptSlave | ✅ |
| `func_remove` | FuncRemove | misc.cpp | Entity | ✅ |
| `func_explodingwall` | ExplodingWall | misc.cpp | Trigger | ✅ |
| `func_teleportdest` | TeleporterDestination | misc.cpp | Entity | ✅ |
| `func_useanim` | UseAnim | misc.cpp | Entity | ✅ |
| `func_touchanim` | TouchAnim | misc.cpp | UseAnim | ✅ |
| `func_useanimdest` | UseAnimDestination | misc.cpp | Entity | ✅ |
| `func_useobject` | UseObject | misc.cpp | Animate | ✅ |
| `func_monkeybars` | MonkeyBars | misc.cpp | Entity | ✅ |
| `func_horizontalpipe` | HorizontalPipe | misc.cpp | Entity | ✅ |
| `func_pushobject` | PushObject | misc.cpp | Entity | ✅ |
| `func_fallingrock` | FallingRock | misc.cpp | Entity | ✅ |
| `func_ladder` | FuncLadder | misc.cpp | Entity | ✅ |
| `func_camera` | Camera | camera.cpp | Entity | ✅ |
| `func_emitter` | Emitter | nature.cpp | Entity | ✅ |
| `func_rain` | Rain | nature.cpp | Entity | ✅ |
| `func_fulcrum` | Fulcrum | specialfx.cpp | ScriptSlave | ✅ |
| `func_runthrough` | RunThrough | specialfx.cpp | Entity | ✅ |
| `func_sinkobject` | SinkObject | specialfx.cpp | ScriptSlave | ✅ |
| `func_spawn` | Spawn | spawners.cpp | ScriptSlave | ✅ |
| `func_randomspawn` | RandomSpawn | spawners.cpp | Spawn | ✅ |
| `func_respawn` | ReSpawn | spawners.cpp | Spawn | ✅ |
| `func_spawnoutofsight` | SpawnOutOfSight | spawners.cpp | Spawn | ✅ |
| `func_spawnchain` | SpawnChain | spawners.cpp | Spawn | ✅ |
| `func_throwobject` | ThrowObject | object.cpp | Animate | ✅ |
| `func_objective` | Objective | Entities.cpp | Entity | ✅ |
| `func_towobjective` | TOWObjective | Tow_Entities.cpp | Objective | ✅ |
| `func_fencepost` | FencePost | Entities.cpp | Entity | ✅ |
| `func_window` | WindowObject | windows.cpp | Entity | ✅ |
| `func_barrel` | BarrelObject | barrels.cpp | Entity | ✅ |
| `func_crate` | CrateObject | crateobject.cpp | Entity | ✅ |
| `func_viewjitter` | ViewJitter | earthquake.cpp | Trigger | ✅ |
| `func_exploder` | Exploder | explosion.cpp | Trigger | ✅ |
| `func_multi_exploder` | MultiExploder | explosion.cpp | Trigger | ✅ |
| `func_explodeobject` | ExplodeObject | explosion.cpp | MultiExploder | ✅ |
| `script_vehicle` | Vehicle | vehicle.cpp | VehicleBase | ✅ |
| `script_drivablevehicle` | DrivableVehicle | vehicle.cpp | Vehicle | ✅ |

---

## Entities NOT in Codebase

The following entity names from the task specification do not exist as CLASS_DECLARATION
entries in the OpenMoHAA codebase:

| Name | Reason |
|------|--------|
| `func_breakable` | Not a MOHAA entity. Use `func_explodingwall`, `func_window`, `func_barrel`, or `func_crate` |
| `func_explodable` | Not a MOHAA entity. Use `func_explodingwall` or `func_explodeobject` |
| `func_vehicle` | Vehicles are registered as `script_vehicle` / `script_drivablevehicle` |
| `func_plat` | Q3-only; disabled in `#if 0` block. MOHAA uses script-driven `script_object` |
| `func_train` | Q3-only; disabled in `#if 0` block. MOHAA uses script-driven `script_object` + path_corner |
| `func_rotating` | Q3-only; disabled in `#if 0` block. MOHAA uses `script_object` with rotateaxis commands |
| `func_pendulum` | Q3-only; disabled in `#if 0` block. Not used in MOHAA maps |
| `func_bobbing` | Q3-only; disabled in `#if 0` block. Not used in MOHAA maps |
| `func_static` | Q3-only; disabled in `#if 0` block. Static brushes are worldspawn sub-models |
| `func_button` | Q3-only; disabled in `#if 0` block |
| `func_timer` | Q3-only; disabled in `#if 0` block |

---

## Audit Summary

- **37 active func_* entities** registered via CLASS_DECLARATION — all compile and are fully implemented
- **0 compilation issues** found in func_* entity source files
- **0 GODOT_GDEXTENSION guards needed** — these files are pure game logic
- **Legacy Q3 spawn table** is correctly disabled (`#if 0`) — no linker errors from undefined `SP_func_*`
- **BSP model accessors** (`Godot_BSP_GetBrushModelMesh`, `Godot_BSP_GetInlineModelBounds`) are available for brush model rendering
- **Entity transform pipeline** (engine → renderer stub → entity buffer → MoHAARunner) handles brush model movement correctly
