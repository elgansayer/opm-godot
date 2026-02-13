# Implementation Roadmap: GodotMoHAA

## Phase 1: The Build System & Scaffolding ✅
- [x] **Task 1.1:** Create a `SConstruct` (SCons) file to build the project as a GDExtension library.
- [x] **Task 1.2:** Configure `godot-cpp` bindings.
- [x] **Task 1.3:** Create the GDExtension entry point (`register_types.cpp`).
- [x] **Task 1.4:** Compile and verify a "Hello World" load in the Godot Editor.

## Phase 2: The Engine Heartbeat ✅
- [x] **Task 2.1:** Identify the `Com_Frame()` (main loop) in OpenMoHAA.
- [x] **Task 2.2:** Create a Godot Node class `MoHAARunner` (extends `Node`).
- [x] **Task 2.3:** Hook Godot's `_process(delta)` to drive the OpenMoHAA frame ticker.
- [x] **Task 2.4:** Redirect `Com_Printf`/`Sys_Print` to Godot's console.
- [x] **Task 2.5:** Make `Com_Frame` non-blocking (bypass `NET_Sleep`/`Sys_Sleep` under Godot).
- [x] **Task 2.6:** Resolve monolithic build symbol conflicts (`Com_Printf`, `Com_Error`, `SV_Malloc`, `SV_Free`, `SV_Error` shadowed by fgame function pointers).
- [x] **Task 2.7:** Verify dedicated server init + map load (mohdm1 loads, entities spawn, server runs).

### Key technical details (Phase 2):
- `DEDICATED` and `GODOT_GDEXTENSION` defines active
- `main()` in sys_main.c guarded with `#ifndef GODOT_GDEXTENSION`
- `Sys_Print` redirects to `Godot_SysPrint` callback under `GODOT_GDEXTENSION`
- `Com_Frame` sleep loop bypassed with `break;` under `GODOT_GDEXTENSION`
- `SV_Frame`'s `Sys_Sleep(-1)` (no-map idle) guarded out under `GODOT_GDEXTENSION`
- Monolithic build links fgame directly; `Sys_GetGameAPI` calls `GetGameAPI` without dlopen
- fgame's `Com_Printf`, `Com_Error`, `SV_Malloc`, `SV_Free`, `SV_Error` guarded with `#ifndef GODOT_GDEXTENSION`
- Comprehensive client/UI/sound/input stubs in `stubs.cpp`
- Build: `scons platform=linux target=template_debug -j$(nproc) dev_build=yes`

## Phase 2.5: Server Operations ✅
- [x] **Task 2.5.1:** Expose `execute_command(cmd)` and `load_map(name)` to GDScript.
- [x] **Task 2.5.2:** Handle `Com_Error` gracefully (ERR_FATAL/Sys_Error no longer kills Godot; uses longjmp + error signal).
- [x] **Task 2.5.3:** Expose server status (`is_map_loaded`, `get_player_count`, `get_current_map`, `get_server_state`, `get_server_state_string`) to GDScript.
- [x] **Task 2.5.4:** Signal/notification system (`engine_error`, `map_loaded`, `map_unloaded`, `engine_shutdown_requested`).
- [x] **Task 2.5.5:** Fix library unload crash (ScriptMaster destructor calling gi.Malloc after engine shutdown — added safe fallbacks for all gi.Malloc/gi.Free call sites + Com_Shutdown in module teardown).

### Key technical details (Phase 2.5):
- `Sys_Error` under `GODOT_GDEXTENSION`: calls `Godot_SysError()` which stores message + longjmps to `godot_error_jmpbuf` (set up in `_ready` and `_process`)
- `Sys_Quit` under `GODOT_GDEXTENSION`: calls `Godot_SysQuit()` which sets flag + longjmps back
- `Sys_SigHandler` under `GODOT_GDEXTENSION`: routes to `Godot_SysError`/`Godot_SysQuit` instead of `Sys_Exit`
- `Q_NO_RETURN` attribute removed from `Sys_Error`/`Sys_Quit` declarations under `GODOT_GDEXTENSION` (qcommon.h)
- `gi.Malloc`/`gi.Free` safe wrappers (`gi_Malloc_Safe`/`gi_Free_Safe`) in `g_main.h` — fall back to system `malloc`/`free` when `gi` function pointers are NULL (library teardown)
- Applied to: `mem_blockalloc.cpp`, `con_arrayset.h`, `con_set.h`, `script.cpp`, `mem_tempalloc.cpp`, `lightclass.cpp`
- Server state accessors via `godot_server_accessors.c` (avoids header conflicts between engine `server.h` and godot-cpp)
- `register_types.cpp` calls `Com_Shutdown()` in uninitialize as safety net
- State-change detection in `_process()` polls `sv.state` and emits signals on transitions

## Phase 3: Script Engine (Morfuse) ✅
The OpenMoHAA script engine (`code/script/` — ScriptVM, ScriptCompiler, ScriptMaster) is already compiled and functional in the monolithic build (`WITH_SCRIPT_ENGINE` define). When maps load, `.scr` scripts are loaded via `gi.FS_ReadFile`, compiled by ScriptCompiler, and executed by ScriptMaster. No separate integration step was needed.

- [x] **Task 3.1:** Script engine compiled into the GDExtension build (already in `src_dirs` in SConstruct).
- [x] **Task 3.2:** ScriptMaster global destructors handled safely (gi_Malloc_Safe/gi_Free_Safe — done in Phase 2.5.5).
- [x] **Task 3.3:** Verified: map load triggers `.scr` script compilation and execution (mohdm1 tested in Phase 2.7).

## Phase 4: Asset Pipeline
**Constraint:** Full compatibility with existing MOHAA/SH/BT pk3 archives, .scr scripts, .tik files, BSP maps, and shader definitions. The engine's native VFS (`files.cpp`) and script loader must not be replaced — they already handle pk3 mounting, search-path ordering, and game selection for all three titles (`main/`, `mainta/`, `maintt/`).

- [ ] **Task 4.1:** Bridge the VFS so Godot can also read assets via the engine's `FS_*` functions (expose file-read helpers to GDScript). Ensure `fs_basepath` correctly resolves for all three game directories. Do not bypass or re-implement the VFS.
- [ ] **Task 4.2:** Implement a BSP parser that generates Godot `ArrayMesh` data from map files at runtime, reading BSP data through the engine VFS.
- [ ] **Task 4.3:** Convert Quake 3 / MOHAA textures and shader definitions to Godot `ShaderMaterial` / `StandardMaterial3D` at runtime.

## Phase 5: Full Client Subsystem ✅ (build compiles, stubs in place)
Converted the build from dedicated-server-only to a full playable client+server. All rendering, sound, and input are routed through Godot backend stubs.

- [x] **Task 5.1:** SConstruct updated — added `code/client`, `code/uilib` to source dirs. Extensive exclusion filters for 14+ sound backend files, OpenAL, curl, mumble.
- [x] **Task 5.2:** Created `godot_renderer.c` — stub `refexport_t` (~80 functions) via `GetRefAPI()`. Sets `glconfig_t` (1280×720, 32-bit). All Register* return sequential handles, all Draw/Render are no-ops.
- [x] **Task 5.3:** Created `godot_sound.c` — all `S_*` and `MUSIC_*` functions (~70+). Includes `snd_local_new.h` variable/function stubs (`s_bSoundPaused`, `soundsystemsavegame_t`, `S_SaveData`/`S_LoadData`/`S_ReLoad`/`S_NeedFullRestart`, etc.).
- [x] **Task 5.4:** Created `godot_input.c` — `IN_Init`/`Shutdown`/`Frame`, `GLimp_Init`/`Shutdown`/`EndFrame`, `Sys_SendKeyEvents`, all as no-ops.
- [x] **Task 5.5:** Engine DEDICATED guards patched — `common.c` and `memory.c` `#undef DEDICATED` under `GODOT_GDEXTENSION` to enable client code paths (`CL_Init`, `CL_Frame`, `S_Init`). `qcommon.h` guard widened for `con_autochat`. `server.h` guards widened for `snd_local.h` include and `soundSystem` struct member. `snd_public.h` includes `snd_local_new.h` under `GODOT_GDEXTENSION`.
- [x] **Task 5.6:** MoHAARunner updated — `+set dedicated 0` (client mode).
- [x] **Task 5.7:** Cgame integration — cgame compiled as separate `.so` with `CGAME_DLL` defined, loaded via `dlopen` in `Sys_GetCGameAPI`. Search path: `fs_homedatapath/game/`, `fs_basepath/game/`, `fs_homepath/game/`. Built with `-fvisibility=hidden` to prevent ELF symbol interposition of template instantiations (con_arrayset, con_set) between cgame.so and the main .so. `Sys_UnloadCGame` intentionally does NOT `dlclose` the handle (avoids unmapped code pages during global destructor teardown). Safe `cgi.Free`/`cgi.Malloc` wrappers in `con_arrayset.h`/`con_set.h` fall back to stdlib when function pointers are NULL after `CL_ShutdownCGame`.
- [x] **Task 5.8:** stubs.cpp reduced — removed ~150 lines of stubs now provided by real client code. Kept: Sys_Get*API, UI stubs, misc Sys stubs, VM stubs, renderer-thread stubs, clipboard/registry stubs.

### Key technical details (Phase 5):
- `DEDICATED` remains globally defined to suppress SDL code in `sys_main.c`/`sys_unix.c`
- `common.c` and `memory.c` `#undef DEDICATED` under `GODOT_GDEXTENSION` so `CL_Init()`, `CL_Frame()`, `S_Init()` are called from `Com_Init`/`Com_Frame`
- `com_dedicated` defaults to `0` (client mode) instead of `1`
- Sound API uses the modern (non-`NO_MODERN_DMA`) branch with `S_StopAllSounds2` macro aliased to `S_StopAllSounds`
- Renderer loads via `CL_InitRef()` → `GetRefAPI()` (our godot_renderer.c)
- Client code (cl_main.cpp, cl_keys.cpp, cl_scrn.cpp, etc.) compiles and runs
- UI framework (uilib/) compiles alongside client
- Build output: 47MB main .so + 4.8MB cgame .so

## Phase 5.5: Shutdown Stability ✅
Fixed EXIT=139 (SIGSEGV) during global C++ destructor teardown at `exit()`.

- [x] **Task 5.5.1:** `Z_MarkShutdown()` in `memory.c` — sets `z_zone_shutting_down` flag. `Z_Free` becomes no-op, `Z_TagMalloc` falls back to system `malloc()`. Called from `MoHAARunner::~MoHAARunner()` and `uninitialize_openmohaa_module()` after `Com_Shutdown()`.
- [x] **Task 5.5.2:** cgame.so built with `-fvisibility=hidden` — prevents ELF template symbol interposition (e.g. `con_arrayset::DeleteTable`, `con_set::DeleteTable`) between cgame.so and main .so. Only `GetCGameAPI` plus a few `HashCode` specialisations are exported.
- [x] **Task 5.5.3:** `Sys_UnloadCGame` no longer calls `dlclose` — avoids unmapped code pages. Handle is abandoned; OS reclaims at process exit.
- [x] **Task 5.5.4:** Safe `cgi.Free`/`cgi.Malloc` wrappers in `con_arrayset.h` and `con_set.h` (`CGAME_DLL` + `GODOT_GDEXTENSION`) — fall back to `free()`/`malloc()` when function pointers are NULL after `CL_ShutdownCGame`.
- [x] **Task 5.5.5:** Both .so files use `-Wl,-Bsymbolic-functions` as defence-in-depth against symbol interposition.

