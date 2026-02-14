# Agent Task 37: SP Cutscenes, AI & Save/Load Audit

## Objective
Audit single-player features: scripted camera cutscenes (script_camera), NPC AI pathfinding, and save/load game functionality. These are critical for campaign gameplay.

## Files to Audit
- `code/fgame/camera.cpp` — Script camera for cutscenes
- `code/fgame/actor.cpp` / `code/fgame/actor.h` — NPC AI base class
- `code/fgame/navigate.cpp` — NPC pathfinding (Recast/Detour integration)
- `code/fgame/g_phys.cpp` — Physics for NPC movement
- `code/fgame/g_spawn.cpp` — Entity spawning
- `code/server/sv_savegame.cpp` — Save/load game
- `code/fgame/g_client.cpp` — Client (player) state save/restore

## Files to Create (EXCLUSIVE)
- `code/godot/godot_game_sp.c` — SP state accessor
- `code/godot/godot_game_sp.h` — Accessor declarations

## Accessor Functions
```c
int Godot_SP_IsCutsceneActive(void);       // letterbox/camera mode
int Godot_SP_GetObjectiveCount(void);      // total objectives
int Godot_SP_GetObjectiveComplete(int i);  // objective i completed?
int Godot_SP_CanSave(void);               // save allowed in current state
int Godot_SP_CanLoad(void);               // any save exists
```

## Audit Checklist

### 1. Script camera
- [ ] `script_camera` entity class exists and compiles
- [ ] Camera path interpolation (spline between waypoints)
- [ ] Letterbox mode (black bars top/bottom)
- [ ] Camera cuts vs smooth transitions
- [ ] Script commands: `cam setpath`, `cam follow`, `cam setfov`

### 2. NPC AI
- [ ] `Actor` class hierarchy compiles under Godot build
- [ ] `Actor::Think()` / `Actor::Idle()` state machine
- [ ] Pathfinding via Recast/Detour (code/thirdparty/recast-detour/)
- [ ] `navigate.cpp`: `FindPath()`, `FindPathToEntity()`
- [ ] AI combat: spot enemy, take cover, shoot, flee
- [ ] Squad behaviour: follow leader, formation

### 3. Recast/Detour
- [ ] Navigation mesh generated from BSP
- [ ] `dtNavMesh` / `dtNavMeshQuery` creation
- [ ] Path corridor following
- [ ] Obstacle avoidance

### 4. Save/Load
- [ ] `SV_SaveGame()` serialises: entity states, player inventory, script threads, world state
- [ ] `SV_LoadGame()` deserialises and restores
- [ ] Quick save (F5) and quick load (F9) keybinds
- [ ] Save file format compatible with upstream OpenMoHAA
- [ ] Memory safety during save/load (no gi.Malloc issues)

### 5. #ifdef issues
- [ ] Save/load may reference `SV_Malloc`/`SV_Free` — verify not shadowed
- [ ] Recast/Detour compilation under GODOT_GDEXTENSION
- [ ] Actor AI includes — verify no header conflicts

## Build Verification
```bash
cd openmohaa && scons platform=linux target=template_debug -j$(nproc) dev_build=yes
```

## Documentation
Append `## Phase 96-98: SP Features Audit ✅` to `TASKS.md`.

## DO NOT MODIFY
- `MoHAARunner.cpp` / `MoHAARunner.h`
