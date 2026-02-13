# Copilot Instructions: OpenMoHAA → Godot GDExtension Port

## Project Overview
This workspace ports **OpenMoHAA** (an ioquake3 / IdTech 3 derivative) into **Godot 4.2** as a GDExtension shared library. The build is **monolithic** — fgame, server, script engine, client, UI, and bot code are all linked into one `.so`/`.dll` via SCons (no dlopen for the main library). A separate `cgame.so` is built alongside and loaded at runtime via `dlopen`. Symbol conflicts are resolved with `-z muldefs` and `#ifndef GODOT_GDEXTENSION` guards.

**Compatibility constraint:** The port must remain **fully compliant** with existing MOHAA, Spearhead (SH), and Breakthrough (BT) clients and servers. All original assets — `.pk3` archives, `.scr` scripts, `.tik` files, BSP maps, shader definitions — must load and behave identically to upstream OpenMoHAA. Do not replace, wrap, or re-implement the engine's native VFS (`files.cpp`) or script loader; they already handle pk3 mounting, search-path ordering, and `com_target_game` / `com_basegame` selection for all three games (`main/`, `mainta/`, `maintt/`).

## Repository Layout
```
opm-godot/                    ← Git root
├── .github/
│   └── copilot-instructions.md  ← THIS FILE
├── godot-cpp/                ← Git submodule (branch 4.2, https://github.com/godotengine/godot-cpp)
├── openmohaa/                ← Engine source (tracked as regular files, NOT a submodule)
│   ├── SConstruct            ← Main SCons build file for GDExtension
│   ├── TASKS.md              ← Full phase-by-phase implementation log
│   ├── AGENTS.md             ← Agent directives
│   ├── code/
│   │   ├── godot/            ← ALL Godot-specific glue code lives here
│   │   │   ├── MoHAARunner.cpp/.h        ← Godot Node: Com_Init/Com_Frame, error recovery, 3D scene, HUD, audio, entities
│   │   │   ├── register_types.cpp        ← GDExtension entry point; calls Com_Shutdown() in module terminator
│   │   │   ├── stubs.cpp                 ← ~100 no-op stubs for Sys_Get*API, UI, VM, misc
│   │   │   ├── godot_renderer.c          ← Stub refexport_t (~80 functions) + entity/poly/swipe/2D capture buffers
│   │   │   ├── godot_sound.c             ← Sound event capture: S_*/MUSIC_* with queue + accessor API
│   │   │   ├── godot_input.c             ← IN_Init/Shutdown/Frame stubs (actual input via godot_input_bridge)
│   │   │   ├── godot_input_bridge.c      ← Godot key/mouse → engine SE_KEY/SE_MOUSE/SE_CHAR injection
│   │   │   ├── godot_bsp_mesh.cpp/.h     ← BSP parser: world mesh, terrain, lightmaps, mark fragments, entity tokens
│   │   │   ├── godot_shader_props.cpp/.h ← .shader file parser: transparency, blend, cull, tcMod, skybox
│   │   │   ├── godot_skel_model.cpp/.h   ← TIKI skeletal mesh builder (ArrayMesh from SKD/SKC/SKB)
│   │   │   ├── godot_skel_model_accessors.cpp ← C++ accessor for TIKI data (dtiki_t, skelHeaderGame_t)
│   │   │   ├── godot_client_accessors.cpp     ← Client state: keyCatchers, guiMouse, paused, SetGameInputMode
│   │   │   ├── godot_server_accessors.c       ← Server state: sv.state, svs.mapName, svs.iNumClients
│   │   │   └── godot_vfs_accessors.c          ← VFS read helper for Godot-side file loading
│   │   ├── qcommon/          ← Core engine (cvars, commands, VFS, memory, net)
│   │   ├── server/           ← Dedicated/listen server
│   │   ├── client/           ← Client state, prediction, keys, screen
│   │   ├── fgame/            ← Server-side game logic, entities, AI
│   │   ├── cgame/            ← Client-side game (compiled as separate cgame.so)
│   │   ├── script/           ← Morfuse script compiler & executor
│   │   ├── tiki/, skeletor/  ← TIKI model & animation loading
│   │   ├── uilib/            ← MOHAA menu/widget system
│   │   ├── botlib/           ← Bot pathfinding & AI
│   │   ├── gamespy/          ← GameSpy master-server support
│   │   └── thirdparty/       ← Recast/Detour navigation, SDL libs
│   ├── bin/                  ← Build output (gitignored): libopenmohaa.so, libcgame.so
│   └── build/                ← Object files (gitignored)
├── project/                  ← Godot editor project for testing
│   ├── Main.gd, Main.tscn   ← GDScript entry point
│   ├── project.godot         ← Godot project config
│   ├── openmohaa.gdextension
│   └── bin/                  ← Deployed .so (gitignored)
├── build.sh                  ← Build + deploy script
├── test.sh                   ← Headless smoke test
└── .gitignore
```