## Phase 6: Input Bridge ✅
Keyboard, mouse, and mouse-capture forwarding from Godot to the engine event queue.

- [x] **Task 6.1:** Create `godot_input_bridge.c` — thin C accessor (includes `keycodes.h` + `qcommon.h`) providing:
  - `Godot_InjectKeyEvent(godot_key, down)` — translates Godot key integer → engine `keyNum_t`, calls `Com_QueueEvent(SE_KEY)`
  - `Godot_InjectCharEvent(unicode)` — injects `SE_CHAR` for console/chat text input
  - `Godot_InjectMouseMotion(dx, dy)` — injects `SE_MOUSE` relative motion
  - `Godot_InjectMouseButton(godot_button, down)` — translates Godot `MouseButton` → engine key (`K_MOUSE1`–`K_MOUSE5`, `K_MWHEELUP`/`DOWN`)
- [x] **Task 6.2:** Full Godot Key → engine keycode mapping:
  - Printable ASCII: Godot `KEY_A`–`KEY_Z` (65–90) → lowercase `'a'`–`'z'` (97–122)
  - ASCII punctuation: passed through (32–127 range)
  - Backtick/tilde (`KEY_QUOTELEFT` = 96, `KEY_ASCIITILDE` = 126) → `K_CONSOLE`
  - Special keys: `KEY_ESCAPE` → `K_ESCAPE`, `KEY_TAB` → `K_TAB`, arrows, Page Up/Down, Home/End, modifiers
  - F keys: `KEY_F1`–`KEY_F15` → `K_F1`–`K_F15`
  - Numpad: `KEY_KP_0`–`KEY_KP_9` → `K_KP_INS`/`K_KP_END`/... (SDL-compatible mapping)
- [x] **Task 6.3:** Override `_unhandled_input()` in `MoHAARunner`:
  - `InputEventKey`: `SE_KEY` on press/release (skip echo), `SE_CHAR` on press/echo for text input
  - `InputEventMouseMotion`: `SE_MOUSE` with relative delta (only when mouse captured)
  - `InputEventMouseButton`: `SE_KEY` for regular buttons; wheel events synthesise press+release pair
- [x] **Task 6.4:** Mouse capture control:
  - `set_mouse_captured(bool)` / `is_mouse_captured()` exposed to GDScript
  - Uses `Input::get_singleton()->set_mouse_mode(MOUSE_MODE_CAPTURED / MOUSE_MODE_VISIBLE)`
  - Auto-capture on `map_loaded` signal; F10 toggles capture (escape hatch)
- [x] **Task 6.5:** Fixed duplicate `.gdextension` in `project/bin/` causing double class registration.

### Key technical details (Phase 6):
- Follows the C accessor pattern (`godot_input_bridge.c` includes engine headers; `MoHAARunner.cpp` includes godot-cpp headers)
- Events are timestamped via `Sys_Milliseconds()`
- `godot_input.c` stubs remain for `IN_Init`/`IN_Shutdown`/`IN_Frame` — the engine calls these, but actual input now flows through the Godot bridge
- The engine's `Com_EventLoop` dequeues and processes events during `Com_Frame`

## Phase 7a: Camera Bridge ✅
- [x] **Task 7a.1:** Capture `refdef_t` data (vieworg, viewaxis, fov) in `GR_RenderScene` (godot_renderer.c).
- [x] **Task 7a.2:** Expose C accessor functions (`Godot_Renderer_GetViewOrigin`, `Godot_Renderer_GetViewAxis`, `Godot_Renderer_GetFov`, etc.).
- [x] **Task 7a.3:** Create Camera3D, DirectionalLight3D, and WorldEnvironment child nodes in `MoHAARunner::setup_3d_scene()`.
- [x] **Task 7a.4:** Update Camera3D transform and FOV from the engine viewpoint each frame in `MoHAARunner::update_camera()`.
- [x] **Task 7a.5:** Implement id Tech 3 → Godot coordinate conversion (position + orientation).
- [x] **Task 7a.6:** Capture world map name in `GR_LoadWorld` for future BSP loader.

### Key technical details (Phase 7a):
- **Coordinate conversion:** id Tech 3 uses X=Forward, Y=Left, Z=Up; Godot uses X=Right, Y=Up, -Z=Forward. Conversion: Godot.x = -id.Y, Godot.y = id.Z, Godot.z = -id.X
- **Unit scale:** MOHAA uses inches (1 unit ≈ 1 inch); Godot uses metres. Scale factor: 1/39.37
- **Camera basis:** Godot Basis columns are (right, up, back). right = -left_godot, back = -forward_godot
- **FOV:** Engine's `fov_y` (vertical) maps directly to Godot Camera3D's `fov` property with `KEEP_HEIGHT` aspect mode
- **Data flow:** `GR_RenderScene()` stores refdef_t → `MoHAARunner::update_camera()` reads via C accessors → updates Camera3D global transform
- **Scene hierarchy:** MoHAARunner (Node) → GameWorld (Node3D) → {EngineCamera (Camera3D), SunLight (DirectionalLight3D), WorldEnv (WorldEnvironment)}

## Phase 7b: BSP World Geometry ✅
- [x] **Task 7b.1:** Create `godot_bsp_mesh.h/.cpp` — BSP parser + Godot mesh builder.
- [x] **Task 7b.2:** Read BSP file from engine VFS (`Godot_VFS_ReadFile`); parse header, validate ident "2015" and version 17–21.
- [x] **Task 7b.3:** Handle version-dependent lump offsets (`Q_GetLumpByVersion` — BSP ≤18 shifts lumps > LUMP_BRUSHES by +1).
- [x] **Task 7b.4:** Parse LUMP_SHADERS, LUMP_DRAWVERTS, LUMP_DRAWINDEXES, LUMP_SURFACES.
- [x] **Task 7b.5:** Process MST_PLANAR and MST_TRIANGLE_SOUP surfaces — convert vertices/indices to Godot ArrayMesh with per-shader batching.
- [x] **Task 7b.6:** Filter out SURF_NODRAW, SURF_HINT, and tool shader surfaces (clip, trigger, caulk, etc.).
- [x] **Task 7b.7:** Apply coordinate conversion (id→Godot) and unit scaling (inches→metres, 1/39.37).
- [x] **Task 7b.8:** Hook BSP loading into `MoHAARunner::check_world_load()` — loads/unloads BSP on map change.
- [x] **Task 7b.9:** Capture world map name in `GR_LoadWorld` for the BSP loader.

### Key technical details (Phase 7b):
- BSP structs defined locally in `godot_bsp_mesh.cpp` (avoids engine header conflicts with godot-cpp)
- `static_assert` verifies struct sizes: `bsp_shader_t=140`, `bsp_drawvert_t=44`, `bsp_surface_t=108`
- Per-shader batching: surfaces grouped by `shaderNum`, each batch becomes one ArrayMesh surface with its own material
- Materials: vertex-colour lit (`FLAG_ALBEDO_FROM_VERTEX_COLOR`), double-sided (`CULL_DISABLED`)
- Test results (mohdm1): 6.5 MB BSP, 215 shaders, 30168 verts, 47298 indices, 6163 surfaces → 6025 processed, 88 batches
- Skipped: MST_PATCH (Bézier — needs tessellation), MST_TERRAIN, MST_FLARE (future work)
- Entity string parsing handled by `CM_LoadMap` (server-side), not by the renderer

## Phase 7c: Textures & Lightmaps ✅
- [x] **Task 7c.1:** Texture loader — tries `.jpg` then `.tga` via engine VFS, matching the engine's search order.
- [x] **Task 7c.2:** Texture cache — `std::unordered_map` keyed by shader name, avoids redundant disk reads.
- [x] **Task 7c.3:** Load lightmaps from LUMP_LIGHTMAPS — 128×128×3 RGB, expanded to RGBA, with overbright shift (<<1).
- [x] **Task 7c.4:** Apply albedo textures to each shader batch via `StandardMaterial3D::TEXTURE_ALBEDO`.
- [x] **Task 7c.5:** Apply lightmaps as detail texture via `FEATURE_DETAIL` + `DETAIL_UV_2` + `BLEND_MODE_MUL`.
- [x] **Task 7c.6:** Fallback to vertex colours when texture is unavailable.
- [x] **Task 7c.7:** Generate mipmaps for both albedo textures and lightmaps.

### Key technical details (Phase 7c):
- Texture format: BSP shader name (e.g. `"textures/mohmain/brick01"`) → append `.jpg`/`.tga` → read from pk3 via VFS
- Godot's `Image::load_jpg_from_buffer()` / `Image::load_tga_from_buffer()` parse the raw file bytes — no custom TGA/JPG parser needed
- Lightmaps use overbrightBits=1 shift (values << 1, clamped to 255) matching the engine's `R_ColorShiftLightingBytes`
- Test results (mohdm1): 53 lightmaps, 82/88 textures loaded (93% hit rate), 6 missing (special shaders/effects)

## Phase 7d: Bézier Patches & Sky Detection ✅
- [x] **Task 7d.1:** Bézier patch tessellation — bi-quadratic evaluation of MST_PATCH surfaces. Decomposes
  `patchWidth × patchHeight` control point grids into 3×3 sub-patches, evaluates on an 8×8 parametric grid,
  stitches adjacent patches, generates triangle indices, and appends to the same `ShaderBatch` system.
- [x] **Task 7d.2:** `bezier_eval()` — evaluates position, normal, UV, lightmap UV, and vertex colour using
  quadratic basis functions B₀(u)=(1-u)², B₁(u)=2u(1-u), B₂(u)=u² on a 3×3 control grid.
- [x] **Task 7d.3:** `tessellate_patch()` — handles arbitrary odd×odd patch dimensions, builds stitched vertex
  grid across all sub-patches, emits 2 triangles per quad.
- [x] **Task 7d.4:** Sky surface filtering — `SURF_SKY` flag (0x4) surfaces skipped and counted separately.
- [x] **Task 7d.5:** Updated surface processing loop to route MST_PATCH to tessellator while keeping
  MST_PLANAR and MST_TRIANGLE_SOUP on the original code path.

### Key technical details (Phase 7d):
- Tessellation level: 8 subdivisions per sub-patch edge (configurable via `PATCH_TESS_LEVEL`)
- Output grid per sub-patch: (N+1)×(N+1) = 81 vertices, 128 triangles; stitched at sub-patch boundaries
- Coordinate conversion applied identically to planar/soup surfaces (id→Godot position + direction)
- Per-vertex normals re-normalised after Bézier interpolation
- Test results (mohdm1): 120 patches tessellated, 57 sky surfaces filtered. 6088 surfaces → 102 batches, 96 textures

## Phase 7e: Entity Capture & Debug Rendering ✅
- [x] **Task 7e.1:** Entity ring buffer in `godot_renderer.c` — `gr_entity_t` struct captures reType, origin,
  axis, scale, hModel, entityNumber, shaderRGBA, renderfx, customShader, parentEntity per entity per frame.
