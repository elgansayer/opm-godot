# Agent Task 07: Game Logic Verification & Entity Audit

## Objective
Systematically verify and fix game logic parity: player movement physics, weapon mechanics, hit detection, game modes, map scripting, single-player features, entity types, script engine, and physics/collision. This agent works primarily on engine-side code (`code/fgame/`, `code/script/`, `code/qcommon/`) ensuring the server-side game logic runs identically to upstream OpenMoHAA.

## Starting Point
Read `.github/copilot-instructions.md`, `openmohaa/AGENTS.md`, and `openmohaa/TASKS.md`. The engine's game logic compiles and runs — maps load, entities spawn, scripts execute. But many game systems have not been verified under the Godot integration. Some engine behaviour may differ due to the `GODOT_GDEXTENSION` and `DEDICATED` defines or due to timing differences with Godot's frame loop.

## Scope — Phases 86–120

### Phase 86: Player Movement Physics
- Verify `bg_pmove.cpp` produces identical movement results
- Test: walking, running, sprinting, crouching, jumping, prone
- Ensure `sv_fps` (server framerate) is correctly honoured
- Verify framerate-independent movement (delta time handling)
- Check `PM_CmdScale`, `PM_Accelerate`, `PM_AirAccelerate`, `PM_Friction`
- If movement differs, trace through `Pmove()` comparing with upstream

### Phase 87: Weapon Mechanics
- Fire, reload, switch, drop, pickup weapon actions
- Bullet spread, recoil patterns, damage falloff values
- Melee attacks (knife, bayonet)
- Verify weapon scripts in `global/weapons/` execute correctly
- Check weapon state machine transitions
- Verify ammunition tracking and depletion

### Phase 88: Hit Detection & Damage
- Trace-based hitscan weapons via BSP + entity collision (`SV_Trace`)
- Area damage (grenades, explosions, artillery) — `G_RadiusDamage()`
- Locational damage system (headshots, limb damage) — `G_LocationDamage()`
- Verify damage values match upstream for all weapon types
- Check armour damage reduction

### Phase 91: Game Modes
- **Free For All (FFA):** Spawn, frag counting, time/frag limit, scoreboard
- **Team Deathmatch (TDM):** Team spawns, team scoring, friendly fire
- **Objective:** Objective entity state machine, plant/defuse, round logic
- **Liberation:** Tag/capture mechanics
- **Demolition:** Bomb plant/defuse mechanics
- Verify `g_gametype` cvar correctly switches between modes
- Check round restart logic, warmup, overtime

### Phase 95: Map Scripting
- `.scr` scripts controlling level flow via Morfuse engine
- Verify all script commands execute (test with known scripts from stock maps)
- Check script thread management: `thread`, `waitthread`, `waittill`
- Test `trigger`, `use`, `damage`, `kill` event handlers
- Verify script-spawned entities function correctly
- Check `waitframe`, `wait`, `waittill animdone` timing accuracy

### Phase 96: Single Player — Cutscenes
- Scripted camera movements via `script_camera` entities
- NPC dialogue triggers and animations
- Letterbox mode (cinematic black bars) — `CG_Letterbox()` state
- Verify camera interpolation between script waypoints

### Phase 97: Single Player — AI Companions
- Friendly NPC pathfinding using Recast/Detour navigation
- Squad following behaviour
- AI combat alongside player (cover, fire, advance)
- Verify bot/AI code paths work under Godot integration

### Phase 98: Single Player — Checkpoints & Saves
- Investigate save/load game state viability under GDExtension
- Engine's `SV_SaveGame` / `SV_LoadGame` functionality
- If feasible: ensure entity state, script state, player state serialise correctly
- If not feasible: document limitations and mark as future work

### Phase 99: Inventory & Item System
- Health packs, ammo, grenades pickup and use
- Pickup entity interaction (`item_health`, `item_ammo`, `weapon_*`)
- Inventory limits and stacking rules
- Verify entity touch triggers

### Phase 100: Door / Mover / Elevator Entities
- `func_door`: open/close with collision, sound triggers, wait times
- `func_rotating`: continuous rotation or triggered
- `func_plat`: elevator platforms with wait states
- `func_train`: path-following movers
- Brush model movement with proper collision updates
- Damage-on-block behaviour

### Phases 101–110: Entity Types Audit
Systematically verify every entity type in `code/fgame/`:
- **101:** `trigger_*` — hurt, push, teleport, relay, multiple, once, use
- **102:** `func_*` — breakable, explodable, vehicle, static, beam
- **103:** `info_*` — player_start, teleport_destination, null, notnull
- **104:** `light_*`, `misc_*` — misc_model, misc_gamemodel, misc_particle_effects
- **105:** `weapon_*` — all weapon pickup entities
- **106:** `worldspawn` — global settings, gravity, ambient sound
- **107:** `path_*` — waypoint, spline, corner nodes
- **108:** `script_*` — script_origin, script_model, script_object
- **109:** `animate_*` — animated scene objects
- **110:** Custom MOHAA types — turret_*, bed, chair, etc.

For each: verify spawn function is called, entity thinks/acts correctly, cleanup works.

### Phases 111–115: Script Engine Verification
- **111:** Verify all Morfuse built-in commands (`exec`, `goto`, `print`, `huddraw_*`, etc.)
- **112:** Thread management — `waitthread`, `waittill`, nested threads
- **113:** Event system — `waittill animdone`, `damaged`, `trigger`, custom events
- **114:** Entity spawning/modification from scripts — `spawn`, `remove`, `setsize`, `link`
- **115:** Timer accuracy — `waitframe`, `wait <seconds>`, scheduled events

