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
│   │   │   ├── godot_renderer.c          ← Stub refexport_t (~80 functions) + entity/poly/swipe/2D capture buffers; calls R_Init() to bootstrap real shader/image/model subsystems
│   │   │   ├── godot_sound.c             ← Sound event capture: S_*/MUSIC_* with queue + accessor API
│   │   │   ├── godot_input.c             ← IN_Init/Shutdown/Frame stubs (actual input via godot_input_bridge)
│   │   │   ├── godot_input_bridge.c      ← Godot key/mouse → engine SE_KEY/SE_MOUSE/SE_CHAR injection
│   │   │   ├── godot_bsp_mesh.cpp/.h     ← BSP parser: world mesh, terrain, lightmaps, mark fragments, entity tokens
│   │   │   ├── godot_shader_props.h      ← Shared struct/enum definitions for shader properties (C/C++ compatible typedefs)
│   │   │   ├── godot_skel_model.cpp/.h   ← TIKI skeletal mesh builder (ArrayMesh from SKD/SKC/SKB)
│   │   │   ├── godot_skel_model_accessors.cpp ← C++ accessor for TIKI data (dtiki_t, skelHeaderGame_t)
│   │   │   ├── godot_client_accessors.cpp     ← Client state: keyCatchers, guiMouse, paused, SetGameInputMode
│   │   │   ├── godot_server_accessors.c       ← Server state: sv.state, svs.mapName, svs.iNumClients
│   │   │   └── godot_vfs_accessors.c          ← VFS read helper for Godot-side file loading
│   │   ├── renderergl1/      ← Real renderer source (compiled into main .so); includes godot_shader_accessors.c bridge
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

### Implementation standards — no shortcuts, no fallbacks
1. **No fallbacks.** Always aim for 1:1 parity with MOHAA/OpenMoHAA. If the original engine does something a particular way, replicate that behaviour exactly. Never substitute a "good enough" approximation when the correct implementation is achievable.
2. **No shortcuts.** Implement everything fully. If a function, accessor, or subsystem is missing (e.g. `Godot_Renderer_RegisterShader`), implement it properly rather than working around its absence. The codebase must grow correctly, not accumulate workarounds.
3. **Put the effort in.** Do what is necessary, not what is easy. Study the original engine code (`renderergl1/`, `client/`, `fgame/`, `skeletor/`, etc.) to understand the correct behaviour, then replicate it faithfully on the Godot side. One-off hacks that bypass the established architecture (shader table, model table, VFS, accessor layer) are not acceptable.
4. **Reuse engine functions — never rewrite them.** The monolithic build links the full engine (`code/qcommon/`, `code/fgame/`, `code/script/`, `code/tiki/`, `code/skeletor/`, etc.). All utility functions from those modules are available at link time. **Always use them** instead of writing custom replacements. Key examples:
   - **Tokeniser:** Use `COM_ParseExt()`, `SkipRestOfLine()`, `COM_Compress()` from `q_shared.c` — never write custom `read_token()`, `skip_ws()`, `skip_line()` functions.
   - **String comparison:** Use `Q_stricmp()`, `Q_stricmpn()`, `Q_strncpyz()` — never write custom `str_ieq()` or use `strcasecmp()`.
   - **Math:** Use `VectorCopy()`, `VectorScale()`, `AngleVectors()`, `LerpAngle()` from `q_math.c` — never reimplement vector/angle operations.
   - **Memory:** Use `Z_Malloc()`/`Z_Free()` for engine-lifetime allocations, `Hunk_AllocateTempMemory()` for frame-temporary data — never use raw `malloc`/`free` for data that participates in engine lifecycle.
   - **VFS:** Use `FS_ReadFile()`, `FS_FreeFile()`, `FS_ListFiles()` (via the accessor layer) — never use `fopen`/`std::ifstream`.
   - **Model/TIKI:** Use `TIKI_RegisterTikiFlags()`, `TIKI_GetSkelAnimFrame()`, `TIKI_GetLocalChannel()` — never rewrite bone transforms or animation evaluation.
   
   Since Godot C++ files cannot `#include` engine headers directly (macro/type conflicts with godot-cpp), declare the needed engine functions via `extern "C"` blocks in the `.cpp` file. This gives access to the engine's battle-tested implementations without header coupling. If an engine function's signature is unclear, check `q_shared.h`, `qcommon.h`, or the relevant module header — do not guess or write a substitute.