- [x] **Task 7e.2:** Dynamic light capture — `gr_dlight_t` stores origin, intensity, RGB, type. Buffer of 64.
- [x] **Task 7e.3:** `GR_ClearScene()` resets entity/dlight counters each frame.
- [x] **Task 7e.4:** `GR_AddRefEntityToScene()` copies compact entity data into ring buffer (up to 1024).
- [x] **Task 7e.5:** `GR_AddLightToScene()` captures dynamic lights into buffer.
- [x] **Task 7e.6:** C accessor functions: `Godot_Renderer_GetEntityCount/GetEntity/GetEntityBeam/GetDlightCount/GetDlight`.
- [x] **Task 7e.7:** `update_entities()` in MoHAARunner — pooled MeshInstance3D with BoxMesh placeholder,
  coordinate-converted transforms, visibility toggling, entity type filtering (RT_MODEL only).
- [x] **Task 7e.8:** `update_dlights()` in MoHAARunner — pooled OmniLight3D nodes, position/colour/range
  from engine data, intensity→range conversion with MOHAA_UNIT_SCALE.

### Key technical details (Phase 7e):
- Entity capture uses value-only struct (no engine pointers) to avoid cross-boundary issues
- Debug rendering: orange 50cm BoxMesh per RT_MODEL entity, hidden for sprites/beams
- OmniLight3D pool for dynamic lights with converted position and range
- BSP inline models (`*1`, `*2`, etc.) registered — 26 on mohdm1 (doors, movers, etc.)

## Phase 7f: TIKI Model Registration ✅
- [x] **Task 7f.1:** Model table `gr_models[1024]` in `godot_renderer.c` with `gr_modtype_t` enum
  (GR_MOD_BAD, GR_MOD_BRUSH, GR_MOD_TIKI, GR_MOD_SPRITE).
- [x] **Task 7f.2:** `GR_RegisterModelInternal()` — name dedup, extension dispatch:
  `.tik` → `ri.TIKI_RegisterTikiFlags()` + `ri.CG_ProcessInitCommands()`,
  `.spr` → GR_MOD_SPRITE, `*N` → GR_MOD_BRUSH.
- [x] **Task 7f.3:** `GR_Model_GetHandle()` returns `dtiki_t*` from model table for TIKI models.
- [x] **Task 7f.4:** `GR_ModelBounds` → `ri.TIKI_CalculateBounds()`, `GR_ModelRadius` → `ri.TIKI_GlobalRadius()`.
- [x] **Task 7f.5:** `GR_ForceUpdatePose`, `GR_TIKI_Orientation`, `GR_TIKI_IsOnGround` delegate to TIKI system.
- [x] **Task 7f.6:** Model table init in `GR_BeginRegistration`, reset in `GR_Shutdown`/`GR_FreeModels`.

## Phase 7g: CGame Render Pipeline Fix ✅
- [x] **Task 7g.1:** Diagnosed entity pipeline: `CG_DrawActiveFrame()` never called because
  `View3D::Display()` (only caller of `SCR_DrawScreenField()`) only runs when `cls.no_menus`
  is transiently true. During normal frames, `UpdateStereoSide()` calls `UI_Update()` which
  sets `view3d->setShow(true)` but never calls `view3d->Display()`.
- [x] **Task 7g.2:** Fix: Added `SCR_DrawScreenField()` call in `UpdateStereoSide()` under
  `#ifdef GODOT_GDEXTENSION` in `cl_scrn.cpp` — ensures `CL_CGameRendering()` →
  `CG_DrawActiveFrame()` runs every frame, driving snapshot processing and entity submission.

### Key technical details (Phase 7f + 7g):
- 158 TIKI models registered on mohdm1 (weapons, player models, ammo, effects, vehicles)
- 9 expansion-pack model failures (non-blocking — Spearhead/Breakthrough content not in base pak files)
- 12 entities per frame flowing through pipeline (player model, weapons, ammo pickups, etc.)
- Snapshot pipeline: `CL_ParseSnapshot()` populates `cl.snap`, `CG_ProcessSnapshots()` reads it,
  `CG_AddPacketEntities()` submits entities via `GR_AddRefEntityToScene()`
- Patched files: `cl_scrn.cpp` (Godot-guarded `SCR_DrawScreenField()` in `UpdateStereoSide`)

## Phase 7h: 2D HUD Overlay Rendering ✅
- [x] **Task 7h.1:** Added shader name table (`gr_shader_t gr_shaders[2048]`) with deduplication
  in `godot_renderer.c`. `GR_RegisterShader`/`GR_RegisterShaderNoMip` store shader names indexed
  by handle. Reset in `GR_BeginRegistration()`.
- [x] **Task 7h.2:** Added 2D draw command buffer (`gr_2d_cmd_t gr_2d_cmds[4096]`) capturing
  `GR_DrawStretchPic`, `GR_DrawStretchPic2`, `GR_DrawTilePic`, `GR_DrawTilePicOffset`, and
  `GR_DrawBox` calls. Commands record type, position, size, UV coords, colour, and shader handle.
  Buffer reset in `GR_BeginFrame()`.
- [x] **Task 7h.3:** Added C accessor functions: `Godot_Renderer_Get2DCmdCount`,
  `Godot_Renderer_Get2DCmd`, `Godot_Renderer_GetShaderName`, `Godot_Renderer_GetShaderCount`.
- [x] **Task 7h.4:** Implemented `update_2d_overlay()` in `MoHAARunner.cpp` — creates a
  `CanvasLayer` (layer 100) + `Control` (full-screen anchor), clears canvas item each frame,
  iterates 2D commands and draws via `RenderingServer::canvas_item_add_rect()` for boxes and
  `canvas_item_add_texture_rect_region()` for textured quads. Scales 640×480 virtual coords
  to actual viewport size.
- [x] **Task 7h.5:** Implemented `get_shader_texture()` — lazy texture loader using VFS. Detects
  JPEG/PNG/TGA by magic bytes, loads via `Image::load_*_from_buffer()`, caches as `ImageTexture`
  in `shader_textures` map.

### Key technical details (Phase 7h):
- 83 draw commands per frame on mohdm1 (crosshair, compass, health/ammo bars, team indicators)
- MOHAA uses 640×480 virtual screen coordinates; scaled to actual viewport via `Control::get_size()`
- Shader table supports up to 2048 shaders with name-based dedup on registration
- 2D command types: `GR_2D_STRETCHPIC` (0) = textured quad, `GR_2D_BOX` (1) = solid colour rect
- Texture loading reuses VFS path (same as BSP texture loading): tries `""`, `.tga`, `.jpg`, `.png`
- No new engine patches — entirely new code in `godot_renderer.c` + `MoHAARunner.cpp/.h`

## Phase 7i: Font & Text Rendering ✅

- **`.RitualFont` parser** in `godot_renderer.c`: `GR_LoadFont_sgl` parses single-page font files (indirections, locations, height, aspect ratio); `GR_LoadFont` handles both single-page and multi-page (`RitFontList`) fonts
- **Fallback fonts**: Both loaders never return NULL — on parse failure or table overflow, a monospace 8×16 fallback font is created in-place
- **Text draw commands**: `GR_DrawString_sgl`/`GR_DrawString` capture per-glyph `GR_2D_STRETCHPIC` commands into the 2D command buffer using font UV coordinates
- **Font tables persist** across map loads (not reset in `GR_BeginRegistration`), matching original renderer behaviour
- **Fonts loaded**: verdana-14, verdana-12, marlett, facfont-20 (4 unique single-page fonts)
- **2D draw commands jumped from 83 → 911** per frame with text rendering active
- **Engine patch** — `uifont.cpp`: Added `#ifdef GODOT_GDEXTENSION` bounds checks in `getCharWidth()` and `UI_FontStringWidth()` to guard `indirection[256]` against out-of-bounds access when UI passes characters > 255 (e.g. Unicode 0xFFE2). Single-page fonts have 256-element indirection arrays but `unsigned short ch` can be 0–65535.
- **Crash chain**: `Com_Printf` → `UI_PrintConsole` → `UIConsole::CalcLineBreaks` → `UIFont::getCharWidth` — any engine printf could trigger the OOB access

### Files modified (Phase 7i):
- `code/godot/godot_renderer.c` — font loader + text draw functions (~250 lines added)
- `code/uilib/uifont.cpp` — two `#ifdef GODOT_GDEXTENSION` bounds-check guards

## Phase 7j: Terrain Mesh Rendering ✅

- **LUMP_TERRAIN (22) parser** in `godot_bsp_mesh.cpp`: reads packed `cTerraPatch_t` structs (388 bytes each) directly from the BSP terrain lump, entirely separate from the surface lump
- **Static max-detail tessellation**: Each terrain patch generates a 9×9 vertex grid (81 vertices, 128 triangles) covering 512×512 world units. No ROAM LOD — full detail always rendered
- **Vertex position**: `(x0 + col×64, y0 + row×64, z0 + heightmap[row×9+col]×2)` where `x0=(int)x<<6`, `y0=(int)y<<6`, `z0=iBaseHeight`
- **Smooth normals**: Computed from heightmap via central finite differences; cross product of tangent vectors → normalised, converted to Godot coordinate space
- **Diffuse UVs**: Bilinearly interpolated from 4 corner texture coordinates stored in `texCoord[2][2][2]`
- **Lightmap UVs**: Computed from `lm_s/lm_t` pixel offsets and `lmapScale` — maps terrain grid to the correct region within the lightmap page
- **Shader batching**: Terrain patches grouped by `iShader` into the same batch system used for planar/soup/patch surfaces; textures and lightmaps applied via existing material pipeline
- **Struct validation**: `static_assert(sizeof(bsp_terrain_patch_t) == 388)` ensures binary layout match
- **Test results**: mohdm2 = 70 patches, m4l0 = 591 patches, m5l2b = 518 patches. 40 of 54 maps contain terrain
- **No engine patches required** — entirely new code in `godot_bsp_mesh.cpp`

### Key technical details (Phase 7j):
- MOHAA terrain is a **parallel system** to BSP surfaces — patches are NOT referenced via `MST_TERRAIN` surface entries. They live in their own BSP lump and are rendered independently
- `bsp_terrain_patch_t` defined locally (avoids engine header conflicts), verified against `cTerraPatch_t` in `qfiles.h`
- Helper functions added: `lerpf()` for bilinear UV interpolation, `compute_terrain_normal()` for heightmap normals
- The `get_lump()` helper already handles the BSP v18 lump index shift (LUMP_FOGS removal)

## Phase 7k: HUD Coordinate Fix ✅

- **Root cause**: `vidWidth=1280, vidHeight=720` (16:9) caused `SCR_AdjustFrom640()` to stretch the 640×480 (4:3) HUD non-uniformly
- **Fix**: Set `vidWidth=640, vidHeight=480` in `GR_BeginRegistration()` so the engine's virtual coordinate system matches 1:1 with the original MOHAA design
- **Aspect-ratio-preserving overlay**: HUD scaled with uniform scale factor and pillarbox/letterbox offsets to maintain 4:3 proportions on any viewport aspect ratio
- **Set2DWindow state tracking**: `GR_Set2DWindow()` now records viewport and projection parameters (was a no-op) and exposes them via `Godot_Renderer_Get2DWindow()` accessor

### Files modified (Phase 7k):
- `code/godot/godot_renderer.c` — vidWidth/vidHeight changed, Set2DWindow state tracking added
- `code/godot/MoHAARunner.cpp` — HUD overlay scaling rewritten with aspect-ratio preservation

