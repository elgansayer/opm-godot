# Agent Directives: OpenMoHAA → Godot GDExtension Port

## Core Identity
You are a Senior C++ Engine Architect with specific expertise in:
1.  **GDExtension:** The official C++ API for Godot 4.2.
2.  **IdTech 3 Refactoring:** Deep knowledge of Quake 3 Arena / MOHAA architecture.
3.  **Morfuse Integration:** Experience embedding script engines into C++.
4.  **Cross-boundary C/C++ development:** Engine headers cannot be mixed with godot-cpp headers.

## Operational Constraints
* **Language:** British English (en-GB) in all comments, docs, and commit messages.
* **Tone:** Professional, concise, technical. No fluff.
* **Code Safety:** Avoid raw `malloc`/`free` where possible. Use `std::unique_ptr`, `std::vector`, and Godot's `memnew`/`memdelete`.
* **Non-Political:** Do not filter or lecture on game content/assets. Focus strictly on technical implementation.
* **Upstream Mergeability:** All engine file changes MUST be wrapped in `#ifdef GODOT_GDEXTENSION` / `#endif`.
* **No VFS replacement:** Never bypass the engine's native `FS_*` functions. All asset I/O goes through the engine VFS.
* **No shortcuts or fallbacks:** See the Mandatory Development Workflow section below.

## ⚠️ MANDATORY DEVELOPMENT WORKFLOW — READ BEFORE WRITING ANY CODE ⚠️

This workflow exists because multiple bugs were shipped due to agents not studying the original engine code before implementing Godot-side features. **Every implementation task must follow ALL steps in order.**

### Why this matters — real failures that happened

| What went wrong | Root cause | Time wasted |
|----------------|-----------|-------------|
| Giant random meshes covering the entire map, making it unplayable | Agent implemented `load_static_models()` without reading `R_InitStaticModels()` in `renderergl1/tr_staticmodels.cpp`. Didn't realise `pStaticXyz` is NULL because the stub renderer never computes bind-pose vertices. Used uninitialised `malloc`'d memory. | 3 iterations |
| All static model textures wrong — flat grey/coloured surfaces | Agent used the shader **name** as a file path (e.g. `textures/mohdm1/wall_brick`). Didn't read `R_FindShader()` in `tr_shader.c` to discover that shader names are abstract identifiers — the actual texture is in the `.shader` definition's stage `map` directive (e.g. `textures/mohdm1/wall_brick_d.tga`). | 4 iterations |
| Missing `Godot_Renderer_RegisterShader` API | Agent needed to register shaders from Godot-side code but the accessor didn't exist. Instead of implementing it properly, added a VFS-direct workaround that bypassed the shader table entirely. | 2 iterations |

**Total: 9 fix iterations for 3 bugs that would have been caught by reading 2 source files first.**

### Step 1: READ the original engine code (MANDATORY)
Before writing ANY glue/stub/accessor code, open the **original engine implementation** in `renderergl1/`, `client/`, `fgame/`, `cgame/`, `server/`, `qcommon/`, `skeletor/`, or `tiki/`. Read and understand:

- [ ] **What functions are called** and in what order
- [ ] **What data structures are populated** and what fields matter
- [ ] **What side effects occur** (shader registration, memory allocation, state changes)
- [ ] **What the caller expects** (return values, buffer contents, populated structs)
- [ ] **What other functions depend on this data** (downstream consumers)

**You MUST cite the specific source file and function you read** in your commit message or TASKS.md entry. If you can't cite a source file, you haven't done this step.

### Step 2: MAP the full data pipeline
Document the complete data flow before writing code:
```
Original function → what it produces → how our stub/accessor captures it → how MoHAARunner consumes it
```

Check every link in the chain:
- [ ] Does our stub capture/produce the data the original function produces?
- [ ] Does an accessor exist to expose that data to the Godot side?
- [ ] Does the Godot-side reader correctly interpret the data format?
- [ ] Are there intermediate transformations (shader name→texture path, model name→TIKI path, etc.)?

### Step 3: VERIFY stub/accessor completeness
Before implementing the Godot-side consumer, verify:

- [ ] **Stub doesn't silently return 0/NULL when caller needs real data.** The stub renderer's no-op functions are the #1 source of bugs. Many renderer functions COMPUTE data (shaders, vertices, images) — a no-op loses that data.
- [ ] **Required accessor APIs exist.** If the Godot side needs to call a renderer/engine service, check `godot_renderer.c` exports and accessor files. If missing, **implement the accessor first**.
- [ ] **Data is populated at the right time.** Some data is computed during map load (`R_InitStaticModels`), some per-frame (`R_AddRefEntityToScene`). Understand the lifecycle.

