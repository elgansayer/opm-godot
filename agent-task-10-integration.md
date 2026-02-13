# Agent Task 10: MoHAARunner Integration, Game Flow & Platform Support

## Objective
You are the **integration agent**. Your job is threefold:
1. Wire all modules created by Agents 1–9 into `MoHAARunner.cpp` and `MoHAARunner.h`
2. Implement full game flow (title screen, new game, save/load, settings, campaign flow)
3. Add cross-platform build support (Windows, macOS)

You should START by implementing the game flow infrastructure (which is independent of other agents), then progressively integrate other agents' modules as they complete their work. Use their TASKS.md documentation to find the **"MoHAARunner Integration Required"** sections.

## Starting Point
Read `.github/copilot-instructions.md`, `openmohaa/AGENTS.md`, and `openmohaa/TASKS.md`. `MoHAARunner.cpp` (~4000 lines) is the central Godot node. `MoHAARunner.h` declares the class. `SConstruct` builds both the main .so and `cgame.so`. All new `.c`/`.cpp` files in `code/godot/` are auto-discovered.

## Scope — Phases 261–300, 301–350, plus cross-cutting integration

---

### Part 1: Module Integration (ongoing as other agents complete)

Read each agent's TASKS.md entries for **"MoHAARunner Integration Required"** sections and wire them in:

#### From Agent 1 (Audio):
- `#include "godot_music.h"` — music playback
- Call `Godot_Music_Init()` in `setup_audio()`
- Call `Godot_Music_Update(delta)` in `update_audio()`
- Add `AudioStreamPlayer *music_player` management
- Wire ubersound alias lookup into `load_wav_from_vfs()`

#### From Agent 2 (Shaders):
- `#include "godot_shader_material.h"`
- Replace `StandardMaterial3D` creation with `Godot_Shader_BuildMaterial(handle)`
- In `check_world_load()`: use multi-stage materials for BSP surfaces
- In `update_entities()`: use multi-stage materials for entity rendering
- In `update_shader_animations()`: update wave/animMap uniforms

#### From Agent 3 (BSP/Environment):
- `#include "godot_weather.h"`, `"godot_vertex_deform.h"`
- Call `Godot_Weather_Init()` in `check_world_load()`
- Call `Godot_Weather_Update(delta)` in `_process()`
- Apply fog volume data to BSP surface materials
- Apply vertex deform parameters to affected materials

#### From Agent 4 (Entity Performance):
- `#include "godot_mesh_cache.h"`, `"godot_entity_lighting.h"`, `"godot_weapon_viewport.h"`
- Replace direct mesh building with cache lookup in `update_entities()`
- Add lightgrid + dlight sampling in `update_entities()`
- Create weapon SubViewport in `setup_3d_scene()`
- Route `RF_FIRST_PERSON` entities to weapon viewport

#### From Agent 5 (UI):
- `#include "godot_ui_system.h"`, `"godot_ui_input.h"`
- Call `Godot_UI_Update()` in `_process()` for input mode management
- In `_unhandled_input()`: check `Godot_UI_IsActive()` for input routing
- Call `Godot_UI_RenderBackground()` in `update_2d_overlay()`
- Create UI CanvasLayer with higher z-index than HUD

#### From Agent 6 (VFX):
- `#include "godot_vfx.h"`, `"godot_screen_effects.h"`
- Call `Godot_VFX_Init(game_world)` in `setup_3d_scene()`
- Call `Godot_VFX_Update(delta)` in `_process()`
- Route `RT_SPRITE` entities through VFX system in `update_entities()`
- Apply camera shake in `update_camera()`
- Create screen effect overlays

#### From Agent 7 (Game Logic):
- `#include "godot_game_accessors.h"`
- Expose game state queries to GDScript if useful
- No major MoHAARunner changes expected

#### From Agent 8 (Network):
- `#include "godot_network_accessors.h"`
- Expose connection state, ping to GDScript
- Handle network error recovery in `_process()` error handling

#### From Agent 9 (Rendering Polish):
- `#include "godot_pvs.h"`, `"godot_debug_render.h"`, `"godot_shadow.h"`, etc.
- Call PVS culling before BSP rendering
- Call shadow update after entity update
- Apply gamma/tonemap to WorldEnvironment
- Call debug render update in `_process()`
- Wire cinematic display into `update_cinematic()`