## Phase 6: Input Bridge Fix ✅

- **Root cause**: Three issues prevented mouse/keyboard input from reaching gameplay:
  1. `in_guimouse` flag starts `true` and gets re-enabled by UI code each frame → mouse deltas go to GUI cursor instead of freelook
  2. `paused` cvar blocks `CL_SendCmd()` and `CL_MouseEvent()` accumulation
  3. `KEYCATCH_UI` flag captures key events away from gameplay
- **Fix**: Periodic enforcement in `_process()` — checks `in_guimouse`, `paused`, and `keyCatchers` every frame when mouse is captured, forces game input mode and unpauses as needed
- **New C accessors**: `Godot_Client_GetPaused()`, `Godot_Client_ForceUnpause()` (sets `paused=0` and calls `IN_MouseOff()`)
- **Updated accessor**: `Godot_Client_SetGameInputMode()` now also calls `Cvar_Set("paused","0")` alongside clearing keyCatchers and calling `IN_MouseOff()`

### Files modified (Phase 6):
- `code/godot/godot_client_accessors.cpp` — paused accessor + force unpause + SetGameInputMode update
- `code/godot/MoHAARunner.cpp` — input enforcement loop added to `_process()`

## Phase 8: Sound Bridge ✅

- **Event-capture architecture** in `godot_sound.c`: replaced all no-op stubs with a sound registry (sfxHandle → name mapping), one-shot event queue (128 events), looping-sound buffer (64 slots), listener state, and music state
- **C accessor API**: 15+ `Godot_Sound_*` functions expose queued events, loops, listener, and music state to C++ side
- **Sound registration**: `S_RegisterSound` does name dedup, returns 1-based handles. 367 sounds registered on mohdm1
- **WAV loader** in `MoHAARunner.cpp`: parses RIFF/WAVE headers from VFS data, creates `AudioStreamWAV` with correct format (8-bit/16-bit PCM, IMA-ADPCM), sample rate, and channel count. Results cached in `sfx_cache` map
- **3D positional audio**: `AudioStreamPlayer3D` pool (32 players), round-robin allocation. Position converted from id→Godot coordinates. Volume mapped from linear→dB. MinDist→unit_size, MaxDist→max_distance
- **2D local audio**: `AudioStreamPlayer` pool (16 players) for UI/announcer sounds
- **Looping sounds**: Tracked via `active_loops` map (sfxHandle→player index). New loops started with `LOOP_FORWARD` mode, positions updated each frame, orphaned loops stopped when removed from the buffer
- **Listener**: `AudioListener3D` node positioned and oriented from `S_Respatialize` data each frame
- **Music state capture**: `MUSIC_NewSoundtrack`, `MUSIC_UpdateVolume`, `MUSIC_StopAllSongs` record actions for future playback implementation
- **No engine patches required** — entirely new code in C and C++

### Files modified (Phase 8):
- `code/godot/godot_sound.c` — complete rewrite: event-capture system + C accessors (~480 lines)
- `code/godot/MoHAARunner.cpp` — `setup_audio()`, `update_audio()`, `load_wav_from_vfs()` (~280 lines added)
- `code/godot/MoHAARunner.h` — audio member variables and includes
## Phase 9: Skeletal Model Module (SKD/SKC/SKB) ✅

- **Module architecture**: Separate C++ accessor layer + Godot mesh builder, following the project's header-conflict boundary pattern
  - `godot_skel_model_accessors.cpp` — C++ file (needed because `dtiki_t` has C++ members like `skelChannelList_c`). Provides `extern "C"` functions to extract mesh geometry from TIKI skeletal models via `TIKI_GetSkel()` → `skelHeaderGame_t` → `skelSurfaceGame_t` chain
  - `godot_skel_model.h` / `godot_skel_model.cpp` — Godot-side module. `GodotSkelModelCache` singleton builds `ArrayMesh` instances from the C accessor data, with per-hModel caching
  - `godot_renderer.c` additions — `Godot_Model_GetTikiPtr()` and `Godot_Model_GetType()` expose the model table's `dtiki_t*` pointers to the accessor layer
- **Data pipeline**: `gr_models[hModel].tiki` → `dtiki_t.mesh[meshNum]` → `TIKI_GetSkel(cacheIndex)` → `skelHeaderGame_t.pSurfaces` (linked list) → extract `pStaticXyz`/`pStaticNormal`/`pStaticTexCoords`/`pTriangles` → convert id→Godot coordinates → build `ArrayMesh`
- **Bind-pose static mesh**: Uses `pStaticXyz` (vec4_t×N), `pStaticNormal` (vec4_t×N), `pStaticTexCoords` (vec2_t[2]×N, UV set 0), `pTriangles` (skelIndex_t×3×numTris)
- **Coordinate conversion**: id→Godot axis remapping (x→-z, y→-x, z→y), scale by `tiki->load_scale × MOHAA_UNIT_SCALE`, winding order reversed (CW→CCW) for correct face culling
- **Shader texture assignment**: Each surface's shader name from `dtikisurface_t` is matched against the renderer's shader table to load textures via `get_shader_texture()`
- **Fallback placeholder**: Models without skeletal data (e.g. brush models) still get a small orange debug BoxMesh
- **Cache invalidation**: `GodotSkelModelCache::clear()` called when BSP world unloads (map change)
- **Test result**: First model built: `models/player/american_army_fps.tik` — 1338 vertices, 1755 triangles, 4 surfaces. All 12 scene entities visible.
- **No engine patches required** — entirely new code in the godot/ directory

### Files created (Phase 9):
- `code/godot/godot_skel_model_accessors.cpp` — TIKI mesh data extraction (~190 lines)
- `code/godot/godot_skel_model.h` — `GodotSkelModelCache` class declaration
- `code/godot/godot_skel_model.cpp` — ArrayMesh builder with caching (~210 lines)

### Files modified (Phase 9):
- `code/godot/godot_renderer.c` — added `Godot_Model_GetTikiPtr()`, `Godot_Model_GetType()`
- `code/godot/MoHAARunner.cpp` — replaced BoxMesh placeholders with actual skeletal model meshes; includes `godot_skel_model.h`, uses `GodotSkelModelCache::get().get_model(hModel)`; clears cache on map unload

## Future Phases (Tracked)

### Skeletal Animation (Phase 9b — planned)
- Extract `refEntity_t.frameInfo[]`, `bone_tag`, `bone_quat` into entity capture
- Build `Skeleton3D` from `skelHeaderGame_t.pBones` hierarchy
- Compute bone transforms via `skeletor_c::SetPose()`/`GetFrame()` or `R_GetFrame()`
- Apply bone weights from `skeletorVertex_t` (numWeights per vertex) to Godot `Skin`/`SkinReference`

### LOD System (Phase 9c — planned)
- `skelHeaderGame_t.lodIndex[10]` maps distance thresholds to triangle counts
- `skelSurfaceGame_t.pCollapse` / `pCollapseIndex` enable progressive mesh vertex collapsing
- `lodControl_t` stores minMetric/maxMetric/consts for distance-based LOD selection
- Currently using LOD 0 (highest detail) for all models

## Phase 10: Static BSP Models & Brush Model Rendering ✅
Extended the BSP loader and entity renderer to handle brush sub-models (doors, movers, lifts) and static TIKI models baked into the BSP (furniture, vegetation, props).

- [x] **Task 10.1:** Parse LUMP_MODELS (13) — `bsp_model_t` struct (40 bytes: mins/maxs/firstSurface/numSurfaces/firstBrush/numBrushes). Identifies brush sub-models `*1`–`*N` and their surface ranges. World model (`*0`) excluded from sub-model processing.
- [x] **Task 10.2:** Surface exclusion — mark all surfaces belonging to brush sub-models 1..N with `is_submodel_surface[]`. These are excluded from the main world ArrayMesh to avoid double rendering (they render at entity positions instead).
- [x] **Task 10.3:** Brush sub-model mesh building — for each sub-model with surfaces, run the same `process_surface()` + `batches_to_array_mesh()` pipeline used for the world mesh. Results cached in `s_brush_models[]` vector (0-indexed: `s_brush_models[0]` = `*1`).
- [x] **Task 10.4:** Code refactoring — extracted `batches_to_array_mesh()` (ShaderBatch map → ArrayMesh with materials/textures/lightmaps) and `process_surface()` (single surface → ShaderBatch, handles PLANAR/SOUP/PATCH) as shared helpers for both world and brush sub-model mesh building.
- [x] **Task 10.5:** Brush sub-model accessors — `Godot_BSP_GetBrushModelCount()` and `Godot_BSP_GetBrushModelMesh()` expose built meshes to MoHAARunner for entity rendering.
- [x] **Task 10.6:** Parse LUMP_STATICMODELDEF (25) — `bsp_static_model_t` struct (164 bytes: model[128]/origin/angles/scale/firstVertexData/numVertexData). 61 static models on mohdm2 (churchpews, cabinets, pianos, bushes, trees, vehicles).
- [x] **Task 10.7:** Static model path resolution — BSP stores paths relative to `models/` (e.g. `static//churchpew.tik`). Mirrors `R_InitStaticModels()`: prepend `models/` if not present, canonicalise double-slashes.
- [x] **Task 10.8:** `load_static_models()` in MoHAARunner — registers TIKI via `Godot_Model_Register()`, builds mesh via `GodotSkelModelCache`, computes transform from origin + angles + scale using `id_angle_vectors()`, creates `MeshInstance3D` with textures under a `StaticModels` parent node.
- [x] **Task 10.9:** Entity renderer brush model support — `update_entities()` now identifies `GR_MOD_BRUSH` entities by model name (`*N`), looks up pre-built BSP mesh from `Godot_BSP_GetBrushModelMesh()`, applies entity origin as translation offset with identity-scale basis (geometry already in world coordinates).
- [x] **Task 10.10:** `Godot_Model_Register()` and `Godot_Model_GetName()` functions added to `godot_renderer.c` for external (non-cgame) model registration.

### Key technical details (Phase 10):
- **Test results (mohdm2)**: 21 models (1 world + 20 brush), 274 surfaces excluded from world mesh, 14 brush sub-model meshes built (6 had 0 surfaces = triggers/clips), 61/61 static models placed successfully
- **Brush model geometry** is at absolute BSP world coordinates — entity origin represents an offset from the resting position, NOT the absolute position. Entity transform uses identity-scale basis (no MOHAA_UNIT_SCALE) to avoid shrinking
- **Static model rotation**: `id_angle_vectors()` converts id Tech 3 [pitch, yaw, roll] to forward/right/up vectors, then remapped to Godot Basis (right, up, back) with scale applied
- **Helper refactoring**: `process_surface()` handles surface type dispatch (PLANAR/SOUP/PATCH), `batches_to_array_mesh()` handles the batch→ArrayMesh conversion shared between world mesh, brush sub-model mesh, and potentially future uses
- **`Godot_BSP_Unload()`** clears `s_static_models` and `s_brush_models` vectors alongside existing world mesh cleanup