### Phases 116–120: Physics & Collision
- **116:** BSP clip model collision (player vs world) — `CM_BoxTrace`, `CM_PointContents`
- **117:** Entity vs entity collision (pushers, triggers, clipmask)
- **118:** Projectile physics (grenade arcs, rocket travel, bullet traces)
- **119:** Water physics (swimming, diving, water damage, waterlevel detection)
- **120:** Fall damage, world damage volumes, kill triggers

## Files You OWN (create or primarily modify)

### New files to create
| File | Purpose |
|------|---------|
| `code/godot/godot_game_accessors.c` | C accessors for game state needed by other agents (game mode, weapon state, player state) |
| `code/godot/godot_game_accessors.h` | Game accessor header |

### Engine files you may modify (with `#ifdef GODOT_GDEXTENSION` guards)
| File | What to change |
|------|----------------|
| `code/fgame/g_main.cpp` | Fix any game init/shutdown issues under GDExtension |
| `code/fgame/g_spawn.cpp` | Entity spawn fixes if needed |
| `code/fgame/g_phys.cpp` | Physics fixes if timing differs |
| `code/fgame/bg_pmove.cpp` | Movement fixes if needed |
| `code/fgame/player.cpp` | Player entity fixes |
| `code/fgame/weapon*.cpp` | Weapon mechanics fixes |
| `code/fgame/navigate.cpp` | AI navigation fixes |
| `code/script/*.cpp` | Script engine fixes if commands fail |
| Any `code/fgame/*.cpp` | Bug fixes wrapped in `#ifdef GODOT_GDEXTENSION` |

**ALL changes to engine files MUST be wrapped in `#ifdef GODOT_GDEXTENSION` / `#endif`.**

## Files You Must NOT Touch
- `MoHAARunner.cpp` / `MoHAARunner.h` — do NOT modify.
- `godot_renderer.c` — not your domain.
- `godot_sound.c` — owned by Agent 1.
- `godot_shader_props.cpp/.h` — owned by Agent 2.
- `godot_bsp_mesh.cpp/.h` — owned by Agent 3.
- `godot_skel_model*.cpp/.h` — owned by Agent 4.
- `godot_client_accessors.cpp` — owned by Agent 5.
- `SConstruct` — auto-discovers new files.
- Files in `code/godot/` created by other agents.

## Architecture Notes

### Verification Approach
For each system:
1. Read the upstream OpenMoHAA code to understand expected behaviour
2. Check if any `#ifdef GODOT_GDEXTENSION` or `DEDICATED` guards change the code path
3. If the code path differs, trace through and fix with minimal, guarded patches
4. If the code path is identical, mark as verified in TASKS.md

### Common Issues to Watch For
- **Timing:** `Com_Frame` under Godot runs once per Godot `_process()` call. If engine code assumes a fixed tick rate, verify `sv_fps` / `com_maxfps` are honoured.
- **`DEDICATED` define:** common.c/memory.c `#undef` it under `GODOT_GDEXTENSION`, but other files may check it. Ensure server-only code paths aren't skipped accidentally.
- **Function pointers:** `gi.*` (game import) functions may differ from standalone operation. Verify `gi.Trace`, `gi.PointContents`, `gi.SetBrushModel` work correctly.
- **File loading:** Scripts loaded via `gi.FS_ReadFile` — verify pk3 search path ordering is correct for AA/SH/BT.

### Game Accessor Design
```c
// godot_game_accessors.h
#ifdef __cplusplus
extern "C" {
#endif

int Godot_Game_GetGameType(void);           // g_gametype->integer
int Godot_Game_GetMaxClients(void);         // sv_maxclients->integer
int Godot_Game_IsRoundBased(void);          // whether current gametype uses rounds
const char *Godot_Game_GetScriptError(void); // last script error message
int Godot_Game_GetPlayerHealth(int clientNum);
int Godot_Game_GetPlayerTeam(int clientNum);

#ifdef __cplusplus
}
#endif
```

## Integration Points
Document in TASKS.md:
1. Game accessor functions available for other agents (especially Agent 5 UI, Agent 10 Integration)
2. Any engine code fixes that require rebuild (SCons should pick up automatically)
3. Any new cvars or commands added
4. Entity types verified and their status

## Build & Test
```bash
cd openmohaa && rm -f .sconsign.dblite && scons platform=linux target=template_debug -j$(nproc) dev_build=yes
```

## Documentation
Add Phase entries (86–120) to `openmohaa/TASKS.md`. For entity audit phases, use a checklist format:
```markdown
## Phase 101: trigger_* Entity Audit
- [x] trigger_hurt — spawns, applies damage, respects wait time
- [x] trigger_push — launches player with correct velocity
- [ ] trigger_teleport — needs fix: destination lookup fails (see Phase 101 notes)
```

## Merge Awareness
- Your primary work is in `code/fgame/` and `code/script/` — no other agent touches these directories.
- All changes are `#ifdef GODOT_GDEXTENSION` guarded — safe for upstream mergeability.
- Your `godot_game_accessors.c/.h` files are new — zero conflict risk.
- Agent 5 (UI) may need your game accessor functions — keep the header clean and well-documented.
- Agent 8 (Network) works in `code/qcommon/` and `code/server/` — there should be no overlap unless you fix bugs in server-side trace code. If you must edit `code/server/*.c`, coordinate via comments in TASKS.md.
