# Agent Task 32: Player Movement Physics Audit

## Objective
Audit and verify that player movement physics (bg_pmove.cpp) work correctly under the Godot GDExtension build. Verify walk, run, sprint, crouch, jump, prone, and lean mechanics match upstream OpenMoHAA behaviour.

## Scope
This is a CODE AUDIT task. Read the relevant engine source files, verify they compile correctly under `GODOT_GDEXTENSION`, and fix any issues found. Do NOT rewrite movement code — only add `#ifdef GODOT_GDEXTENSION` guards where needed.

## Files to Audit (READ, fix if needed)
- `code/fgame/bg_pmove.cpp` — Core movement physics
- `code/fgame/bg_public.h` — Movement constants
- `code/fgame/bg_local.h` — Internal movement types
- `code/fgame/player.cpp` — Player entity class
- `code/fgame/playerbot.cpp` — Bot movement (if it uses same pmove)

## Files to Create (EXCLUSIVE)
- `code/godot/godot_game_movement.c` — C accessor for movement state (if needed)
- `code/godot/godot_game_movement.h` — Accessor declarations

## Audit Checklist

### 1. Gravity & sv_fps
- [ ] Verify `pm->ps->gravity` is correctly set from `sv_gravity` cvar
- [ ] Verify `pml.frametime` is derived from `sv_fps` (not hardcoded 20Hz)
- [ ] Verify `pm->ps->speed` matches expected values for each stance

### 2. Walk/Run/Sprint
- [ ] `PM_WalkMove()`: forward/backward/strafe velocity
- [ ] `PM_Accelerate()`: acceleration model
- [ ] `PM_Friction()`: ground friction
- [ ] Sprint: `PMF_SPRINT` flag, stamina drain if applicable

### 3. Crouch/Prone
- [ ] `PM_CrouchMove()`: reduced speed, hull change
- [ ] Prone: reduced hull, very slow speed
- [ ] Transition: standing↔crouch↔prone (no clip through ceilings)
- [ ] `pm->mins` and `pm->maxs` correctly set per stance

### 4. Jump
- [ ] `PM_CheckJump()`: initial velocity, jump height
- [ ] Air movement: `PM_AirMove()`, air acceleration
- [ ] Double-jump prevention
- [ ] Fall damage calculation: `PM_CrashLand()`

### 5. Lean
- [ ] Left/right lean (MOHAA-specific)
- [ ] Lean collision traces
- [ ] Camera offset during lean

### 6. Water/Ladder
- [ ] `PM_WaterMove()`: swimming physics
- [ ] `PM_LadderMove()`: ladder climbing
- [ ] Water level detection: `pm->waterlevel`

### 7. #ifdef issues
- [ ] Check for any `#ifdef` guards that might disable movement code
- [ ] Verify `GAME_DLL` is defined (required for bg_pmove.cpp)
- [ ] Check `pm->trace()` function pointer is valid (it's `SV_Trace` on server)

## What to Fix
- Add `#ifdef GODOT_GDEXTENSION` only if there's a genuine compile/link issue
- If `pm->trace` or `pm->pointcontents` pointers are NULL, document the issue
- Do NOT change movement constants or gameplay behaviour

## Build Verification
```bash
cd openmohaa && scons platform=linux target=template_debug -j$(nproc) dev_build=yes
```

## Documentation
Append `## Phase 86: Player Movement Audit ✅` to `TASKS.md` with findings.

## DO NOT MODIFY
- `MoHAARunner.cpp` / `MoHAARunner.h`
- Any code/godot/ files owned by other agents