### Files modified (Phase 10):
- `code/godot/godot_bsp_mesh.cpp` — LUMP_MODELS parsing, surface exclusion, brush sub-model mesh building, LUMP_STATICMODELDEF parsing, helper function extraction (~300 lines added)
- `code/godot/godot_bsp_mesh.h` — `BSPStaticModelDef` struct, new accessor declarations
- `code/godot/godot_renderer.c` — `Godot_Model_Register()`, `Godot_Model_GetName()`
- `code/godot/MoHAARunner.cpp` — `load_static_models()`, brush model entity rendering, `id_angle_vectors()` (~160 lines added)
- `code/godot/MoHAARunner.h` — `static_model_root` member, `load_static_models()` method

## Phase 6.5: Input & HUD Client-Side Fixes ✅
Fixed two interrelated issues — the main menu rendering on top of the 3D world, and input events being swallowed by the UI key catcher — both caused by the engine's `developer 1` startup path calling `UI_ToggleConsole()` which sets `KEYCATCH_UI` and `in_guimouse`.

- [x] **Task 6.5.1:** Create `godot_client_accessors.cpp` — C++ file (compiled as C++ for `cl_ui.h` `bool`) with `extern "C"` accessors:
  - `Godot_Client_GetState()`, `GetKeyCatchers()`, `GetGuiMouse()`, `GetStartStage()`, `GetMousePos()` — read-only diagnostics
  - `Godot_Client_SetGameInputMode()` — clears `KEYCATCH_UI | KEYCATCH_CONSOLE`, calls `UI_ForceMenuOff(true)` then `IN_MouseOff()` (order matters: UI_FocusMenuIfExists may re-enable guiMouse)
  - `Godot_Client_SetKeyCatchers()` — direct setter
- [x] **Task 6.5.2:** MoHAARunner calls `SetGameInputMode()` after map load when `KEYCATCH_UI` or `KEYCATCH_CONSOLE` is set. Post-fix diagnostic logs confirm `catchers=0x0 guiMouse=0`.
- [x] **Task 6.5.3:** Patch `UI_Update()` in `cl_ui.cpp` with `#ifdef GODOT_GDEXTENSION` — under Godot, always take the HUD-only path (`view3d + health/ammo/compass`) when `clc.state == CA_ACTIVE`, regardless of `cls.no_menus`. Prevents main menu backgrounds (`main_a`, `main_b`, `fan_anim1`, `menu_button_trans`, `textures/mohmenu/quit`) from rendering on top of the 3D world.
- [x] **Task 6.5.4:** Fullscreen opaque BOX fills (>50% area, alpha>0.9) filtered in `update_2d_overlay()` to prevent large black/white fills from blocking the 3D view.
- [x] **Task 6.5.5:** StretchPic with failed-to-load textures now silently skipped instead of drawing an opaque white rectangle.

### Files created (Phase 6.5):
- `code/godot/godot_client_accessors.cpp` — client-side state accessors

### Files modified (Phase 6.5):
- `code/godot/MoHAARunner.cpp` — client state diagnostics after map load, `SetGameInputMode()` call, input debug logging (first 10 key presses log godot_key, mapped key, catchers, guiMouse)
- `code/client/cl_ui.cpp` — `#ifdef GODOT_GDEXTENSION` guard in `UI_Update()` for CA_ACTIVE HUD-only path

### Key technical details (Phase 6.5):
- **Root cause:** `developer 1` cmdline → `CL_TryStartIntro()` → `UI_ToggleConsole()` → sets `KEYCATCH_UI=0x2` + `in_guimouse=qtrue`. All key events routed to UI, mouse in cursor mode.
- **Order dependency:** `IN_MouseOff()` must be called AFTER `UI_ForceMenuOff(true)` because `UI_FocusMenuIfExists()` internally calls `IN_MouseOn()` if any persistent menu remains in `menuManager.CurrentMenu()`.
- **cls.no_menus:** Only transiently true during `CL_Stufftext_f` processing. Cannot be used as a permanent flag. The `#ifdef GODOT_GDEXTENSION` guard in `UI_Update()` bypasses this check entirely.

## Phase 11: Shader Transparency & Blend Modes ✅
Implemented .shader script file parsing to extract transparency, blend, and cull properties for all materials.

- [x] **Task 11.1:** Created `godot_shader_props.h` — public API with `GodotShaderTransparency` enum (OPAQUE/ALPHA_TEST/ALPHA_BLEND/ADDITIVE/MULTIPLICATIVE), `GodotShaderCull` enum, `GodotShaderProps` struct.
- [x] **Task 11.2:** Created `godot_shader_props.cpp` — parser reads `scripts/shaderlist.txt` from VFS, loads each listed `.shader` file, extracts `alphaFunc`, `blendFunc`, `surfaceparm trans`, `cull` directives. Stores in `std::unordered_map` keyed by lowercase name.
- [x] **Task 11.3:** Parser handles nested brace blocks (outer block for surfaceparm/cull, inner stage blocks for alphaFunc/blendFunc), comments, and both shorthand (`blend`/`add`/`filter`) and full GL_* blend function forms.
- [x] **Task 11.4:** Integrated into BSP mesh builder — `Godot_ShaderProps_Load()` called at start of `Godot_BSP_LoadWorld()`, `Godot_ShaderProps_Unload()` called in `Godot_BSP_Unload()`.
- [x] **Task 11.5:** Applied shader properties in `batches_to_array_mesh()` — sets `TRANSPARENCY_ALPHA_SCISSOR` (with threshold) for alpha-tested shaders, `TRANSPARENCY_ALPHA` for blended, `BLEND_MODE_ADD` for additive, `BLEND_MODE_MUL` for multiplicative. Cull mode updated from default `CULL_DISABLED`.
- [x] **Task 11.6:** Created `apply_shader_props_to_material()` helper in `MoHAARunner.cpp` — applies shader properties to any `StandardMaterial3D`, used by static model and entity material creation.
- [x] **Task 11.7:** Applied shader properties to static model surface materials in `load_static_models()`.
- [x] **Task 11.8:** Applied shader properties to entity TIKI model surface materials in `update_entities()`.

### Key technical details (Phase 11):
- **Test results (mohdm2)**: 3030 shader definitions parsed from 84 shader files (89 listed in shaderlist.txt)
- **Transparency mapping**: `alphaFunc GT0` → threshold 0.01, `GE128`/`LT128` → threshold 0.5
- **Blend mode mapping**: `blendFunc blend` → `TRANSPARENCY_ALPHA`, `add` → `BLEND_MODE_ADD`, `filter` → `BLEND_MODE_MUL`
- **First definition wins** — matches engine behaviour for duplicate shader names across files
- **Case-insensitive lookup** — shader names lowercased for consistent matching

## Phase 12: Skybox Rendering ✅
Loads skybox cubemap textures from BSP sky shaders and displays them as a Godot Sky environment.

- [x] **Task 12.1:** Extended `GodotShaderProps` struct with `is_sky` bool and `sky_env[64]` char array for cubemap path.
- [x] **Task 12.2:** Added `skyParms` directive parsing to shader body parser — extracts env basename (e.g. `env/m5l2`).
- [x] **Task 12.3:** Added `surfaceparm sky` detection to set `is_sky` flag.
- [x] **Task 12.4:** Added `Godot_ShaderProps_GetSkyEnv()` API — returns first sky shader's env basename.
- [x] **Task 12.5:** Implemented `load_skybox()` in `MoHAARunner.cpp`:
  - Loads 6 cubemap face images from VFS (`_rt`, `_lf`, `_up`, `_dn`, `_bk`, `_ft` in OpenGL layer order)
  - Tries `.jpg` then `.tga` extensions
  - Creates `Cubemap` via `create_from_images()`
  - Creates custom sky `Shader` (shader_type sky) with `samplerCube` uniform
  - Creates `ShaderMaterial` with cubemap assigned
  - Creates `Sky` resource, updates `Environment` from `BG_COLOR` to `BG_SKY`
- [x] **Task 12.6:** Called `load_skybox()` after `load_static_models()` in `check_world_load()`.
- [x] **Task 12.7:** Fixed stray code blocks from Phase 11 shader prop application that caused compilation errors.

### Key technical details (Phase 12):
- **Test results (mohdm2)**: Sky shader `textures/sky/m5l2` → `skyParms env/lighthousesky 512 -` → 6 face JPGs loaded from Pak2.pk3
- **Cubemap face ordering**: Layers 0–5 = +X(`_rt`), -X(`_lf`), +Y(`_up`), -Y(`_dn`), +Z(`_bk`), -Z(`_ft`) — standard OpenGL convention
- **Sky shader code**: `shader_type sky; uniform samplerCube sky_cubemap; void sky() { COLOR = texture(sky_cubemap, EYEDIR).rgb; }`
- **112 BSP sky surfaces** excluded from world mesh rendering (handled by skybox instead)
- **No engine patches required** — entirely new code in Godot glue layer

### Files created (Phase 11):
- `code/godot/godot_shader_props.h` — shader property struct and query API
- `code/godot/godot_shader_props.cpp` — .shader file parser (~280 lines)

### Files modified (Phase 11):
- `code/godot/godot_bsp_mesh.cpp` — includes `godot_shader_props.h`, calls `Load`/`Unload`, applies properties in `batches_to_array_mesh()`
- `code/godot/MoHAARunner.cpp` — includes `godot_shader_props.h`, `apply_shader_props_to_material()` helper, applied to static model and entity materials

## Phase 13: Skeletal Animation (CPU Skinning) ✅
Implements per-frame CPU skinning for animated TIKI entities, mirroring the GL1 renderer's
`R_AddSkelSurfaces` → `RB_SkelMesh` pipeline within the Godot GDExtension.

- [x] **Task 13.1:** Extended `gr_entity_t` with animation fields: `frameInfo[MAX_FRAMEINFOS]`, `actionWeight`, `bone_tag[5]`, `bone_quat[5][4]`, `tiki` pointer.
- [x] **Task 13.2:** Updated `GR_AddRefEntityToScene` to copy animation data from `refEntity_t`.
- [x] **Task 13.3:** Fixed `GR_ForceUpdatePose` — now calls `ri.TIKI_SetPoseInternal()` (was a broken stub).
- [x] **Task 13.4:** Added ri wrapper functions in `godot_renderer.c` — thin C exports for `ri.TIKI_GetSkeletor`, `ri.TIKI_SetPoseInternal`, `ri.GetFrameInternal`, `ri.TIKI_GetNumChannels`, `ri.TIKI_GetLocalChannel`.
- [x] **Task 13.5:** Added `Godot_Renderer_GetEntityAnim()` accessor — returns entity animation data to MoHAARunner.
- [x] **Task 13.6:** Implemented `Godot_Skel_PrepareBones()` — sets pose, computes bone matrices, converts `SkelMat4` → `skelBoneCache_t`.
- [x] **Task 13.7:** Implemented `Godot_Skel_SkinSurface()` — CPU-skins vertices using bone cache, handles mesh 0/N bone index remapping.
- [x] **Task 13.8:** Integrated skinning in `MoHAARunner::update_entities()` — per-entity `ArrayMesh` from skinned positions, material cache per model handle.

### Key technical details (Phase 13):
- **C/C++ boundary**: `godot_renderer.c` (C) exports thin ri wrapper functions. `godot_skel_model_accessors.cpp` (C++) calls them via `extern "C"`.
- **Lightweight POD structs**: `godot_SkelMat4_t` (48 bytes) and `godot_skelAnimFrame_t` match SkelMat4/skelAnimFrame_t layout without including `skeletor.h`.
- **Bone computation mirrors GL1**: `SkelMat4.val[3]` → `offset`, `SkelMat4.val[0..2]` → `matrix[0..2]`, padding columns = 0.
- **Vertex skinning**: Walks variable-stride `pVerts` buffer (skeletorVertex_t + morphs + weights), applies `SkelWeightGetXyz` formula.
- **Per-frame mesh rebuild**: Animated entities get a new `ArrayMesh` each frame. Falls back to bind-pose cached mesh if no animation data.