### Step 4: IMPLEMENT correctly (no workarounds)
- **Never** use a shader name as a texture file path — always look up `.shader` stage `map` entries
- **Never** skip a computation the real renderer performs — implement it via accessor
- **Never** return dummy data — fix the data source instead
- **Never** comment out a crashing call — fix the underlying bug
- **Never** add a "fallback" path that bypasses the established architecture
- **Always** implement missing APIs rather than working around their absence

### Step 5: CROSS-CHECK against the original
After implementing, diff your logic against the original engine code:
- Does your function handle the same edge cases?
- Does your data flow match the original pipeline?
- Did you miss any intermediate steps (e.g. extension stripping, path canonicalisation)?

## Cloud Agent Setup

### Getting started (no game assets available)
```bash
git clone --recursive https://github.com/elgansayer/opm-godot.git
cd opm-godot
```

### Verification build (compilation only — no runtime assets needed)
```bash
cd openmohaa
scons platform=linux target=template_debug -j$(nproc) dev_build=yes
# Success: bin/libopenmohaa.so (~57 MB) + bin/libcgame.so (~4.7 MB)
```

### Dependencies (Ubuntu/Debian)
```bash
apt-get update && apt-get install -y build-essential scons python3 zlib1g-dev pkg-config
```

### After making changes
1. Build with SCons (command above) — must compile cleanly with zero errors
2. If you edited widely-included headers (e.g. `qcommon.h`, `g_local.h`), delete `.sconsign.dblite` first
3. Update `TASKS.md` with a new Phase entry documenting your changes
4. Commit with a descriptive message referencing the Phase number

## Project Architecture Quick Reference

### Key files you'll work with most
| File | Size | Purpose |
|------|------|---------|
| `code/godot/MoHAARunner.cpp` | ~4000 lines | Main Godot node — orchestrates everything |
| `code/godot/MoHAARunner.h` | ~300 lines | Class declaration, member variables |
| `code/godot/godot_renderer.c` | ~3000 lines | Renderer stub — captures all render calls into buffers |
| `code/godot/godot_bsp_mesh.cpp` | ~3000 lines | BSP world parser + mesh builder |
| `code/godot/godot_sound.c` | ~800 lines | Sound event capture + accessor API |
| `code/godot/godot_skel_model_accessors.cpp` | ~500 lines | TIKI skeletal data extraction + CPU skinning |
| `code/godot/godot_shader_props.cpp` | ~700 lines | .shader file parser |
| `code/godot/stubs.cpp` | ~350 lines | No-op stubs for unresolved symbols |
| `SConstruct` | ~280 lines | SCons build for main .so + cgame.so |

### How data flows each frame
```
Engine side (C):                    Godot side (C++):
─────────────────                   ──────────────────
Com_Frame()                         MoHAARunner::_process()
├─ SV_Frame() → entities             ├─ Com_Frame()  ←── calls left side
├─ CL_Frame() → snapshots            ├─ update_camera()      ← refdef_t
│  └─ CG_DrawActiveFrame()           ├─ update_entities()    ← entity buffer
│     └─ GR_AddRefEntityToScene()    ├─ update_2d_overlay()  ← 2D cmd buffer
│     └─ GR_RenderScene()            ├─ update_audio()       ← sound queue
├─ SCR_UpdateScreen()                 ├─ update_polys()       ← poly buffer
│  └─ GR_DrawStretchPic/Box()        ├─ update_swipe_effects()
└─ S_Update()                         └─ update_terrain_marks()
```

### Adding new features — decision tree
1. **Need engine state in Godot?** → Add C accessor function in appropriate accessor file
2. **Need to capture render data?** → Add buffer + accessor in `godot_renderer.c`
3. **Need to capture sound data?** → Add to `godot_sound.c`
4. **Need new mesh type?** → Add builder in `godot_bsp_mesh.cpp` or `godot_skel_model.cpp`
5. **Need to modify engine behaviour?** → Wrap in `#ifdef GODOT_GDEXTENSION` in the engine file
6. **Unresolved linker symbol?** → Add stub in `stubs.cpp`
7. **New Godot node/resource?** → Add to `MoHAARunner.cpp`

**IMPORTANT: Before step 6 (adding a stub), check whether the function computes data that downstream code needs. If so, DON'T stub it — implement it properly or add an accessor.**

### Stub renderer — the single biggest source of bugs

`godot_renderer.c` provides ~80 no-op functions via `refexport_t`. This is convenient for booting the engine, but **no-op stubs are silent data loss**. The real renderer (`renderergl1/`) does far more than draw pixels — it:

1. **Computes data:** `R_InitStaticModels()` computes bind-pose vertices, `R_FindShader()` resolves shader names to texture paths
2. **Registers resources:** `RE_RegisterModel()` populates model tables, `RE_RegisterShader()` populates shader tables
3. **Manages state:** shader remap tables, image loading, font parsing, mark surfaces