---

### Part 2: Game Flow (Phases 261–270)

These are independent of other agents and can be built immediately:

#### Phase 261: Title Screen
- Detect engine state at boot (no map loaded, UI not yet initialised)
- Show MOHAA logo splash (load from VFS: `textures/mohmenu/` or similar)
- "Press any key to continue" text
- Transition to main menu (execute `togglemenu 1` or equivalent engine command)

#### Phase 262: New Game Flow
- Handle `ui_startgame` → difficulty selection → mission briefing → map load
- Pass difficulty cvar (`skill 0/1/2`) before map load
- Handle mission briefing text display during loading

#### Phase 263: Mission Completion
- Detect end-of-mission (map change to next SP level or final completion)
- Display statistics screen (if engine provides it)
- Medal awards display
- Transition to next mission or campaign complete screen

#### Phase 264: Save / Load Game
- Engine's `SV_SaveGame` / `SV_LoadGame` — verify they work under GDExtension
- Quick save (F5): `savegame quick`
- Quick load (F9): `loadgame quick`
- Expose save/load slots to GDScript for menu integration
- Handle save file location (`fs_homepath/save/`)

#### Phase 265: Multiplayer Quick Match
- Server browser UI driven by Agent 5's UI system
- Implement "Quick Match" logic: query servers, sort by ping, auto-connect
- Recent servers list (store in cvar or config file)

#### Phase 266: Create Server
- Map selection list (enumerate available BSP files via VFS)
- Game mode selection (`g_gametype` cvar)
- Player limit (`sv_maxclients`)
- Start server: `map <name>` or `spmap <name>` (single-player map)

#### Phase 267: Key Bindings
- Default MOHAA key layout (WASD, mouse, etc.)
- Stored in engine's key binding system (`bind` command)
- Engine already handles key binding — ensure it persists across sessions
- Write default bindings if none exist (`default.cfg`)

#### Phase 268: Audio Settings
- Map engine cvars to UI: `s_volume`, `s_musicvolume`, `s_dialogvolume`
- Forward to Godot audio bus volumes
- Sound quality settings (if applicable under Godot audio)

#### Phase 269: Video Settings
- Resolution: map to Godot `DisplayServer` resolution
- Fullscreen/windowed: `DisplayServer.window_set_mode()`
- Quality presets: set multiple engine + Godot cvars at once
- Texture quality (`r_picmip`), draw distance, effects quality