### Files modified (Phase 13):
- `code/godot/godot_renderer.c` — `gr_entity_t` animation fields, `GR_AddRefEntityToScene`, `GR_ForceUpdatePose`, ri wrappers, `Godot_Renderer_GetEntityAnim`
- `code/godot/godot_skel_model_accessors.cpp` — `Godot_Skel_PrepareBones`, `Godot_Skel_SkinSurface`
- `code/godot/MoHAARunner.cpp` — extern "C" declarations, skinning integration, material cache

## Phase 14: Fog Rendering ✅

- [x] 14.1 Read `Godot_Renderer_GetFarplane()` full signature (distance, color[3], cull)
- [x] 14.2 In `update_camera()`, enable Godot `Environment` fog when `farplane_distance > 0`
- [x] 14.3 Set fog colour from `farplane_color[3]` via `set_fog_light_color()`
- [x] 14.4 Approximate MOHAA linear distance fog with Godot exponential: density = 2.3 / (dist * MOHAA_UNIT_SCALE)
- [x] 14.5 Set `set_fog_sky_affect(1.0)` so sky is also fogged
- [x] 14.6 Disable fog when `farplane_distance == 0`
- [x] 14.7 Build and test — no crashes, fog path inactive on mohdm2 (no farplane set)

### Key technical details (Phase 14):
- MOHAA fog is linear distance-based (`start=0, end=farplane_distance`); Godot uses exponential fog
- Approximation: `fog_factor = 1 - exp(-density * dist)` → density = 2.3/dist gives ~90% at farplane
- `farplane_color` is RGB [0..1] captured in `godot_renderer.c` from `refdef_t.farplane_color`
- `farplane_cull` controls far-plane culling (already handled by `camera->set_far()`)

### Files modified (Phase 14):
- `code/godot/MoHAARunner.cpp` — `update_camera()` fog section expanded with Environment fog API

## Phase 15: First-Person Weapon Rendering ✅

- [x] 15.1 Fix RF_* flag values (`RF_THIRD_PERSON`=0x01, `RF_FIRST_PERSON`=0x02, `RF_DEPTHHACK`=0x04)
- [x] 15.2 Skip `RF_THIRD_PERSON` (0x01) entities — player body invisible in first person
- [x] 15.3 Skip `RF_DONTDRAW` (0x80) entities
- [x] 15.4 Render `RF_FIRST_PERSON` (0x02) entities instead of skipping them
- [x] 15.5 Depth hack: duplicate materials with `FLAG_DISABLE_DEPTH_TEST` + `render_priority=127`
- [x] 15.6 Handle `RF_DEPTHHACK` (0x04) the same way as `RF_FIRST_PERSON`
- [x] 15.7 Build and test — 17 weapon models registered, no crashes

### Key technical details (Phase 15):
- Previous code had wrong RF_ values (0x0004 was RF_DEPTHHACK not RF_FIRST_PERSON)
- Weapons rendered with `FLAG_DISABLE_DEPTH_TEST + render_priority=127` so they always draw on top
- Material duplicated per-frame for first-person entities to avoid modifying cached originals
- Future refinement: SubViewport overlay for proper weapon self-occlusion

### Files modified (Phase 15):
- `code/godot/MoHAARunner.cpp` — `update_entities()`: fixed RF flags, weapon depth hack, diagnostic log

## Phase 16: Poly/Sprite Effects ✅

- [x] 16.1 Add poly capture buffer in `godot_renderer.c` (2048 polys, 8192 verts)
- [x] 16.2 Implement `GR_AddPolyToScene` to copy poly vertex data (xyz, st, rgba)
- [x] 16.3 Add `Godot_Renderer_GetPolyCount` / `Godot_Renderer_GetPoly` C accessors
- [x] 16.4 Implement `update_polys()` in MoHAARunner — builds ArrayMesh per poly, billboard material
- [x] 16.5 Add sprite entity fields (`radius`, `rotation`) to `gr_entity_t`
- [x] 16.6 Add `Godot_Renderer_GetEntitySprite` C accessor
- [x] 16.7 Handle `RT_SPRITE` entities in `update_entities()` — quad billboard with shader texture
- [x] 16.8 Fix entity filter to render both `RT_MODEL` and `RT_SPRITE` (skip beams/portals)
- [x] 16.9 Build and test — sprites registered (muzsprite, spritely_water), first-person entity rendered

### Key technical details (Phase 16):
- Polys are triangle fans built from `polyVert_t` data (position, UV, RGBA vertex colour)
- Poly materials: unshaded, alpha-blended, double-sided, vertex colour enabled
- Sprites: billboard quads (`BILLBOARD_ENABLED`) sized by entity `radius`
- `customShader` field used as sprite texture when set, else `hModel`
- Poly buffers cleared each frame in `GR_ClearScene`

### Files modified (Phase 16):
- `code/godot/godot_renderer.c` — poly buffer, GR_AddPolyToScene, sprite accessors, entity fields
- `code/godot/MoHAARunner.cpp` — `update_polys()`, RT_SPRITE handling, extern declarations
- `code/godot/MoHAARunner.h` — poly member variables, `update_polys()` declaration

## Phase 17: Mark Fragments (Decals) ✅

Implemented the mark fragment system that enables bullet holes, blood splatters,
explosion marks, and shadow blobs.  The engine's cgame code calls
`re.MarkFragments` to project a polygon onto nearby world surfaces; the
returned clipped polygons are then rendered as `R_AddPolyToScene` quads
(already handled by Phase 16).

### How it works (Phase 17):

1. **BSP data retention** — On map load, `Godot_BSP_LoadWorld` now retains
   planes, nodes, leaves, leaf-surface indices, surfaces, draw verts, draw
   indices, brush models, shader surface flags, and terrain patches in a
   static `BSPMarkData` struct.  Freed on map unload.

2. **BSP tree walk** — `mark_BoxSurfaces_r` recursively walks BSP nodes,
   classifying the mark's AABB against each splitting plane
   (`mark_BoxOnPlaneSide`), collecting candidate surfaces from reached leaves.
   Per-surface dedup via `viewCount` stamps prevents double-processing.

3. **Polygon clipping** — `mark_ChopPolyBehindPlane` implements
   Sutherland-Hodgman clipping against half-planes.  Edge planes are built
   from the input polygon edges × projection vector.  Near/far planes bound
   the projection depth.

4. **Surface tessellation** — `mark_TessellateAndClip` iterates collected
   `MST_PLANAR` and `MST_TRIANGLE_SOUP` surfaces, extracting triangles from
   vertex + index buffers, filtering by face normal vs. projection direction,
   and clipping each triangle against the mark bounding planes.

5. **Inline brush models** — `Godot_BSP_MarkFragmentsForInlineModel`
   transforms input points into the brush model's local coordinate space
   (accounting for rotation and translation) and iterates only that model's
   surfaces.

### Key technical details (Phase 17):
- `markFragment_t = { firstPoint, numPoints, iIndex }` — iIndex: 0=world, >0=terrain, <0=brush entity
- `MAX_MARK_FRAGMENTS = 128`, `MF_MAX_VERTS = 64` per polygon
- Surface flags `SURF_NOIMPACT (0x10)` and `SURF_NOMARKS (0x20)` skip surfaces
- Planar surface normal filtering: `dot(normal, projDir) > -0.5` rejected
- Triangle soup per-triangle normal filtering: `dot(triNormal, projDir) > -0.1` rejected
- Log line on load: `[BSP] Mark data retained: N planes, N nodes, N leaves, N leafsurfs`
- v17 leaves (40-byte) vs. v18+ leaves (64-byte) handled with unified `MarkLeaf` format

### Files modified (Phase 17):
- `code/godot/godot_bsp_mesh.cpp` — BSP struct definitions (`bsp_plane_t`, `bsp_node_t`, `bsp_leaf_t`, `bsp_leaf_t_v17`), `BSPMarkData` storage, data parsing in `Godot_BSP_LoadWorld` (section 4d), cleanup in `Godot_BSP_Unload`, BSP tree walk (`mark_BoxSurfaces_r`), polygon clipping (`mark_ChopPolyBehindPlane`, `mark_AddFragments`, `mark_TessellateAndClip`), extern "C" API (`Godot_BSP_MarkFragments`, `Godot_BSP_MarkFragmentsForInlineModel`)
- `code/godot/godot_bsp_mesh.h` — extern "C" mark fragment API declarations
- `code/godot/godot_renderer.c` — `GR_MarkFragments` and `GR_MarkFragmentsForInlineModel` now call through to the BSP query API

## Phase 18: Entity Token Parser ✅
Exposed the BSP entity string to the renderer via `GR_GetEntityToken`, allowing cgame to iterate entity definitions.

- [x] **Task 18.1:** Retain entity string from LUMP_ENTITIES in `BSPWorldData` during `Godot_BSP_LoadWorld`.
- [x] **Task 18.2:** Implement `Godot_BSP_GetEntityToken()` — iterates entity string with whitespace/quote handling, returns next token. `Godot_BSP_ResetEntityTokenParse()` resets offset.
- [x] **Task 18.3:** Wire `GR_GetEntityToken` in `godot_renderer.c` to call `Godot_BSP_GetEntityToken`.

### Files modified (Phase 18):
- `code/godot/godot_bsp_mesh.cpp` — `BSPWorldData` entity string storage, entity token parser
- `code/godot/godot_bsp_mesh.h` — extern "C" declarations
- `code/godot/godot_renderer.c` — `GR_GetEntityToken` wired to BSP accessor

## Phase 19: Inline Model Bounds ✅
Exposed BSP inline model bounding boxes to the renderer.

- [x] **Task 19.1:** Store model bounds (mins/maxs) from `bsp_model_t` array in `BSPWorldData`.
- [x] **Task 19.2:** Implement `Godot_BSP_GetInlineModelBounds()` — returns mins/maxs by model index.
- [x] **Task 19.3:** Wire `GR_GetInlineModelBounds` in `godot_renderer.c`.

### Files modified (Phase 19):
- `code/godot/godot_bsp_mesh.cpp` — model bounds storage, accessor
- `code/godot/godot_bsp_mesh.h` — new declaration
- `code/godot/godot_renderer.c` — stub wired

## Phase 20: Map Version ✅
Exposed the BSP map version number to the renderer.

- [x] **Task 20.1:** Store BSP version in `BSPWorldData` during header parse.
- [x] **Task 20.2:** Implement `Godot_BSP_GetMapVersion()` accessor.
- [x] **Task 20.3:** Wire `GR_MapVersion` in `godot_renderer.c`.

### Files modified (Phase 20):
- `code/godot/godot_bsp_mesh.cpp` — version stored, accessor added
- `code/godot/godot_bsp_mesh.h` — new declaration
- `code/godot/godot_renderer.c` — stub wired

## Phase 21: Entity Colour Tinting ✅
Modulates entity material albedo with `shaderRGBA` from the render entity.

