# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project Overview

ShinMOHAA ports **OpenMoHAA** (an ioquake3/IdTech3 derivative) into **Godot 4** as a monolithic GDExtension shared library. All engine subsystems (fgame, server, client, script, UI, bot) are linked into one `.so`/`.dll` — no dlopen for the main library. A separate `cgame.so` is built alongside and loaded at runtime via dlopen.

The port must remain fully compatible with original MOHAA, Spearhead (SH), and Breakthrough (BT) assets (`.pk3`, `.scr`, `.tik`, BSP maps, `.shader` files).

## Build Commands

```bash
# Full build + deploy (from repo root)
./build.sh

# Manual build (from openmohaa/)
scons platform=linux target=template_debug -j$(nproc) dev_build=yes

# Deploy built libraries
cp -f openmohaa/bin/libopenmohaa.so project/bin/libopenmohaa.so
cp -f openmohaa/bin/libcgame.so ~/.local/share/openmohaa/main/cgame.so

# Headless smoke test (requires game assets in ~/.local/share/openmohaa/main/)
cd project && godot --headless --quit-after 5000

# Compilation-only check (no game assets needed)
cd openmohaa && scons platform=linux target=template_debug -j$(nproc) dev_build=yes

# Web build
./scripts/build-web.sh

# Launch game
./launch.sh linux
```

**Build outputs:** `openmohaa/bin/libopenmohaa.so` (~57MB debug) and `openmohaa/bin/libcgame.so` (~4.7MB).

**Prerequisites:** Godot 4.2+ (in PATH as `godot`), SCons (`pip install scons`), GCC 11+/Clang 14+, bison, flex, pkg-config, zlib, libdl.

**SCons cache gotcha:** After editing widely-included headers (e.g. `qcommon.h`), delete `openmohaa/.sconsign.dblite` to force a full rebuild — SCons sometimes misses transitive dependencies.

## Architecture

### Key directories

- `openmohaa/code/godot/` — All Godot-specific glue code (C/C++ bridge layer)
- `openmohaa/code/qcommon/` — Core engine (cvars, commands, VFS, memory, networking)
- `openmohaa/code/renderergl1/` — Real renderer source (compiled into main .so, GL calls stubbed out)
- `openmohaa/code/fgame/` — Server-side game logic, entities, AI
- `openmohaa/code/cgame/` — Client-side game (separate cgame.so)
- `openmohaa/code/script/` — Morfuse script compiler & executor
- `openmohaa/code/tiki/`, `code/skeletor/` — TIKI model & animation loading
- `project/` — Godot editor project (Main.gd, Main.tscn, project.godot)
- `relay/` — WebSocket-to-UDP relay server (Node.js) for web clients
- `godot-cpp/` — Git submodule (branch 4.2)

### Core data flow per frame

```
Com_Frame()
  ├── SV_Frame()     → server logic, entity updates, script execution
  ├── CL_Frame()     → client prediction, snapshot processing
  │   └── CG_DrawActiveFrame() → entity submission via GR_AddRefEntityToScene
  │       └── GR_RenderScene() → captures refdef (camera), entity buffer, dlights
  ├── SCR_UpdateScreen() → captures 2D HUD commands
  └── S_Update()     → captures sound events

MoHAARunner::_process()
  ├── Com_Frame()
  ├── update_camera()         → refdef → Camera3D
  ├── update_entities()       → entity buffer → MeshInstance3D pool
  ├── update_2d_overlay()     → 2D cmds → CanvasLayer
  ├── update_audio()          → sound events → AudioStreamPlayer3D pool
  ├── update_polys/swipes/terrain_marks() → effect MeshInstance3Ds
  └── update_shader_animations() → tcMod UV offsets
```

### Stub renderer architecture

`godot_renderer.c` provides the full `refexport_t` function table. It captures engine render calls into buffers that `MoHAARunner.cpp` reads each frame: entity buffer (1024), dynamic lights (64), 2D commands (4096), polys (2048), swipe state, terrain marks (256), shader table (2048), model table (1024), font tables.

The real renderer's **data management** code (shader parsing, image loading, model registration) runs via `R_Init()` called from `GR_BeginRegistration()`. All GL draw calls are stubbed out. Godot-side code reads from real `trGlobals_t tr` structs via accessor files — never reimplement the parser.

### Header conflict boundary — C accessor layer

Engine headers cannot be included in godot-cpp C++ files due to macro/type collisions. When you need engine state in `MoHAARunner.cpp`, add a thin C function in an accessor file and call it via `extern "C"`.