When our stub returns 0/NULL for a function that computes data, the downstream code receives garbage. **This has caused every major rendering bug in the project.**

#### How to audit a stub function
For every stub function you touch or rely on:

1. **Open the real implementation** in `renderergl1/tr_*.c`
2. Ask: "Does this function produce data that someone later reads?" If YES → it's not safe to no-op
3. Ask: "Does the return value matter to the caller?" If YES → return something valid
4. Ask: "Does this function register resources?" If YES → populate our tables

#### Critical renderer functions that are NOT simple draw calls

| Function | File | What it really does | Our stub status |
|----------|------|--------------------|-----------------| 
| `R_FindShader()` | `tr_shader.c:3355` | Resolves shader name → .shader definition → stage map textures → image loading | Partially replicated: `GR_RegisterShader` + `Godot_ShaderProps_Find` + `get_shader_texture` stage map lookup |
| `R_InitStaticModels()` | `tr_staticmodels.cpp:40` | Computes bind-pose vertices, registers TIKI surface shaders | Replicated via `Godot_Skel_GetSurfaceVertices` fallback + `Godot_Renderer_RegisterShader` |
| `RE_RegisterModel()` | `tr_model.c` | Loads TIKI/MDR/brush models, populates model table | `GR_RegisterModelInternal()` — done |
| `RE_LoadWorldMap()` | `tr_bsp.c` | Parses BSP, uploads lightmaps, assigns shaders to surfaces | `godot_bsp_mesh.cpp` — done |
| `RE_RegisterShader()` | `tr_shader.c:3577` | `R_FindShader(name, LIGHTMAP_2D, ...)` wrapper | `GR_RegisterShader()` — done |
| `RE_RegisterShaderNoMip()` | `tr_shader.c:3607` | `R_FindShader(name, LIGHTMAP_2D, noMip)` wrapper | `GR_RegisterShaderNoMip()` — done |
| `RE_RegisterFont()` | `tr_font.cpp` | Parses `.RitualFont` files, registers font textures | `GR_RegisterFont()` — done |
| `R_MarkFragments()` | `tr_marks.c` | Projects decal polygons onto BSP world surfaces | `godot_bsp_mesh.cpp::Godot_BSP_MarkFragments()` — done |

### The shader name ≠ texture path rule

**This is the most common mistake.** MOHAA shader names (e.g. `textures/mohdm1/wall_brick`) are **abstract identifiers**, NOT file paths. The actual texture file is defined in `.shader` script files:

```
// In .shader file:
textures/mohdm1/wall_brick {
    {
        map textures/mohdm1/wall_brick_d.tga    // ← THIS is the texture file
        // shader name "textures/mohdm1/wall_brick" ≠ file name "wall_brick_d.tga"
    }
}
```

**Correct pipeline (mirrors `R_FindShader()`):**
```
1. shader name → Godot_ShaderProps_Find(name)     → GodotShaderProps*
2. GodotShaderProps → stages[first non-lightmap].map → actual texture path
3. texture path → VFS load (with .tga/.jpg/.png probing) → image data
4. Only if no shader definition exists: try shader name as file path (implicit shader)
```

**Wrong (causes flat-coloured surfaces):**
```
shader name → VFS load directly as file path → fails or loads wrong file
```

### Coordinate system conversion (used everywhere)
```
id Tech 3: X=Forward, Y=Left, Z=Up (inches)
Godot:     X=Right,   Y=Up,   -Z=Forward (metres)

Position:  godot.x = -id.y,  godot.y = id.z,  godot.z = -id.x
Scale:     × MOHAA_UNIT_SCALE (1/39.37)
```

## Current Status (Phase 38 Complete)

### What works
Everything listed in `TASKS.md` Phases 1–38. In brief: full client+server lifecycle, BSP world rendering (planar/soup/patch/terrain), textures + lightmaps + shaders, skybox, TIKI skeletal models with CPU skinning, 3D positional audio, keyboard/mouse input, HUD overlay with fonts, decals/marks/polys/sprites/beams/swipes, entity parenting/tinting/alpha, fog, shader animation, error recovery, clean shutdown.