- [x] **Task 21.1:** In `update_entities()`, read `shaderRGBA[0..3]` from entity data.
- [x] **Task 21.2:** When RGBA is not opaque white (255,255,255,255), duplicate material and tint via `set_albedo()` multiplied by normalised RGB.
- [x] **Task 21.3:** Build and verify — no crashes, tinting applies to coloured entities.

### Files modified (Phase 21):
- `code/godot/MoHAARunner.cpp` — shaderRGBA tinting in `update_entities()`

## Phase 22: Entity Alpha Effects ✅
Enables transparency for entities with alpha < 255 or `RF_ALPHAFADE` flag.

- [x] **Task 22.1:** Detect `RF_ALPHAFADE` (0x0400) in entity `lightmapNum` (renderfx) field.
- [x] **Task 22.2:** When `shaderRGBA[3] < 255` or RF_ALPHAFADE is set, duplicate material and set `TRANSPARENCY_ALPHA` with alpha value.
- [x] **Task 22.3:** Build and verify — translucent entities render correctly.

### Files modified (Phase 22):
- `code/godot/MoHAARunner.cpp` — alpha transparency in `update_entities()`

## Phase 23: Beam Entities ✅
Renders `RT_BEAM` entities as flat quad meshes between `origin` and `oldorigin`.

- [x] **Task 23.1:** Add beam endpoint (`oldorigin`) and beam diameter (`frame`) to entity capture and accessor.
- [x] **Task 23.2:** In `update_entities()`, detect `RT_BEAM` (reType=3) and generate a flat quad mesh between the two endpoints with width from `frame` field.
- [x] **Task 23.3:** Apply unshaded double-sided material to beam quads.

### Key technical details (Phase 23):
- Beam direction computed as `endpoint − origin`, perpendicular axis from `cross(beam_dir, up)` fallback to `cross(beam_dir, right)` when nearly vertical
- Quad width = `entity.frame` value (beam diameter in world units)
- Material: unshaded, double-sided, vertex colour from shaderRGBA

### Files modified (Phase 23):
- `code/godot/godot_renderer.c` — beam accessor `Godot_Renderer_GetEntityBeam`
- `code/godot/MoHAARunner.cpp` — RT_BEAM rendering in `update_entities()`

## Phase 24: Swipe Trail Effects ✅
Captures and renders sword/knife swipe trails as triangle strip meshes.

- [x] **Task 24.1:** Add swipe state in `godot_renderer.c` — `gr_currentSwipe` struct (shader handle, lifetime, points array with xyz/st, active flag).
- [x] **Task 24.2:** Implement `GR_SwipeBegin` (init), `GR_SwipePoint` (add point), `GR_SwipeEnd` (finalise).
- [x] **Task 24.3:** Add C accessors: `Godot_Renderer_GetSwipeData`, `Godot_Renderer_GetSwipePoint`.
- [x] **Task 24.4:** Implement `update_swipe_effects()` in MoHAARunner — builds triangle strip mesh from swipe points.

### Files modified (Phase 24):
- `code/godot/godot_renderer.c` — swipe capture + accessors
- `code/godot/MoHAARunner.cpp` — `update_swipe_effects()`
- `code/godot/MoHAARunner.h` — swipe member variables, method declaration

## Phase 25: Terrain Mark Decals ✅
Captures terrain-surface decal marks and renders them as fan-triangulated meshes.

- [x] **Task 25.1:** Add terrain mark buffer in `godot_renderer.c` — 256 marks, 4096 total vertices.
- [x] **Task 25.2:** Implement `GR_AddTerrainMarkToScene` — captures terrain mark vertex data (xyz, st, rgba).
- [x] **Task 25.3:** Add C accessors: `Godot_Renderer_GetTerrainMarkCount`, `GetTerrainMark`, `GetTerrainMarkVert`.
- [x] **Task 25.4:** Implement `update_terrain_marks()` in MoHAARunner — fan-triangulation of captured mark polygons.

### Files modified (Phase 25):
- `code/godot/godot_renderer.c` — terrain mark buffer + accessors
- `code/godot/MoHAARunner.cpp` — `update_terrain_marks()`
- `code/godot/MoHAARunner.h` — terrain mark member variables, method declaration

## Phase 26: Shader Remapping ✅
Name-to-name shader replacement table for runtime texture swapping effects.

- [x] **Task 26.1:** Add `gr_shaderRemaps[128]` table in `godot_renderer.c` (oldName/newName/timeOffset).
- [x] **Task 26.2:** Implement `GR_RemapShader` — update in-place or append new remap entry.
- [x] **Task 26.3:** Add `Godot_Renderer_GetShaderRemap` accessor for Godot-side queries.
- [x] **Task 26.4:** Clear remap table in `GR_Shutdown`.

### Files modified (Phase 26):
- `code/godot/godot_renderer.c` — remap table + GR_RemapShader + accessor

## Phase 27: Perlin Noise ✅
Pseudo-random noise function used by shader effects.

- [x] **Task 27.1:** Implement `GR_Noise(x, y, z, t)` — sin-hash pseudo-noise returning -0.5 to 0.5.

### Files modified (Phase 27):
- `code/godot/godot_renderer.c` — `GR_Noise` implementation

## Phase 28: Lightgrid Sampling ✅
BSP lightgrid data parsing and point-sampling for lighting queries.

- [x] **Task 28.1:** Parse LUMP_LIGHTGRIDPALETTE (16), LUMP_LIGHTGRIDOFFSETS (17), LUMP_LIGHTGRIDDATA (18) from BSP into `BSPWorldData`.
- [x] **Task 28.2:** Implement `Godot_BSP_LightForPoint(origin, ambientOut, directedOut, directionOut)` — grid position calculation, palette RGB lookup from ambient + directed indices, lat/lon direction decoding.
- [x] **Task 28.3:** Wire accessor in `godot_bsp_mesh.h`.

### Key technical details (Phase 28):
- Lightgrid size: 64×64×128 world units per cell
- Palette: 256 RGB entries, 768 bytes total
- Data: ambient index (1 byte) + directed index (1 byte) + lat (1 byte) + lon (1 byte) per sample
- Offsets: int16_t per grid cell, pointing into data array
- Direction: lat/lon → spherical coordinates → directional vector

### Files modified (Phase 28):
- `code/godot/godot_bsp_mesh.cpp` — lightgrid parsing + `Godot_BSP_LightForPoint`
- `code/godot/godot_bsp_mesh.h` — new declarations

## Phase 29: Decal/Smoke Lighting ✅
Lighting functions for decal and smoke effects using lightgrid data.

- [x] **Task 29.1:** Implement `GR_GetLightingForDecal(origin, facing)` — samples lightgrid, computes `ambient + directed × max(dot(direction, facing), 0)`.
- [x] **Task 29.2:** Implement `GR_GetLightingForSmoke(origin)` — samples lightgrid, computes `ambient + 0.5 × directed` (omnidirectional).

### Files modified (Phase 29):
- `code/godot/godot_renderer.c` — `GR_GetLightingForDecal`, `GR_GetLightingForSmoke`

## Phase 30: Light Source Gathering ✅
Gathers dynamic light sources near a point for entity/effect lighting.

- [x] **Task 30.1:** Implement `GR_GatherLightSources(pos, radius, intensityScale, lightVecOut, colorOut)` — iterates `gr_dlights[]`, checks distance < `dlight.intensity + radius`, applies attenuation and accumulates direction-weighted colour.

### Key technical details (Phase 30):
- Uses `gr_dlight_t` fields: `origin[3]`, `intensity`, `r`, `g`, `b` (individual fields, not array)
- Attenuation: `(1 - dist/intensity)` clamped to [0,1], scaled by `intensityScale`

### Files modified (Phase 30):
- `code/godot/godot_renderer.c` — `GR_GatherLightSources`

## Phase 31: PVS Visibility ✅
Conservative potentially-visible-set check.

- [x] **Task 31.1:** Implement `Godot_BSP_InPVS(p1, p2)` — conservative implementation, always returns 1 (true). Full leaf-cluster PVS data not retained.
- [x] **Task 31.2:** Wire `GR_inPVS` in `godot_renderer.c`.

### Files modified (Phase 31):
- `code/godot/godot_bsp_mesh.cpp` — `Godot_BSP_InPVS`
- `code/godot/godot_renderer.c` — `GR_inPVS` wired

## Phase 32: Scissor Clipping ✅
Scissor rectangle state capture for UI clipping.

- [x] **Task 32.1:** Add scissor state (x, y, w, h) in `godot_renderer.c`.
- [x] **Task 32.2:** Implement `GR_Scissor` — stores scissor rect.
- [x] **Task 32.3:** Add `Godot_Renderer_GetScissor` accessor.

### Files modified (Phase 32):
- `code/godot/godot_renderer.c` — scissor state + accessor

## Phase 33: Draw Background ✅
Background image data capture for menu/loading screens.

- [x] **Task 33.1:** Add background buffer (1024×1024×4 RGBA) in `godot_renderer.c`.
- [x] **Task 33.2:** Implement `GR_DrawBackground` — memcpy RGB data per row.
- [x] **Task 33.3:** Add `Godot_Renderer_GetBackground` accessor (returns pointer, cols, rows, active flag).
- [x] **Task 33.4:** Clear background state in `GR_ClearScene`.

### Files modified (Phase 33):
- `code/godot/godot_renderer.c` — background buffer + accessor

## Phase 34: Raw Image Loading (TGA) ✅
Full TGA image loader for engine use (loading screens, raw image resources).

- [x] **Task 34.1:** Implement `GR_LoadRawImage` — reads file via `ri.FS_ReadFile`, parses TGA header, handles uncompressed and RLE-compressed 24-bit (BGR) and 32-bit (BGRA) images, vertical flip for bottom-origin images.
- [x] **Task 34.2:** Implement `GR_FreeRawImage` — frees image data via `ri.Free`.
- [x] **Task 34.3:** Uses `ri.Malloc(int bytes)` directly (no TAG parameter in function pointer).

### Key technical details (Phase 34):
- TGA types: 2 (uncompressed true colour), 10 (RLE true colour)
- Bit depths: 24-bit (BGR→RGBA) or 32-bit (BGRA→RGBA)
- Vertical flip: bit 5 of image descriptor; bottom-origin rows reversed
- RLE: per-packet header (run/raw flag + count), supports straddling row boundaries

### Files modified (Phase 34):
- `code/godot/godot_renderer.c` — `GR_LoadRawImage`, `GR_FreeRawImage`

## Phase 35: Entity Parenting ✅
Composes parent entity transforms onto child entities.

- [x] **Task 35.1:** In `update_entities()`, add a post-pass that iterates entities with `parentEntity >= 0`.
- [x] **Task 35.2:** Find the parent entity by `entityNumber`, extract parent's `MeshInstance3D` transform.
- [x] **Task 35.3:** Composite child transform: `child_global = parent_global × child_local`.

### Files modified (Phase 35):
- `code/godot/MoHAARunner.cpp` — parenting post-pass in `update_entities()`

## Phase 36: Shader Animation (tcMod) ✅
UV scroll/rotate/scale/turb from shader definitions, parsed and applied at runtime.

