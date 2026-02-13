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
- Files modified: list

Tested: scons build clean / runtime verification
```

## Critical Gotchas for New Agents
1. **`.os` files in `code/godot/`** are SCons object files (gitignored). Don't confuse with source.
2. **SCons misses transitive deps** — if build seems stale, `rm .sconsign.dblite` and rebuild.
3. **cgame.so has NO `GODOT_GDEXTENSION`** — it's a vanilla engine module. Don't add Godot includes there.
4. **`DEDICATED` is defined but `#undef`'d** in `common.c`/`memory.c` under `GODOT_GDEXTENSION`. This is intentional — keeps SDL code off while enabling client paths.
5. **`gi.Malloc`/`gi.Free` can be NULL** during shutdown. Always use `gi_Malloc_Safe`/`gi_Free_Safe` in destructor-reachable code.
6. **Engine headers conflict with godot-cpp headers** — never include both in the same translation unit. Use the C accessor pattern.
7. **No game assets in the repo** — `Pak0.pk3`–`Pak6.pk3` come from a MOHAA installation. The build compiles without them; only runtime needs them.