## Current Status — Phase 38 Complete
**Phases 1–38 are done.** The engine boots, loads maps, renders BSP world geometry with textures/lightmaps/shaders/terrain/patches/skybox, renders animated skeletal models (TIKI), plays positional 3D audio, handles keyboard/mouse input, draws HUD overlay with fonts, supports decals/marks/polys/sprites/beams/swipes, and exits cleanly.

See `openmohaa/TASKS.md` for the full phase-by-phase implementation log with technical details.

### What works
- Full client+server engine lifecycle (Com_Init → Com_Frame → Com_Shutdown)
- BSP world rendering: planar surfaces, triangle soups, Bézier patches, terrain
- Textures, lightmaps (128×128 overbright), .shader transparency/blend/cull/tcMod
- Skybox cubemaps from sky shaders
- TIKI skeletal models with CPU skinning animation
- Static BSP models (furniture, props) and brush sub-models (doors, movers)
- 3D positional audio (WAV from VFS, AudioStreamPlayer3D pool)
- Keyboard/mouse input bridge (Godot → engine event queue)
- 2D HUD overlay (health, ammo, compass, crosshair, fonts)
- Decals (mark fragments via BSP tree walk), polys, sprites, beams, swipes
- Entity colour tinting, alpha transparency, parenting
- Fog rendering, lightgrid sampling
- Shader animation (tcMod scroll/rotate/scale/turb)
- Error recovery (longjmp, no exit()), clean shutdown (Z_MarkShutdown)

### What's next (remaining work)
- **Skeletal animation LOD** — `skelHeaderGame_t.lodIndex[10]` + `pCollapse`/`pCollapseIndex` progressive mesh
- **Music playback** — MUSIC_* state is captured but not yet played through Godot audio
- **Network multiplayer testing** — engine networking is functional but untested with real clients
- **Performance optimisation** — per-frame mesh rebuilds for animated entities; material caching
- **Expansion pack support** — SH/BT game dirs (`mainta/`, `maintt/`) tested minimally
- **Windows/macOS builds** — only Linux tested; SCons has platform stubs

## Key Conventions
- **Language:** British English (en-GB) in comments and docs.
- **Preprocessor guard:** All engine patches must be wrapped in `#ifdef GODOT_GDEXTENSION` / `#endif` to keep upstream mergeability. Never modify engine behaviour unconditionally.
- **Active defines (main .so):** `DEDICATED`, `GODOT_GDEXTENSION`, `GAME_DLL`, `BOTLIB`, `WITH_SCRIPT_ENGINE`, `APP_MODULE`.
- **Active defines (cgame.so):** `CGAME_DLL` (only — no DEDICATED, no GODOT_GDEXTENSION).
- **No raw `malloc`/`free` in new C++ code.** Prefer `std::unique_ptr`, `std::vector`, or Godot's `memnew`/`memdelete`.
- **Coordinate system:** id Tech 3 (X=Forward, Y=Left, Z=Up, inches) → Godot (X=Right, Y=Up, -Z=Forward, metres). Scale: `MOHAA_UNIT_SCALE = 1/39.37`.