#### Phase 270: Network Settings
- Rate presets: modem, ISDN, cable, LAN → set `rate`, `snaps`, `cl_maxpackets`
- Netgraph toggle (engine's `cg_drawnetgraph`)

---

### Part 3: Campaign Testing (Phases 271–300)

Verify full game play flow by loading and testing progression through campaigns:
- **271–276:** Allied Assault missions (m1l1 through m6l3)
- **277:** Spearhead campaign (if mainta/ assets available)
- **278:** Breakthrough campaign (if maintt/ assets available)
- **279:** Scripted sequences execute correctly
- **280:** All objectives completable

Multiplayer mode testing:
- **281–290:** Each game mode with bots, map rotation, warmup, overtime

Integration testing:
- **291–300:** Extended play sessions, stability, performance, load times

---

### Part 4: Parity Verification (Phases 301–350)

Systematic comparison against upstream OpenMoHAA:
- **301–310:** Rendering parity (screenshots, lighting, shaders, HUD, fonts, skybox, fog)
- **311–320:** Audio parity (weapons, ambient, music, impacts, voice, 3D positioning)
- **321–330:** Gameplay parity (movement, weapons, damage, AI, scripting)
- **331–340:** Network parity (snapshots, bandwidth, prediction, protocol)
- **341–350:** Stress testing (max entities, max players, memory, error handling, shutdown)

---

### Part 5: Cross-Platform (Phases 156–160)

#### Phase 156: Windows Build
- Modify `SConstruct` to handle `platform=windows` properly
- MSVC or MinGW cross-compilation
- Handle Windows-specific `code/sys/sys_win32.c` compilation
- Replace Linux-specific socket calls if needed (`#ifdef _WIN32`)

#### Phase 157: macOS Build
- Modify `SConstruct` for `platform=macos`
- Handle `code/sys/sys_unix.c` (macOS compatible) or `sys_osx.c`
- Universal binary (x86_64 + arm64) if feasible
- Handle `dlopen` → macOS `dlsym` (should be identical on macOS)

## Files You OWN (exclusively modify)
| File | Purpose |
|------|---------|
| `code/godot/MoHAARunner.cpp` | Central integration — wire all modules |
| `code/godot/MoHAARunner.h` | Add new members, includes, method declarations |
| `code/godot/register_types.cpp` | Module init/shutdown |
| `openmohaa/SConstruct` | Build system — platform support, new defines |

## Files You Must NOT Touch
- `godot_sound.c` — owned by Agent 1
- `godot_shader_props.cpp/.h` — owned by Agent 2
- `godot_bsp_mesh.cpp/.h` — owned by Agent 3
- `godot_skel_model*.cpp/.h` — owned by Agent 4
- `godot_client_accessors.cpp` — owned by Agent 5
- `godot_renderer.c` — owned by Agent 9 for modifications
- `stubs.cpp` — owned by Agent 9 for new stubs
- `code/fgame/*.cpp` — owned by Agent 7
- Engine networking files — owned by Agent 8

You MAY `#include` any header created by other agents and call their public APIs.

## Architecture Notes

### Integration Order
Integrate modules in this priority order (least risk first):
1. Game accessors (Agent 7, 8) — pure data, no rendering changes
2. Audio improvements (Agent 1) — independent subsystem
3. Shader materials (Agent 2) — changes material creation
4. Entity performance (Agent 4) — changes entity update loop
5. BSP/environment (Agent 3) — changes world loading
6. UI system (Agent 5) — adds new overlay logic
7. VFX (Agent 6) — adds effect spawning
8. Rendering polish (Agent 9) — final visual tweaks

### Defensive Integration Pattern
When integrating a module, use compile-time guards:
```cpp
#if __has_include("godot_music.h")
#include "godot_music.h"
#define HAS_MUSIC_MODULE 1
#endif

// In _process():
#ifdef HAS_MUSIC_MODULE
    Godot_Music_Update(delta);
#endif
```
This way your MoHAARunner compiles even if other agents haven't finished yet.

### Game Flow State Machine
```
BOOT → TITLE_SCREEN → MAIN_MENU → {
    NEW_GAME → MISSION_BRIEFING → LOADING → IN_GAME → {
        PAUSED, SCOREBOARD, TEAM_SELECT, WEAPON_SELECT
    } → MISSION_COMPLETE → NEXT_MISSION / CAMPAIGN_COMPLETE
    
    LOAD_GAME → LOADING → IN_GAME
    
    MULTIPLAYER → SERVER_BROWSER / CREATE_SERVER → LOADING → IN_GAME → {
        SCOREBOARD, TEAM_SELECT, WEAPON_SELECT, CHAT
    }
    
    OPTIONS → { VIDEO, AUDIO, CONTROLS, NETWORK, GAME }
    
    QUIT → CONFIRM → EXIT
}
```

## Build & Test
```bash
cd openmohaa && rm -f .sconsign.dblite && scons platform=linux target=template_debug -j$(nproc) dev_build=yes
```

For Windows cross-compile (once implemented):
```bash
scons platform=windows target=template_debug -j$(nproc) dev_build=yes
```

## Documentation
- Update `openmohaa/TASKS.md` with all integration phase entries
- Update `.github/copilot-instructions.md` with new status as phases complete
- Update `openmohaa/AGENTS.md` if architecture changes significantly

## Merge Awareness
- **You are the LAST to merge.** All other agents should merge first; you integrate their work.
- If merging incrementally: your changes to `MoHAARunner.cpp` will conflict with each other across branches, so merge your integration work in one go after other agents complete.
- Use `#if __has_include(...)` guards so your branch compiles even without other agents' files present.
- `SConstruct` changes (platform support) are low-risk — they add new `elif` blocks that don't conflict with existing code.
- If other agents add `#include` lines or calls you also need, the merge conflict will be in `MoHAARunner.cpp` — easy to resolve since you're adding different lines.