### Mandatory research-before-code workflow
**Every feature implementation or bug fix MUST follow this workflow.** No exceptions.

#### Step 1: Trace the original engine code path
Before writing a single line of Godot glue code, **read the original engine implementation** in `renderergl1/`, `client/`, `fgame/`, `cgame/`, `server/`, `qcommon/`, `skeletor/`, or `tiki/`. Understand:
- What functions are called and in what order
- What data structures are populated and what fields matter
- What side effects occur (shader registration, memory allocation, state changes)
- What the caller expects to receive (return values, buffer contents, populated structs)

**Example:** Before implementing static model rendering on the Godot side, you must read `renderergl1/tr_staticmodels.cpp::R_InitStaticModels()` to discover that it:
1. Registers shaders via `R_FindShader()` for each TIKI surface
2. Computes bind-pose vertices via `TIKI_GetSkelAnimFrame()` + bone matrix transforms
3. Allocates `pStaticXyz`/`pStaticNormal`/`pStaticTexCoords` arrays
4. Uses `TIKI_GetLocalChannel()` for multi-mesh bone remapping

Without reading this, you'd miss that `pStaticXyz` is NULL because our stub renderer never calls `R_InitStaticModels()`, and attempts to read those arrays produce garbage.

#### Step 2: Identify the full data pipeline
Map the complete data flow from engine source to Godot rendering:
```
Engine function → what data it produces → how our stub captures it → how MoHAARunner consumes it
```

**Example for shaders:**
```
R_FindShader(name)
  → looks up .shader script definition (hashTable lookup)
  → parses stages[].map to find actual texture file paths
  → loads texture image from VFS
  → returns shader_t* with index

Our equivalent must:
  1. GR_RegisterShader(name) → assigns handle in gr_shaders[] table
  2. get_shader_texture(handle) → looks up shader name
     → calls Godot_ShaderProps_Find(name) to get parsed .shader definition
     → reads stages[].map for the actual texture path (NOT the shader name!)
     → loads texture via VFS using that path
```

If any step is missing or simplified, textures will be wrong or absent.

#### Step 3: Verify stub completeness
Our stub renderer (`godot_renderer.c`) provides no-op implementations of `refexport_t`. When the real renderer does **computation** (not just rendering), our stub must replicate that computation or expose it via an accessor. Key cases:

| Real renderer function | What it computes | Our stub must... |
|------------------------|------------------|------------------|
| `R_InitStaticModels()` | Bind-pose vertices, shader registration | Provide accessor for `TIKI_GetSkelAnimFrame` + bone transforms; register shaders via `GR_RegisterShader` |
| `R_FindShader()` | Shader script → texture path resolution | **Real `R_FindShader()` is called** — `godot_shader_accessors.c` reads from real `shader_t` structs |
| `RE_RegisterModel()` | TIKI loading, model table population | `GR_RegisterModelInternal()` — already done |
| `R_LoadWorldMap()` / `RE_LoadWorldMap()` | BSP parsing, lightmap upload, surface shader assignment | `godot_bsp_mesh.cpp` BSP parser — already done |

**If a no-op stub silently returns zero/NULL and the caller needs real data, you have a bug.** Always check what the real renderer computes.

#### Step 4: Implement, don't work around
If the correct implementation requires a new accessor, buffer, or function — create it. Never:
- Use a shader name as a file path when the shader definition maps to a different texture
- Skip a computation step because "it usually works without it"
- Return dummy data from a stub when the caller needs real values
- Comment out a function call because it crashes (fix the crash instead)

### Known footguns — things that went wrong before
These are real bugs that were shipped and required multiple fix iterations. Learn from them:

| Bug | Root cause | Lesson |
|-----|-----------|--------|
| Giant random meshes covering the map | `pStaticXyz` was NULL — stub renderer never calls `R_InitStaticModels()` which computes bind-pose vertices. `Godot_Skel_GetSurfaceVertices` returned success with uninitialised malloc'd data. | **Never trust that engine-internal data is populated.** The stub renderer skips all computation. If the Godot side needs data that the real renderer computes, implement the computation via an accessor. |
| Wrong/missing textures on static models | `get_shader_texture()` used the shader name directly as a file path (e.g. `textures/mohdm1/wall_brick`). But MOHAA shader names are abstract identifiers — the actual texture path is in the `.shader` definition's stage `map` directive (e.g. `textures/mohdm1/wall_brick_d.tga`). | **Always trace `R_FindShader()`'s resolution pipeline.** Shader name ≠ texture file path. Must look up shader definition stages. |
| `Godot_Renderer_RegisterShader` didn't exist | The stub renderer had `GR_RegisterShader` (internal, called by engine paths like `RE_RegisterShaderNoMip`) but no public accessor for Godot-side code to register shaders. Static model loading needed to register TIKI surface shaders but had no API to do so. | **When adding Godot-side features that need renderer services, check whether the accessor API exists.** If not, implement it — don't work around it. |
| Custom `.shader` tokeniser missed definitions | `godot_shader_props.cpp` used hand-written `read_token()`, `skip_ws()`, `skip_line()` that didn't handle `//` comments, `/* */` blocks, or quoted strings identically to the engine. Shader definitions were silently mis-parsed or skipped, causing wrong textures. | **Never write custom parsing/tokenising functions.** The engine's `COM_ParseExt()`, `SkipRestOfLine()`, `COM_Compress()` are linked and handle all edge cases. Declare them via `extern "C"` and use them directly. |
| 1700-line custom shader parser was unnecessary | `godot_shader_props.cpp` reimplemented `.shader` file parsing to build `GodotShaderProps` structs. But the real renderer's `R_Init()` → `R_StartupShaders()` already parses all `.shader` files into `shader_t` structs with all stage data, blend modes, cull, tcMod, etc. The entire custom parser was replaced with a ~650-line accessor (`godot_shader_accessors.c`) that reads from the real `shader_t` data. | **Never rewrite an engine subsystem parser.** If the engine already parses data (shaders, models, configs), initialise that subsystem and read from its output structs via an accessor. The real code handles edge cases, MOHAA extensions, and conditional blocks that a rewrite will inevitably miss. |
| `surfaceParm trans` forced alpha blending on opaque surfaces | `godot_shader_props.cpp` treated `surfaceParm trans` as a runtime transparency flag, setting `SHADER_ALPHA_BLEND`. This prevented the post-parse stage blendFunc analysis from running (it only ran when `transparency == SHADER_OPAQUE`). Result: any shader with `surfaceParm trans` (walls, buildings, floors — very common in MOHAA) rendered as alpha-blended, causing see-through surfaces. | **`surfaceParm` keywords are BSP compiler flags (Q3MAP), NOT runtime rendering directives.** Transparency is determined solely by stage `blendFunc`. See the Q3A Shader Manual reference below. |
| Default `CULL_DISABLED` on entity/static model materials | Entity skeletal models and static TIKI models defaulted to `CULL_DISABLED` (show both sides). Most models lack `.shader` definitions, so `apply_shader_props_to_material()` never overrode the default. Back faces were visible, causing see-through/ghostly appearance. | **MOHAA's renderer default is `CT_FRONT_SIDED` = Godot `CULL_BACK`.** Always default materials to `CULL_BACK`. Only set `CULL_DISABLED` when the shader definition explicitly says `cull none`/`cull twosided`. |

## Q3A Shader Manual — Key Rendering Rules

**Reference:** https://icculus.org/gtkradiant/documentation/Q3AShader_Manual/

The Q3A Shader Manual is the authoritative reference for how id Tech 3 shaders work. MOHAA/OpenMoHAA extends this system but follows the same core rules. Key rules that directly affect our Godot rendering:

### Keyword classification: compile-time vs runtime