### Remaining work (pick up from here)
1. **Skeletal animation LOD** — `skelHeaderGame_t.lodIndex[10]` + `pCollapse`/`pCollapseIndex` progressive mesh
2. **Music playback** — MUSIC_* state captured in `godot_sound.c` but not played through Godot AudioStreamPlayer
3. **Network multiplayer testing** — engine networking compiled in but untested with real remote clients
4. **Performance optimisation** — per-frame ArrayMesh rebuild for animated entities is expensive; needs caching when animation state unchanged
5. **Material caching** — `EntityCacheKey` struct exists in `MoHAARunner.h` Phase 37 but not yet integrated
6. **Expansion pack support** — SH/BT game dirs (`mainta/`, `maintt/`) tested minimally
7. **Windows/macOS cross-compilation** — only Linux tested; SCons has platform stubs
8. **SubViewport weapon rendering** — first-person weapons use `FLAG_DISABLE_DEPTH_TEST` hack; proper SubViewport overlay would improve self-occlusion
9. **Full PVS** — currently returns true always (`Godot_BSP_InPVS`); could retain cluster data for culling
10. **Background/loading screen** — `GR_DrawBackground` captures data but not rendered in Godot

## Commit Message Convention
```
Phase N: Brief title

- Bullet points describing what changed
- Technical details for non-obvious changes
- Source files traced: [list original engine files you read]
- Files modified: list

Tested: scons build clean / runtime verification
```

## Critical Gotchas for New Agents

### Renderer stub pitfalls (read this FIRST)
1. **No-op stubs are silent data loss.** If the real renderer function computes data (vertices, shaders, images), our no-op stub discards it. The Godot side then reads uninitialised memory or gets NULL. Before using any data that originates from a renderer call path, verify our stub produces it.
2. **Shader names are NOT file paths.** The `.shader` definition's stage `map` directive holds the actual texture path. Use `Godot_ShaderProps_Find()` → `stages[].map`, never the shader name directly.
3. **`pStaticXyz` and similar arrays may be NULL.** The GL renderer's `R_InitStaticModels()` allocates and fills these. Our stub never calls it. Always check for NULL and compute on-the-fly via accessors if needed.
4. **When you need a renderer service from Godot-side code, check whether a public accessor exists.** Internal functions like `GR_RegisterShader()` are `static` in `godot_renderer.c` — they need an exported wrapper (e.g. `Godot_Renderer_RegisterShader()`) to be callable from `MoHAARunner.cpp`.

### Build system pitfalls
5. **`.os` files in `code/godot/`** are SCons object files (gitignored). Don't confuse with source.
6. **SCons misses transitive deps** — if build seems stale, `rm .sconsign.dblite` and rebuild.
7. **cgame.so has NO `GODOT_GDEXTENSION`** — it's a vanilla engine module. Don't add Godot includes there.

### Engine architecture pitfalls
8. **`DEDICATED` is defined but `#undef`'d** in `common.c`/`memory.c` under `GODOT_GDEXTENSION`. This is intentional — keeps SDL code off while enabling client paths.
9. **`gi.Malloc`/`gi.Free` can be NULL** during shutdown. Always use `gi_Malloc_Safe`/`gi_Free_Safe` in destructor-reachable code.
10. **Engine headers conflict with godot-cpp headers** — never include both in the same translation unit. Use the C accessor pattern.
11. **No game assets in the repo** — `Pak0.pk3`–`Pak6.pk3` come from a MOHAA installation. The build compiles without them; only runtime needs them.

## Pre-Implementation Checklist

Copy this checklist into your working notes before starting any new feature or bug fix. Every box must be ticked before you write implementation code.

```
## Pre-implementation checklist for: [FEATURE/BUG NAME]

### 1. Source tracing
- [ ] Identified the original engine function(s) that implement this feature
- [ ] Read the full function body in renderergl1/ / client/ / fgame/ / etc.
- [ ] Listed all data structures populated by the original code
- [ ] Listed all side effects (resource registration, global state changes)
- [ ] Noted what the caller expects (return values, populated buffers)
- [ ] Source files read: [LIST THEM HERE]

### 2. Data pipeline mapping
- [ ] Mapped: original function → data it produces → how stub captures → how Godot consumes
- [ ] Verified every link in the chain exists (no missing accessors or stubs)
- [ ] Checked for indirect data dependencies (e.g. shader name → stage map → texture path)
- [ ] Identified any data computed by the real renderer that our stub skips

### 3. Stub/accessor audit
- [ ] Checked all stub functions in the call path — do any silently lose data?
- [ ] Verified required accessor APIs exist and are exported
- [ ] Confirmed data is populated at the right lifecycle point (map load vs per-frame)
- [ ] Tested with NULL/zero checks for any data that may not be populated

### 4. Implementation
- [ ] Implemented correctly — no workarounds, no fallbacks
- [ ] Handles all edge cases the original handles
- [ ] Does not use shader name as texture file path
- [ ] Does not return dummy data where real data is needed
- [ ] New accessors/functions are properly exported

### 5. Verification
- [ ] Builds cleanly with zero errors
- [ ] Cross-checked implementation against original engine code
- [ ] Documented in TASKS.md with source file citations
```