## Critical Patterns

### Engine patch pattern — `#ifdef GODOT_GDEXTENSION`
Every modification to upstream engine files **must** be wrapped. Two forms are used:
```c
// POSITIVE guard — inject Godot-specific behaviour:
#ifdef GODOT_GDEXTENSION
    // Under Godot, never block — Godot drives the frame rate.
    NET_Sleep(0);
    break;
#else
    // ...original engine code...
#endif

// NEGATIVE guard — suppress symbols that conflict with the monolithic link:
#ifndef GODOT_GDEXTENSION
void *(*SV_Malloc)(int size);   // would shadow sv_game.c's real SV_Malloc
void (*SV_Free)(void *ptr);
#endif
```
Patched upstream files: `sys_main.c`, `common.c`, `memory.c`, `sv_main.c`, `qcommon.h`, `server.h`, `snd_public.h`, `g_main.cpp`, `g_main.h`, `mem_blockalloc.cpp`, `con_arrayset.h`, `con_set.h`, `script.cpp`, `mem_tempalloc.cpp`, `lightclass.cpp`, `cl_scrn.cpp`, `cl_ui.cpp`, `uifont.cpp`.

### Memory safety — `gi.Malloc`/`gi.Free` teardown crash
During library unload, `gi.Malloc`/`gi.Free` function pointers become NULL before global C++ destructors run (e.g. `ScriptMaster::~ScriptMaster`). Any allocator call site reachable from destructors **must** use the safe wrappers:
```c
// Defined in code/fgame/g_main.h, under #ifdef GODOT_GDEXTENSION
static inline void *gi_Malloc_Safe(int size) { return gi.Malloc ? gi.Malloc(size) : malloc(size); }
static inline void  gi_Free_Safe(void *ptr)  { if (gi.Free) gi.Free(ptr); else free(ptr); }
```
Already applied in: `mem_blockalloc.cpp`, `con_arrayset.h`, `con_set.h`, `script.cpp`, `mem_tempalloc.cpp`, `lightclass.cpp`.

### Error recovery — no `exit()` under Godot
`Sys_Error` and `Sys_Quit` must never call `exit()`. They longjmp to `godot_error_jmpbuf` set up in `MoHAARunner::_ready()`/`_process()`. The `Q_NO_RETURN` attribute is stripped from their declarations in `qcommon.h` under `GODOT_GDEXTENSION` so the compiler doesn't assume they never return.

### Shutdown safety — `Z_MarkShutdown` and cgame symbol visibility
During `exit()`, global C++ destructors (e.g. `~con_arrayset` for `Event::commandList`) call `Z_Free`/`ARRAYSET_Free`/`SET_Free`. Four mechanisms prevent crashes:
1. **`Z_MarkShutdown()`** (in `memory.c`) — marks `Z_Free` as a no-op and `Z_TagMalloc` as a system-`malloc` fallback. Called from `MoHAARunner::~MoHAARunner()` and `uninitialize_openmohaa_module()` after `Com_Shutdown()`.
2. **cgame.so uses `-fvisibility=hidden`** — prevents ELF dynamic linker from interposing cgame's template instantiations (which use `cgi.Free`) onto the main .so's copies (which use `Z_Free`). Only `GetCGameAPI` is exported.
3. **`Sys_UnloadCGame` does NOT `dlclose`** — avoids unmapping cgame code pages that might still be referenced by atexit handlers.
4. **Safe `cgi` wrappers** — in `con_arrayset.h`/`con_set.h`, `CGAME_DLL + GODOT_GDEXTENSION` sections use inline functions that check `cgi.Free`/`cgi.Malloc` for NULL before calling, falling back to `free()`/`malloc()`.

### Header conflict boundary — C accessor layer
Engine headers (`server.h`, `g_local.h`) cannot be included in godot-cpp C++ translation units due to macro/type collisions. When you need to read engine state from `MoHAARunner.cpp`, add a thin C function in an accessor file and call it via `extern "C"`.

