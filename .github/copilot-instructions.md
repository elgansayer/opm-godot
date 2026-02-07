# Copilot Instructions: OpenMoHAA → Godot GDExtension Port

## Project Overview
This workspace ports the **OpenMoHAA** dedicated server (an ioquake3 / IdTech 3 derivative) into **Godot 4.x** as a GDExtension shared library. The build is **monolithic** — fgame, server, script engine, and bot code are all linked into one `.so`/`.dll` via SCons. There is no dlopen; symbol conflicts are resolved with `-z muldefs` and `#ifndef GODOT_GDEXTENSION` guards.

**Compatibility constraint:** The port must remain **fully compliant** with existing MOHAA, Spearhead (SH), and Breakthrough (BT) clients and servers. All original assets — `.pk3` archives, `.scr` scripts, `.tik` files, BSP maps, shader definitions — must load and behave identically to upstream OpenMoHAA. Do not replace, wrap, or re-implement the engine's native VFS (`files.cpp`) or script loader; they already handle pk3 mounting, search-path ordering, and `com_target_game` / `com_basegame` selection for all three games (`main/`, `mainta/`, `maintt/`).

## Repository Layout
- `openmohaa/` — engine source + `SConstruct` build (the main codebase being ported)
- `openmohaa/code/godot/` — GDExtension glue layer (all new Godot-specific code lives here):
  - `MoHAARunner.cpp/.h` — Godot `Node` that drives `Com_Init`/`Com_Frame`, error recovery via `setjmp`/`longjmp`, signal emission on state changes
  - `stubs.cpp` — ~250 no-op stubs for client, UI, sound, and input subsystems (dedicated-only build)
  - `register_types.cpp` — GDExtension entry point; calls `Com_Shutdown()` in the module terminator as a safety net
  - `godot_server_accessors.c` — thin C file exposing `sv.state`/`svs.mapName`/`svs.iNumClients` (avoids header conflicts between engine `server.h` and godot-cpp C++ headers)
- `godot-cpp/` — Godot C++ bindings (submodule, do not modify)
- `project/` — Godot editor project for testing (`Main.gd`, `.tscn`, `.gdextension`)

## Key Conventions
- **Language:** British English (en-GB) in comments and docs.
- **Preprocessor guard:** All engine patches must be wrapped in `#ifdef GODOT_GDEXTENSION` / `#endif` to keep upstream mergeability. Never modify engine behaviour unconditionally.
- **Active defines:** `DEDICATED`, `GODOT_GDEXTENSION`, `GAME_DLL`, `BOTLIB`, `WITH_SCRIPT_ENGINE`, `APP_MODULE`.
- **No raw `malloc`/`free` in new C++ code.** Prefer `std::unique_ptr`, `std::vector`, or Godot's `memnew`/`memdelete`.

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
Patched files: `sys_main.c`, `common.c`, `sv_main.c`, `qcommon.h`, `g_main.cpp`, `g_main.h`, `mem_blockalloc.cpp`, `con_arrayset.h`, `con_set.h`, `script.cpp`, `mem_tempalloc.cpp`, `lightclass.cpp`.

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
During `exit()`, global C++ destructors (e.g. `~con_arrayset` for `Event::commandList`) call `Z_Free`/`ARRAYSET_Free`/`SET_Free`. Two mechanisms prevent crashes:
1. **`Z_MarkShutdown()`** (in `memory.c`) — marks `Z_Free` as a no-op and `Z_TagMalloc` as a system-`malloc` fallback. Called from `MoHAARunner::~MoHAARunner()` and `uninitialize_openmohaa_module()` after `Com_Shutdown()`.
2. **cgame.so uses `-fvisibility=hidden`** — prevents ELF dynamic linker from interposing cgame's template instantiations (which use `cgi.Free`) onto the main .so's copies (which use `Z_Free`). Only `GetCGameAPI` is exported.
3. **`Sys_UnloadCGame` does NOT `dlclose`** — avoids unmapping cgame code pages that might still be referenced by atexit handlers.
4. **Safe `cgi` wrappers** — in `con_arrayset.h`/`con_set.h`, `CGAME_DLL + GODOT_GDEXTENSION` sections use inline functions that check `cgi.Free`/`cgi.Malloc` for NULL before calling, falling back to `free()`/`malloc()`.

### Header conflict boundary — C accessor layer
Engine headers (`server.h`, `g_local.h`) cannot be included in godot-cpp C++ translation units due to macro/type collisions. When you need to read engine state from `MoHAARunner.cpp`, add a thin C function in `godot_server_accessors.c` and call it via `extern "C"`.

### Adding stubs for unresolved symbols
When linking pulls in new client/UI/renderer symbols, add a no-op stub in `stubs.cpp` with the correct signature. Check `code/null/null_client.c` for reference signatures.

## Build & Test Workflow
```bash
# Build (from openmohaa/)
scons platform=linux target=template_debug -j$(nproc) dev_build=yes

# Deploy to project
\cp -f openmohaa/bin/libopenmohaa.so project/bin/libopenmohaa.so
\cp -f openmohaa/bin/libcgame.so ~/.local/share/openmohaa/main/cgame.so

# Headless smoke test
cd project && godot --headless --quit-after 5000
```
**SCons cache gotcha:** After editing widely-included headers (e.g. `qcommon.h`), delete `openmohaa/.sconsign.dblite` to force a full rebuild — SCons sometimes misses transitive dependencies.

## Asset & VFS Architecture
The engine's VFS (`code/qcommon/files.cpp`) is fully functional and must not be bypassed:
- **Main data directory:** `/home/elgan/.local/share/openmohaa/main/` — contains Pak0–Pak6.pk3 (36,640 files total), cgame.so, and openmohaa.pk3
- `fs_basepath` / `fs_homedatapath` resolve to `/home/elgan/.local/share/openmohaa` (set via engine defaults)
- `fs_homepath` resolves to `/home/elgan/.config/openmohaa` (user configs)
- `com_basegame` defaults to `"main"` (`BASEGAME` in `q_shared.h`); `com_target_game` selects AA (0), SH (1), or BT (2)
- Expansion game dirs: `main/` (AA), `mainta/` (SH), `maintt/` (BT) — pk3 files searched in descending pak order
- `.scr` scripts loaded via `gi.FS_ReadFile` → compiled by `code/script/` → executed by `ScriptMaster` in `code/fgame/`
- All I/O goes through the engine's `FS_*` functions; never use `fopen`/`std::ifstream` for game assets
- cgame.so deployed to: `/home/elgan/.local/share/openmohaa/main/cgame.so`

## Roadmap
See `openmohaa/TASKS.md` for the full phase breakdown. Phases 1–5.5 are complete (build, engine heartbeat, server ops, script engine, full client subsystem with cgame, shutdown stability). Engine boots, loads maps, spawns players, exits cleanly. Next: Phase 6 (input bridge), Phase 7 (BSP renderer), Phase 8 (sound bridge).

## When Adding Engine Patches
1. Wrap in `#ifdef GODOT_GDEXTENSION` with a one-line comment explaining *why*.
2. If the patch touches allocators reachable from destructors, use `gi_Malloc_Safe`/`gi_Free_Safe`.
3. If you need engine state in `MoHAARunner.cpp`, add a C accessor in `godot_server_accessors.c`.
4. Test with `scons` (GDExtension build). Test with upstream CMake if possible.
5. Document the change in the relevant Phase section of `TASKS.md`.
