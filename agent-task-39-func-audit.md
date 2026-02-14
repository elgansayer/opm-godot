# Agent Task 39: Entity Audit — func_* Family

## Objective
Audit all `func_*` entity types: doors, rotating objects, platforms, trains, breakables, and explodables. Verify they compile, spawn, and execute their movement/interaction logic correctly.

## Files to Audit
- `code/fgame/doors.cpp` / `code/fgame/doors.h` — func_door, func_door_rotating
- `code/fgame/mover.cpp` / `code/fgame/mover.h` — func_plat, func_train, func_rotating
- `code/fgame/misc.cpp` / `code/fgame/misc.h` — func_breakable, func_explodable, func_static
- `code/fgame/vehicle.cpp` — func_vehicle, VehicleBase
- `code/fgame/g_spawn.cpp` — Spawn table

## Files to Create (EXCLUSIVE)
- `code/godot/godot_func_audit.md` — Audit results documentation

## Entity Types to Verify

### Doors
- [ ] `func_door` — sliding door (move along axis, open on touch/use)
- [ ] `func_door_rotating` — rotating door (swing open)
- [ ] Door sounds: open/close/locked
- [ ] Blocked: damage or reverse on block
- [ ] Trigger from script: `open`, `close`, `toggle`
- [ ] Key requirements (locked doors)

### Movers
- [ ] `func_plat` — elevator/lift (up/down between positions)
- [ ] `func_train` — moving platform along path corners
- [ ] `func_rotating` — continuously rotating object (fan, wheel)
- [ ] `func_pendulum` — swinging pendulum- [ ] Movement: `Think_LinearMove()`, `Think_AngularMove()`
- [ ] Path following: `path_corner` entity chain
- [ ] Speed, acceleration, deceleration

### Breakables
- [ ] `func_breakable` — destroyed by damage
- [ ] Health, damage threshold
- [ ] Destruction debris (type: glass, wood, stone, metal)
- [ ] Target firing on destruction
- [ ] Sound on break

### Others
- [ ] `func_static` — non-moving brush model
- [ ] `func_explodable` — explodes on destruction (radius damage)
- [ ] `func_vehicle` — vehicle base (jeep, tank in SP)
- [ ] `func_beam` — beam effect between entities

### Brush model rendering
- [ ] `func_*` entities reference inline BSP models (`*1`, `*2`, etc.)
- [ ] Verify `Godot_BSP_GetModelBounds()` / `Godot_BSP_GetModelSurfaces()` provide correct data
- [ ] Movement: brush model origin updates → MeshInstance3D transform update

## Build Verification
```bash
cd openmohaa && scons platform=linux target=template_debug -j$(nproc) dev_build=yes
```

## Documentation
Append `## Phase 102: func_* Audit ✅` to `TASKS.md`.

## DO NOT MODIFY
- `MoHAARunner.cpp` / `MoHAARunner.h`