| Category | Keywords | When processed | Affects rendering? |
|----------|----------|----------------|--------------------|
| **Q3MAP (compile-time only)** | `surfaceParm *`, `q3map_*`, `tessSize` | BSP compilation | **NO** — changes require map rebuild, ignored by renderer |
| **General (runtime)** | `cull`, `sort`, `deformVertexes`, `fogparms`, `skyParms`, `nopicmip`, `nomipmaps`, `polygonOffset`, `portal` | Renderer at load time | Yes |
| **Stage-specific (runtime)** | `map`, `blendFunc`, `rgbGen`, `alphaGen`, `alphaFunc`, `tcMod`, `tcGen`, `depthWrite`, `depthFunc`, `detail` | Renderer per-stage | Yes |

**Critical rule:** `surfaceParm` keywords (including `trans`, `nolightmap`, `noimpact`, `nomarks`, etc.) are Q3MAP directives. They tell the BSP compiler about surface properties for vis, lighting, and physics. They do **NOT** affect how the renderer draws the surface at runtime. Never use `surfaceParm` to determine transparency or cull mode.

### Transparency determination (SortNewShader logic)

Transparency is determined **solely** by stage `blendFunc`:

1. **No blendFunc on first stage** → shader is **opaque** (sort order = `opaque` = 3)
2. **`blendFunc add`** → additive blending (`GL_ONE GL_ONE`)
3. **`blendFunc filter`** → multiplicative (`GL_DST_COLOR GL_ZERO`) — used for lightmap modulation, NOT transparency
4. **`blendFunc blend`** → alpha blending (`GL_SRC_ALPHA GL_ONE_MINUS_SRC_ALPHA`)
5. **`alphaFunc GT0/LT128/GE128`** → alpha-test (hard cutoff, not smooth blending)

**Standard opaque lightmapped pattern** (most common in MOHAA):
```
textures/foo/bar
{
    surfaceparm trans     // ← Q3MAP ONLY — does NOT make this transparent!
    {
        map $lightmap
        rgbGen identity
    }
    {
        map textures/foo/bar.tga
        blendFunc filter   // ← filter = GL_DST_COLOR GL_ZERO = lightmap modulation = OPAQUE
    }
}
```
Despite `surfaceParm trans`, this shader is **opaque** because the first non-lightmap stage's blendFunc is `filter` (multiplicative lightmap modulation).

### Cull mode rules

- **Default:** `cull front` (Q3 terminology) = show front faces, cull back faces = Godot `CULL_BACK`
- **`cull back`** = show back faces, cull front = Godot `CULL_FRONT`
- **`cull none` / `cull disable` / `cull twosided`** = show both sides = Godot `CULL_DISABLED`

**Note on Q3 cull terminology:** "cull front" means "the front side is the visible side" (back faces are culled), NOT "cull the front faces". This is confusing but matches the source code: `CT_FRONT_SIDED` → `glCullFace(GL_BACK)`.

### Sort order

| Value | Name | Usage |
|-------|------|-------|
| 1 | portal | Portal/mirror surfaces |
| 2 | sky | Skybox (drawn after opaque) |
| 3 | **opaque** | Default for shaders without blendFunc |
| 6 | banner | Transparent, close to walls |
| 8 | underwater | Behind normal transparent surfaces |
| 9 | **additive** | Default for shaders WITH blendFunc |
| 16 | nearest | Always in front (muzzle flashes, blobs) |

### Shader stage rendering pipeline

Each stage is a separate rendering pass. The outputs combine cumulatively:

```
Stage 0: map $lightmap → writes to framebuffer (initial lighting data)
Stage 1: map textures/foo.tga + blendFunc filter → modulates with framebuffer
Stage 2: map textures/foo_glow.tga + blendFunc add → adds glow on top
```

Our Godot-side renderer flattens multi-stage shaders into a single `StandardMaterial3D`. The first non-lightmap stage's `map` directive provides the albedo texture. Blend mode and transparency come from that stage's `blendFunc`.

## MOHAA Shader Extensions

**Additional reference:** https://graphics.stanford.edu/courses/cs448-00-spring/q3ashader_manual.pdf (MOHAATools-provided manual)