- [x] **Task 36.1:** Extend `GodotShaderProps` with tcMod fields: `scroll_s/t`, `rotate`, `scale_s/t`, `turb_amp/freq`, `has_tcmod`.
- [x] **Task 36.2:** Add tcMod keyword parsing to `godot_shader_props.cpp` — `scroll`, `rotate`, `scale`, `turb` directives parsed from shader stage blocks.
- [x] **Task 36.3:** Apply `tcMod scale` via `set_uv1_scale()` in `apply_shader_props_to_material()`.
- [x] **Task 36.4:** Implement `update_shader_animations(delta)` — accumulates time, applies `tcMod scroll` as UV offset via `set_uv1_offset()` per frame.

### Files modified (Phase 36):
- `code/godot/godot_shader_props.h` — tcMod fields added to struct
- `code/godot/godot_shader_props.cpp` — tcMod parsing
- `code/godot/MoHAARunner.cpp` — UV animation in `update_shader_animations()`, tcMod scale in `apply_shader_props_to_material()`
- `code/godot/MoHAARunner.h` — `shader_anim_time`, method declaration

## Phase 37: Entity Mesh Cache Key ✅
Scaffolding for per-entity mesh caching to avoid redundant mesh rebuilds.

- [x] **Task 37.1:** Define `EntityCacheKey` struct in `MoHAARunner.h` — captures `hModel`, `customShader`, `frameInfo` animation state, `shaderRGBA` for change detection.
- [x] **Task 37.2:** Add `entity_cache_keys` vector to `MoHAARunner.h` for future per-entity cache lookups.
- [x] **Task 37.3:** Struct ready for integration once animation overhead profiling identifies cache-worthy entities.

### Files modified (Phase 37):
- `code/godot/MoHAARunner.h` — `EntityCacheKey` struct, `entity_cache_keys` vector

## Phase 38: Static Model Placement Parity ✅
Fixed incorrect static TIKI placement/rotation that produced random prop meshes obscuring gameplay view.

- [x] **Task 38.1:** Replaced helper with `AngleVectorsLeft`-compatible axis generation (`forward/left/up`) to match upstream static-model orientation.
- [x] **Task 38.2:** Applied the upstream origin offset path: `origin + axis * (tiki->load_origin * load_scale * instance_scale)`.
- [x] **Task 38.3:** Corrected Godot basis derivation from id-space axes (`right=-left`, `up=up`, `back=-forward`).
- [x] **Task 38.4:** Removed stale TODO marker around `load_static_models()` after fix.

### Key technical details (Phase 38):
- Mirrors `renderergl1/tr_main.c:R_RotateForStaticModel` and `renderergl1/tr_staticmodels.cpp:R_AddStaticModelSurfaces` transform logic
- Ensures static props are no longer spawned with incorrect offsets that stack over the camera path

### Files modified (Phase 38):
- `code/godot/MoHAARunner.cpp` — static-model angle basis + load-origin offset transform fix

## Phase 39: Music Fade Transitions ✅
- [x] **Task 39.1:** Added smooth music volume fading using engine's `fadeTime` parameter.
- [x] **Task 39.2:** When `MUSIC_UpdateVolume` provides a non-zero `fadeTime`, music volume interpolates linearly over that duration instead of snapping instantly.
- [x] **Task 39.3:** Fade state tracked via `music_fade_from`, `music_fade_to`, `music_fade_duration`, `music_fade_elapsed` members in MoHAARunner.
- [x] **Task 39.4:** Per-frame interpolation in `update_audio(delta)` uses the real Godot frame delta for accurate timing.

### Key technical details (Phase 39):
- `update_audio()` now takes `double delta` parameter from `_process(delta)`
- Fade uses linear interpolation: `cur_vol = from + (to - from) * (elapsed / duration)`
- Instant volume change still used when `fadeTime <= 0.01`

### Files modified (Phase 39):
- `code/godot/MoHAARunner.h` — added fade state members, changed `update_audio` signature
- `code/godot/MoHAARunner.cpp` — fade interpolation logic, delta pass-through

## Phase 40: Position-Aware Looping Sounds ✅
- [x] **Task 40.1:** Changed looping sound tracking key from `sfxHandle` alone to a composite key of `sfxHandle + quantised position`.
- [x] **Task 40.2:** Allows multiple instances of the same sound effect at different world positions (e.g. two water fountains).
- [x] **Task 40.3:** Position quantised to 128-unit grid for stable matching across frames.

### Key technical details (Phase 40):
- Loop key = `(sfxHandle << 36) | posHash` where posHash encodes quantised X/Y/Z
- `active_loops` map changed from `int` to `int64_t` keys
- Existing loop update/cleanup logic preserved

### Files modified (Phase 40):
- `code/godot/MoHAARunner.h` — changed `active_loops` key type to `int64_t`
- `code/godot/MoHAARunner.cpp` — composite loop key generation via lambda

## Phase 41: Sound Channel Priority Eviction ✅
- [x] **Task 41.1:** Added `PlayerSlotInfo` tracking for each 3D audio player slot (entity number + channel).
- [x] **Task 41.2:** When starting a new 3D sound, first check if the same entity+channel already has a slot — evict it to reuse that slot.
- [x] **Task 41.3:** Fallback: find an idle (non-playing) slot before resorting to round-robin eviction.

### Key technical details (Phase 41):
- `player_slot_info` vector tracks `{entnum, channel, in_use}` per 3D player slot
- Priority: same entity+channel eviction > idle slot > round-robin
- Prevents the same entity playing duplicate sounds on the same channel

### Files modified (Phase 41):
- `code/godot/MoHAARunner.h` — added `PlayerSlotInfo` struct and `player_slot_info` vector
- `code/godot/MoHAARunner.cpp` — channel-aware player allocation logic

## Build Fix: Generated Parser Files & Include Guards
- [x] Generated `yyParser.cpp`, `yyParser.hpp`, `yyLexer.cpp`, `yyLexer.h` from bison/flex sources
- [x] Removed `/code/parser/generated` from `.gitignore` so generated files are tracked (SCons has no generation step)
- [x] Added `#ifndef __BOTLIB_H` / `#define __BOTLIB_H` / `#endif` include guards to `code/fgame/botlib.h` to fix redefinition errors

## Phase 43: MP3-in-WAV Audio Decoding ✅
- [x] **Task 43.1:** Detect MP3-encoded data inside WAV containers (WAVE format tag 0x0055) in `load_wav_from_vfs()`.
- [x] **Task 43.2:** When format 0x0055 is detected, extract the data chunk and create `AudioStreamMP3` instead of rejecting the file.
- [x] **Task 43.3:** Also detect raw MP3 files (ID3 tag or MP3 sync word) and load them as `AudioStreamMP3`.
- [x] **Task 43.4:** Changed return type and cache from `Ref<AudioStreamWAV>` to `Ref<AudioStream>` to support both WAV and MP3.
- [x] **Task 43.5:** Updated looping sound code to handle both `AudioStreamWAV` (set_loop_mode) and `AudioStreamMP3` (set_loop) for loop creation.

### Key technical details (Phase 43):
- MOHAA stores many sound effects as MP3-encoded WAV files (RIFF/WAVE with fmt tag 0x0055)
- The data chunk contains raw MP3 frames that Godot's `AudioStreamMP3` can decode
- `Ref<AudioStream>` is the common base type for both `AudioStreamWAV` and `AudioStreamMP3`
- Loop handling uses `dynamic_cast`-style Ref conversion to determine stream type

### Files modified (Phase 43):
- `code/godot/MoHAARunner.h` — changed `sfx_cache` to `Ref<AudioStream>`, changed `load_wav_from_vfs` return type, added `array_mesh.hpp` include
- `code/godot/MoHAARunner.cpp` — MP3-in-WAV detection, raw MP3 detection, dual-type loop handling

## Phase 60: Per-Entity Skeletal Mesh Caching ✅
- [x] **Task 60.1:** Added `SkelMeshCacheEntry` struct with animation state hash and cached `ArrayMesh`.
- [x] **Task 60.2:** Compute FNV-1a hash of frameInfoBuf + boneTagBuf + boneQuatBuf + actionWeight + hModel per entity per frame.
- [x] **Task 60.3:** Check cache before CPU skinning — if animation state hash matches, reuse the cached mesh.
- [x] **Task 60.4:** Cache newly built skinned meshes after successful CPU skinning.
- [x] **Task 60.5:** Clear skeletal mesh cache on map change.

### Key technical details (Phase 60):
- Cache key is `entityNumber` → `(anim_hash, Ref<ArrayMesh>)`
- FNV-1a hash computed over 256-byte frameInfo + 20-byte boneTag + 80-byte boneQuat + actionWeight + hModel
- When animation state hasn't changed between frames, the expensive bone preparation and CPU skinning are skipped entirely
- Cache is invalidated on map change (BSP unload)

### Files modified (Phase 60):
- `code/godot/MoHAARunner.h` — added `SkelMeshCacheEntry` struct and `skel_mesh_cache` map
- `code/godot/MoHAARunner.cpp` — animation hash computation, cache lookup/store, cache clear on map change

## Phase 61: Tinted Material Cache ✅
- [x] **Task 61.1:** Added `tinted_mat_cache` mapping composite key → cached `StandardMaterial3D`.
- [x] **Task 61.2:** Cache key combines hModel, surface index, entity RGBA, and quantised lightgrid colour.
- [x] **Task 61.3:** On cache hit, reuse the previously duplicated tinted material instead of creating a new one.
- [x] **Task 61.4:** On cache miss, duplicate the base material, apply tinting, and store in cache.
- [x] **Task 61.5:** Clear tinted material cache on map change.

### Key technical details (Phase 61):
- Previously, entity colour tinting duplicated materials every frame for every entity with non-white RGBA or lightgrid tint
- Cache key: `(hModel:20b | surfIdx:8b | rgba[0..3]:32b | quantised_light:4b)` packed into `uint64_t`
- Light colour quantised to 4-bit precision (16 levels per channel) for stable cache matching
- Cache is invalidated on map change alongside skeletal mesh cache

### Files modified (Phase 61):
- `code/godot/MoHAARunner.h` — added `tinted_mat_cache` member, added `standard_material3d.hpp` include
- `code/godot/MoHAARunner.cpp` — cache lookup/store in entity tinting code, cache clear on map change

## Phase 65: Fullbright/Nolightmap Surface Rendering ✅
- [x] **Task 65.1:** Added `no_lightmap` field to `GodotShaderProps` struct.
- [x] **Task 65.2:** Parse `surfaceparm nolightmap` in the shader parser alongside existing surfaceparm handling.
- [x] **Task 65.3:** In `apply_shader_props_to_material`, set `SHADING_MODE_UNSHADED` for nolightmap surfaces, rendering them fullbright without Godot's lighting calculations.

### Key technical details (Phase 65):
- Surfaces with `surfaceparm nolightmap` in their .shader definition have no lightmap stage
- In the original engine, these surfaces are rendered using vertex colours alone (fullbright)
- In Godot, `SHADING_MODE_UNSHADED` achieves the same effect — the albedo texture renders at full intensity without directional/ambient lighting influence
- This fixes surfaces like skybox fragments, decal overlays, and certain UI-in-world surfaces that were previously too dark

### Files modified (Phase 65):
- `code/godot/godot_shader_props.h` — added `bool no_lightmap` to `GodotShaderProps`
- `code/godot/godot_shader_props.cpp` — parse `surfaceparm nolightmap`
- `code/godot/MoHAARunner.cpp` — set `SHADING_MODE_UNSHADED` for nolightmap materials