**Accessor files:**
- `godot_server_accessors.c` — sv.state, svs.mapName, svs.iNumClients
- `godot_client_accessors.cpp` — keyCatchers, in_guimouse, paused
- `godot_vfs_accessors.c` — Godot_VFS_ReadFile/FreeFile
- `godot_input_bridge.c` — Key/mouse → Com_QueueEvent
- `godot_skel_model_accessors.cpp` — TIKI mesh extraction, bone transforms, CPU skinning
- `renderergl1/godot_shader_accessors.c` — Bridges real shader_t → GodotShaderProps

## Golden Rule — 100% Parity with OpenMoHAA

**If it works in OpenMoHAA, it MUST work identically here.** We are wrapping and bridging the existing engine into Godot — NOT reinventing it. Never rewrite, replace, or second-guess engine logic. Never add custom implementations when the engine already provides the functionality. Trace the original code path first, then bridge it. No exceptions.

## Critical Conventions

### Language and guards
- **British English** (en-GB) in comments and docs.
- **All engine patches** must be wrapped in `#ifdef GODOT_GDEXTENSION` / `#endif` to keep upstream mergeability.
- **Active defines (main .so):** `DEDICATED`, `GODOT_GDEXTENSION`, `GAME_DLL`, `BOTLIB`, `WITH_SCRIPT_ENGINE`, `APP_MODULE`.
- **Active defines (cgame.so):** `CGAME_DLL` only (no DEDICATED, no GODOT_GDEXTENSION).

### Coordinate system
id Tech 3 (X=Forward, Y=Left, Z=Up, inches) → Godot (X=Right, Y=Up, -Z=Forward, metres). Scale: `MOHAA_UNIT_SCALE = 1/39.37`.

### Memory and safety
- No raw `malloc`/`free` in new C++ code — use `std::unique_ptr`, `std::vector`, or Godot's `memnew`/`memdelete`.
- During library unload, `gi.Malloc`/`gi.Free` become NULL before destructors run. Use `gi_Malloc_Safe`/`gi_Free_Safe` wrappers (defined in `g_main.h`) for allocator calls reachable from destructors.
- `Sys_Error`/`Sys_Quit` must never call `exit()` — they longjmp to `godot_error_jmpbuf`.
- `Z_MarkShutdown()` makes `Z_Free` a no-op during shutdown to prevent crashes in global destructors.
- cgame.so uses `-fvisibility=hidden` to prevent symbol interposition issues.

### Reuse engine functions — never rewrite them
The monolithic build links the full engine. Always use existing functions:
- **Tokeniser:** `COM_ParseExt()`, `SkipRestOfLine()`, `COM_Compress()` — never write custom parsers
- **String:** `Q_stricmp()`, `Q_stricmpn()`, `Q_strncpyz()`
- **Math:** `VectorCopy()`, `VectorScale()`, `AngleVectors()`
- **Memory:** `Z_Malloc()`/`Z_Free()` for engine-lifetime, `Hunk_AllocateTempMemory()` for frame-temporary
- **VFS:** `FS_ReadFile()`, `FS_FreeFile()`, `FS_ListFiles()` — never use `fopen`/`std::ifstream`
- **Model/TIKI:** `TIKI_RegisterTikiFlags()`, `TIKI_GetSkelAnimFrame()`, `TIKI_GetLocalChannel()`

Since Godot C++ files can't include engine headers directly, declare needed engine functions via `extern "C"` blocks.

### Shader system
- `surfaceParm` keywords are BSP compile-time flags (Q3MAP) — they do NOT affect runtime rendering
- Transparency is determined solely by stage `blendFunc`, not by `surfaceParm trans`
- Shader name ≠ texture file path — must look up shader definition stages for actual texture path
- Default cull mode is `CULL_BACK` (Godot) — only set `CULL_DISABLED` when shader explicitly says `cull none`/`cull twosided`
- The real renderer parses all `.shader` files via `R_Init()` → `R_StartupShaders()`. Read from real `shader_t` via `godot_shader_accessors.c` — never reparse `.shader` files on the Godot side

### Implementation standards
1. **No fallbacks** — aim for 1:1 parity with MOHAA/OpenMoHAA
2. **No shortcuts** — implement fully, never work around missing accessors
3. **Research before code** — trace original engine code path, identify full data pipeline, verify stub completeness before implementing
4. **If a stub returns zero/NULL and the caller needs real data, you have a bug** — check what the real renderer computes

## VFS / Asset Architecture
- `fs_basepath`/`fs_homedatapath` → `~/.local/share/openmohaa`
- `fs_homepath` → `~/.config/openmohaa`
- Game dirs: `main/` (AA), `mainta/` (SH), `maintt/` (BT)
- Game assets (pk3 files) are NOT in the repo — only needed for runtime testing, not compilation
- All I/O goes through engine `FS_*` functions — never bypass the VFS