MOHAA extends the Q3A shader system with ~70+ additional keywords. The real renderer parses these in `renderergl1/tr_shader.c`. Since `R_Init()` is called from `GR_BeginRegistration()`, the real parser handles **all** MOHAA extensions. The `godot_shader_accessors.c` bridge reads the parsed results from `shader_t` structs — no Godot-side shader text parsing is needed.

### Conditional shader blocks (`#if` / `#if_not` / `#else` / `#endif`)

MOHAA's most significant shader extension. Allows conditional shader content based on runtime cvars:
```
textures/foo/bar
{
    #if separate_env
    {
        map textures/foo/bar_env.tga
        tcGen environmentmodel
        blendFunc add
    }
    #else
    {
        map textures/foo/bar_detail.tga
        blendFunc filter
    }
    #endif
}
```
**Conditions:** `separate_env` (true if `r_textureDetails != 0`), literal `0`/`false`, literal `1`/`true`. `#if_not` inverts the result.

**Real renderer behaviour:** The real parser (`tr_shader.c`) evaluates these conditions at shader parse time based on current cvar values. Since `R_Init()` is called, all conditional blocks are resolved by the engine — the `godot_shader_accessors.c` bridge reads the final resolved `shader_t` state.

### MOHAA-specific general (top-level) directives

| Keyword | Parameters | Purpose | Our parser |
|---------|-----------|---------|------------|
| `portalsky` | none | Portal sky shader (`SS_PORTALSKY`) | Partial (sets `is_sky`) |
| `spritegen` | `parallel`\|`parallel_oriented`\|`parallel_upright`\|`oriented` | Billboard sprite type | Recognised, skipped |
| `spritescale` | `<float>` | Sprite scale factor | Recognised, skipped |
| `force32bit` | none | Force 32-bit image loading | Recognised, no-op |
| `noMerge` | none | Prevent surface merging optimisation | Recognised, no-op |

### Additional `sort` values (MOHAA-specific)

| Value | Name | Usage |
|-------|------|-------|
| 5 | `decal` | Decal surfaces (between opaque and banner) |
| 7 | `seeThrough` | See-through surfaces (between banner and underwater) |

### Additional `deformVertexes` subtypes

| Keyword | Parameters | Purpose |
|---------|-----------|---------|
| `lightglow` | none | Light glow effect deformation |
| `flap` | `s`\|`t` `<spread>` `<waveform>` `[min max]` | Flap deformation on S or T texture axis |

### MOHAA surface material types (`surfaceParm`)

These are Q3MAP compile-time flags stored in `surfaceFlags` — used for **impact effects** (bullet sparks, footstep sounds, decal selection), NOT for rendering. The Godot side can read these from BSP surface data to select appropriate effects:

`fence`, `weaponclip`, `vehicleclip`, `ladder`, `paper`, `wood`, `metal`, `rock`, `dirt`, `grill`, `grass`, `mud`, `puddle`, `glass`, `gravel`, `sand`, `foliage`, `snow`, `carpet`, `castshadow`, `nodamage`

### MOHAA-specific stage-level directives

| Category | Keywords | Purpose | Our parser |
|----------|----------|---------|------------|
| **Multi-texture** | `nextBundle [add]` | Multi-texture pass separator (multi-texture unit) | **Yes** |
| **Stage conditionals** | `ifCvar <name> <value>`, `ifCvarnot <name> <value>` | Activate/deactivate stage based on cvar | No |
| **Image loading** | `normalmap <file>`, `clampmapx <file>`, `clampmapy <file>`, `animMapOnce`, `animMapPhase` | Extended image directives | Partial |
| **blendFunc** | `alphaadd` = `GL_SRC_ALPHA GL_ONE` | Alpha-modulated additive blend | **Yes** |
| **alphaFunc** | `LT_FOLIAGE1`, `GE_FOLIAGE1`, `LT_FOLIAGE2`, `GE_FOLIAGE2` | Foliage-specific alpha test thresholds | No |
| **Depth/colour** | `nofog`, `noDepthTest`, `nodepthwrite`/`nodepthmask`, `nocolorwrite`/`nocolormask`, `depthmask` (alias for depthwrite) | Extended render state control | No |