**Existing accessor files:**
| File | Language | Purpose |
|------|----------|---------|
| `godot_server_accessors.c` | C | `sv.state`, `svs.mapName`, `svs.iNumClients` |
| `godot_client_accessors.cpp` | C++ | `keyCatchers`, `in_guimouse`, `paused`, `SetGameInputMode` |
| `godot_vfs_accessors.c` | C | `Godot_VFS_ReadFile`, `Godot_VFS_FreeFile` |
| `godot_input_bridge.c` | C | Key/mouse → `Com_QueueEvent(SE_KEY/SE_MOUSE/SE_CHAR)` |
| `godot_skel_model_accessors.cpp` | C++ | TIKI mesh extraction, bone preparation, CPU skinning |

### Adding stubs for unresolved symbols
When linking pulls in new client/UI/renderer symbols, add a no-op stub in `stubs.cpp` with the correct signature. Check `code/null/null_client.c` for reference signatures.

### Renderer stub architecture
`godot_renderer.c` provides the full `refexport_t` function table (returned by `GetRefAPI()`). It captures engine render calls into buffers that `MoHAARunner.cpp` reads each frame:
- **Entity buffer** (`gr_entities[1024]`) — position, animation, model handle, shader RGBA
- **Dynamic light buffer** (`gr_dlights[64]`) — position, colour, intensity
- **2D command buffer** (`gr_2d_cmds[4096]`) — HUD draw calls (textured quads, solid rects)
- **Poly buffer** (`gr_polys[2048]`) — triangle fan polygons for effects
- **Swipe state** — sword/knife trail points
- **Terrain mark buffer** (`gr_terrain_marks[256]`) — decal mark polygons
- **Shader table** (`gr_shaders[2048]`) — name↔handle mapping
- **Model table** (`gr_models[1024]`) — TIKI/brush/sprite model registration
- **Font tables** — RitualFont parser for `.RitualFont` files

## Build & Test Workflow

### Prerequisites
- **Godot 4.2** (must be in PATH as `godot`)
- **SCons** (`pip install scons`)
- **Linux build tools:** `gcc`, `g++`, `make`, `pkg-config`
- **Libraries:** `zlib`, `libdl` (standard on Linux)
- **Game assets (for runtime testing only — NOT needed for compilation):**
  `~/.local/share/openmohaa/main/` must contain `Pak0.pk3`–`Pak6.pk3` from a MOHAA installation

### Build commands
```bash
# Full build (from repo root)
./build.sh

# Or manually (from openmohaa/):
scons platform=linux target=template_debug -j$(nproc) dev_build=yes

# Deploy to project (build.sh does this automatically):
cp -f openmohaa/bin/libopenmohaa.so project/bin/libopenmohaa.so
cp -f openmohaa/bin/libcgame.so ~/.local/share/openmohaa/main/cgame.so

# Headless smoke test (requires game assets):
cd project && godot --headless --quit-after 5000
```

### Build outputs
- `openmohaa/bin/libopenmohaa.so` — main GDExtension library (~57 MB debug)
- `openmohaa/bin/libcgame.so` — client-game module (~4.7 MB)

### Compilation-only verification (no game assets needed)
```bash
cd openmohaa && scons platform=linux target=template_debug -j$(nproc) dev_build=yes
# Success = both .so files produced in bin/
```

**SCons cache gotcha:** After editing widely-included headers (e.g. `qcommon.h`), delete `openmohaa/.sconsign.dblite` to force a full rebuild — SCons sometimes misses transitive dependencies.

### Clone instructions (for cloud agents)
```bash
git clone --recursive https://github.com/elgansayer/opm-godot.git
cd opm-godot
# godot-cpp submodule is auto-cloned by --recursive (branch 4.2)
# openmohaa/ is regular tracked source, not a submodule
```

