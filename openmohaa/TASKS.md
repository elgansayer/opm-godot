
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

## Phase 121: Network Initialisation ✅

Verified that the engine's UDP networking stack initialises and operates correctly under the Godot GDExtension runtime. No Godot-specific patches were required — standard POSIX socket APIs work without modification in the GDExtension process model.

- [x] **Task 121.1:** `NET_Init()` creates UDP sockets correctly — calls `NET_Config(qtrue)` → `NET_OpenIP()` → `NET_IPSocket()` which uses standard `socket(AF_INET, SOCK_DGRAM, IPPROTO_UDP)` + `bind()`. No Godot process model interference.
- [x] **Task 121.2:** `Sys_IsLANAddress()` correctly identifies RFC1918 private networks and link-local addresses (unchanged from upstream).
- [x] **Task 121.3:** `NET_SendPacket()` / `Sys_SendPacket()` uses standard `sendto()` on the UDP socket. Works correctly under Godot.
- [x] **Task 121.4:** `NET_GetPacket()` uses `recvfrom()` with non-blocking sockets. Works correctly.
- [x] **Task 121.5:** `net_port` cvar defaults to 12203 (`PORT_SERVER` in `qcommon.h`). Port scanning (+10 increments) in `NET_OpenIP()` handles busy ports.
- [x] **Task 121.6:** IPv4 binding on all interfaces via `net_ip` cvar (default "0.0.0.0"). IPv6 supported via `net_ip6` / `net_port6` when `net_enabled` includes `NET_ENABLEV6`.
- [x] **Task 121.7:** `NET_Sleep()` correctly uses `select()` for packet polling. Under Godot, `common.c` already passes `NET_Sleep(0)` (non-blocking) so the frame loop never blocks.

### Key technical details (Phase 121):
- **No `#ifdef GODOT_GDEXTENSION` needed in `net_ip.c`** — the socket code is standard POSIX/Winsock with platform conditionals already in place. Godot's process model does not restrict UDP socket operations.
- **Blocking prevention already handled**: `common.c` line 2330 has `#ifdef GODOT_GDEXTENSION` guard that calls `NET_Sleep(0)` and breaks out of the frame loop immediately, preventing any blocking.
- **`sv_main.c` idle sleep already guarded**: line 1054 has `#if defined(DEDICATED) && !defined(GODOT_GDEXTENSION)` to prevent `Sys_Sleep(-1)` blocking when no map is loaded.
- **PROTOCOL_VERSION = 17**, PORT_SERVER = 12203 (defined in `qcommon.h`).

## Phase 122: Server Hosting ✅

Verified that the server subsystem initialises and runs correctly under the GDExtension build.

- [x] **Task 122.1:** `SV_Init()` registers all server cvars (`sv_maxclients`, `sv_hostname`, `g_gametype`, `sv_fps`, `sv_timeout`, `sv_mapRotation`) and initialises the server state machine.
- [x] **Task 122.2:** Listen server mode (dedicated 0) is the default under Godot — client + server run in one process via `Com_Frame()` → `SV_Frame()` + `CL_Frame()`.
- [x] **Task 122.3:** Dedicated server mode (dedicated 1) works when DEDICATED is defined (build already supports this).
- [x] **Task 122.4:** `sv_mapRotation` and `SV_MapRestart()` use standard engine paths — no Godot-specific changes needed.
- [x] **Task 122.5:** Server state transitions (SS_DEAD → SS_LOADING → SS_GAME) tracked via existing `Godot_GetServerState()` accessor in `godot_server_accessors.c`.

## Phase 123: Client Connection Flow ✅

Verified the full client connection pipeline is intact under the GDExtension build.

- [x] **Task 123.1:** `connect <ip:port>` command triggers `CL_Connect_f()` in `cl_main.cpp`.
- [x] **Task 123.2:** Challenge/response handshake: `getchallenge` → `challengeResponse` → `connect` packet sequence implemented in `CL_CheckForResend()`.
- [x] **Task 123.3:** Connection accepted → gamestate download → first snapshot via `CL_ConnectionlessPacket()` → `CL_ParseGamestate()` → `CL_ParseSnapshot()`.
- [x] **Task 123.4:** Client state machine: CA_DISCONNECTED → CA_CONNECTING → CA_CHALLENGING → CA_CONNECTED → CA_LOADING → CA_PRIMED → CA_ACTIVE.
- [x] **Task 123.5:** Timeout handling via `cl_timeout` and `cl_connect_timeout` cvars — `CL_CheckTimeout()` disconnects on prolonged silence.

## Phase 124: Snapshot System ✅

Verified delta-compressed entity snapshots work correctly.

- [x] **Task 124.1:** `SV_BuildClientSnapshot()` gathers visible entities using PVS (Potential Visibility Set) for each connected client.
- [x] **Task 124.2:** `SV_SendClientSnapshot()` delta-compresses against the last acknowledged snapshot using `MSG_WriteDeltaEntity()`.
- [x] **Task 124.3:** `CL_ParseSnapshot()` on the client side decodes delta-compressed entities and applies them to the local game state.
- [x] **Task 124.4:** Entity baselines (`cl.entityBaselines[]`) provide the initial state for delta encoding — no issues found.
- [x] **Task 124.5:** Snapshot size controlled by `sv_maxRate` and client `rate` cvar — standard rate-limiting logic unchanged.

## Phase 125: Client Prediction ✅

Verified client-side prediction infrastructure.

- [x] **Task 125.1:** `CL_PredictPlayerState()` runs `Pmove()` locally with pending usercmds — code is standard, shared between client and server (`bg_pmove.cpp`).
- [x] **Task 125.2:** Prediction error correction applies smooth snap-back when server state diverges from predicted state.
- [x] **Task 125.3:** `cl_predict` cvar (default 1) enables/disables prediction — standard functionality.

## Phase 126: Lag Compensation ✅

Verified server-side lag compensation code paths.

- [x] **Task 126.1:** `sv_antilag` cvar enables server-side entity rewind for hit detection.
- [x] **Task 126.2:** `G_AntilagRewind()` / `G_AntilagForward()` in fgame code rewind entity positions to the client's timestamp — standard engine functionality, no Godot changes needed.

## Phase 127: Reliable Commands ✅

Verified reliable command delivery system.

- [x] **Task 127.1:** `clc_clientCommand` / `svc_serverCommand` use sequence numbers for guaranteed delivery over UDP.
- [x] **Task 127.2:** `MAX_RELIABLE_COMMANDS` (64) limits the reliable command buffer — overflow handled by dropping the oldest command.
- [x] **Task 127.3:** Config string updates (`CS_PLAYERS`, `CS_SERVERINFO`) delivered via reliable commands — standard path.

## Phase 128: Configstrings & Userinfo ✅

Verified configstring and userinfo propagation.

- [x] **Task 128.1:** Server sends configstrings during gamestate via `SV_UpdateConfigstrings()`.
- [x] **Task 128.2:** Client sends userinfo (`name`, `rate`, `model`, etc.) via `CL_AddReliableCommand()`.
- [x] **Task 128.3:** `CL_SystemInfoChanged()` processes all system info fields from the server.

## Phase 129: Master Server Registration ✅

Verified GameSpy heartbeat protocol integration.

- [x] **Task 129.1:** `sv_gamespy` cvar controls master server registration (default enabled).
- [x] **Task 129.2:** `SV_MasterHeartbeat()` sends periodic heartbeats (every `HB_TIME` interval) when gamespy is enabled.
- [x] **Task 129.3:** `SV_GamespyHeartbeat()` uses the GameSpy protocol library in `code/gamespy/`.
- [x] **Task 129.4:** Master server addresses configured via engine defaults — standard functionality.

## Phase 130: Connection Robustness ✅

Verified timeout handling and disconnect logic.

- [x] **Task 130.1:** `cl_timeout` (default 200s) and `sv_timeout` (default 120s) control timeout detection.
- [x] **Task 130.2:** Graceful disconnect: `disconnect` command sends reliable disconnect packet, cleans up client slot.
- [x] **Task 130.3:** Ungraceful disconnect: `SV_CheckTimeouts()` detects silent clients and calls `SV_DropClient()`.
- [x] **Task 130.4:** Network error recovery: malformed packets ignored via sequence number validation in `Netchan_Process()`.
- [x] **Task 130.5:** `reconnect` command re-establishes connection to the last known server address (`clc.servername`).

## Phases 131–140: Protocol Compatibility (Verified by Code Review) ✅

These phases cover cross-client protocol compatibility. Verified by code inspection — the GDExtension build uses identical network protocol code to upstream OpenMoHAA.

- [x] **Task 131:** Protocol code is shared — our client/server uses the same `SV_DirectConnect()`, `CL_Connect_f()`, `MSG_Read/WriteDelta*()` functions as upstream.
- [x] **Task 132:** No Godot-specific protocol modifications — wire protocol is byte-identical.
- [x] **Task 133:** `PROTOCOL_VERSION = 17` matches upstream OpenMoHAA (defined in `qcommon.h` line 371).
- [x] **Task 134:** `com_target_game` cvar selects AA (0), SH (1), BT (2) — game directory switching (`main/`, `mainta/`, `maintt/`) is VFS-level, not protocol-level.
- [x] **Task 135:** Cross-version edge cases handled by game version checks in `SV_DirectConnect()`.
- [x] **Task 136:** `sv_maxclients` controls player limit — `SV_Init()` allocates `client_t` array accordingly.
- [x] **Task 137:** `sv_mapRotation` cycling handled by `SV_MapRestart()` and map rotation logic in `sv_ccmds.c`.
- [x] **Task 138:** Vote system: `callvote`, `vote yes/no` routed through reliable commands → `SV_ExecuteClientCommand()` → fgame processing.
- [x] **Task 139:** RCON: `rconpassword` cvar + `SVC_RemoteCommand()` in `sv_main.c` — standard Q3 RCON.
- [x] **Task 140:** Spectator mode: handled by fgame entity states — no network-level changes needed.

## Phases 141–150: Network Edge Cases (Verified by Code Review) ✅

- [x] **Task 141:** `net_port` correctly bound via `NET_OpenIP()` → `NET_IPSocket()` → `bind()`.
- [x] **Task 142:** IPv4 fully supported; IPv6 supported when `net_enabled` includes `NET_ENABLEV6`.
- [x] **Task 143:** Rate limiting: `rate`, `snaps`, `cl_maxpackets` cvars honoured by `SV_RateMsec()` and `CL_WritePacket()`.
- [x] **Task 144:** Packet fragmentation handled by `Netchan_Transmit()` / `Netchan_TransmitNextFragment()` in `net_chan.c`.
- [x] **Task 145:** Server-authoritative state enforced — client usercmds validated server-side by `SV_ClientThink()`.
- [x] **Task 146:** Client disconnect cleanup: `SV_DropClient()` frees entity, notifies other clients, sets `CS_ZOMBIE` state.
- [x] **Task 147:** `killserver` → `SV_Shutdown()` sends disconnect to all clients, cleans up all slots.
- [x] **Task 148:** Multiple servers on different ports: `+set net_port XXXXX` supported via cvar system.
- [x] **Task 149:** RCON password authentication: `SVC_RemoteCommand()` checks `rconpassword` before executing.
- [x] **Task 150:** Server status query: `SVC_Status()` and `SVC_Info()` respond to external queries (server browsers).

## Phases 151–155: Network Performance (Verified by Code Review) ✅

- [x] **Task 151:** Bandwidth governed by `rate` cvar (client) and `sv_maxRate` (server). `SV_RateMsec()` calculates packet scheduling.
- [x] **Task 152:** Delta compression in `MSG_WriteDeltaEntity()` / `MSG_ReadDeltaEntity()` — only changed fields are transmitted.
- [x] **Task 153:** PVS-based snapshot building in `SV_BuildClientSnapshot()` → `SV_AddEntitiesVisibleFromPoint()` — only entities visible to the client are included.
- [x] **Task 154:** Server tick rate controlled by `sv_fps` cvar (default 20). `SV_Frame()` accumulates residual time and runs game frames at consistent intervals.
- [x] **Task 155:** Client interpolation: `CL_InterpolatePlayerState()` smoothly interpolates between snapshots using `cl.serverTime`.

### Network Accessor API (Phase 121)

Created `code/godot/godot_network_accessors.c` and `code/godot/godot_network_accessors.h` to expose network state to MoHAARunner.cpp:

| Function | Returns |
|----------|---------|
| `Godot_Net_GetClientState()` | `connstate_t` enum (CA_UNINITIALIZED..CA_ACTIVE) |
| `Godot_Net_GetServerClientCount()` | Count of CS_ACTIVE server client slots |
| `Godot_Net_GetServerConnectedCount()` | Count of CS_CONNECTED+ server client slots |
| `Godot_Net_GetPing()` | Snapshot ping (ms), 0 if not active |
| `Godot_Net_GetSnapshotRate()` | `snaps` cvar value |
| `Godot_Net_GetServerAddress()` | Server address string, "" if disconnected |
| `Godot_Net_IsLANGame()` | 1 if server is on LAN |
| `Godot_Net_IsServerRunning()` | 1 if com_sv_running is true |
| `Godot_Net_GetPort()` | `net_port` cvar value |
| `Godot_Net_GetProtocolVersion()` | PROTOCOL_VERSION (17) |

### Files created:
- `code/godot/godot_network_accessors.h` — network accessor declarations
- `code/godot/godot_network_accessors.c` — network accessor implementations

### Integration notes for other agents:
- **Agent 5 (UI):** Network accessors available for server browser, connection status display.
- **Agent 10 (Integration):** All functions use `extern "C"` linkage, callable from MoHAARunner.cpp.
- **No engine files modified** — all networking code is standard upstream OpenMoHAA. The only Godot-specific guards affecting networking are pre-existing in `common.c` (non-blocking frame loop) and `sv_main.c` (no idle sleep).
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

## Phase 81: Gamma/Overbright Tonemap ✅
- [x] **Task 81.1:** Added Reinhardt tonemap to the WorldEnvironment to approximate MOHAA's overbright gamma.
- [x] **Task 81.2:** Set exposure to 1.2 to compensate for MOHAA's 2x overbright lightmap factor.
- [x] **Task 81.3:** Set tonemap white to 1.0 for proper highlight rolloff.

### Key technical details (Phase 81):
- MOHAA's GL1 renderer applies a 2x overbright factor to lightmap texels during upload
- Godot's Reinhardt tonemap with a slight exposure boost (1.2) approximates this look
- The existing lightmap 128×128 overbright in the BSP mesh builder (Phase 7b) combined with tonemap produces visual parity

### Files modified (Phase 81):
- `code/godot/MoHAARunner.cpp` — added tonemap settings to Environment in `setup_3d_scene()`
## Phase 42: Music Playback — OGG/MP3 Streaming Module ✅
Standalone music manager that loads MP3 files from the engine VFS and plays them through Godot AudioStreamPlayer nodes with crossfade support.

- [x] **Task 42.1:** Created `godot_music.h` with C-linkage API: `Godot_Music_Init`, `Godot_Music_Shutdown`, `Godot_Music_Update`, `Godot_Music_SetVolume`, `Godot_Music_IsPlaying`, `Godot_Music_GetCurrentTrack`.
- [x] **Task 42.2:** Created `godot_music.cpp` — two AudioStreamPlayer nodes for crossfade, plus a triggered-music player.
- [x] **Task 42.3:** VFS path resolution: tries name as-is, `sound/music/<name>.mp3`, `sound/music/<name>`, `<name>.mp3`.
- [x] **Task 42.4:** Music state machine reads `Godot_Sound_GetMusicAction()` each frame — handles PLAY, STOP, VOLUME actions.
- [x] **Task 42.5:** Crossfade: when switching tracks, the old player fades out over `fadeTime` seconds while the new one fades in.
- [x] **Task 42.6:** Triggered music: reads `Godot_Sound_GetTriggeredAction()` for setup/start/stop/pause/unpause.
- [x] **Task 42.7:** Volume conversion: linear 0–1 → Godot dB scale via `20 * log10(linear)`, clamped to -80 dB minimum.

### Key technical details (Phase 42):
- Uses `Godot_VFS_ReadFile` to load MP3 bytes from pk3 archives
- Creates `AudioStreamMP3` from raw bytes via `PackedByteArray`
- Two-player crossfade: `s_players[0]` and `s_players[1]` alternate as active
- `s_triggered_player` handles `S_TriggeredMusic_*` events separately
- All Godot node creation/destruction uses `memnew`/`memdelete`

### Files created (Phase 42):
- `code/godot/godot_music.h` — C-linkage header
- `code/godot/godot_music.cpp` — Implementation (~300 lines)

### MoHAARunner Integration Required (Phase 42):
**New `#include` lines:**
```cpp
#include "godot_music.h"
```

**New calls needed:**
- In `setup_audio()` or `_ready()`: `Godot_Music_Init((void*)this);`
- In `update_audio(delta)`: `Godot_Music_Update((float)delta);`
- In `~MoHAARunner()` or shutdown: `Godot_Music_Shutdown();`
- Optionally in volume cvar handling: `Godot_Music_SetVolume(s_musicVolume->value);`

## Phase 43: Enhanced Loop Sound Management ✅
Added entity number tracking to looping sounds for entity-attached loop position updates.

- [x] **Task 43.1:** Added `entnum` field (int, -1 = none) to `gr_loop_sound_t` struct in `godot_sound.c`.
- [x] **Task 43.2:** Initialise `entnum = -1` in `S_AddLoopingSound` (extended API has no entity parameter).
- [x] **Task 43.3:** Added `Godot_Sound_GetLoopEx()` — extended accessor that also returns entity number.

### Key technical details (Phase 43):
- The extended `S_AddLoopingSound` signature (from `snd_public.h` line 118) does not include an entity number
- `entnum` field defaults to -1; MoHAARunner can match loop positions to entities for tracking
- Original `Godot_Sound_GetLoop()` unchanged for backward compatibility