### MOHAA-specific `rgbGen` / `alphaGen` types

**rgbGen additions:** `colorwave (r g b) <wave>`, `global`, `lightingGrid`, `lightingSpherical`, `static`, `sCoord`/`tCoord`, `dot`/`oneMinusDot`, `fromentity` (alias for `entity`), `fromclient` (alias for `vertex`), `oneMinusVertex`

**alphaGen additions:** `global`, `distFade [near range]`, `oneMinusDistFade`, `tikiDistFade`, `oneMinusTikiDistFade`, `dot [min max]`, `oneMinusDot`, `dotView [min max]`, `oneMinusDotView`, `heightFade [min max]`, `lightingSpecular [maxAlpha x y z]`, `skyAlpha`, `oneMinusSkyAlpha`, `sCoord`/`tCoord`, `fromentity`, `fromclient`, `oneMinusFromClient`

### MOHAA-specific `tcGen` / `tcMod` types

**tcGen:** `environmentmodel` (handled), `sunreflection`

**tcMod additions:**
- `offset <s> <t> [randS] [randT]` — static UV offset
- `parallax <rateS> <rateT>` — view-dependent UV parallax
- `macro <scaleS> <scaleT>` — macro-scale UV (stored as 1/value)
- `wavetrans <waveform>` / `wavetrant <waveform>` — wave UV on S/T axis
- `bulge <base> <amp> <freq> <phase>` — UV bulge transform
- `scroll`/`rotate` support `fromEntity` sentinel (speed read from entity at runtime)
- `scroll` extended: `<s> <t> [randS] [randT]` — random offset added to scroll
- `rotate` extended: `<speed> [start] [coef]` — rotation with offset and coefficient

## Renderer Parity Reference

The stub renderer (`godot_renderer.c`) replaces `renderergl1/`. The real renderer does **far more than rendering** — it manages shaders, models, images, fonts, marks, and static model initialisation. Our stub must capture or replicate every piece of data that downstream Godot code needs.

### What `R_FindShader()` actually does (tr_shader.c:3355)
This is the single most important function to understand. It is called hundreds of times per map load.

```
R_FindShader(name, lightmapIndex, mipRawImage, picmip, wrapx, wrapy)
  1. Strip file extension from name
  2. Hash lookup in shader text table (parsed from .shader files)
  3. If shader definition found:
     a. Parse stages (map directives, blend modes, tcMod, alpha, etc.)
     b. Each stage's "map" directive = actual texture file path
     c. Load texture images from VFS
     d. Create shader_t with stages[], image pointers, sort order
  4. If no shader definition found:
     a. Try loading name + ".tga" / ".jpg" / ".png" from VFS
     b. Create implicit shader with single diffuse stage
  5. Return shader_t* (never NULL — returns defaultShader on failure)
```

**How our Godot-side code accesses this data:**
Since `R_Init()` is called from `GR_BeginRegistration()`, the real `R_FindShader()` is available and populates real `shader_t` structs. The `godot_shader_accessors.c` bridge calls `R_FindShader()` / `R_FindShaderByName()` and converts the resulting `shader_t` into a `GodotShaderProps` struct that the Godot side can read.

- `Godot_ShaderProps_Find(name)` → calls `R_FindShaderByName` (cheap lookup), then `R_FindShader` on demand → converts `shader_t` → `GodotShaderProps`
- Texture paths come from `shader_t->unfoggedStages[i]->bundle[0].image[0]->imgName` — the real resolved path, not the shader name
- Blend mode, cull, sort, tcMod, rgbGen, alphaGen — all read from the real parsed `shader_t` stage data

### What `R_InitStaticModels()` actually does (tr_staticmodels.cpp:40)
Called once per map load after BSP parsing. Our code must replicate its effects:

