# Agent Task 35: Game Mode Logic Audit (FFA/TDM/OBJ)

## Objective
Audit game mode initialisation, round logic, scoring, warmup, and overtime for FFA, TDM, Objective, Liberation, and Demolition modes. Verify they initialise correctly and run their frame logic under the Godot build.

## Files to Audit
- `code/fgame/g_main.cpp` — `G_InitGame()`, game mode init
- `code/fgame/g_spawn.cpp` — Entity spawning per mode
- `code/fgame/g_utils.cpp` — Utility functions
- `code/fgame/dm_manager.cpp` — Deathmatch/team manager
- `code/fgame/dm_team.cpp` — Team logic
- `code/fgame/player.cpp` — Player spawn/respawn per mode
- `code/fgame/g_cmds.cpp` — Vote system, admin commands

## Files to Create (EXCLUSIVE)
- `code/godot/godot_game_modes.c` — Game mode state accessor
- `code/godot/godot_game_modes.h` — Accessor declarations

## Accessor Functions
```c
int Godot_GameMode_GetType(void);           // g_gametype value
int Godot_GameMode_GetRoundState(void);     // round in progress, warmup, intermission
int Godot_GameMode_GetScoreLimit(void);     // fraglimit/roundlimit
int Godot_GameMode_GetTimeLimit(void);      // timelimit
int Godot_GameMode_GetTeamScore(int team);  // team 0/1 score
int Godot_GameMode_IsWarmup(void);          // warmup period active
int Godot_GameMode_GetPlayerCount(void);    // active players
```

## Audit Checklist

### 1. Game type initialisation
- [ ] `g_gametype` cvar: 0=FFA, 1=TDM, 2=Roundbased, 3=Objective, 4=Liberation, 5=Demolition
- [ ] `G_InitGame()` sets up correct mode manager
- [ ] Entity spawn filtering by game type (some entities only in specific modes)

### 2. FFA (Free For All)
- [ ] Spawn at `info_player_deathmatch`
- [ ] Scoring: per-kill, `fraglimit` ends match
- [ ] No team assignment

### 3. TDM (Team Deathmatch)
- [ ] Team selection: Allies/Axis/Auto
- [ ] Team spawn points: `info_player_allied` / `info_player_axis`
- [ ] Team scoring: kill = +1 to team
- [ ] Friendly fire controlled by `g_teamdamage`

### 4. Objective
- [ ] Objective entities: `func_objective`, `trigger_objective`
- [ ] Attackers vs defenders
- [ ] Round timer, round switching
- [ ] Bomb plant/defuse mechanics

### 5. Warmup/Intermission
- [ ] `g_warmup` — countdown before match starts
- [ ] Intermission: scoreboard display, map vote, next map

### 6. Scoring & limits
- [ ] `fraglimit`, `timelimit`, `roundlimit` cvars
- [ ] Score updates via configstrings
- [ ] Overtime/sudden death

## Build Verification
```bash
cd openmohaa && scons platform=linux target=template_debug -j$(nproc) dev_build=yes
```

## Documentation
Append `## Phase 91: Game Mode Audit ✅` to `TASKS.md`.

## DO NOT MODIFY
- `MoHAARunner.cpp` / `MoHAARunner.h`