### Files modified (Phase 43):
- `code/godot/godot_sound.c` — `gr_loop_sound_t` struct + `Godot_Sound_GetLoopEx()`

### MoHAARunner Integration Required (Phase 43):
**New accessor available:**
```c
extern "C" void Godot_Sound_GetLoopEx(int index, float *origin, float *velocity,
                                       int *sfxHandle, float *volume, float *minDist,
                                       float *maxDist, float *pitch, int *flags,
                                       int *entnum);
```
Can replace `Godot_Sound_GetLoop()` calls to also receive entity number for position tracking.

## Phase 44: Sound Channel & Priority Metadata
Reserved for future channel priority enhancements. Current channel-aware eviction (Phase 41) handles the primary use case. Additional priority weighting based on sound type/distance can be added here.

## Phase 45: Sound Alias / Ubersound System ✅
Ubersound/alias parser that reads `.scr` files from VFS and builds a lookup table for sound alias resolution with random variant selection.

- [x] **Task 45.1:** Created `godot_ubersound.h` with C-linkage API: `Godot_Ubersound_Init`, `Godot_Ubersound_Shutdown`, `Godot_Ubersound_Resolve`, `Godot_Ubersound_GetAliasCount`, `Godot_Ubersound_IsLoaded`, `Godot_Ubersound_HasAlias`.
- [x] **Task 45.2:** Created `godot_ubersound.cpp` — parses `alias` and `aliascache` commands from `.scr` files.
- [x] **Task 45.3:** Tokeniser handles whitespace-delimited tokens, quoted strings, and `//` comments.
- [x] **Task 45.4:** Optional parameters parsed: `soundparms`, `volume`, `mindist`, `maxdist`, `pitch`, `channel`, `subtitle`/`dialog`.
- [x] **Task 45.5:** Random variant selection: when multiple entries share an alias name, `Godot_Ubersound_Resolve` picks one at random.
- [x] **Task 45.6:** Scans `ubersound/` directory for `.scr` files, plus `sound/ubersound.scr` and `sound/uberdialog.scr`.

### Key technical details (Phase 45):
- Uses `std::unordered_map<std::string, UbersoundAlias>` for O(1) alias lookup
- Each `UbersoundAlias` contains a `std::vector<UbersoundEntry>` for multi-variant aliases
- Simple LCG PRNG for deterministic random selection (avoids `<random>` dependency)
- VFS file listing via `Godot_VFS_ListFiles("ubersound", ".scr", &count)`
- No engine header includes — all VFS access via extern "C" accessors

### Files created (Phase 45):
- `code/godot/godot_ubersound.h` — C-linkage header
- `code/godot/godot_ubersound.cpp` — Implementation (~300 lines)

### MoHAARunner Integration Required (Phase 45):
**New `#include` lines:**
```cpp
#include "godot_ubersound.h"
```

**New calls needed:**
- In `check_world_load()` after map loads: `Godot_Ubersound_Init();`
- In shutdown or map unload: `Godot_Ubersound_Shutdown();`
- In sound loading (before `load_wav_from_vfs`): check `Godot_Ubersound_Resolve(name, ...)` to resolve alias to real filename
- Optional: `Godot_Ubersound_HasAlias(name)` to check before resolving

## Phase 46: MP3-in-WAV Decoding Support ✅
Added detection function for MOHAA's MP3-in-WAV files (WAVE format tag `0x0055`).

- [x] **Task 46.1:** Added `Godot_Sound_DetectMP3InWav()` function to `godot_sound.c`.
- [x] **Task 46.2:** Walks RIFF/WAV chunks to find `fmt ` and `data` sections.
- [x] **Task 46.3:** Checks format tag for `0x0055` (MPEG audio) vs `0x0001` (PCM).
- [x] **Task 46.4:** Returns MP3 payload offset and length for extraction.

### Key technical details (Phase 46):
- WAVE format tag `0x0055` indicates MPEG audio stored inside a WAV container
- Function walks chunk headers (word-aligned) to locate both `fmt ` and `data` chunks
- Returns 1 (MP3 found), 0 (standard PCM), or -1 (parse error)
- Caller extracts the MP3 payload bytes and creates `AudioStreamMP3` instead of `AudioStreamWAV`

### Files modified (Phase 46):
- `code/godot/godot_sound.c` — `Godot_Sound_DetectMP3InWav()` function

### MoHAARunner Integration Required (Phase 46):
**New accessor available:**
```c
extern "C" int Godot_Sound_DetectMP3InWav(const unsigned char *data, int dataLen,
                                           int *out_mp3_offset, int *out_mp3_length);
```
In `load_wav_from_vfs()`, after reading the file, call this function before parsing WAV headers. If it returns 1, extract `[out_mp3_offset .. out_mp3_offset+out_mp3_length]` bytes and create `AudioStreamMP3` instead of `AudioStreamWAV`.

## Phase 47: Speaker Entity Sounds ✅
Speaker entity support — parses BSP entity strings for sound-emitting entities and creates persistent AudioStreamPlayer3D nodes.

- [x] **Task 47.1:** Created `godot_speaker_entities.h` with C-linkage API: `Godot_Speakers_Init`, `Godot_Speakers_Shutdown`, `Godot_Speakers_LoadFromEntities`, `Godot_Speakers_Update`, `Godot_Speakers_GetCount`, `Godot_Speakers_TriggerByIndex`.
- [x] **Task 47.2:** Created `godot_speaker_entities.cpp` — BSP entity string parser.
- [x] **Task 47.3:** Parses entities with `noise` key for sound file, `wait`/`random` for timing.
- [x] **Task 47.4:** Creates AudioStreamPlayer3D at entity origin (id-space → Godot coordinate conversion).
- [x] **Task 47.5:** Handles WAV, MP3, and MP3-in-WAV loading via `Godot_Sound_DetectMP3InWav`.
- [x] **Task 47.6:** Repeating speakers: `wait_time` controls replay interval with optional `random_time` offset.
- [x] **Task 47.7:** Triggered speakers (`spawnflags & 1`): start inactive, activate via `Godot_Speakers_TriggerByIndex`.

### Key technical details (Phase 47):
- Up to `MAX_SPEAKER_ENTITIES` (64) speakers per map
- Coordinate conversion: id(X,Y,Z) → Godot(Y, Z, -X) × `MOHAA_UNIT_SCALE`
- Attenuation model: `ATTENUATION_INVERSE_DISTANCE`, max_distance=100m, unit_size=10
- On map change, all existing speaker nodes are cleaned up before new ones are created

### Files created (Phase 47):
- `code/godot/godot_speaker_entities.h` — C-linkage header + `godot_speaker_t` struct
- `code/godot/godot_speaker_entities.cpp` — Implementation (~340 lines)

### MoHAARunner Integration Required (Phase 47):
**New `#include` lines:**
```cpp
#include "godot_speaker_entities.h"
```

**New calls needed:**
- In `setup_3d_scene()` or `_ready()`: `Godot_Speakers_Init((void*)scene_root);`
- In `check_world_load()` after BSP entity parsing: `Godot_Speakers_LoadFromEntities(entity_string);`
- In `update_audio(delta)`: `Godot_Speakers_Update((float)delta);`
- In shutdown: `Godot_Speakers_Shutdown();`

## Phase 48: Sound Occlusion (Basic) ✅
Basic line-of-sight sound occlusion using the engine's collision model (CM_BoxTrace).

- [x] **Task 48.1:** Created `godot_sound_occlusion.h` with C-linkage API: `Godot_SoundOcclusion_Check`, `Godot_SoundOcclusion_SetEnabled`, `Godot_SoundOcclusion_IsEnabled`.
- [x] **Task 48.2:** Created `godot_sound_occlusion.c` — point trace via `CM_BoxTrace`.
- [x] **Task 48.3:** Binary occlusion model: trace fraction < 1.0 → `OCCLUSION_FACTOR` (0.3), otherwise 1.0.
- [x] **Task 48.4:** Disabled by default — must be explicitly enabled via `Godot_SoundOcclusion_SetEnabled(1)`.

### Key technical details (Phase 48):
- Uses `CM_BoxTrace` with zero-size box (point trace) through world model (handle 0)
- Brush mask: `CONTENTS_SOLID` from `surfaceflags.h`
- Attenuation factor: 0.3× for fully occluded sounds (single fixed value)
- No multi-ray sampling or material-based attenuation — deliberately simple
- Disabled by default to avoid performance impact; enable when needed

### Limitations (Phase 48):
- Binary occlusion only (no partial/frequency-dependent attenuation)
- Single ray from listener to sound origin (no multi-sample)
- Does not account for sound propagation through openings
- May false-positive through thin walls or windows

### Files created (Phase 48):
- `code/godot/godot_sound_occlusion.h` — C-linkage header
- `code/godot/godot_sound_occlusion.c` — Implementation (~50 lines)

### MoHAARunner Integration Required (Phase 48):
**New `#include` lines:**
```cpp
#include "godot_sound_occlusion.h"
```

**New calls needed:**
- Optionally in `_ready()` or via cvar: `Godot_SoundOcclusion_SetEnabled(1);`
- In `update_audio()` when setting volume for 3D sounds:
  ```cpp
  float occl = Godot_SoundOcclusion_Check(
      listener_origin[0], listener_origin[1], listener_origin[2],
      sound_origin[0], sound_origin[1], sound_origin[2]);
  effective_volume *= occl;
  ```

## Phase 66: Multi-Stage Shader Parsing & Rendering ✅
- [x] **Task 66.1:** Added `MohaaShaderStage` struct to `godot_shader_props.h` with per-stage fields: `map`, `blendSrc`/`blendDst` (`MohaaBlendFactor`), `rgbGen` (`MohaaStageRgbGen`), `alphaGen` (`MohaaStageAlphaGen`), `tcGen` (`MohaaStageTcGen`), `tcMod` array (`MohaaStageTcMod`), `animMap` frames, `isClampMap`, `isLightmap`, `hasAlphaFunc`.
- [x] **Task 66.2:** Added supporting enums: `MohaaBlendFactor` (10 GL blend factors), `MohaaWaveFunc` (5 wave types), `MohaaStageRgbGen` (8 types), `MohaaStageAlphaGen` (7 types), `MohaaStageTcGen` (4 types), `MohaaStageTcModType` (6 types).
- [x] **Task 66.3:** Added `MohaaWaveParams` struct (func, base, amplitude, phase, frequency) and `MohaaStageTcMod` struct (type, params, wave).
- [x] **Task 66.4:** Extended `GodotShaderProps` with `stages[MOHAA_SHADER_STAGE_MAX]` array and `stage_count` field.
- [x] **Task 66.5:** Extended `parse_shader_body()` in `godot_shader_props.cpp` to parse ALL stages (not just first). Each `{ }` block at depth 2 populates a `MohaaShaderStage` entry. Backward compatibility maintained: first-stage data still populates the existing flat fields.
- [x] **Task 66.6:** Added `parse_blend_factor()` and `parse_wave_func()` helper functions for tokenising GL blend factor names and wave function names into enums.
- [x] **Task 66.7:** Per-stage `map`/`clampMap` parsing — stores texture path, sets `isClampMap` and `isLightmap` (for `$lightmap`).
- [x] **Task 66.8:** Per-stage `blendFunc` parsing — stores `blendSrc`/`blendDst` as `MohaaBlendFactor` enums; shorthand forms (`blend`, `add`, `filter`) mapped to correct factor pairs.
- [x] **Task 66.9:** Created `godot_shader_material.h` — public API: `Godot_Shader_BuildMaterial()`, `Godot_Shader_GenerateCode()`, `Godot_Shader_ClearCache()`.
- [x] **Task 66.10:** Created `godot_shader_material.cpp` — multi-stage `.gdshader` code generator with stage compositing via per-stage blend functions. Common patterns optimised: additive (GL_ONE GL_ONE → `+=`), modulate (GL_DST_COLOR GL_ZERO → `*=`), alpha blend (GL_SRC_ALPHA GL_ONE_MINUS_SRC_ALPHA → `mix()`). Generic fallback for arbitrary blend factor combinations.

### Key technical details (Phase 66):
- Type names prefixed with `Mohaa` to avoid collision with Godot's `RenderingDevice::ShaderStage` enum
- Up to `MOHAA_SHADER_STAGE_MAX` (8) stages per shader, `MOHAA_SHADER_STAGE_MAX_TCMODS` (4) tcMod directives per stage, `MOHAA_SHADER_STAGE_MAX_ANIM_FRAMES` (8) animMap frames per stage
- Shader cache (`s_shader_cache`) maps unique config keys to `Ref<Shader>` to avoid regenerating identical shaders
- Generated render_mode includes: `unshaded` (default unless `lightingDiffuse`), `blend_add`/`blend_mul`/`blend_mix`, `cull_disabled`/`cull_front`
- Lightmap stages detected by `isLightmap` flag; composited with `overbright_factor` uniform (default 2.0)
- Entity color passed via `entity_color` vec4 uniform for `rgbGen entity`/`alphaGen entity`

### Files created (Phase 66):
- `code/godot/godot_shader_material.h` — public API header
- `code/godot/godot_shader_material.cpp` — shader code generator and material builder

### Files modified (Phase 66):
- `code/godot/godot_shader_props.h` — added per-stage structs, enums, stage array in `GodotShaderProps`
- `code/godot/godot_shader_props.cpp` — extended parser for multi-stage data

## Phase 67: Environment Mapping (`tcGen environment`) ✅
- [x] **Task 67.1:** Added `STAGE_TCGEN_ENVIRONMENT` enum value to `MohaaStageTcGen`.
- [x] **Task 67.2:** Parser sets `stg->tcGen = STAGE_TCGEN_ENVIRONMENT` for `tcGen environment` / `tcGen environmentmodel` directives.
- [x] **Task 67.3:** Shader code generator emits view-dependent UV computation: `reflect(normalize(VERTEX), NORMAL).xy * 0.5 + 0.5` in the fragment shader when a stage uses environment tcGen.

### Key technical details (Phase 67):
- Environment UVs computed per-fragment from view direction and surface normal
- Uses Godot's built-in `VERTEX` (view-space position) and `NORMAL` (view-space normal) in the spatial shader
- Compatible with multi-stage compositing — environment mapping can be one stage among many

## Phase 68: Animated Texture Sequences (`animMap`) ✅
- [x] **Task 68.1:** Per-stage `animMap` parsing stores `animMapFreq` and up to 8 frame texture paths in `MohaaShaderStage.animMapFrames[]`.
- [x] **Task 68.2:** Shader code generator emits per-stage frame uniforms (`stage<N>_frame<F>`) and time-based frame selection using `mod(TIME, period)`.
- [x] **Task 68.3:** Frame selection uses integer index from `int(anim_time * freq)` with if/else chain for each frame.

### Key technical details (Phase 68):
- Uses Godot's built-in `TIME` uniform — no per-frame uniform update needed from MoHAARunner
- Period = `frame_count / freq`; wraps via `mod()` for seamless looping
- Caller sets `stage<N>_frame<F>` sampler2D uniforms with loaded textures

## Phase 71: `rgbGen wave` / `alphaGen wave` ✅
- [x] **Task 71.1:** Implemented 5 wave functions in generated GLSL: `wave_sin`, `wave_triangle`, `wave_square`, `wave_sawtooth`, `wave_inversesawtooth`.
- [x] **Task 71.2:** `rgbGen wave <func> <base> <amp> <phase> <freq>` — modulates stage RGB by clamped wave value.
- [x] **Task 71.3:** `alphaGen wave <func> <base> <amp> <phase> <freq>` — modulates stage alpha by clamped wave value.
- [x] **Task 71.4:** Also handles: `rgbGen identity`, `rgbGen identityLighting`, `rgbGen vertex`, `rgbGen entity`, `rgbGen oneMinusEntity`, `rgbGen lightingDiffuse`, `rgbGen const`.
- [x] **Task 71.5:** Also handles: `alphaGen identity`, `alphaGen vertex`, `alphaGen wave`, `alphaGen entity`, `alphaGen oneMinusEntity`, `alphaGen portal <dist>`, `alphaGen const`.

### Key technical details (Phase 71):
- Wave functions only emitted in GLSL when at least one stage uses them (avoids unused function warnings)
- `rgbGen vertex` / `alphaGen vertex` multiply by Godot's `COLOR` built-in (vertex color)
- `alphaGen portal <dist>` uses `length(VERTEX)` as a distance proxy for portal fade
- Wave values clamped to [0, 1] for RGB/alpha safety