```
R_InitStaticModels()
  For each static model in the BSP:
    1. Resolve TIKI path (prepend "models/" if needed)
    2. Register TIKI via ri.TIKI_RegisterTikiFlags()
    3. For each surface: R_FindShader(surf->shader[k]) → hShader[k]
    4. ri.TIKI_GetSkelAnimFrame() → bone transforms (bind pose)
    5. For each mesh/surface:
       a. Allocate pStaticXyz, pStaticNormal, pStaticTexCoords
       b. For each vertex: read skelWeight_t, transform by bone matrix
       c. Multi-mesh: TIKI_GetLocalChannel() for bone remapping
```

If the Godot side tries to read `surf->pStaticXyz` without step 5, it gets NULL or garbage.

### Stub function audit checklist
When adding or modifying stub renderer functions, verify:

- [ ] **Does the real function compute data?** If yes, our stub must produce equivalent data or provide an accessor.
- [ ] **Does the caller check the return value?** If yes, return a valid handle/pointer, not 0/NULL.
- [ ] **Does the function register resources?** (shaders, models, images) If yes, populate our tables.
- [ ] **Does the function have side effects?** (setting globals, queueing events) If yes, replicate them.
- [ ] **Is the data consumed on the Godot side?** If yes, verify the Godot-side reader matches the stub's output format.

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
| `godot_shader_accessors.c` | C (in `renderergl1/`) | Bridges real `shader_t` → `GodotShaderProps`; uses `R_FindShader()` |

### Adding stubs for unresolved symbols
When linking pulls in new client/UI/renderer symbols, add a no-op stub in `stubs.cpp` with the correct signature. Check `code/null/null_client.c` for reference signatures.

### Real renderer initialisation — R_Init() from GR_BeginRegistration
`GR_BeginRegistration()` (in `godot_renderer.c`) calls `R_Init()` once on first invocation. This bootstraps the **real** renderer subsystems — shader text parsing (`R_StartupShaders`), image loading (`R_InitImages`), model table (`R_ModelInit`), font loading (`R_LoadFont`) — without any OpenGL calls (all GL paths are guarded by `#ifdef GODOT_GDEXTENSION` stubs or `qgl` NULL function pointers).

This means the real `trGlobals_t tr` is populated: `tr.shaders[]`, `tr.numShaders`, `tr.images[]`, `tr.numImages`, `tr.models[]`. The `godot_shader_accessors.c` bridge reads from these real data structures instead of re-parsing `.shader` files.

**Key principle:** If the engine already has a subsystem that parses/loads data (shaders, models, images, fonts), initialise it via `R_Init()` and read from its output — never rewrite the parser on the Godot side.

### Shader accessor bridge — godot_shader_accessors.c
`code/renderergl1/godot_shader_accessors.c` implements the `Godot_ShaderProps_*` API by reading from real `shader_t` structs:
- `Godot_ShaderProps_Load()` — pre-populates a hash cache from `tr.shaders[]`
- `Godot_ShaderProps_Find(name)` — cache lookup → `R_FindShaderByName()` / `R_FindShader()` on demand → converts `shader_t` → `GodotShaderProps`
- `Godot_ShaderProps_GetSkyEnv()` — scans `tr.shaders[]` for `isSky` flag
- `Godot_ShaderProps_GetTextureMap()` — returns first non-lightmap stage texture path

The struct definitions live in `code/godot/godot_shader_props.h` (shared between C and C++ via `typedef`). The old `godot_shader_props.cpp` (1700-line custom parser) is **excluded from the build** in `SConstruct`.

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

Source exclusion filters remove sound backends (DMA, OpenAL, Miles), SDL/OpenGL files, GameSpy samples, old parser duplicates, and `godot_shader_props.cpp` (replaced by the `godot_shader_accessors.c` bridge that reads real `shader_t` data).

**Architecture rule for renderer modules:** The `renderergl1/` source files are compiled into the main `.so`. All OpenGL calls are guarded by `#ifdef GODOT_GDEXTENSION` or use `qgl` NULL function pointers (defined in `tr_godot_gl_stubs.c`). This means the renderer's **data management** code (shader parsing, image loading, model registration) runs correctly — only the actual GL draw calls are stubbed out. New Godot-side code that needs renderer data should read from the real `trGlobals_t tr` structs via accessor files in `renderergl1/`, never by reimplementing the parser.