## Asset & VFS Architecture
The engine's VFS (`code/qcommon/files.cpp`) is fully functional and must not be bypassed:
- `fs_basepath` / `fs_homedatapath` resolve to `~/.local/share/openmohaa` (set via engine defaults)
- `fs_homepath` resolves to `~/.config/openmohaa` (user configs)
- `com_basegame` defaults to `"main"` (`BASEGAME` in `q_shared.h`); `com_target_game` selects AA (0), SH (1), or BT (2)
- Expansion game dirs: `main/` (AA), `mainta/` (SH), `maintt/` (BT) — pk3 files searched in descending pak order
- `.scr` scripts loaded via `gi.FS_ReadFile` → compiled by `code/script/` → executed by `ScriptMaster` in `code/fgame/`
- All I/O goes through the engine's `FS_*` functions; never use `fopen`/`std::ifstream` for game assets
- **Note:** Game assets (pk3 files) are NOT in the repo — they come from a MOHAA installation. Build/compilation does NOT require them; only runtime testing does.

## When Adding Engine Patches
1. Wrap in `#ifdef GODOT_GDEXTENSION` with a one-line comment explaining *why*.
2. If the patch touches allocators reachable from destructors, use `gi_Malloc_Safe`/`gi_Free_Safe`.
3. If you need engine state in `MoHAARunner.cpp`, add a C accessor in the appropriate accessor file (see table above).
4. Test with `scons` (GDExtension build). Test with upstream CMake if possible.
5. Document the change in the relevant Phase section of `TASKS.md`.

## Architecture Notes for Agents

### MoHAARunner.cpp structure (~4000 lines)
The main Godot node that orchestrates everything. Key methods:
- `_ready()` — `Com_Init`, setjmp, signal setup, 3D scene creation
- `_process(delta)` — `Com_Frame`, camera update, entity update, HUD, audio, input enforcement
- `_unhandled_input()` — key/mouse → engine event injection
- `setup_3d_scene()` — creates Camera3D, DirectionalLight3D, WorldEnvironment
- `check_world_load()` — detects map change, loads BSP, textures, static models, skybox
- `update_camera()` — reads refdef_t via accessor, updates Camera3D transform + FOV + fog
- `update_entities()` — reads entity buffer, builds/caches meshes (skeletal or brush), applies transforms
- `update_2d_overlay()` — reads 2D command buffer, draws HUD via RenderingServer
- `update_audio()` — reads sound event queue, manages AudioStreamPlayer3D pool
- `update_polys()`, `update_swipe_effects()`, `update_terrain_marks()` — effect rendering
- `update_shader_animations(delta)` — tcMod UV scroll/rotate/scale

### Data flow per frame
```
Com_Frame()
  ├── SV_Frame()     → server logic, entity updates, script execution
  ├── CL_Frame()     → client prediction, snapshot processing
  │   └── CG_DrawActiveFrame()  → entity submission via GR_AddRefEntityToScene
  │       └── GR_RenderScene()  → captures refdef (camera), entity buffer, dlights
  ├── SCR_UpdateScreen()
  │   └── GR_DrawStretchPic/Box → captures 2D HUD commands
  └── S_Update()     → captures sound events

MoHAARunner::_process()
  ├── Com_Frame()  [above]
  ├── update_camera()         → read refdef → Camera3D
  ├── update_entities()       → read entity buffer → MeshInstance3D pool
  ├── update_2d_overlay()     → read 2D cmds → CanvasLayer
  ├── update_audio()          → read sound events → AudioStreamPlayer3D pool
  ├── update_polys()          → read poly buffer → MeshInstance3D
  ├── update_swipe_effects()  → read swipe data → MeshInstance3D
  ├── update_terrain_marks()  → read terrain marks → MeshInstance3D
  └── update_shader_animations() → tcMod UV offsets
```

### Build system (SConstruct)
Two targets built by default:
1. **Main GDExtension .so** — all engine code + godot/ glue. Links: `-lz`, `-ldl`, `-z muldefs`, `-Bsymbolic-functions`
2. **cgame.so** — client game module with `-fvisibility=hidden`. Variant dir: `build/cgame/`

Source exclusion filters remove sound backends (DMA, OpenAL, Miles), SDL/OpenGL files, GameSpy samples, and old parser duplicates.