## Phase 72: `tcGen lightmap` / `tcGen vector` ✅
- [x] **Task 72.1:** `tcGen lightmap` — uses `UV2` channel (Godot's second UV set, used for lightmap coordinates from BSP).
- [x] **Task 72.2:** `tcGen vector ( sx sy sz ) ( tx ty tz )` — projects UVs from view-space vertex position using two direction vectors via `dot(VERTEX, vec3(...))`.
- [x] **Task 72.3:** Parser reads vector components from parenthesised format: `( sx sy sz ) ( tx ty tz )`.

### Key technical details (Phase 72):
- Lightmap stages automatically set `isLightmap = true` when `$lightmap` map or `tcGen lightmap` is encountered
- Vector projection uses `VERTEX` in view space; world-space projection would require a `MODEL_MATRIX` transform (documented as future enhancement)

### MoHAARunner Integration Required (Phases 66–72):

**Where to call `Godot_Shader_BuildMaterial()`:**
1. `check_world_load()` — BSP surface materials: replace `StandardMaterial3D` creation with `Godot_Shader_BuildMaterial()` for shaders with `stage_count > 1`; set `stage<N>_tex` uniforms with loaded textures
2. `update_entities()` — entity materials: use `Godot_Shader_BuildMaterial()` for multi-stage entity shaders
3. `update_polys()` — poly/particle materials: use for effect shaders with blending
4. `get_shader_texture()` — can remain as-is; textures loaded here are set as uniforms on the ShaderMaterial

**Animated shaders (TIME uniform):**
- The generated `.gdshader` uses Godot's built-in `TIME` uniform for all time-based effects (animMap, rgbGen wave, alphaGen wave, tcMod scroll/rotate/turb/stretch)
- The existing `update_shader_animations()` in MoHAARunner is NOT needed for ShaderMaterial paths (only for StandardMaterial3D fallback)
- No per-frame uniform update required from C++ code

**Material cache invalidation:**
- Call `Godot_Shader_ClearCache()` on map change (in `check_world_load()` or `unload_world()`)

**Uniform naming convention:**
- `stage0_tex`, `stage1_tex`, ... — primary sampler2D per stage
- `stage0_frame0`, `stage0_frame1`, ... — animMap frame samplers
- `overbright_factor` — float, default 2.0 (lightmap overbright)
- `entity_color` — vec4, default (1,1,1,1) (for rgbGen/alphaGen entity)
## Phase 65: Fullbright / Vertex-Lit Surface Fallback ✅
- [x] **Task 65.1:** Added `SURF_NOLIGHTMAP` (0x100) constant to `godot_bsp_mesh.cpp`.
- [x] **Task 65.2:** Added `nolightmap` and `surface_flags` fields to `ShaderBatch` struct.
- [x] **Task 65.3:** `process_surface()` now detects `SURF_NOLIGHTMAP` flag and sets `batch.nolightmap = true`.
- [x] **Task 65.4:** `batches_to_array_mesh()` skips lightmap detail texture for nolightmap surfaces and applies vertex colour fallback.
- [x] **Task 65.5:** Added `Godot_BSP_SurfaceHasLightmap()` extern "C" accessor in `godot_bsp_mesh.cpp/.h`.

### Key technical details (Phase 65):
- Surfaces with `SURF_NOLIGHTMAP` skip the detail-texture lightmap multiply, rendering fullbright.
- Vertex colours are used directly via `FLAG_ALBEDO_FROM_VERTEX_COLOR` when no lightmap is present.
- The `Godot_BSP_SurfaceHasLightmap()` function checks the BSP shader's surface flags via the retained mark data.

### Files modified (Phase 65):
- `code/godot/godot_bsp_mesh.cpp` — nolightmap detection in process_surface(), lightmap skip in batches_to_array_mesh()
- `code/godot/godot_bsp_mesh.h` — added Godot_BSP_SurfaceHasLightmap() declaration

## Phase 69: deformVertexes — Autosprite ✅
- [x] **Task 69.1:** Created `godot_vertex_deform.h` with deform type constants and API declarations.
- [x] **Task 69.2:** Created `godot_vertex_deform.cpp` with GLSL code generators.
- [x] **Task 69.3:** Implemented `generate_autosprite_vertex()` — sets MODELVIEW_MATRIX to billboard towards camera.
- [x] **Task 69.4:** Implemented `generate_autosprite2_vertex()` — Y-axis aligned billboard using camera-to-object direction.

### Key technical details (Phase 69):
- Autosprite: Rebuilds MODELVIEW_MATRIX from INV_VIEW_MATRIX axes + model origin for full billboard.
- Autosprite2: Keeps Y-up axis, derives X/Z from camera direction for axis-aligned billboard.
- GLSL code returned as String for injection into Godot ShaderMaterial vertex() functions.

### Files created (Phase 69):
- `code/godot/godot_vertex_deform.h` — deform type enums, API
- `code/godot/godot_vertex_deform.cpp` — GLSL generators

## Phase 70: deformVertexes — Wave / Bulge / Move ✅
- [x] **Task 70.1:** Implemented `generate_wave_vertex()` — sinusoidal displacement along vertex normal.
- [x] **Task 70.2:** Implemented `generate_bulge_vertex()` — pulsating outward displacement using S texture coordinate.
- [x] **Task 70.3:** Implemented `generate_move_vertex()` — vertex translation along normal with wave function.
- [x] **Task 70.4:** Implemented `Godot_Deform_GenerateFullShader()` for complete shader code generation.

### Key technical details (Phase 70):
- Wave: `offset = (V.x+V.y+V.z)/div`, `wave = base + amp * sin(TIME*freq + phase + offset)`
- Bulge: `bulge = height * sin((TIME*speed + UV.x*width) * TAU)`
- Move: Simplified to normal-axis translation with wave modulation
- All deform parameters match GodotShaderProps struct fields (Phase 63 in shader_props.h)

### Files modified (Phase 70):
- `code/godot/godot_vertex_deform.cpp` — wave, bulge, move GLSL generators

## Phase 73: Portal Surfaces ✅
- [x] **Task 73.1:** Portal surfaces (surfaceparm portal) are now detected in the BSP surface processing loop.
- [x] **Task 73.2:** Portal surfaces are skipped from world geometry mesh — they will be rendered separately by Agent 10.

### MoHAARunner Integration Required (Phase 73):
- Portal surfaces need special rendering treatment (flat reflective surface or SubViewport).
- Agent 10 should check `GodotShaderProps::is_portal` when processing entity/surface materials.

### Files modified (Phase 73):
- `code/godot/godot_bsp_mesh.cpp` — portal surface skip in world surface loop

## Phase 74: Flare Rendering ✅
- [x] **Task 74.1:** Added `BSPFlare` struct to `godot_bsp_mesh.h` (origin, colour, shader).
- [x] **Task 74.2:** Flare surfaces (`MST_FLARE`) are now collected during BSP surface processing.
- [x] **Task 74.3:** Flare positions converted to Godot coordinates with vertex colour as flare tint.
- [x] **Task 74.4:** Added `Godot_BSP_GetFlareCount()` and `Godot_BSP_GetFlare()` accessor API.

### MoHAARunner Integration Required (Phase 74):
- `Godot_BSP_GetFlareCount()` / `Godot_BSP_GetFlare()` provide flare positions after map load.
- Agent 10 should create billboard MeshInstance3D nodes with additive blending at each flare position.
- Optional: distance fade and BSP raycast occlusion check.

### Files modified (Phase 74):
- `code/godot/godot_bsp_mesh.h` — BSPFlare struct, accessor declarations
- `code/godot/godot_bsp_mesh.cpp` — flare collection in surface loop, accessor implementations

## Phase 75: Volumetric Smoke & Dust ✅
- [x] **Task 75.1:** Documented that cgame's cg_volumetricsmoke.cpp submits smoke polys via the renderer.
- [x] **Task 75.2:** These polys arrive in `gr_polys[]` buffer (already captured by godot_renderer.c).
- [x] **Task 75.3:** Correct billboarding and alpha fade handled by existing poly rendering in MoHAARunner.

### Key technical details (Phase 75):
- Smoke polygons are submitted as `RE_AddPolyToScene` calls from cgame.
- The `gr_polys[]` capture buffer in `godot_renderer.c` already handles them.
- MoHAARunner's `update_polys()` renders them as triangle fans with correct materials.
- No additional code changes needed — the existing pipeline handles smoke polys.

## Phase 76: Rain & Snow Weather Effects ✅
- [x] **Task 76.1:** Created `godot_weather.h` with weather API: Init, Update, Shutdown, GetState, GetDensity.
- [x] **Task 76.2:** Created `godot_weather.cpp` with GPUParticles3D emitters for rain and snow.
- [x] **Task 76.3:** Rain: 2000 particles, fast downward velocity, thin quad streaks, 1s lifetime.
- [x] **Task 76.4:** Snow: 1500 particles, slow drifting, small white quads, 3s lifetime.
- [x] **Task 76.5:** Created `godot_weather_accessors.c` with state/density query functions.
- [x] **Task 76.6:** Weather volume follows camera position each frame.

### MoHAARunner Integration Required (Phase 76):
1. Call `Godot_Weather_Init(scene_root)` in `check_world_load()` after BSP map load.
2. Call `Godot_Weather_Update(camera_position, delta)` in `_process()` each frame.
3. Call `Godot_Weather_Shutdown()` in BSP unload / scene teardown.
4. Weather state is currently WEATHER_NONE by default; Agent 10 should set state when engine communicates weather commands via configstrings.

### Files created (Phase 76):
- `code/godot/godot_weather.h` — weather API
- `code/godot/godot_weather.cpp` — GPUParticles3D rain/snow manager
- `code/godot/godot_weather_accessors.c` — C accessor for weather state

## Phase 77: Water / Liquid Surfaces ✅
- [x] **Task 77.1:** Water surfaces use `deformVertexes wave` which is implemented in Phase 70.
- [x] **Task 77.2:** Transparency from `surfaceparm trans` + blend mode is handled by existing shader prop system.
- [x] **Task 77.3:** Water colour tinting available via `rgbGen` in shader props (Phase 64).

### Key technical details (Phase 77):
- Water surfaces are regular BSP surfaces with wave deform and transparency.
- Phase 70's `generate_wave_vertex()` provides the GLSL code for water surface animation.
- Agent 2's shader props provide transparency/blend mode for correct alpha rendering.
- Sort order handled by `sort_key` in shader props (Phase 67).

## Phase 78: Fog Volumes (Per-Surface) ✅
- [x] **Task 78.1:** Added `BSPFogVolume` struct to `godot_bsp_mesh.h` (shader, brush, colour, depth).
- [x] **Task 78.2:** Added `bsp_fog_t` on-disc struct (72 bytes, matches dfog_t from qfiles.h).
- [x] **Task 78.3:** Fog lump parsing in `Godot_BSP_LoadWorld()` for BSP versions ≤ 18.
- [x] **Task 78.4:** Fog colour and distance read from shader props (`has_fog`, `fog_color`, `fog_distance`).
- [x] **Task 78.5:** Added `Godot_BSP_GetFogVolumeCount()` and `Godot_BSP_GetFogVolume()` accessor API.

### MoHAARunner Integration Required (Phase 78):
- Fog volumes are distinct from global fog (which is in `update_camera()` via Environment).
- Each fog volume defines a brush region with per-fog colour and density.
- Agent 9 (Rendering Polish) or Agent 10 should apply fog volume data to affected BSP surfaces during material creation, or use proximity-based fog blending.
- The `fogNum` field in `bsp_surface_t` maps a surface to its fog volume index (-1 = none).

### Files modified (Phase 78):
- `code/godot/godot_bsp_mesh.h` — BSPFogVolume struct, accessor declarations
- `code/godot/godot_bsp_mesh.cpp` — fog lump parsing, accessor implementations, fog volume cache cleanup in Unload()

## Phase 59: Entity LOD System ✅
Distance-based LOD selection using skelHeaderGame_t::lodIndex[] and progressive mesh vertex collapse.

- [x] **Task 59.1:** Added LOD data accessor functions to `godot_skel_model_accessors.cpp`: `Godot_Skel_GetLodIndexCount()`, `Godot_Skel_GetLodIndex()`, `Godot_Skel_GetCollapseData()`.
- [x] **Task 59.2:** Implemented `Godot_Skel_SelectLodLevel()` — distance-based LOD level selection using 10 distance thresholds (256–8192 inches).
- [x] **Task 59.3:** Implemented `Godot_Skel_GetLodVertexLimit()` — returns the maximum vertex count for a given LOD level from lodIndex[].
- [x] **Task 59.4:** Implemented `Godot_Skel_BuildLodMesh()` — progressive mesh vertex collapse using pCollapse/pCollapseIndex to reduce triangle count for distant entities.

### Key technical details (Phase 59):
- `skelHeaderGame_t.lodIndex[10]` maps LOD levels to maximum vertex counts
- `skelSurfaceGame_t.pCollapse[]` defines collapse chain (vertex v → vertex collapse[v])
- `skelSurfaceGame_t.pCollapseIndex[]` provides remapped indices for collapsed mesh
- Collapse walks the chain until vertex index < maxVerts; degenerate triangles are discarded
- Falls back to full detail (LOD 0) if collapse data is missing

### MoHAARunner Integration Required (Phase 59):
- In `update_entities()`: compute distance from camera to entity, call `Godot_Skel_SelectLodLevel()` to get LOD level
- Pass LOD level to mesh building pipeline to reduce vertex/triangle count for distant entities
- Include LOD level in EntityMeshCacheKey for proper cache keying

### Files modified (Phase 59):
- `code/godot/godot_skel_model_accessors.cpp` — LOD data accessor functions
- `code/godot/godot_skel_model.cpp` — LOD selection + collapse implementation
- `code/godot/godot_skel_model.h` — LOD function declarations

## Phase 60: Per-Entity Mesh Caching ✅
Mesh cache to eliminate redundant ArrayMesh rebuilds for animated entities.

- [x] **Task 60.1:** Created `godot_mesh_cache.h` with `EntityMeshCacheKey` struct (hModel, 4 frame info slots, LOD level) and `EntityMeshCacheHash` for std::unordered_map.
- [x] **Task 60.2:** Implemented `Godot_MeshCache` singleton with `lookup()`, `store()`, `evict_stale()`, `clear()` methods.
- [x] **Task 60.3:** Time-based eviction: entries unused for 120 frames (default) are removed during `evict_stale()`.
- [x] **Task 60.4:** FNV-1a hash over raw bytes of the cache key for efficient lookups.

### Key technical details (Phase 60):
- Cache key captures: hModel + 4 animation frame slots (index, weight, time) + LOD level
- `EntityMeshCacheEntry` stores Ref<ArrayMesh> + per-surface shader names + last-used frame
- Eviction runs once per frame; configurable stale threshold (default 120 frames ≈ 2s at 60fps)
- Stats: hit/miss counters for performance audit

### MoHAARunner Integration Required (Phase 60):
1. In `update_entities()`: build `EntityMeshCacheKey` from entity animation state
2. Call `Godot_MeshCache::get().lookup()` — returns cached mesh or nullptr
3. If nullptr, build mesh normally, then call `Godot_MeshCache::get().store()`
4. In `_process()`: call `Godot_MeshCache::get().evict_stale(frame_number)` once per frame

### Files created (Phase 60):
- `code/godot/godot_mesh_cache.h` — cache key structs, Godot_MeshCache class
- `code/godot/godot_mesh_cache.cpp` — cache implementation

## Phase 61: Material Cache System ✅
Material caching to share materials across entities with identical appearance.

- [x] **Task 61.1:** Created `MaterialCacheKey` struct keyed on (shader_handle, rgba[4], blend_mode).
- [x] **Task 61.2:** Implemented `Godot_MaterialCache` singleton with `lookup()`, `store()`, `evict_stale()`, `clear()`.
- [x] **Task 61.3:** Cache stores `Ref<Material>` base class — works with both StandardMaterial3D and ShaderMaterial.
- [x] **Task 61.4:** LRU-style eviction with configurable stale frame threshold (default 300 frames ≈ 5s at 60fps).

### MoHAARunner Integration Required (Phase 61):
1. In `update_entities()`: build `MaterialCacheKey` from (shader_handle, shaderRGBA, blend_mode)
2. Call `Godot_MaterialCache::get().lookup()` — returns cached material or empty Ref
3. If empty, create material normally, then call `Godot_MaterialCache::get().store()`
4. In `_process()`: call `Godot_MaterialCache::get().evict_stale(frame_number)` once per frame

### Files created (Phase 61):
- `code/godot/godot_mesh_cache.h` — MaterialCacheKey, Godot_MaterialCache class (same header as Phase 60)
- `code/godot/godot_mesh_cache.cpp` — material cache implementation

## Phase 62: Weapon Rendering via SubViewport ✅
SubViewport weapon rendering for first-person weapons (RF_FIRST_PERSON + RF_DEPTHHACK).

- [x] **Task 62.1:** Created `Godot_WeaponViewport` singleton managing SubViewport + Camera3D + Node3D + CanvasLayer + TextureRect.
- [x] **Task 62.2:** `create()` builds the full node hierarchy: weapon_viewport → weapon_camera + weapon_root, weapon_overlay → weapon_rect.
- [x] **Task 62.3:** `sync_camera()` copies main camera transform/FOV/near/far to weapon camera each frame.
- [x] **Task 62.4:** `resize()` handles viewport resize. `destroy()` cleanly frees all nodes.
- [x] **Task 62.5:** Transparent background + CanvasLayer compositing for weapon over main view.

### Scene tree layout (Phase 62):
```
MoHAARunner (Node)
  game_world (Node3D)
    camera (Camera3D)           ← main camera
    entity_root (Node3D)        ← world entities
  weapon_viewport (SubViewport) ← weapon rendering
    weapon_camera (Camera3D)    ← copies main camera transform
    weapon_root (Node3D)        ← RF_FIRST_PERSON entities go here
  weapon_overlay (CanvasLayer)  ← composites weapon_viewport
    weapon_rect (TextureRect)   ← ViewportTexture from weapon_viewport
```

### MoHAARunner Integration Required (Phase 62):
1. In `setup_3d_scene()`: call `Godot_WeaponViewport::get().create(this, camera, width, height)`
2. In `update_entities()`: for entities with RF_FIRST_PERSON (0x04) or RF_DEPTHHACK (0x08), parent their MeshInstance3D to `Godot_WeaponViewport::get().get_weapon_root()` instead of entity_root
3. In `_process()`: call `Godot_WeaponViewport::get().sync_camera()` each frame
4. On shutdown: call `Godot_WeaponViewport::get().destroy()`

### Files created (Phase 62):
- `code/godot/godot_weapon_viewport.h` — Godot_WeaponViewport class
- `code/godot/godot_weapon_viewport.cpp` — SubViewport setup + camera sync

## Phase 63: Lightgrid Entity Lighting ✅
BSP lightgrid sampling for per-entity light modulation.

- [x] **Task 63.1:** Implemented `Godot_EntityLight_Sample()` — samples lightgrid at entity position via `Godot_BSP_LightForPoint()`.
- [x] **Task 63.2:** Combines ambient + directed light into a single colour: `ambient + directed * 0.5` for material modulation.
- [x] **Task 63.3:** Falls back to (0.5, 0.5, 0.5) mid-grey if lightgrid data is unavailable.
- [x] **Task 63.4:** All positions in id Tech 3 coordinates — caller converts from Godot space if needed.

### MoHAARunner Integration Required (Phase 63):
1. In `update_entities()`: call `Godot_EntityLight_Sample()` with entity origin (id-space)
2. Apply returned RGB as material modulation: `material.albedo_color *= Color(r, g, b)`
3. Handle RF_LIGHTING_ORIGIN (0x0080): sample at lightingOrigin instead of render origin

### Files created (Phase 63):
- `code/godot/godot_entity_lighting.h` — lighting API declarations
- `code/godot/godot_entity_lighting.cpp` — lightgrid sampling implementation

## Phase 64: Dynamic Lights on Entities ✅
Dynamic light accumulation from muzzle flashes, explosions, etc.

- [x] **Task 64.1:** Implemented `Godot_EntityLight_Dlights()` — reads gr_dlights[] via accessor, sorts by distance, accumulates contribution.
- [x] **Task 64.2:** Linear attenuation model: `1 - (distance / intensity)`, clamped to 0.
- [x] **Task 64.3:** Configurable max lights per entity (default 4 for performance).
- [x] **Task 64.4:** Insertion sort for ≤64 candidates — efficient for small N.
- [x] **Task 64.5:** `Godot_EntityLight_Combined()` convenience function: lightgrid + dlights, clamped to [0,1].

### MoHAARunner Integration Required (Phase 64):
1. In `update_entities()`: call `Godot_EntityLight_Combined()` or separate Sample + Dlights
2. Apply as material modulation: `material.albedo_color *= Color(r, g, b)`

### Files created (Phase 64):
- `code/godot/godot_entity_lighting.h` — dlight API declarations
- `code/godot/godot_entity_lighting.cpp` — dlight accumulation implementation

## Phase 85: Render Performance Audit ✅
Performance statistics infrastructure for entity rendering profiling.

- [x] **Task 85.1:** Created `Godot_RenderStats` struct with per-frame counters: frame time, entities rendered/skeletal/static, cache hits/misses, draw calls.
- [x] **Task 85.2:** `Godot_RenderStats_BeginFrame()` / `Godot_RenderStats_EndFrame()` bracket frame timing via `Time::get_ticks_usec()`.
- [x] **Task 85.3:** `Godot_RenderStats_Log()` prints a single-line summary with all counters + cache sizes.
- [x] **Task 85.4:** Per-cache statistics: `stat_hits()`, `stat_misses()`, `stat_size()`, `stat_reset()` on both mesh and material caches.

### MoHAARunner Integration Required (Phase 85):
1. In `_process()`: call `Godot_RenderStats_BeginFrame()` before `Com_Frame()`
2. In `_process()`: call `Godot_RenderStats_EndFrame()` after all rendering
3. Optionally call `Godot_RenderStats_Log()` every N frames or on cvar toggle
4. Increment `g_render_stats.entities_rendered` / `entities_skeletal` / `entities_static` / `draw_calls` in `update_entities()`

### Files created (Phase 85):
- `code/godot/godot_mesh_cache.h` — Godot_RenderStats struct + C API
- `code/godot/godot_mesh_cache.cpp` — stats implementation


## Phase 46: Menu Background Rendering ✅
- [x] **Task 46.1:** `GR_DrawBackground` in `godot_renderer.c` already captures raw background image data into `gr_bgData[]` (RGB, up to 1024×1024×4 bytes).
- [x] **Task 46.2:** Created `godot_ui_system.cpp/.h` with `Godot_UI_HasBackground()` and `Godot_UI_GetBackgroundData()` — delegates to `Godot_Renderer_GetBackground()`.
- [x] **Task 46.3:** Background visibility toggled automatically: `gr_bgActive` set by `GR_DrawBackground`, cleared by `GR_ClearScene` and `GR_Shutdown`.

### Key technical details (Phase 46):
- Background image data flows: engine `re.DrawBackground()` → `GR_DrawBackground()` → `gr_bgData[]` → `Godot_UI_GetBackgroundData()` → MoHAARunner (via integration layer)
- MoHAARunner integration point: call `Godot_UI_HasBackground()` / `Godot_UI_GetBackgroundData()` to render a fullscreen `TextureRect` on a dedicated `CanvasLayer`

### Files created/modified (Phase 46):
- `code/godot/godot_ui_system.h` — UI system API header
- `code/godot/godot_ui_system.cpp` — UI rendering manager

## Phase 47: Main Menu Display ✅
- [x] **Task 47.1:** Engine's UI system (`code/uilib/`) calls `GR_DrawStretchPic`, `GR_DrawBox`, `GR_DrawString` for menu rendering — these already flow into `gr_2d_cmds[]` buffer.
- [x] **Task 47.2:** Created UI state machine in `godot_ui_system.cpp` that tracks `GODOT_UI_MAIN_MENU` state via `KEYCATCH_UI` flag from `Godot_Client_GetKeyCatchers()`.
- [x] **Task 47.3:** `.urc` file loading is handled entirely by engine VFS — no Godot-side changes needed.
- [x] **Task 47.4:** Menu transitions (fade in/out) rendered through existing 2D command buffer with alpha blending.

### Key technical details (Phase 47):
- UI state enum: `GODOT_UI_NONE`, `GODOT_UI_MAIN_MENU`, `GODOT_UI_CONSOLE`, `GODOT_UI_LOADING`, `GODOT_UI_SCOREBOARD`, `GODOT_UI_MESSAGE`
- `Godot_UI_Update()` polls `Godot_Client_GetKeyCatchers()` each frame and returns the current state
- MoHAARunner integration point: call `Godot_UI_Update()` once per frame in `_process()` to track UI state changes

## Phase 48: Menu Input Routing ✅
- [x] **Task 48.1:** Created `godot_ui_input.cpp/.h` with `Godot_UI_HandleKeyEvent()`, `Godot_UI_HandleCharEvent()`, `Godot_UI_HandleMouseButton()`, `Godot_UI_HandleMouseMotion()`.
- [x] **Task 48.2:** Input routing: when `Godot_UI_IsActive()` returns true, all input forwarded to engine via existing `Godot_Inject*()` functions — engine's `cl_keys.c` dispatches to `UI_KeyEvent()` / `Console_Key()` / `Message_Key()` based on `keyCatchers`.
- [x] **Task 48.3:** Added `Godot_InjectMousePosition()` to `godot_input_bridge.c` for absolute mouse position injection in UI mode (computes delta from previous position).
- [x] **Task 48.4:** Added `Godot_ResetMousePosition()` to reset tracking state when switching between UI and game modes.
- [x] **Task 48.5:** Cursor visibility: `Godot_UI_ShouldShowCursor()` returns 1 when any of `KEYCATCH_UI | KEYCATCH_CONSOLE | KEYCATCH_MESSAGE` is set.
- [x] **Task 48.6:** Cursor position: `Godot_UI_GetCursorPos()` reads `cl.mousex`/`cl.mousey` via `Godot_Client_GetMousePos()`.

### Key technical details (Phase 48):
- Input flow (UI active): Godot `_unhandled_input()` → `Godot_UI_Handle*()` → `Godot_Inject*()` → `Com_QueueEvent()` → engine key dispatch → `UI_KeyEvent()` / `Console_Key()`
- Input flow (game active): Godot `_unhandled_input()` → `Godot_Inject*()` directly → `Com_QueueEvent()` → game input
- `Godot_UI_ShouldCaptureInput()` is a convenience alias for `Godot_UI_IsActive()`
- MoHAARunner integration points:
  1. In `_unhandled_input()`: check `Godot_UI_ShouldCaptureInput()` — if true, use `Godot_UI_Handle*()` instead of direct `Godot_Inject*()`
  2. In `_process()`: check `Godot_UI_ShouldShowCursor()` — if true, set `MOUSE_MODE_VISIBLE`; if false, set `MOUSE_MODE_CAPTURED`
  3. On mode switch: call `Godot_ResetMousePosition()` to avoid cursor jumps

### Files created/modified (Phase 48):
- `code/godot/godot_ui_input.h` — UI input routing API
- `code/godot/godot_ui_input.cpp` — UI input routing implementation
- `code/godot/godot_input_bridge.c` — added `Godot_InjectMousePosition()` and `Godot_ResetMousePosition()`

## Phase 49: Console Overlay ✅
- [x] **Task 49.1:** MOHAA drop-down console activated by `~` / backtick key — handled by engine's `KEYCATCH_CONSOLE` flag.
- [x] **Task 49.2:** Created `godot_console_accessors.cpp` with `Godot_Console_IsOpen()` (wraps `UI_ConsoleIsOpen()`), `Godot_Console_GetKeyCatchers()`, `Godot_Console_IsConsoleKeyActive()`.
- [x] **Task 49.3:** Console state tracked in `godot_ui_system.cpp` — `GODOT_UI_CONSOLE` state set when `KEYCATCH_CONSOLE` detected.
- [x] **Task 49.4:** Console rendering: engine calls `GR_DrawStretchPic` (background) + `GR_DrawSmallStringExt` (text) → 2D command buffer → existing `update_2d_overlay()` in MoHAARunner.
- [x] **Task 49.5:** Console scrolling (Page Up/Down) and command history (Up/Down arrows) handled by engine's console code — input routed via `Godot_UI_HandleKeyEvent()`.
- [x] **Task 49.6:** Console text input via `SE_CHAR` events from `Godot_UI_HandleCharEvent()`.

### Key technical details (Phase 49):
- Console rendering is entirely engine-driven via the 2D command buffer — no separate Godot console rendering needed
- `Godot_Console_IsOpen()` calls `UI_ConsoleIsOpen()` from `cl_ui.h` — file is `.cpp` because `cl_ui.h` includes C++ headers
- Console background renders as semi-transparent via alpha in the 2D command's colour values

### Files created (Phase 49):
- `code/godot/godot_console_accessors.cpp` — console state accessors

## Phase 50: Server Browser UI ✅
- [x] **Task 50.1:** GameSpy master server query handled by engine code (`code/gamespy/`) — no Godot-side changes needed.
- [x] **Task 50.2:** Server list renders as UI text/list widgets via 2D command buffer — flows through existing `update_2d_overlay()`.
- [x] **Task 50.3:** "Connect" action sends `connect <ip>` command through engine's UI command system.

### Key technical details (Phase 50):
- Server browser is entirely engine-driven via uilib `.urc` files
- All rendering goes through the existing 2D command buffer pipeline
- No new Godot-side code needed — the UI state machine in `godot_ui_system.cpp` correctly detects `KEYCATCH_UI` when the server browser is open

## Phase 51: Options Menu ✅
- [x] **Task 51.1:** Video, audio, controls, game options submenus — all handled by engine's uilib.
- [x] **Task 51.2:** Cvar binding to UI sliders/checkboxes handled by engine uilib internally.
- [x] **Task 51.3:** Key binding UI captures next keypress via engine's `KEYCATCH_UI` input routing.
- [x] **Task 51.4:** Apply/Cancel/Default button handling — engine uilib manages cvar writes.
- [x] **Task 51.5:** UI elements (sliders, checkboxes, text fields) render through 2D command buffer.

### Key technical details (Phase 51):
- Options menus are `.urc`-driven — engine handles all widget state and cvar binding
- Input routing through `Godot_UI_HandleKeyEvent()` / `Godot_UI_HandleMouseButton()` ensures correct interaction

## Phase 52: Loading Screen ✅
- [x] **Task 52.1:** Created `Godot_UI_OnMapLoad()` to notify the UI system that a map load has started — sets `GODOT_UI_LOADING` state.
- [x] **Task 52.2:** Loading state detected via `CA_LOADING` connection state from `Godot_Client_GetState()`.
- [x] **Task 52.3:** Loading screen rendering: engine calls `SCR_UpdateScreen()` repeatedly during load, producing 2D commands for background, text, and progress bar.
- [x] **Task 52.4:** `Godot_UI_IsLoading()` returns 1 during map load for MoHAARunner to manage loading screen display.

### Key technical details (Phase 52):
- Loading state priority: `GODOT_UI_LOADING` takes precedence over other UI states in `Godot_UI_Update()`
- Loading flag cleared automatically when connection state advances past `CA_LOADING`
- MoHAARunner integration point: call `Godot_UI_OnMapLoad()` from `check_world_load()` when a new map load is detected

## Phase 53: Scoreboard ✅
- [x] **Task 53.1:** In-game scoreboard (Tab key) — renders through 2D command buffer when active.
- [x] **Task 53.2:** Player names, kills, deaths, ping columns — all rendered by engine's cgame code via `GR_DrawStretchPic` / `GR_DrawBox`.
- [x] **Task 53.3:** Team colours applied via colour values in 2D commands.

### Key technical details (Phase 53):
- Scoreboard rendering is cgame-driven — flows through existing 2D command buffer
- No separate Godot scoreboard rendering needed — `update_2d_overlay()` handles it

## Phase 54: Team Selection / Weapon Selection ✅
- [x] **Task 54.1:** Team selection (Allies/Axis/Auto/Spectator) and weapon selection — engine UI dialogs rendered via uilib.
- [x] **Task 54.2:** Input routing via `Godot_UI_HandleKeyEvent()` / `Godot_UI_HandleMouseButton()` ensures correct keyboard/mouse navigation.

### Key technical details (Phase 54):
- Team/weapon selection dialogs are `.urc`-driven uilib menus
- Render through existing 2D command buffer pipeline

## Phase 55: Chat & Message Display ✅
- [x] **Task 55.1:** Chat messages (`messagemode` / `messagemode2`) — `KEYCATCH_MESSAGE` flag detected by `Godot_UI_IsMessageActive()`.
- [x] **Task 55.2:** Added `Godot_Client_IsMessageActive()` accessor to `godot_client_accessors.cpp`.
- [x] **Task 55.3:** Kill feed, centre-print messages — rendered through 2D command buffer by engine's cgame code.
- [x] **Task 55.4:** Chat text input routed via `Godot_UI_HandleCharEvent()` when `KEYCATCH_MESSAGE` is set.

### Key technical details (Phase 55):
- `GODOT_UI_MESSAGE` state in the UI state machine handles the chat input mode
- Centre-print messages (`CG_CenterPrint`) render as 2D text commands — flow through existing HUD overlay

### Files modified (Phase 55):
- `code/godot/godot_client_accessors.cpp` — added `Godot_Client_IsMessageActive()`

## Phases 57–58: UI Polish & Edge Cases ✅
- [x] **Task 57.1:** Modal dialog boxes (quit/disconnect confirmation) — rendered by engine uilib, displayed via 2D command buffer.
- [x] **Task 57.2:** Mouse cursor management: `Godot_UI_ShouldShowCursor()` returns cursor visibility state — MoHAARunner sets `MOUSE_MODE_VISIBLE` or `MOUSE_MODE_CAPTURED` accordingly.
- [x] **Task 57.3:** UI sound effects routed through engine's sound system → `godot_sound.c` capture → MoHAARunner audio pipeline.
- [x] **Task 57.4:** Graceful handling of missing UI assets: engine's `GR_RegisterShaderNoMip` returns valid handles for all assets; if texture loading fails in Godot, existing fallback to coloured rectangles applies.
- [x] **Task 58.1:** Added comprehensive client state accessors: `Godot_Client_IsUIActive()`, `Godot_Client_IsConsoleVisible()`, `Godot_Client_GetUIMousePos()`, `Godot_Client_IsAnyOverlayActive()`.
- [x] **Task 58.2:** `Godot_UI_ShouldCaptureInput()` convenience wrapper for input suppression in game mode.

### Key technical details (Phases 57–58):
- All modal dialogs are engine-driven uilib menus — render through 2D command buffer
- Cursor clamping to window bounds handled by Godot's `MOUSE_MODE_VISIBLE` — engine tracks cursor position internally
- UI sound effects: engine UI code calls `S_StartLocalSound()` → captured by `godot_sound.c` → played by MoHAARunner's audio pipeline

### Files modified (Phases 57–58):
- `code/godot/godot_client_accessors.cpp` — added 5 new accessor functions

## MoHAARunner Integration Required (Phases 46–58)

The following integration points document how `MoHAARunner.cpp` (owned by Agent 10) should wire in the UI system:

1. **In `_process()`:** Call `Godot_UI_Update()` to poll keyCatchers and update UI state. Check `Godot_UI_ShouldShowCursor()` to toggle mouse mode (`MOUSE_MODE_VISIBLE` vs `MOUSE_MODE_CAPTURED`).
2. **In `_unhandled_input()`:** Check `Godot_UI_ShouldCaptureInput()` — if true, forward events via `Godot_UI_HandleKeyEvent()` / `Godot_UI_HandleCharEvent()` / `Godot_UI_HandleMouseButton()` / `Godot_UI_HandleMouseMotion()` instead of direct `Godot_Inject*()` calls.
3. **In `update_2d_overlay()`:** Call `Godot_UI_HasBackground()` / `Godot_UI_GetBackgroundData()` before processing 2D commands — render background as fullscreen `TextureRect` on a dedicated `CanvasLayer`.
4. **In `check_world_load()`:** Call `Godot_UI_OnMapLoad()` when a new map load is detected — activates the `GODOT_UI_LOADING` state.
5. **Create a dedicated `CanvasLayer`** for UI background at higher z-index than HUD overlay.
6. **On mode transitions:** Call `Godot_ResetMousePosition()` when switching between UI and game input to avoid cursor jumps.

## Phase 263: Multiplayer Server Browser + Hosting ✅

Wired the engine's existing GameSpy master server query and server hosting into Godot-accessible functions via C accessors and GDScript-callable methods.

### Implementation details:
- **`godot_multiplayer_accessors.c/.h`** — C accessor layer exposing `Godot_MP_ConnectToServer()`, `Godot_MP_Disconnect()`, `Godot_MP_HostServer()`, `Godot_MP_RefreshServerList()`, `Godot_MP_RefreshLAN()`, `Godot_MP_GetServerCount()`
- **MoHAARunner methods** — `host_server(map, maxplayers, gametype)`, `refresh_server_list()`, `refresh_lan()`, `get_server_count()` bound to GDScript via ClassDB
- Existing `connect_to_server()` and `disconnect_from_server()` updated to route through accessor layer
- Uses `Cbuf_ExecuteText(EXEC_APPEND, ...)` to queue engine commands for connect, disconnect, host, and server list refresh
- Server count reads `cls.numlocalservers` from client state via accessor

### Files created (Phase 263):
- `code/godot/godot_multiplayer_accessors.c`
- `code/godot/godot_multiplayer_accessors.h`

### Files modified (Phase 263):
- `code/godot/MoHAARunner.h` — added `host_server`, `refresh_server_list`, `refresh_lan`, `get_server_count` declarations + `HAS_MULTIPLAYER_MODULE` guard
- `code/godot/MoHAARunner.cpp` — added new method implementations and bind_method entries

## Phase 221: VFX Manager Foundation ✅

- [x] **Task 221.1:** Created `code/godot/godot_vfx_accessors.c` — C accessor layer that filters `gr_entities[]` for `RT_SPRITE` entities via the existing `Godot_Renderer_GetEntity()` / `Godot_Renderer_GetEntitySprite()` accessors. Provides `Godot_VFX_GetSpriteCount()` (scans and caches sprite indices) and `Godot_VFX_GetSprite()` (returns origin, radius, resolved shader handle, rotation, RGBA).
- [x] **Task 221.2:** Created `code/godot/godot_vfx.h` — public API header declaring the C++ management functions (`Godot_VFX_Init`, `Godot_VFX_Update`, `Godot_VFX_Shutdown`, `Godot_VFX_Clear`) and C-linkage accessor prototypes.
- [x] **Task 221.3:** Created `code/godot/godot_vfx.cpp` — VFX manager with a pool of 512 `MeshInstance3D` billboard quads. Each frame: reads sprites via accessor → assigns to pool slots → applies `StandardMaterial3D` with `BILLBOARD_ENABLED`, `TRANSPARENCY_ALPHA`, unshaded, no depth write. Texture loaded from VFS (TGA/JPG/PNG) with shader remap support and caching. Unused slots hidden. `Godot_VFX_Clear()` hides all on map change.

### Key technical details (Phase 221):
- **Coordinate conversion:** id Tech 3 (X-fwd, Y-left, Z-up, inches) → Godot (X-right, Y-up, -Z-fwd, metres) via `MOHAA_UNIT_SCALE = 1/39.37`
- **Shared unit quad mesh:** All pool slots share a single 1×1 `ArrayMesh` quad; per-sprite size is applied via node scale (`radius × 2 × MOHAA_UNIT_SCALE`)
- **Texture cache:** `std::unordered_map<int, Ref<ImageTexture>>` keyed by shader handle, with VFS loading and magic-byte format detection (mirrors `MoHAARunner::get_shader_texture`)
- **Shader resolve:** `customShader` takes priority over `hModel`; shader remap applied via `Godot_Renderer_GetShaderRemap()`
- **No shadows:** Pool nodes use `SHADOW_CASTING_SETTING_OFF` — sprites are VFX, not geometry
- **Build integration:** Files are automatically included via recursive `add_sources("code/godot")` in SConstruct — no build system changes needed

### Files created (Phase 221):
- `code/godot/godot_vfx_accessors.c` — C accessor: sprite filter + data extraction
- `code/godot/godot_vfx.h` — public API declarations
- `code/godot/godot_vfx.cpp` — VFX manager: sprite pool, lifecycle, update

### MoHAARunner Integration Required (Phase 221):
1. **In `_ready()` or `check_world_load()`:** Call `Godot_VFX_Init(game_world)` to create the sprite pool.
2. **In `_process()`:** Call `Godot_VFX_Update(delta)` each frame to sync sprites.
3. **On map change:** Call `Godot_VFX_Clear()` to hide all pool slots.
4. **On shutdown:** Call `Godot_VFX_Shutdown()` to free pool nodes and caches.

## Phase 222: Impact Effects ✅
- [x] **Task 222.1:** Created `ImpactSurfaceType` enum covering all engine surface types (metal, wood, stone, dirt, grass, water, glass, flesh, sand, snow, mud, gravel, foliage, carpet, paper, grill).
- [x] **Task 222.2:** Defined `ImpactTemplate` struct with particle count, velocity, lifetime, colour, size, decal texture, decal size, decal lifetime, gravity scale, and spread angle.
- [x] **Task 222.3:** Populated per-surface templates with visually distinct parameters (e.g. metal = bright-orange sparks, wood = brown splinters, water = white droplets with no decal).
- [x] **Task 222.4:** Implemented `Godot_Impact_Init()` — pre-allocates a pool of 256 particle MeshInstance3D nodes and 64 decal MeshInstance3D nodes under an "ImpactEffects" Node3D.
- [x] **Task 222.5:** Implemented `Godot_Impact_Spawn()` — spawns N billboard-quad particles with randomised velocity in a cone around the hit normal, plus a surface-aligned decal quad.
- [x] **Task 222.6:** Implemented `Godot_Impact_Update(delta)` — animates particle positions (velocity + gravity), fades alpha over lifetime, fades decals in last 20% of life, recycles expired particles/decals.
- [x] **Task 222.7:** Implemented `Godot_Impact_Shutdown()` — cleans up all nodes and resets state.
- [x] **Task 222.8:** Implemented `Godot_Impact_SurfaceFromFlags()` — converts engine SURF_* bit-masks to ImpactSurfaceType enum values.

### Key technical details (Phase 222):
- Particle pool uses a ring buffer (s_next_particle wraps around MAX_IMPACT_PARTICLES=256) to avoid per-frame allocation.
- Decal pool similarly uses a ring buffer of MAX_DECALS=64 entries.
- Billboard materials are unshaded with alpha transparency; particle quads are billboarded via BaseMaterial3D::BILLBOARD_ENABLED.
- Decals are oriented to face along the surface normal with a 0.005m offset to avoid z-fighting.
- Gravity applied at 9.8 m/s² to all particles (scaled by per-template gravity_scale — not yet exposed but available for tuning).
- All positions/normals expected in Godot coordinates (Y-up, metres).
- Standalone Node3D parent ("ImpactEffects") — integrates with Agent 12's VFX foundation when available.

### Files created (Phase 222):
- `code/godot/godot_impact_effects.h` — Public API: enums, struct, Init/Spawn/Update/Shutdown/SurfaceFromFlags
- `code/godot/godot_impact_effects.cpp` — Full implementation with particle pool, decal pool, per-surface templates

### MoHAARunner integration point (Phase 222):
1. **In `_ready()` or `check_world_load()`:** Call `Godot_Impact_Init(scene_root)` after the 3D scene is set up.
2. **In `_process()`:** Call `Godot_Impact_Update(delta)` each frame.
3. **When processing impacts:** Call `Godot_Impact_SurfaceFromFlags(surfaceFlags)` to get the type, then `Godot_Impact_Spawn(type, position, normal)`.
4. **On map unload / shutdown:** Call `Godot_Impact_Shutdown()`.

## Phase 223: Explosion Effects ✅

Implemented explosion visual effects and a camera shake API in
`code/godot/godot_explosion_effects.{h,cpp}`.

### Camera Shake API
- `Godot_CameraShake_Trigger()` — queue a shake event with intensity, duration,
  falloff distance, and source position.
- `Godot_CameraShake_Update()` — apply accumulated shake to Camera3D each frame;
  offset is restored on the next call. Linear decay over duration, distance
  attenuation from source, random per-axis offset. Multiple shakes stack
  additively with total offset capped to ±0.15 m.
- `Godot_CameraShake_Clear()` — reset all pending shake events.

### Explosion System
- `Godot_Explosion_Init()` — create a pool of 16 explosion node hierarchies
  (fireball sphere, smoke torus, omni light, 10 debris box chunks each).
- `Godot_Explosion_Spawn()` — activate a pool slot at a world position with
  configurable radius and intensity. Automatically triggers camera shake.
- `Godot_Explosion_Update()` — per-frame update of three visual phases:
  - Phase 1 (0–0.2 s): Expanding bright-orange fireball sphere.
  - Phase 2 (0.1–0.8 s): Dark smoke ring expanding outward, alpha fading.
  - Phase 3 (0–0.5 s): 5–10 debris chunks with parabolic arcs and alpha fade.
  - Short-lived OmniLight3D (orange, 0.3 s, energy from intensity parameter).
- `Godot_Explosion_Clear()` — hide all active explosions without freeing pools.
- `Godot_Explosion_Shutdown()` — free pooled nodes and shared materials.

### Debris Chunks
- Small BoxMesh (0.05–0.15 m), dark grey-brown colour.
- Parabolic arc: random outward + upward initial velocity, gravity applied each frame.
- Alpha fades over 1–2 s randomised lifetime, then recycled.

### Integration
Call `Godot_Explosion_Init(parent)` after map load and
`Godot_Explosion_Update(delta)` + `Godot_CameraShake_Update(delta, camera)`
each frame.  `Godot_Explosion_Shutdown()` on map unload or module teardown.

## Phase 224: Muzzle Flash & Shell Casings ✅

- [x] **Task 224.1:** Muzzle flash system — pooled billboard quads (max 8) with additive blending and warm yellow-white colour, plus OmniLight3D (3 m range) that fades over 0.08 s.
- [x] **Task 224.2:** Shell casing system — pooled brass-coloured cylinder meshes (max 32) ejected with parabolic gravity (9.8 m/s²), random spin (720°/s), single ground bounce (0.3× velocity retention), and 2 s lifetime with scale fade-out.
- [x] **Task 224.3:** Shared StandardMaterial3D instances: flash material (unshaded, additive, billboard) and casing material (metallic=0.8, roughness=0.3, brass albedo).
- [x] **Task 224.4:** Three casing sizes: pistol (0.01×0.005 m), rifle (0.014×0.006 m), shotgun (0.018×0.01 m).
- [x] **Task 224.5:** Ring-buffer pool recycling for both systems — oldest slot reused when pool is full.

### Key technical details (Phase 224):
- `Godot_MuzzleFlash_Spawn()` places a billboard quad + OmniLight3D at the muzzle position; `Godot_MuzzleFlash_Update()` fades both via scale and energy over `MUZZLE_FLASH_LIFETIME` (0.08 s)
- `Godot_ShellCasing_Eject()` spawns a CylinderMesh sized per casing type; `Godot_ShellCasing_Update()` integrates velocity with gravity, applies spin rotation via `Basis::rotated()`, and handles a single bounce at Y=0
- All scene nodes pre-created during `Godot_WeaponEffects_Init()` and reused — no per-frame allocation
- Visual fade uses `set_scale()` since MeshInstance3D does not support `set_modulate()` (which is a CanvasItem method)

### Files created (Phase 224):
- `code/godot/godot_weapon_effects.h` — public API: spawn/update/clear/init/cleanup
- `code/godot/godot_weapon_effects.cpp` — muzzle flash pool (8 slots) + shell casing pool (32 slots) with physics simulation

## Phase 227: Screen Effects ✅
- [x] **Task 227.1:** Created `godot_screen_effects.h` — public API for damage flash, underwater tint, flash-bang, and pain flinch.
- [x] **Task 227.2:** Created `godot_screen_effects.cpp` — screen effect manager with CanvasLayer (z_index 100) and independent ColorRect overlays.
- [x] **Task 227.3:** Damage flash: red overlay (intensity × 0.4 alpha), additive stacking capped at 0.6, fades over 0.3s.
- [x] **Task 227.4:** Underwater tint: persistent blue-green overlay (Color 0.0, 0.1, 0.3) with sine-wave alpha oscillation (0.25–0.35 at 0.5 Hz).
- [x] **Task 227.5:** Flash-bang: white overlay fading over 2.0s, stacks with damage flash via separate ColorRect.
- [x] **Task 227.6:** Pain flinch: temporary camera pitch offset with smooth interpolation back to zero over 0.2s.

### Key technical details (Phase 227):
- All overlays use a single `CanvasLayer` at z_index 100 with three independent `ColorRect` children
- `MOUSE_FILTER_IGNORE` on all rects to avoid blocking input
- `PRESET_FULL_RECT` anchor for automatic viewport fill
- Pain flinch applies additive pitch rotation to camera (does not modify position)
- Engine integration points: `v_dmg_time`/`v_dmg_pitch`/`v_dmg_roll` in cgame, `CG_PointContents()` for underwater detection

### MoHAARunner Integration Required (Phase 227):
1. Call `Godot_ScreenFX_Init()` once after scene setup
2. Call `Godot_ScreenFX_Update(delta, camera)` each frame in `_process()`
3. Call `Godot_ScreenFX_DamageFlash(intensity)` when damage is detected (via cgame `v_dmg_time` changes)
4. Call `Godot_ScreenFX_UnderwaterTint(active)` based on camera position content test
5. Call `Godot_ScreenFX_FlashBang(intensity)` when flash-bang event is detected
6. Call `Godot_ScreenFX_PainFlinch(pitch_offset)` when `v_dmg_pitch` changes
7. Call `Godot_ScreenFX_Shutdown()` on map unload or exit

## Phase 56: Cinematic Playback Stub ✅
- [x] **Task 56.1:** Created `godot_cinematic.cpp` / `godot_cinematic.h` — standalone cinematic skip-hint overlay module.
- [x] **Task 56.2:** Detects cinematic playback via existing `Godot_Renderer_IsCinematicActive()` accessor (reads `gr_cin_active` flag set by `GR_DrawStretchRaw` in `godot_renderer.c`).
- [x] **Task 56.3:** Fullscreen black `ColorRect` on `CanvasLayer` z_index 200 (above HUD and cinematic frame display).
- [x] **Task 56.4:** "Press ESC to skip" label centred at bottom with smooth alpha pulse animation.
- [x] **Task 56.5:** Overlay auto-shows when cinematic starts, auto-hides when cinematic ends.
- [x] **Task 56.6:** No CIN_* stubs needed — real RoQ decoder in `cl_cin.cpp` handles all cinematic functions.

### Key technical details (Phase 56):
- Public API: `Godot_Cinematic_Init(Node*)`, `Godot_Cinematic_Update(delta)`, `Godot_Cinematic_Shutdown()`, `Godot_Cinematic_IsActive()`
- The overlay complements MoHAARunner's Phase 11 cinematic frame display (layer 11) by adding the skip hint on layer 200
- ESC key input is already handled by the engine's `SCR_StopCinematic()` path — no additional input injection needed
- Label alpha oscillates between 0.3 and 1.0 at 2.5 rad/s using `sinf()`
- Auto-discovered by SConstruct's recursive source walk of `code/godot/`

### Files created (Phase 56):
- `code/godot/godot_cinematic.cpp` — Cinematic skip-hint overlay implementation
- `code/godot/godot_cinematic.h` — Public API header

### Files modified (Phase 56):
- `TASKS.md` — Added Phase 56 documentation

## Phase 80: Lightmap Styles ✅

Implemented BSP lightmap style support.  MOHAA maps can have up to 4 lightmap styles per surface (stored in `lightmapStyles[4]`), controlled by server configstrings.  Light switches, flickering lights, and pulsing lights use alternate lightmap styles baked by the map compiler.

- [x] **Task 80.1:** C accessor (`godot_lightmap_styles_accessors.c`) — reads lightstyle pattern strings from `sv.configstrings[CS_LIGHTSTYLES + index]` and evaluates brightness at the current server time.  Pattern characters map `'a'` = 0 (off) through `'z'` = 255 (full), advancing at 10 Hz.
- [x] **Task 80.2:** Lightmap style manager (`godot_lightmap_styles.cpp`) — tracks 64 styles (MAX_LIGHTSTYLES × 2), polls engine brightness each frame via the C accessor, and interpolates between steps for smooth transitions (INTERP_SPEED = 10.0).
- [x] **Task 80.3:** Public API header (`godot_lightmap_styles.h`) — declares `Godot_LightStyles_Init()`, `Godot_LightStyles_Update(delta)`, `Godot_LightStyles_Shutdown()`, `Godot_LightStyles_GetBrightness(style_index)`, plus C accessor declarations.
- [x] **Task 80.4:** Documentation of integration points for BSP lightmap rendering.

### Key technical details (Phase 80):
- Style 0 = always full brightness (1.0); style 255 = unused slot (0.0)
- Styles 1–31 are switchable via `SV_SetLightStyle()` / `gi.SetLightStyle()`
- Pattern format: each character is a brightness frame, 'a'=0.0 through 'z'=1.0, cycling at 10 Hz
- Smooth interpolation prevents jarring brightness jumps between pattern steps
- Final surface light = sum of (lightmap_i × brightness_i) for each active style slot

### Integration points for MoHAARunner / BSP renderer:
1. **Init:** Call `Godot_LightStyles_Init()` at map load time (in `check_world_load()`).
2. **Update:** Call `Godot_LightStyles_Update(delta)` once per frame in `_process()`.
3. **Query:** Call `Godot_LightStyles_GetBrightness(style_index)` when building/updating lightmap data for each BSP surface.
4. **Shutdown:** Call `Godot_LightStyles_Shutdown()` on map unload or engine shutdown.
5. **For StandardMaterial3D:** Modulate lightmap texture brightness by the returned multiplier.
6. **For ShaderMaterial:** Set a `lightstyle_brightness` uniform with the brightness value.

### Files created (Phase 80):
- `code/godot/godot_lightmap_styles.cpp` — lightmap style manager
- `code/godot/godot_lightmap_styles.h` — public API header
- `code/godot/godot_lightmap_styles_accessors.c` — C accessor for configstring light state

## Phase 83: Draw Distance ✅
- [x] **Task 83.1:** Created `godot_draw_distance_accessors.c` — C accessors for `r_znear`, `r_zfar`, `cg_farplane`, `cg_farplane_color`, `farplane_cull`.
- [x] **Task 83.2:** Created `godot_draw_distance.h` — public API header (`Godot_DrawDistance_Init`, `Godot_DrawDistance_Update`, `Godot_DrawDistance_GetCullDistance`).
- [x] **Task 83.3:** Created `godot_draw_distance.cpp` — draw distance manager: maps engine cvars to Camera3D near/far planes and Environment fog.
- [x] **Task 83.4:** Near plane: `r_znear` (default 4 inches) converted to metres via `÷39.37`, applied to `camera->set_near()`.
- [x] **Task 83.5:** Far plane: `cg_farplane` overrides `r_zfar`; converted to metres, applied to `camera->set_far()`. Default 1000m when both are 0.
- [x] **Task 83.6:** Fog: when `cg_farplane > 0`, enables Environment fog with colour from `cg_farplane_color` and density `2.3/distance` for ~90% opacity at the far plane.
- [x] **Task 83.7:** Far plane culling: `Godot_DrawDistance_GetCullDistance()` returns cull distance in metres when `farplane_cull=1`; MoHAARunner should check entity distance before spawning MeshInstance3D nodes.
- [x] **Task 83.8:** Update frequency: cvars polled once per second via delta accumulator, not every frame.

### Key technical details (Phase 83):
- `r_znear` and `r_zfar` are read via `Cvar_Get()` (created with defaults if not already registered by the stub renderer)
- `cg_farplane`, `farplane_color`, and `farplane_cull` are read from the per-frame refdef capture in `godot_renderer.c` via `Godot_Renderer_GetFarplane()`
- Fog density formula: `exp(-density * dist) = 0.1` → `density = 2.3 / dist_metres`
- Coordinate conversion: inches → metres via `INCHES_TO_METRES = 1/39.37`
- Near plane clamped to minimum 0.001m to avoid rendering artefacts

### MoHAARunner integration points (Phase 83):
1. **In `_ready()`:** Call `Godot_DrawDistance_Init()` after engine initialisation.
2. **In `_process()`:** Call `Godot_DrawDistance_Update(camera, env, delta)` each frame (internally rate-limited).
3. **Entity culling:** Before spawning entity MeshInstance3D, call `Godot_DrawDistance_GetCullDistance()` — if > 0, skip entities beyond that distance from the camera.

### Files created (Phase 83):
- `code/godot/godot_draw_distance_accessors.c` — C accessor layer (~90 lines)
- `code/godot/godot_draw_distance.h` — public API header
- `code/godot/godot_draw_distance.cpp` — draw distance manager (~140 lines)

## Phase 84: Debug Rendering ✅

Implements developer debug overlays controlled by engine cvars:

- **r_showtris** — toggles viewport wireframe debug draw (`Viewport::DEBUG_DRAW_WIREFRAME`)
- **r_shownormals** — draws entity orientation axes as coloured lines at entity origins using `ImmediateMesh` (blue forward axis, max 32 entities, distance-culled to 20m)
- **r_speeds** — displays per-frame stats overlay on `CanvasLayer` (z=150): FPS, entity counts (total/skeletal/static), mesh cache hit rate, draw calls, polygon estimate. Updated every 10 frames for readability.
- **r_lockpvs** — accessor exposed (PVS freeze logic is in the BSP culling path)
- **r_showbbox** — draws wireframe bounding boxes around entities using `ImmediateMesh` with `PRIMITIVE_LINES` (green=static, yellow=dynamic)

All cvars are read via thin C accessor functions (`godot_debug_render_accessors.c`) using `Cvar_Get()` with `CVAR_CHEAT` flag, matching upstream renderer behaviour. The C++ manager (`godot_debug_render.cpp`) creates and manages Godot scene nodes (CanvasLayer, Label, MeshInstance3D pools) without modifying MoHAARunner.

### Files created:
- `code/godot/godot_debug_render_accessors.c` — C cvar accessors for r_showtris, r_shownormals, r_speeds, r_lockpvs, r_showbbox
- `code/godot/godot_debug_render.h` — Public API: Init/Update/Shutdown + extern "C" accessor declarations
- `code/godot/godot_debug_render.cpp` — Debug render manager: wireframe toggle, stats overlay, normal lines, bbox wireframes

### MoHAARunner Integration Required:
1. **In `_ready()`:** Call `Godot_DebugRender_Init(this)` after 3D scene setup.
2. **In `_process()`:** Call `Godot_DebugRender_Update(delta)` each frame.
3. **In destructor/map unload:** Call `Godot_DebugRender_Shutdown()`.

## Phase 241-242: Animation Events ✅
- [x] **Task 241.1:** Created C accessor layer (`godot_animation_event_accessors.cpp`) for TIKI animation event data — reads `dtikianimdef_t` / `dtikicmd_t` structures via `dtiki_t *` pointer, exposing animation count, aliases, event count, and per-event frame number + type + parameters.
- [x] **Task 241.2:** Created animation event dispatcher (`godot_animation_events.cpp`) with per-entity tracking state — detects animation changes, fires ENTRY/EXIT/EVERY/frame events, handles animation looping (frame wrap to 0).
- [x] **Task 242.1:** Event type classification: `sound`, `footstep`, `effect`/`tagspawn`, `bodyfall` — mapped to typed constants for downstream handlers.
- [x] **Task 242.2:** Fired-event output queue (`godot_anim_fired_event_t[256]`) with accessor API — MoHAARunner can drain per frame and route to audio/VFX systems.

### Key technical details (Phases 241-242):
- TIKI frame constants: `TIKI_FRAME_ENTRY` (-3), `TIKI_FRAME_EXIT` (-2), `TIKI_FRAME_EVERY` (-1), `TIKI_FRAME_FIRST` (0+)
- Server commands are indexed first, then client commands, in a flat event index space
- Per-entity state tracks: current_anim, last_fired_frame, entry_fired, tiki_ptr — detects animation transitions and fires exit→entry sequence
- Loop handling: when current_frame < last_fired_frame, fires remaining events from old cycle tail then new cycle head

### Files created (Phases 241-242):
- `code/godot/godot_animation_events.h` — public API header
- `code/godot/godot_animation_event_accessors.cpp` — C accessor for TIKI animation event data
- `code/godot/godot_animation_events.cpp` — animation event dispatcher with per-entity tracking

### MoHAARunner Integration Required (Phases 241-242):
1. **In `_ready()`:** Call `Godot_AnimEvents_Init()` after `Com_Init()`.
2. **In `update_entities()`:** For each animated entity, call `Godot_AnimEvents_Fire(entity_index, tikiPtr, anim_index, current_frame, pos)`.
3. **After entity update:** Call `Godot_AnimEvents_GetFiredCount()` / `Godot_AnimEvents_GetFiredEvents()` to drain the queue — route sound events to the audio pipeline, effect events to VFX, footstep events to surface-type lookup + audio.
4. **After draining:** Call `Godot_AnimEvents_ClearFired()`.
5. **In shutdown:** Call `Godot_AnimEvents_Shutdown()`.

## Phase 241: Animation Blending ✅

- [x] **Task 241.1:** Audit existing CPU skinning pipeline (`godot_skel_model_accessors.cpp`) — confirmed that `Godot_Skel_PrepareBones()` correctly passes all 16 `frameInfo[]` channels and `actionWeight` through to `ri.TIKI_SetPoseInternal()`, which performs multi-channel blending internally.
- [x] **Task 241.2:** Create `godot_anim_blend.h` — public API with `AnimBlendInput` struct (frame indices, weights, times, action_weight, active channel count, per-group weight sums) and `AnimBlendValidation` struct (diagnostic output).
- [x] **Task 241.3:** Create `godot_anim_blend.cpp` — implementation of extraction, validation, bone computation wrapper, and debug logging helpers.
- [x] **Task 241.4:** `Godot_AnimBlend_ExtractFromEntity()` reads entity buffer via `Godot_Renderer_GetEntityAnim()`, splits channels into group A (0–7, action/upper body) and group B (8–15, legs/movement), and computes per-group weight sums.
- [x] **Task 241.5:** `Godot_AnimBlend_Validate()` checks weight sanity: at least one active channel, actionWeight in [0,1], per-group weight sums ≈ 1.0 (tolerance 0.1).
- [x] **Task 241.6:** `Godot_AnimBlend_ComputeBones()` convenience wrapper reconstructs `frameInfo_t[]` from `AnimBlendInput`, delegates to `Godot_Skel_PrepareBones()` (engine-internal blending), and copies result to caller buffer.
- [x] **Task 241.7:** `Godot_AnimBlend_DebugLogEntity()` logs per-channel state and validation results via `Com_Printf` for runtime debugging.

### Key technical details (Phase 241):
- MOHAA uses `MAX_FRAMEINFOS` = 16 channels (not 4), split at `FRAMEINFO_BLEND` = 8 into action (group A) and movement (group B) groups.
- `actionWeight` blends group A vs group B: 0.0 = all action, 1.0 = all movement.
- The engine's skeletor (`ri.TIKI_SetPoseInternal`) already performs correct weighted blending of all channels internally — no Godot-side quaternion blending is needed.
- `Godot_Skel_PrepareBones()` correctly delegates the full `frameInfo[16]` array and `actionWeight` to the engine; bone cache output already reflects multi-channel blended transforms.
- Vertex skinning in `Godot_Skel_SkinSurface()` correctly applies per-vertex bone weights from the blended bone cache.

### Verification findings (Phase 241):
- All 16 frameInfo channels are captured by `GR_AddRefEntityToScene()` via `memcpy(ge->frameInfo, re->frameInfo, sizeof(ge->frameInfo))`.
- `Godot_Renderer_GetEntityAnim()` exposes the full `frameInfo[MAX_FRAMEINFOS]` to the Godot layer.
- No fixes required in `godot_skel_model_accessors.cpp` — the existing pipeline is correct.

### Files created (Phase 241):
- `code/godot/godot_anim_blend.h` — public API (AnimBlendInput, AnimBlendValidation, 5 exported functions)
- `code/godot/godot_anim_blend.cpp` — implementation (extraction, validation, bone computation, debug logging)

## Phase 251: Transparent Sort Order ✅

- [x] **Task 251.1:** Created `godot_render_sort.h` with `SortableEntity` struct and public API (`Init`, `SortEntities`, `ApplyPriority`, `Shutdown`).
- [x] **Task 251.2:** Implemented sort comparator: primary key = shader sort value (ascending), secondary key = camera distance (front-to-back for opaque, back-to-front for transparent/additive).
- [x] **Task 251.3:** Implemented Godot `render_priority` mapping: opaque → 0, transparent → 1–100 (distance-based), additive → 101–127.
- [x] **Task 251.4:** `Godot_RenderSort_ApplyPriority()` iterates surface override materials on a `MeshInstance3D` and sets `render_priority` per the distance mapping.

### Key technical details (Phase 251):
- Sort keys from `.shader` files parsed by `godot_shader_props.cpp` (`sort_key` field in `GodotShaderProps`): 0=portal, 2=opaque, 6=decal, 8=see-through, 9=banner, 12=underwater, 14–15=blend, 16=additive.
- Transparent surfaces (sort_key > 2) are rendered back-to-front: furthest entities get the lowest `render_priority` (rendered first), nearest get the highest (rendered last).
- Additive surfaces (sort_key ≥ 16) are placed in the 101–127 priority range, ensuring they render after all standard transparents.
- Distance normalisation uses a max squared distance of 64 516 m² (~254 m, or ~10 000 id units) — entities beyond this all receive minimum priority.
- `std::sort` with a custom comparator handles the two-level sort (sort_key then distance).

### MoHAARunner Integration Required (Phase 251):
1. In `update_entities()`, after building the entity list, construct a `SortableEntity` array for transparent entities.
2. Call `Godot_RenderSort_SortEntities()` with the camera position to sort the array.
3. For each entity, call `Godot_RenderSort_ApplyPriority(mesh, sort_key, distance_sq)` to set `render_priority` on the `MeshInstance3D`.
4. Only entities with `TRANSPARENCY_ALPHA` or `TRANSPARENCY_ALPHA_DEPTH_PRE_PASS` materials need sorting.

### Files created (Phase 251):
- `code/godot/godot_render_sort.h` — Public API: `SortableEntity`, sort key thresholds, function declarations (~105 lines)
- `code/godot/godot_render_sort.cpp` — Sort + priority implementation (~170 lines)

## Phase 258: Frustum Culling ✅

Camera frustum culling for entities and effects.  Extracts 6 frustum
planes from the active Camera3D's view-projection matrix and provides
fast AABB / sphere visibility tests.  Entities or effects whose bounding
volumes fall entirely outside the frustum can be skipped, reducing draw
calls when many objects exist off-screen.

### Public API (`godot_frustum_cull.h`)

| Function | Purpose |
|----------|---------|
| `Godot_FrustumCull_Init()` | Initialise internal state (planes, stats). |
| `Godot_FrustumCull_UpdateCamera(Camera3D*)` | Extract 6 frustum planes from camera; reset per-frame stats. |
| `Godot_FrustumCull_TestAABB(AABB)` | Return true if AABB intersects or is inside frustum. |
| `Godot_FrustumCull_TestSphere(Vector3, float)` | Return true if sphere intersects or is inside frustum. |
| `Godot_FrustumCull_GetStats(int*, int*)` | Retrieve per-frame tested/culled counters. |
| `Godot_FrustumCull_Shutdown()` | Release internal state. |

### Implementation details
- **Plane extraction:** Combined view-projection matrix (proj × view) →
  Gribb/Hartmann method for left/right/bottom/top/near/far planes, each
  normalised.
- **AABB test:** "p-vertex" method — for each plane, pick the AABB corner
  most in the direction of the plane normal.  If that vertex is behind the
  plane, the box is entirely outside.
- **Sphere test:** Signed distance from centre to each plane; if
  distance < −radius for any plane, sphere is outside.
- **Stats:** Per-frame counters (`tested`, `culled`) reset by
  `UpdateCamera()`, queried via `GetStats()`.

### MoHAARunner Integration Required
In `update_entities()`, for each entity:
1. Compute entity AABB from model bounds + position.
2. Call `Godot_FrustumCull_TestAABB(aabb)`.
3. If false, skip mesh creation/update for that entity.

### Files created
- `code/godot/godot_frustum_cull.h`
- `code/godot/godot_frustum_cull.cpp`

## Phase 86: Player Movement Physics Audit ✅

Audited player movement physics (`bg_pmove.cpp`, `bg_slidemove.cpp`, `bg_public.h`, `bg_local.h`, `player.cpp`, `playerbot.cpp`) for correctness under the `GODOT_GDEXTENSION` build. **No code changes required** — all movement code is architecture-agnostic.

### 1. Gravity & sv_fps ✅
- `pm->ps->gravity` correctly set from `sv_gravity` cvar in `player.cpp:4112`: `client->ps.gravity = sv_gravity->value * gravity` (entity gravity multiplier defaults to `1.0`).
- `pml.frametime` derived from command timestamp delta (`pml.msec = pmove->cmd.serverTime - pm->ps->commandTime`), NOT hardcoded 20Hz. Frame step chopping via `pmove_fixed`/`pmove_msec` cvars (clamped 8–33ms).
- `pm->ps->speed` set per stance in `player.cpp:4067–4099` using `sv_runspeed`, `sv_walkspeedmult`, `sv_crouchspeedmult`, weapon movement speed, zoom movement, and DM speed multiplier.

### 2. Walk/Run/Sprint ✅
- `PM_WalkMove()` (line 554): forward/backward via `PM_GetMove()` (applies `pm_backspeed` 0.80× and `pm_strafespeed` 0.85×), ground-plane projected, then `PM_Accelerate()` + `PM_StepSlideMove()`.
- `PM_Accelerate()` (line 232): standard Quake-style model — `canPush = accel * frametime * wishspeed`.
- `PM_Friction()` (line 166): ground friction `pm_friction=6.0`, slick `pm_slipperyfriction=0.25`, water friction scaled by `waterlevel`.
- `BUTTON_RUN` flag distinguishes walking/running (line 572). `pm->ps->pm_time` accumulates while sprinting forward.

### 3. Crouch/Prone ✅
- `PM_CheckDuck()` (line 1014): sets `mins`/`maxs`/`viewheight` per `PMF_DUCKED`, `PMF_VIEW_PRONE`, `PMF_VIEW_DUCK_RUN`, `PMF_VIEW_JUMP_START` flags.
- AA (protocol < MOHTA): full prone support (`PRONE_MAXS_Z=20`, `PRONE_VIEWHEIGHT=16`), crouch-run (`CROUCH_RUN_MAXS_Z=60`), crouch-prone (`CROUCH_MAXS_Z=54`, `CROUCH_VIEWHEIGHT=48`).
- SH/BT (protocol >= MOHTA): prone removed — only crouch (`CROUCH_MAXS_Z=54`) and jump-start (`JUMP_START_VIEWHEIGHT=52`).
- Stance flags set in `player.cpp:4039–4051` from actual `maxs.z` and `viewheight` values.

### 4. Jump ✅
- Jump initiation through player entity movement control (not in bg_pmove.cpp directly). `JUMP_VELOCITY=270` defined in `bg_local.h`.
- `PM_AirMove()` (line 391): standard air acceleration (`pm_airaccelerate=1.0`), ground-plane clipping, step-slide.
- `PM_CrashLand()` (line 746): fall damage from landing velocity delta — `EV_FALL_SHORT` (>20), `EV_FALL_MEDIUM` (>40), `EV_FALL_FAR` (>80), `EV_FALL_FATAL` (>100). Water reduces damage (×0.5 at level 1, ×0.25 at level 2). `SURF_NODAMAGE` surfaces skip damage.
- `PM_CheckTerminalVelocity()` (line 295): triggers `EV_TERMINAL_VELOCITY` event when speed exceeds `TERMINAL_VELOCITY=1200`.
- Double-jump prevention: `Pmove()` (line 1514) chops commands into ≤66ms steps; no explicit double-jump prevention in pmove — controlled by player entity movement state machine.

### 5. Lean ✅
- Lean handling in `PmoveSingle()` (lines 1349–1413): `BUTTON_LEAN_LEFT`/`BUTTON_LEAN_RIGHT` input.
- Lean speed/recovery/max controlled by `pm->leanSpeed`, `pm->leanRecoverSpeed`, `pm->leanAdd`, `pm->leanMax` fields.
- Lean restricted when moving (forward/right/up ≠ 0) unless `pm->alwaysAllowLean` (multiplayer DF_ALLOW_LEAN_MOVEMENT).
- Camera offset via bone angles: `PmoveAdjustAngleSettings()` applies lean to pelvis (0.8×), torso (0.2×), arms tags.
- Lean zeroed when dead, on ladder (`PM_CLIMBWALL`), or `PMF_NO_HUD` set.
- No lean collision traces — lean is a camera/bone rotation effect, not a position shift.

### 6. Water/Ladder ✅
- `PM_SetWaterLevel()` (line 970): uses `pm->pointcontents()` for 3-level water detection (feet/waist/head).
- Water movement: `PM_WalkMove()` scales `wishspeed` by 0.80 (level 1) or 0.50 (level 2+). `PM_Friction()` applies `pm_waterfriction=2.0` scaled by `waterlevel` (5× for slime).
- `PM_WaterEvents()` (line 1153): generates `EV_WATER_TOUCH`/`LEAVE`/`UNDER`/`CLEAR` events.
- Ladder: `PM_CLIMBWALL` pm_type (line 1323) — zeroes lean, restricts view angles via `PmoveAdjustViewAngleSettings_OnLadder()`.

### 7. #ifdef / Build Configuration ✅
- **No `#ifdef GODOT_GDEXTENSION`** guards in any `bg_*` files, `player.cpp`, or `playerbot.cpp` — none needed.
- `GAME_DLL` defined in SConstruct (line 63) for main .so build. `bg_pmove.cpp` does not use `GAME_DLL` directly.
- `bg_pmove.cpp` and `bg_slidemove.cpp` compiled into **both** main .so (`GAME_DLL`) and cgame.so (`CGAME_DLL`) per SConstruct lines 342–344.
- `pm->trace` set to `gi.trace` (server game interface) in `Player::SetMoveInfo()` (line 3678). Never NULL at runtime — `gi` populated by `SV_InitGameProgs()`.
- `pm->pointcontents` set to `gi.pointcontents` (line 3684). Never NULL at runtime.
- Syntax-only compilation verified: both `bg_pmove.cpp` and `bg_slidemove.cpp` pass `g++ -fsyntax-only` with `GAME_DLL + GODOT_GDEXTENSION` and `CGAME_DLL` defines.

### Files audited (Phase 86):
- `code/fgame/bg_pmove.cpp` (1760 lines) — core movement physics
- `code/fgame/bg_slidemove.cpp` (309 lines) — slide/step movement
- `code/fgame/bg_public.h` — movement constants, pmove_t struct, PMF flags
- `code/fgame/bg_local.h` — pml_t struct, local movement defines
- `code/fgame/player.cpp` — Player::ClientMove(), SetMoveInfo(), GetMoveInfo()
- `code/fgame/playerbot.cpp` — bot movement (uses same usercmd_t interface)

### Files created (Phase 86):
- None — no accessor files needed. Movement state is fully server-side and requires no Godot-side access.

## Phase 87: Weapon Mechanics Audit ✅
- [x] **Task 87.1:** Audited `weapon.h` / `weapon.cpp` — Weapon class (inherits Item) with full event table (Fire, Shoot, Reload, Idle, etc.), spread/recoil system, and multi-firemode support. No `#ifdef GODOT_GDEXTENSION` guards needed — no engine-specific code.
- [x] **Task 87.2:** Audited fire mechanics — `Fire()` (line 2153) sets animation + uses ammo; `Shoot()` (line 1346) dispatches by firetype: `FT_BULLET` → `BulletAttack()`, `FT_PROJECTILE` → `ProjectileAttack()`, `FT_MELEE` → `MeleeAttack()`, `FT_HEAVY` → `HeavyAttack()`. All operational under GODOT_GDEXTENSION.
- [x] **Task 87.3:** Audited hitscan — `BulletAttack()` in `weaputils.cpp` (line 2137) uses `G_Trace()` → `gi.trace()` for raycasting with bullet penetration, damage falloff through surfaces, and multi-hit mechanics. `G_Trace()` wrapper in `g_utils.cpp` (line 366) delegates to `gi.trace` — function pointer populated by `GetGameAPI()`.
- [x] **Task 87.4:** Audited projectile spawning — `ProjectileAttack()` in `weaputils.cpp` (line 1896) spawns entity with `MOVETYPE_BOUNCE`, velocity from charge fraction, and configurable life/speed. No GODOT_GDEXTENSION issues.
- [x] **Task 87.5:** Audited spread and recoil — Per-weapon spread via `bulletspread[mode]` / `bulletspreadmax[mode]` with time-decaying `m_fFireSpreadMult` (amount/falloff/cap/timecap). View kick via `viewkickmin[]` / `viewkickmax[]` applied randomly to view angles. Zoom reduces spread. Movement increases spread via `GetSpreadFactor()`.
- [x] **Task 87.6:** Audited reload — `StartReloading()` (line 2924) plays "reload" anim, sets `WEAPON_RELOADING` state; `DoneReloading()` (line 2943) resets to `WEAPON_READY`. `FillAmmoClip` / `EmptyAmmoClip` / `AddToAmmoClip` events handle ammo transfer. Reload cancel handled by weapon state machine (switching weapons interrupts reload state).
- [x] **Task 87.7:** Audited weapon switching — Player weapon selection via `EV_Player_PrevWeapon` / `EV_Player_NextWeapon` events (player.cpp lines 247–263). Holster/draw via `EV_Player_Holster` / `EV_Player_SafeHolster` events. Weapon raise/lower animations via `DoneRaising` / `DoneLowering` events.
- [x] **Task 87.8:** Audited melee — `MeleeAttack()` in `weaputils.cpp` (line 46) uses `G_Trace()` for world collision + `G_TraceEntities()` for entity hit detection within bounding box. Applies `Damage()` to all victims in range. Weapon.cpp `Shoot()` melee branch (line 1566) calculates melee position/end from forward vector and `bulletrange[mode]`.
- [x] **Task 87.9:** Audited turret weapons — `TurretGun` (weapturret.cpp line 352) extends Weapon with AI burst-fire logic (`AI_DoFiring`), configurable burst time/delay, player camera attachment, and view model support. No GODOT_GDEXTENSION guards needed.
- [x] **Task 87.10:** Audited weapon scripts — TIKI weapon files load via Item base class; weapon events (`EV_Weapon_AmmoType`, `EV_Weapon_StartAmmo`, `EV_Weapon_SetBulletSpread`, etc.) set per-weapon properties from `.tik` definitions. Script engine in `code/script/` has no GODOT_GDEXTENSION guards — operates identically in both builds.
- [x] **Task 87.11:** Audited item pickup/drop — `item.cpp` `ItemPickup()` (line 570) adds to Sentient inventory via `giveItem()`, plays sound, handles respawn. `Drop()` (line 491) detaches from owner with physics. No `gi.Malloc`/`gi.Free` in weapon or item code.
- [x] **Task 87.12:** Verified `gi.Malloc`/`gi.Free` safety — weapon files (weapon.cpp, weapturret.cpp, weaputils.cpp, item.cpp) do NOT use `gi.Malloc`/`gi.Free` directly. Memory allocation uses C++ `new`/`delete` through the class system. Safe wrappers in `g_main.h` (lines 39–46) are available but not needed by weapon code.
- [x] **Task 87.13:** Verified `G_Trace` validity — `G_Trace()` in `g_utils.cpp` wraps `gi.trace()`, populated by `GetGameAPI()` (g_main.cpp line 1647: `gi = *import`). Function pointer is valid throughout game lifetime. No GODOT_GDEXTENSION guards needed.
- [x] **Task 87.14:** Verified class registration — `Weapon` (weapon.cpp:473), `TurretGun` (weapturret.cpp:352), `InventoryItem` (inventoryitem.cpp:47) all use `CLASS_DECLARATION` macro. Class hierarchy: Trigger → Item → Weapon → TurretGun/InventoryItem. Auto-registered via static initialisation — works identically under GODOT_GDEXTENSION.
- [x] **Task 87.15:** Build verification — all weapon files (weapon.cpp, weapturret.cpp, weaputils.cpp, player.cpp, item.cpp, g_items.cpp) pass syntax check with full GODOT_GDEXTENSION defines (`-DDEDICATED -DBOTLIB -DGAME_DLL -DARCHIVE_SUPPORTED -DWITH_SCRIPT_ENGINE -DAPP_MODULE -DGODOT_GDEXTENSION`). Zero errors, zero warnings.

### Key technical details (Phase 87):
- **No code changes required** — all weapon mechanics compile and operate correctly under GODOT_GDEXTENSION
- Weapon code is pure game logic that communicates through the `gi` (game_import_t) interface, which is fully populated by the engine's `SV_InitGameProgs()` → `GetGameAPI()` path
- The `gi.trace` function pointer used by all weapon trace calls is valid throughout the game's lifetime — set once by `GetGameAPI()` and never cleared until `G_ShutdownGame()`
- No `gi.Malloc`/`gi.Free` calls exist in weapon files — C++ `new`/`delete` used instead, managed by the class system's memory pool
- No new accessor files needed — weapon state is entirely server-side game logic, not read by MoHAARunner

## Phase 88: Hit Detection & Damage Audit ✅
- [x] **Task 88.1:** Hitscan traces — `G_Trace()` (two overloads in `g_utils.cpp`) properly delegates to `gi.trace()` function pointer, which is assigned to `SV_Trace` in `sv_game.c`. Entity results mapped via `g_entities[trace.entityNum]` with NULL checks.
- [x] **Task 88.2:** Bullet traces — `BulletAttack()` (`weaputils.cpp`) performs hitscan with penetration via `G_Trace()` calls, supports wood/metal pass-through, tracer visuals, and per-bullet location-based damage.
- [x] **Task 88.3:** Melee traces — `MeleeAttack()` (`weaputils.cpp`) uses `G_Trace()` for world-blocking check then `G_TraceEntities()` for entity sweeps, properly filters by `takedamage`.
- [x] **Task 88.4:** Radius damage — `RadiusDamage()` (`weaputils.cpp`) enumerates entities via `findradius()`, performs per-target `G_SightTrace()` LOS checks, applies linear distance falloff, and reduces self-damage to 90%.
- [x] **Task 88.5:** Location-based damage — `hitloc_t` enum defines 19 body zones (head, torso, limbs); `Sentient::ArmorDamage()` applies per-location multipliers from `m_fDamageMultipliers[]` array (e.g. head=5.0×, limbs=0.5–0.8×).
- [x] **Task 88.6:** MOD types — 30 means-of-death constants (MOD_NONE through MOD_LANDMINE) with string table in `g_utils.cpp`; `MOD_string_to_int()` provides lookup.
- [x] **Task 88.7:** Damage pipeline — `Entity::Damage()` queues `EV_Damage` → `Entity::DamageEvent()` processes damage, checks immunity, deducts health → fires `EV_Killed` (health ≤ 0) or `EV_Pain` (alive). `Sentient::ArmorDamage()` applies location multipliers and armour reduction.
- [x] **Task 88.8:** Death handling — `Player::Killed()` sets death state, fires pain event for death anim, calls `Obituary()` for kill feed, sets respawn timer (1–2s in DM). NPC death via `Entity::Killed()` virtual dispatch.
- [x] **Task 88.9:** `#ifdef` verification — No `#ifdef DEDICATED` or `#ifdef GODOT_GDEXTENSION` guards exist in the damage pipeline (`entity.cpp`, `sentient.cpp`, `player.cpp`, `weaputils.cpp`, `g_utils.cpp`). None are needed: the entire pipeline operates through the `gi` function-pointer interface which `sv_game.c` initialises unconditionally before game code runs.
- [x] **Task 88.10:** Function pointer safety — `gi.trace`, `gi.pointcontents`, `gi.AreaEntities`, `gi.SightTrace` all assigned in `SV_InitGameProgs()` (`sv_game.c`) before `GetGameAPI()` returns. No NULL pointer risk during normal gameplay.
- [x] **Task 88.11:** Accessor assessment — No `godot_game_damage.h` accessor needed. The damage system runs entirely server-side via `gi` function pointers; `MoHAARunner.cpp` does not read damage state.

### Key technical details (Phase 88):
- **No code changes required.** The hit detection and damage pipeline is fully functional under the GDExtension build.
- Damage flow: `BulletAttack()`/`MeleeAttack()`/`RadiusDamage()` → `Entity::Damage()` → `EV_Damage` → `DamageEvent()`/`ArmorDamage()` → health deduction → `EV_Killed`/`EV_Pain`
- All trace functions (`G_Trace`, `G_SightTrace`, `G_TraceEntities`) use the `gi` interface which bridges to the server's `SV_Trace` (collision detection via BSP/CM system)
- `g_entities[]` array indexing for trace results is bounds-safe (ENTITYNUM_NONE check)
- The `gi_Malloc_Safe`/`gi_Free_Safe` wrappers in `g_main.h` are not needed in the damage pipeline (no allocator calls in hot damage path)

## Phase 91: Game Mode Audit ✅

Audited game mode initialisation, round logic, scoring, warmup, and intermission for all multiplayer modes (FFA, TDM, Team Rounds, Objective, TOW, Liberation). Created accessor layer so `MoHAARunner.cpp` can query game mode state without including fgame headers.

### Audit findings

**Game type initialisation (`g_main.cpp`, `gamecvars.cpp`):**
- `g_gametype` cvar maps: 0=SP, 1=FFA, 2=TDM, 3=TeamRounds, 4=Objective, 5=TOW, 6=Liberation
- `G_InitGame()` allocates entity pool, initialises DM manager via `level.SpawnEntities()` for multiplayer modes
- Entity spawn filtering by game type handled in `g_spawn.cpp` (notfree/notteam/notsingle spawnflags)

**FFA (Free For All):**
- Spawns at `info_player_deathmatch`; no team assignment
- Scoring via `fraglimit` cvar; kills tracked per-player in FFA team

**TDM (Team Deathmatch):**
- Team selection: Allies/Axis/Auto via `DM_Manager::JoinTeam()`
- Team spawn points: `info_player_allied` / `info_player_axis`
- Friendly fire controlled by `g_teamdamage` cvar

**Round-based modes (TeamRounds, Objective, TOW, Liberation):**
- `DM_Manager::m_bRoundBasedGame` flag set during `InitGame()`
- Round lifecycle: `StartRound()` → `m_bRoundActive=true` → `CheckEndMatch()` → `EndRound()`
- Warmup: `g_warmup` cvar (default 20s), `CS_WARMUP` configstring set via `GetMatchStartTime()`
- Score limits: `roundlimit` cvar for round-based; `fraglimit` for FFA/TDM

**Intermission:**
- `level.intermissiontime` set when match ends
- `g_maxintermission` controls duration before next map

### Files created
- `code/godot/godot_game_modes.h` — C-linkage accessor declarations
- `code/godot/godot_game_modes.cpp` — Accessor implementations (7 functions)

### Accessor API
| Function | Returns |
|----------|---------|
| `Godot_GameMode_GetType()` | `g_gametype` cvar value (0–6) |
| `Godot_GameMode_GetRoundState()` | 0=inactive, 1=warmup, 2=active, 3=intermission |
| `Godot_GameMode_GetScoreLimit()` | `fraglimit` or `roundlimit` depending on mode |
| `Godot_GameMode_GetTimeLimit()` | `timelimit` cvar value (minutes) |
| `Godot_GameMode_GetTeamScore(team)` | Team win count (0=allies, 1=axis) |
| `Godot_GameMode_IsWarmup()` | 1 if warmup/pre-round period is active |
| `Godot_GameMode_GetPlayerCount()` | Number of active players in DM manager |

## Phase 96-98: SP Features Audit ✅

Audited single-player campaign features: scripted camera cutscenes, NPC AI
pathfinding, and save/load game functionality.

### Script camera (cutscenes)
- [x] `Camera` class exists in `camera.cpp` / `camera.h` with `CameraThink`, `CameraMoveState`, BSpline interpolation.
- [x] Letterbox mode tracked via `level.m_letterbox_fraction` / `m_letterbox_dir`; exposed to clients through `STAT_LETTERBOX`.
- [x] `STAT_CINEMATIC` carries bit 0 (`level.cinematic`) and bit 1 (`actor_camera`).
- [x] Script commands (`cam setpath`, `cam follow`, `cam setfov`) handled via the event/listener system.
- [x] No `#ifdef GODOT_GDEXTENSION` guards needed — camera code compiles as-is.

### NPC AI
- [x] `Actor` class hierarchy (`Actor → SimpleActor → Sentient → Animate → Entity → Listener`) compiles.
- [x] `Actor::Think()` / `IdleThink()` / `Think_Idle()` state machine present with 56+ actor flags.
- [x] `PathSearch` grid-based navigation in `navigate.cpp` (MOHAA's own pathfinding, not Recast/Detour).
- [x] Combat AI: spot enemy, take cover, shoot, flee — implemented via actor state machine.
- [x] No header conflicts under `GODOT_GDEXTENSION`.

### Recast/Detour
- [x] Recast/Detour source in `code/thirdparty/recast-detour/` compiles.
- [x] MOHAA primarily uses its own `PathSearch` grid; Recast/Detour is available but secondary.

### Save/Load
- [x] `SV_SaveGame()` / `SV_Loadgame_f()` in `sv_ccmds.c` serialise entity states, player inventory, script threads.
- [x] Save files: `.ssv` (server), `.sav` (level), `.spv` (persistant), `.tga` (screenshot).
- [x] `SV_AllowSaveGame()` guarded by `#ifndef DEDICATED` — always returns `qfalse` under Godot build (DEDICATED defined). New `Godot_SP_CanSave()` accessor reimplements checks without that guard.
- [x] Memory safety: `gi_Malloc_Safe`/`gi_Free_Safe` already applied in allocator sites reachable from save/load paths.

### Accessor files created
- `code/godot/godot_game_sp.h` — declarations for 5 SP state accessors.
- `code/godot/godot_game_sp.c` — implementations:
  - `Godot_SP_IsCutsceneActive()` — reads `STAT_CINEMATIC` and `STAT_LETTERBOX` from first client.
  - `Godot_SP_GetObjectiveCount()` — stub (objectives live in C++ entity layer).
  - `Godot_SP_GetObjectiveComplete(i)` — stub (same reason).
  - `Godot_SP_CanSave()` — mirrors `SV_AllowSaveGame` logic, works under `GODOT_GDEXTENSION`.
  - `Godot_SP_CanLoad()` — checks for quick-save `.ssv` file via `FS_ReadFileEx`.

### #ifdef audit
- [x] `SV_AllowSaveGame` in `sv_ccmds.c` uses `#ifndef DEDICATED` — entire body compiled out under Godot. New accessor provides equivalent checks.
- [x] `g_main.h` already has `gi_Malloc_Safe`/`gi_Free_Safe` guards for allocator teardown.
- [x] Actor AI headers compile without conflicts under `GODOT_GDEXTENSION`.
- [x] Recast/Detour compiles under `GODOT_GDEXTENSION` with no issues.

## Phase 102: func_* Audit ✅
- [x] **Task 102.1:** Audited all `func_*` entity types — 37 active entities registered via CLASS_DECLARATION, all fully implemented.
- [x] **Task 102.2:** Verified door entities: `func_door` (SlidingDoor), `func_rotatingdoor` (RotatingDoor), `script_door` (ScriptDoor) — open/close/block/lock/sound all implemented.
- [x] **Task 102.3:** Verified mover base: `Mover` class provides `MoveTo()`, `LinearInterpolate()`, `MoveDone()`, `Stop()` — core movement engine for all func_* movers.
- [x] **Task 102.4:** Verified breakable/explodable entities: `func_explodingwall`, `func_exploder`, `func_multi_exploder`, `func_explodeobject`, `func_window`, `func_barrel`, `func_crate` — destruction, debris, and damage all implemented.
- [x] **Task 102.5:** Verified vehicle entities: `script_vehicle` (Vehicle), `script_drivablevehicle` (DrivableVehicle) — enter/exit/physics all implemented.
- [x] **Task 102.6:** Verified beam entity: `func_beam` (FuncBeam) — beam rendering, damage, shader configuration all implemented.
- [x] **Task 102.7:** Verified miscellaneous func_* entities: ladders, monkey bars, push objects, spawners, cameras, emitters, rain, fulcrums, objectives — all implemented.
- [x] **Task 102.8:** Confirmed legacy Q3 spawn table (`spawns[]`, `G_CallSpawn()`, `SP_func_*`) is disabled within `#if 0` block (g_spawn.cpp:607–1312) — no linker errors.
- [x] **Task 102.9:** Confirmed BSP model accessors available: `Godot_BSP_GetBrushModelMesh()`, `Godot_BSP_GetInlineModelBounds()`, `Godot_BSP_MarkFragmentsForInlineModel()`.
- [x] **Task 102.10:** Confirmed no `#ifdef GODOT_GDEXTENSION` guards needed in func_* files — pure game logic with no platform-specific behaviour.

### Key technical details (Phase 102):
- Entity spawning uses CLASS_DECLARATION macro system exclusively — `SpawnArgs::getClassDef()` resolves classID strings to C++ class definitions
- Legacy Q3 C-style spawn table is dead code in `#if 0` block — MOHAA replaced it with object-oriented class registration
- `func_breakable`, `func_explodable`, `func_vehicle`, `func_plat`, `func_train`, `func_rotating`, `func_pendulum` do not exist as CLASS_DECLARATION entries — MOHAA uses different classnames (see audit document for equivalents)
- Door state machine: `STATE_CLOSED` → `STATE_OPENING` → `STATE_OPEN` → `STATE_CLOSING` → `STATE_CLOSED`
- Movement pipeline: engine entity state → `godot_renderer.c` capture buffer → `MoHAARunner::update_entities()` → `MeshInstance3D` transform update

### Files created (Phase 102):
- `code/godot/godot_func_audit.md` — comprehensive audit of all 37 active func_* entities

## Phase 116-120: Collision & Physics Audit ✅
- [x] **BSP collision (CM_BoxTrace):** `CM_BoxTrace()` traces boxes through BSP world correctly. `CM_PointContents()` returns content flags. Brush collision (solid, water, lava, clip), patch collision hulls from Bézier patches, and terrain heightfield traces all function correctly. No `#ifdef GODOT_GDEXTENSION` guards needed — compiled identically for Godot and native.
- [x] **Entity collision:** `SV_Trace()` wraps `CM_BoxTrace` with entity clipping via `SV_ClipMoveToEntities()`. Entity clip models (bounding boxes and BSP sub-models) handled by `SV_ClipHandleForEntity()`. Pusher entities (doors, elevators) use `G_Push()` with rollback on blocking. Trigger touches detected via `G_TouchTriggers()`. `CONTENTS_BODY`, `CONTENTS_SOLID`, `CONTENTS_PLAYERCLIP` masks used correctly.
- [x] **Projectile physics:** Grenades use `MOVETYPE_BOUNCE` with engine gravity and surface-aware bounce sounds. Rockets travel straight-line and detonate on impact with `RadiusDamage()` splash. Bullets use instant-hit `G_Trace()` with material penetration (up to 5 layers). Per-weapon definitions loaded from TIKI files via `SpawnArgs`. Projectile–entity collision applies damage with knockback and means-of-death tracking.
- [x] **Water physics:** `PM_WaterMove()` applies velocity scaling (80%/50% by water level) and water friction. Water level detection via `PM_SetWaterLevel()` (0–3 tiers). Drowning damage in `P_WorldEffects()` scales from 2–15 HP/tick. Transition sounds: `EV_WATER_TOUCH`, `EV_WATER_LEAVE`, `EV_WATER_UNDER`, `EV_WATER_CLEAR`.
- [x] **Fall damage:** `PM_CrashLand()` uses kinematic delta calculation with four severity tiers (short/medium/far/fatal). Water reduces fall damage by 50–75%. `SURF_NODAMAGE` suppresses damage on bounce pads. Terminal velocity event at 1200 ups.
- [x] **Kill triggers and world damage:** `trigger_hurt` applies configurable damage with `DAMAGE_NO_ARMOR`. Lava deals 30×waterlevel, slime deals 10×waterlevel per frame via `P_WorldEffects()`. Out-of-world kills handled by map-placed `trigger_hurt` volumes (standard id Tech 3 practice).

### Audit documentation:
- `code/godot/godot_physics_audit.md` — full audit results with per-subsystem findings

## Phase 268: Entity Lighting Integration ✅

Wired `godot_entity_lighting.cpp` into `MoHAARunner::update_entities()` so entities are properly lit by the BSP lightgrid **and** dynamic lights (muzzle flashes, explosions).

### Changes
- **`godot_renderer.c`:** Added `lightingOrigin[3]` field to `gr_entity_t`, captured from `refEntity_t::lightingOrigin` in `GR_AddRefEntityToScene()`. Added `Godot_Renderer_GetEntityLightingOrigin()` accessor.
- **`MoHAARunner.cpp`:** Replaced direct `Godot_BSP_LightForPoint()` call with `Godot_EntityLight_Combined()` (guarded by `HAS_ENTITY_LIGHTING_MODULE`). Handles `RF_LIGHTING_ORIGIN` (0x0080) — when set, samples lightgrid at `lightingOrigin` instead of render origin. Fallback to old `Godot_BSP_LightForPoint()` path when module is absent.

### Technical Details
- `Godot_EntityLight_Combined(pos, 4, &r, &g, &b)` samples lightgrid ambient+directed and accumulates up to 4 closest dynamic lights with linear attenuation.
- Dynamic lights already rendered as `OmniLight3D` nodes in `update_dlights()`; this adds per-entity material modulation for more accurate lighting.
- Existing tinted material cache (Phase 61) works unchanged — the quantised light key captures the combined lighting colour.

## Phase 300: MoHAARunner Module Integration ✅
Full integration of all standalone agent modules into MoHAARunner.cpp.

- [x] **Task 300.1:** Added `__has_include` guards for `godot_ubersound.h`, `godot_speaker_entities.h`, `godot_sound_occlusion.h` in `MoHAARunner.h`.
- [x] **Task 300.2:** Integrated UI system (`godot_ui_system.h`/`godot_ui_input.h`) — `Godot_UI_Update()` called in `_process()`, cursor mode toggled via `Godot_UI_ShouldShowCursor()`.
- [x] **Task 300.3:** Integrated UI input routing in `_unhandled_input()` — when `Godot_UI_ShouldCaptureInput()` returns true, key/mouse/char events route through `Godot_UI_Handle*()` functions.
- [x] **Task 300.4:** Integrated render statistics (`Godot_RenderStats_BeginFrame()`/`EndFrame()`) and per-frame mesh/material cache eviction in `_process()`.
- [x] **Task 300.5:** Integrated entity lighting (`Godot_EntityLight_Combined()`) in `update_entities()` — replaces manual `Godot_BSP_LightForPoint` calls with combined lightgrid + dynamic light sampling.
- [x] **Task 300.6:** Integrated weapon SubViewport (`Godot_WeaponViewport`) — created in `setup_3d_scene()`, camera synced in `_process()`, RF_FIRST_PERSON/RF_DEPTHHACK entities reparented to weapon root.
- [x] **Task 300.7:** Integrated ubersound alias system — `Godot_Ubersound_Init()` called in `setup_audio()`, alias resolution in `load_wav_from_vfs()` when direct VFS load fails.
- [x] **Task 300.8:** Integrated speaker entities — `Godot_Speakers_Init()`/`LoadFromEntities()` called on map load, `Godot_Speakers_Update()` called per frame.
- [x] **Task 300.9:** Integrated sound occlusion — `Godot_SoundOcclusion_Check()` applied to 3D sound volume before playback.
- [x] **Task 300.10:** Added `Godot_BSP_GetEntityString()` accessor to `godot_bsp_mesh.cpp`/`.h` for speaker entity parsing.
- [x] **Task 300.11:** Fixed pre-existing Weather and Music init call signature mismatches (`Godot_Weather_Init(game_world)`, `Godot_Music_Init((void*)this)`).
- [x] **Task 300.12:** Added module shutdown hooks in `~MoHAARunner()`: weapon viewport destroy, speaker shutdown, ubersound shutdown, cache clearing, shader cache clearing.
- [x] **Task 300.13:** Integrated UI map load notification — `Godot_UI_OnMapLoad()` called in `check_world_load()`.
- [x] **Task 300.14:** Integrated shader material cache clearing on map change via `Godot_Shader_ClearCache()`.

### Key technical details (Phase 300):
- All module calls are guarded by `#ifdef HAS_<MODULE>_MODULE` preprocessor checks generated by `__has_include` in `MoHAARunner.h`
- Entity lighting uses `Godot_EntityLight_Combined()` which samples both BSP lightgrid and dynamic lights (Phase 63+64)
- Weapon viewport reparents entities with `RF_FIRST_PERSON` (0x02) or `RF_DEPTHHACK` (0x04) renderfx flags
- Sound occlusion factor applied as volume offset: `vol_db += 20 * log10(occlusion_factor)`
- Ubersound alias resolution is a fallback — tried only when direct VFS file load fails
- Frame counter for cache eviction uses a local `static uint64_t` incremented each `_process()` call

### Modules integrated:
| Module | Header | Purpose | Integration Points |
|--------|--------|---------|--------------------|
| UI System | `godot_ui_system.h` | UI state machine, cursor control | `_process()`, `check_world_load()` |
| UI Input | `godot_ui_input.h` | Input routing to menus/console/chat | `_unhandled_input()` |
| Mesh Cache | `godot_mesh_cache.h` | Entity mesh caching + eviction | `_process()`, `check_world_load()` |
| Material Cache | `godot_mesh_cache.h` | Material sharing + eviction | `_process()`, `check_world_load()` |
| Render Stats | `godot_mesh_cache.h` | Per-frame performance counters | `_process()` |
| Entity Lighting | `godot_entity_lighting.h` | Lightgrid + dlight sampling | `update_entities()` |
| Weapon Viewport | `godot_weapon_viewport.h` | SubViewport for first-person weapons | `setup_3d_scene()`, `_process()`, `update_entities()` |
| Ubersound | `godot_ubersound.h` | Sound alias resolution | `setup_audio()`, `load_wav_from_vfs()` |
| Speaker Entities | `godot_speaker_entities.h` | BSP ambient sound entities | `check_world_load()`, `_process()` |
| Sound Occlusion | `godot_sound_occlusion.h` | BSP trace-based attenuation | `update_audio()` |
| Shader Material | `godot_shader_material.h` | Cache clear on map change | `check_world_load()`, `~MoHAARunner()` |

### Files modified (Phase 300):
- `code/godot/MoHAARunner.h` — added `__has_include` guards for ubersound, speakers, occlusion
- `code/godot/MoHAARunner.cpp` — integrated all module hooks (262 lines added)
- `code/godot/godot_bsp_mesh.h` — added `Godot_BSP_GetEntityString()` declaration
- `code/godot/godot_bsp_mesh.cpp` — added `Godot_BSP_GetEntityString()` implementation

## Phase 59: MoHAARunner UI System Integration ✅
- [x] **Task 59.1:** Added `extern "C"` declarations for all `Godot_UI_*` and `Godot_ResetMousePosition` functions in MoHAARunner.cpp (guarded with `#ifndef HAS_UI_SYSTEM_MODULE` / `HAS_UI_INPUT_MODULE` to avoid conflicts when headers are available).
- [x] **Task 59.2:** Call `Godot_UI_Update()` each frame in `_process()` immediately after `Com_Frame()` — polls engine keyCatchers and updates the UI state machine.
- [x] **Task 59.3:** Cursor management: `Godot_UI_ShouldShowCursor()` checked each frame — toggles between `MOUSE_MODE_VISIBLE` (UI active) and `MOUSE_MODE_CAPTURED` (game mode). Calls `Godot_ResetMousePosition()` on transitions to prevent cursor jumps.
- [x] **Task 59.4:** `_unhandled_input()` now checks `Godot_UI_ShouldCaptureInput()` — routes keyboard, mouse button, mouse motion, and character events through `Godot_UI_Handle*()` when UI is active; falls through to direct `Godot_Inject*()` for game mode.
- [x] **Task 59.5:** `check_world_load()` calls `Godot_UI_OnMapLoad()` when a new BSP load begins — activates `GODOT_UI_LOADING` state in the UI state machine.
- [x] **Task 59.6:** Removed hardcoded input-fix logic in `_process()` (forcible keyCatcher clearing, ForceUnpause) — now superseded by the UI state machine's automatic cursor/input mode management.
- [x] **Task 59.7:** Added `last_ui_cursor_shown` tracking member to MoHAARunner to detect cursor state transitions and avoid redundant mode switches.

### Key technical details (Phase 59):
- UI state machine (`godot_ui_system.cpp`) polls `Godot_Client_GetKeyCatchers()` each frame via `Godot_UI_Update()` and derives the UI state (NONE, MAIN_MENU, CONSOLE, LOADING, SCOREBOARD, MESSAGE)
- Input routing is decided once per event in `_unhandled_input()` — the `Godot_UI_Handle*()` functions internally delegate to the same `Godot_Inject*()` calls but mark events as consumed
- The engine's own key dispatch in `cl_keys.c` routes events to `Console_Key()`, `UI_KeyEvent()`, `Message_Key()`, or `CG_KeyEvent()` based on the keyCatchers flags — the UI input module does not bypass this
- Mouse mode transitions use `Godot_ResetMousePosition()` to clear absolute mouse tracking state in `godot_input_bridge.c`, preventing position jumps when switching between UI (absolute) and game (relative) input modes
- Background rendering (item 3 above) and dedicated UI CanvasLayer (item 5) remain as future work — the engine's 2D command buffer already captures background/loading screen content

### Files modified (Phase 59):
- `code/godot/MoHAARunner.cpp` — UI update, cursor management, input routing, map load notification
- `code/godot/MoHAARunner.h` — added `last_ui_cursor_shown` member

## Phase 262: Save/Load Game Integration ✅
- [x] **Task 262.1:** Created `code/godot/godot_save_accessors.c` — C accessor wrapping engine `savegame`/`loadgame` console commands via `Cbuf_ExecuteText(EXEC_APPEND, ...)`.
- [x] **Task 262.2:** Created `code/godot/godot_save_accessors.h` — header with extern "C" declarations for `Godot_Save_QuickSave`, `Godot_Save_QuickLoad`, `Godot_Save_SaveToSlot`, `Godot_Save_LoadFromSlot`, `Godot_Save_SlotExists`.
- [x] **Task 262.3:** Wired F5 (quick save) and F9 (quick load) key handlers in `MoHAARunner::_unhandled_input()`. Moved HUD toggle from F9 to F10.
- [x] **Task 262.4:** `Godot_Save_SlotExists` uses `Com_GetArchiveFileName` + `FS_ReadFile` to check for save slot `.sav` files.

### Key technical details (Phase 262):
- Save/load commands are queued via `Cbuf_ExecuteText(EXEC_APPEND, ...)` — engine's `SV_Savegame_f`/`SV_Loadgame_f` (in `sv_ccmds.c`) handle all serialisation.
- Slot-based saves use names `slot0`–`slotN`; quick save/load uses name `quick`.
- `Godot_Save_SlotExists` checks `save/<config>/<slotN>.sav` via `Com_GetArchiveFileName` and `FS_ReadFile(path, NULL)`.
- No SConstruct changes needed — `code/godot/` is already in `src_dirs` and `add_sources()` recursively collects `.c`/`.cpp`.

### Files created (Phase 262):
- `code/godot/godot_save_accessors.c`
- `code/godot/godot_save_accessors.h`

### Files modified (Phase 262):
- `code/godot/MoHAARunner.cpp` — added save accessor extern declarations, F5/F9 key handlers, moved HUD toggle to F10
