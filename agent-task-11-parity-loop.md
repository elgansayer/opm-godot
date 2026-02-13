# Agent Task 11: Continuous Parity Verification & Completion Loop

## Objective
You are the **parity completion agent**. Your single mission: ensure this Godot GDExtension port is a **complete, 1:1 functional replacement** for OpenMoHAA — both client and server. You will be run **repeatedly**. Each run, you must:

1. **Audit** the current state of the port against what upstream OpenMoHAA can do
2. **Identify** the highest-impact gap or deficiency
3. **Fix it** — implement the missing feature, fix the bug, or improve the fidelity
4. **Build & verify** — ensure it compiles cleanly
5. **Document** what you did in `openmohaa/TASKS.md`
6. **Report** what you fixed and what the next highest-priority gap is

If after thorough audit you genuinely cannot find anything to improve, say so explicitly: **"PARITY COMPLETE — no further gaps identified."** Until then, always find and fix something.

---

## How to Work — Every Single Run

### Step 1: Read the current state
```
Read these files FIRST, every time:
  .github/copilot-instructions.md    — project architecture, conventions, what works
  openmohaa/AGENTS.md                — agent directives, gotchas
  openmohaa/TASKS.md                 — what has been implemented (scroll to the END)
```

### Step 2: Audit against OpenMoHAA capabilities
Compare the port's current state against this **complete feature checklist** of what OpenMoHAA does. Find the first unchecked item or an item marked done that is actually broken/incomplete.

### Step 3: Pick ONE high-impact task
Choose the single most impactful gap. Prefer:
- Things that crash or break over things that are cosmetic
- Things that block gameplay over things that affect polish
- Things that affect both client and server over client-only features
- Compilation fixes over runtime fixes (can't test what doesn't build)

### Step 4: Implement the fix
Follow all project conventions:
- `#ifdef GODOT_GDEXTENSION` guards on all engine file changes
- C accessor pattern for engine state (never mix engine + godot-cpp headers)
- New files in `code/godot/` are auto-discovered by SConstruct
- No raw `malloc`/`free` in new C++ code
- British English (en-GB) in comments

### Step 5: Build
```bash
cd openmohaa && rm -f .sconsign.dblite && scons platform=linux target=template_debug -j$(nproc) dev_build=yes
```
Fix any errors before proceeding. Do NOT leave a broken build.

### Step 6: Document in TASKS.md
Append a new Phase entry at the end of `openmohaa/TASKS.md` with:
- Phase number (increment from the last one)
- What was implemented/fixed
- Files created/modified
- Key technical details
- What remains (next priority)

### Step 7: Report
End your response with:
```
## Status
FIXED: <one-line summary of what you did>
NEXT PRIORITY: <the next most important gap>
REMAINING GAPS: <count of known remaining gaps>
```

---

## Complete OpenMoHAA Feature Checklist

Use this as your audit reference. Every item here is something upstream OpenMoHAA does. Check the codebase to see if the port handles it correctly.

### Engine Lifecycle
- [ ] `Com_Init()` completes without errors
- [ ] `Com_Frame()` runs each tick without crashes
- [ ] `Com_Shutdown()` cleans up without leaks or segfaults
- [ ] `Com_Error(ERR_DROP)` recovers gracefully (returns to menu)
- [ ] `Com_Error(ERR_FATAL)` / `Sys_Error` recovers without killing Godot
- [ ] `Sys_Quit` exits cleanly
- [ ] Signal handlers (SIGSEGV, SIGTERM, etc.) don't kill the host process
- [ ] Global C++ destructors don't crash at exit
- [ ] `Z_MarkShutdown()` prevents allocator crashes during teardown
- [ ] Library can be loaded, used, and unloaded multiple times

### VFS & Asset Loading
- [ ] pk3 archives mount correctly from `fs_basepath`/`fs_homedatapath`
- [ ] Search path ordering: loose files > higher-numbered pk3 > lower-numbered pk3
- [ ] `com_basegame` ("main") and `com_target_game` (0=AA, 1=SH, 2=BT) select correct dirs
- [ ] `fs_game` override works for mods
- [ ] `.cfg` config files load from correct paths
- [ ] `.scr` script files load and compile
- [ ] `.tik` TIKI files parse correctly
- [ ] `.shader` files parse all stages (multi-stage, animMap, tcMod, tcGen, rgbGen, alphaGen, deformVertexes)
- [ ] BSP files load (all lump types: vertices, surfaces, patches, terrain, fogs, entities, visdata, lightgrid, lightmaps)
- [ ] Texture loading: TGA, JPG, BMP from pk3
- [ ] WAV audio loading (PCM and MP3-in-WAV format tag 0x0055)
- [ ] MP3 audio loading (music files)
- [ ] RoQ cinematic files (at minimum: graceful skip without crash)
- [ ] `ubersound.scr` / `uberdialog.scr` sound alias parsing

### Rendering — World
- [ ] BSP planar surfaces with correct UVs and lightmaps
- [ ] BSP triangle soup surfaces
- [ ] BSP Bézier patch surfaces (tessellated)
- [ ] BSP terrain surfaces (heightmap-based)
- [ ] Lightmap rendering (128×128 per surface, overbright multiply)
- [ ] Lightgrid sampling for entity ambient lighting
- [ ] Skybox from sky shader (6-face cubemap)
- [ ] Global fog (`fogparms` in worldspawn shader)
- [ ] Per-surface fog volumes (LUMP_FOGS)
- [ ] Fullbright surfaces (`surfaceparm nolightmap`)
- [ ] Vertex-lit surfaces (vertex colour only, no lightmap)
- [ ] Portal/mirror surfaces (at minimum: visible, not invisible)
- [ ] Flare surfaces (`MST_FLARE`)
- [ ] Water surfaces with transparency
- [ ] PVS (Potentially Visible Set) culling from BSP visdata
- [ ] Frustum culling for surfaces and entities
- [ ] Correct draw order: opaque front-to-back, transparent back-to-front, additive last

### Rendering — Shaders
- [ ] Single-stage shaders (base texture + blend mode)
- [ ] Multi-stage shaders (base + lightmap + detail, composited)
- [ ] `blendFunc` (all GL blend factor combinations)
- [ ] `tcMod scroll` — scrolling UVs
- [ ] `tcMod rotate` — rotating UVs
- [ ] `tcMod scale` — scaled UVs
- [ ] `tcMod turb` — turbulent UVs (water, fire)
- [ ] `tcMod stretch` — pulsing UV scale
- [ ] `tcGen environment` — environment mapping (view-dependent UVs)
- [ ] `tcGen lightmap` — lightmap UV channel
- [ ] `tcGen vector` — arbitrary UV projection
- [ ] `animMap` — animated texture sequences
- [ ] `rgbGen identity` / `identityLighting` / `vertex` / `entity` / `oneMinusEntity` / `lightingDiffuse`
- [ ] `rgbGen wave` — colour pulsing (sin, triangle, square, sawtooth, inversesawtooth)
- [ ] `alphaGen portal` / `entity` / `oneMinusEntity` / `vertex`
- [ ] `alphaGen wave` — alpha pulsing
- [ ] `deformVertexes autosprite` — camera-facing billboards
- [ ] `deformVertexes autosprite2` — axis-aligned billboards
- [ ] `deformVertexes wave` — sinusoidal vertex displacement
- [ ] `deformVertexes bulge` — surface bulging
- [ ] `deformVertexes move` — vertex translation
- [ ] `surfaceparm trans` — transparent surfaces
- [ ] `surfaceparm alphashadow` — alpha-tested shadows
- [ ] `cull front` / `cull back` / `cull disable` (two-sided)
- [ ] `sort` — explicit sort key for shader draw order
- [ ] Gamma correction (`r_gamma`) applied correctly
- [ ] Overbright bits (`r_overbrightBits`) on lightmaps

### Rendering — Entities
- [ ] TIKI skeletal models load and display (SKD/SKC/SKB data)
- [ ] CPU skinning with bone transforms
- [ ] Multi-channel animation blending (`frameInfo[4]` with weights)
- [ ] Animation LOD (distance-based vertex collapse via `lodIndex`/`pCollapse`)
- [ ] Brush sub-models (doors, movers, platforms) from BSP inline models
- [ ] Sprite entities (`RT_SPRITE`) — billboarded quads
- [ ] Beam entities (`RT_BEAM`) — line between two points
- [ ] Entity colour tinting (`shaderRGBA`)
- [ ] Entity alpha transparency
- [ ] Entity `RF_FIRST_PERSON` — only visible in first-person view
- [ ] Entity `RF_THIRD_PERSON` — only visible in third-person
- [ ] Entity `RF_DEPTHHACK` — weapon depth hack for first-person weapons
- [ ] Entity `RF_LIGHTING_ORIGIN` — sample lighting from different position
- [ ] Entity `RF_SHADOW` — shadow blob projection
- [ ] Entity parenting (attached to other entities via bone tags)
- [ ] Dynamic lights (`gr_dlights[]`) affecting entities
- [ ] Mesh caching for animated entities (avoid per-frame rebuild when unchanged)
- [ ] Material caching (share materials across same-shader entities)

### Rendering — Effects
- [ ] Polygon effects (`GR_AddPolyToScene`) — fan polygons for particles/effects
- [ ] Swipe trails (sword/knife trail geometry)
- [ ] Mark fragments / decals on BSP surfaces (bullet holes, blood splats)
- [ ] Terrain marks (decals on terrain surfaces)
- [ ] Impact effects per surface type (metal sparks, wood chips, dirt puffs, etc.)
- [ ] Explosion effects (fireball, smoke, debris)
- [ ] Muzzle flash (sprite + dynamic light)
- [ ] Bullet tracers (stretched quads along trajectory)
- [ ] Shell casing ejection
- [ ] Blood spray on hit
- [ ] Screen damage flash (red tint overlay)
- [ ] Underwater colour tint
- [ ] Rain weather particles
- [ ] Snow weather particles
- [ ] Dust/smoke environmental particles

### Rendering — 2D / HUD
- [ ] HUD health, ammo, compass rendering
- [ ] Crosshair rendering
- [ ] Font rendering (`.RitualFont` files)
- [ ] 2D textured quads (`GR_DrawStretchPic`)
- [ ] 2D solid rectangles (`GR_DrawBox`)
- [ ] 2D string rendering
- [ ] Centre-print messages (objectives, hints)
- [ ] Kill feed / obituary messages
- [ ] Chat messages
- [ ] Scoreboard display
- [ ] Loading screen (background + progress bar + tips)
- [ ] Console overlay (drop-down, text history, input line)
- [ ] Menu backgrounds
- [ ] Cinematic display (RoQ playback or graceful skip)
- [ ] Letterbox / cinematic bars

### Audio
- [ ] PCM WAV playback (mono, stereo, 8-bit, 16-bit)
- [ ] MP3-in-WAV decoding (format tag 0x0055)
- [ ] 3D positional audio (`S_StartSound` with entity origin)
- [ ] 2D local audio (`S_StartLocalSound`)
- [ ] Looping sounds (`S_AddLoopingSound` / `S_StopLoopingSound`)
- [ ] Sound distance attenuation
- [ ] Sound entity tracking (follows entity position)
- [ ] Sound channel priority (evict lowest priority when full)
- [ ] Music playback (MP3 from `sound/music/`)
- [ ] Music state machine (play, stop, pause, crossfade, volume)
- [ ] Sound aliases / ubersound system (alias → file mapping, random selection)
- [ ] Speaker entity sounds (`func_speaker`)
- [ ] Sound occlusion (basic — through BSP walls)
- [ ] Sound volume cvars (`s_volume`, `s_musicvolume`)
- [ ] Audio listener position driven by camera

### Input
- [ ] Keyboard key mapping (all keys including special: F1-F12, arrows, numpad, etc.)
- [ ] Mouse buttons (left, right, middle, wheel up/down, mouse4/5)
- [ ] Mouse relative motion for look/aim
- [ ] Character input for console/chat (`SE_CHAR` events)
- [ ] Mouse capture/release toggling
- [ ] `KEYCATCH_GAME` — input to game
- [ ] `KEYCATCH_UI` — input to menu system
- [ ] `KEYCATCH_CONSOLE` — input to console
- [ ] `KEYCATCH_CGAME` — input to client game
- [ ] Key binding system (`bind <key> <command>`)
- [ ] Mouse sensitivity (`sensitivity` cvar)
- [ ] Mouse invert (`m_pitch` negative)

### UI / Menus
- [ ] Main menu display (`.urc` UI Resource files)
- [ ] Menu input (mouse + keyboard navigation)
- [ ] Mouse cursor rendering (custom cursor texture)
- [ ] Server browser (GameSpy query, server list, connect)
- [ ] Options: video, audio, controls, game, network
- [ ] Key binding menu (press-a-key capture)
- [ ] Team selection menu (Allies/Axis/Auto/Spectator)
- [ ] Weapon selection menu
- [ ] Create server menu
- [ ] Quit confirmation dialog
- [ ] Disconnect confirmation dialog
- [ ] Message of the Day (MOTD)
- [ ] UI sound effects (click, hover)

### Game Logic — Server Side
- [ ] Player spawn at correct spawn points
- [ ] Player movement: walk, run, sprint, crouch, prone, jump, lean
- [ ] Weapon fire, reload, switch, drop, pickup
- [ ] Weapon spread, recoil, damage, range
- [ ] Melee attacks (knife, bayonet)
- [ ] Hitscan weapon traces through BSP + entities
- [ ] Area damage (grenades, explosions, artillery)
- [ ] Locational damage (headshot multiplier, limb damage)
- [ ] Health packs, ammo pickups
- [ ] `trigger_*` entities (hurt, push, teleport, relay, once, multiple, use)
- [ ] `func_door` — open/close with collision
- [ ] `func_rotating` — rotating brushes
- [ ] `func_plat` — elevator platforms
- [ ] `func_train` — path-following movers
- [ ] `func_breakable` — destructible objects
- [ ] `func_speaker` — ambient sound emitters
- [ ] `info_player_start` / `info_player_deathmatch` etc.
- [ ] `path_*` waypoint entities
- [ ] `script_*` entities (script_origin, script_model, script_object)
- [ ] Worldspawn settings (gravity, ambient sound, farplane)
- [ ] Entity parenting and attachment
- [ ] Entity state synchronisation to clients

### Game Logic — Script Engine
- [ ] Morfuse script compilation from `.scr` files
- [ ] Script execution: `thread`, `waitthread`, `end`
- [ ] Event system: `waittill`, `notify`, `waittill animdone`
- [ ] All built-in script commands execute correctly
- [ ] Script-driven entity spawning and modification
- [ ] Timer/wait accuracy (`wait`, `waitframe`)
- [ ] Complex thread management (nested waits, thread counts)
- [ ] `ubersound.scr` and `uberdialog.scr` processing

### Game Modes
- [ ] Free For All (deathmatch)
- [ ] Team Deathmatch
- [ ] Objective mode
- [ ] Liberation mode
- [ ] Demolition mode
- [ ] Round-based logic (round restart, warmup, overtime)
- [ ] Score tracking and limits (frag limit, time limit)
- [ ] Map rotation (`sv_mapRotation`)
- [ ] Vote system (`callvote`, `vote`)

### Single Player
- [ ] Campaign progression (mission → next mission)
- [ ] Mission briefing display
- [ ] Scripted cutscenes / camera sequences
- [ ] AI companion pathfinding and combat
- [ ] Objective completion tracking
- [ ] Checkpoint / save game
- [ ] Difficulty levels (`skill` cvar)

### Networking
- [ ] UDP socket creation and management
- [ ] Server hosting (listen server + dedicated server)
- [ ] Client connection flow (challenge → connect → gamestate → snapshot)
- [ ] Delta-compressed entity snapshots
- [ ] Client prediction (`CL_PredictPlayerState`)
- [ ] Prediction error correction
- [ ] Lag compensation (`sv_antilag`)
- [ ] Reliable command delivery
- [ ] Configstring updates
- [ ] Userinfo sending/receiving
- [ ] Master server registration (GameSpy heartbeats)
- [ ] Server browser queries and responses
- [ ] RCON (remote console) authentication and commands
- [ ] Timeout and disconnect handling
- [ ] Rate limiting (`rate`, `snaps`, `cl_maxpackets`)
- [ ] Spectator mode (free-fly, follow)
- [ ] All 3 game versions compatible (AA, SH, BT protocols)

### Expansion Pack Support
- [ ] Spearhead (`mainta/`) — pk3 loading, game dir selection
- [ ] Breakthrough (`maintt/`) — pk3 loading, game dir selection
- [ ] `com_target_game` cvar selects correct expansion
- [ ] Expansion-specific entities and weapons

### Platform Support
- [ ] Linux x86_64 — builds and runs
- [ ] Windows x86_64 — builds and runs
- [ ] macOS x86_64/arm64 — builds and runs

### Stability & Performance
- [ ] No crashes during normal 30-minute play session
- [ ] No memory leaks (stable RSS over time)
- [ ] 60+ FPS on mid-range hardware
- [ ] Map load time < 30 seconds
- [ ] Memory usage < 1 GB during gameplay
- [ ] All 54 stock maps load without errors
- [ ] Clean shutdown: no segfault, no hang, no zombie process

---

## File Ownership Rules

You may modify ANY file in the project. However, prefer this approach:
1. **New features** → create new files in `code/godot/`
2. **Engine fixes** → `#ifdef GODOT_GDEXTENSION` guards in engine files
3. **Integration** → modify `MoHAARunner.cpp` / `MoHAARunner.h`
4. **Build fixes** → modify `SConstruct`
5. **Stubs** → append to `stubs.cpp`

If you see work done by other agents (files like `godot_music.cpp`, `godot_vfx.cpp`, etc.), integrate and build on their work rather than replacing it.

## When You Find Nothing To Fix
If after thoroughly auditing every section of the checklist above you cannot find any gap, missing feature, bug, or improvement:

```
## Status
PARITY COMPLETE — no further gaps identified.
All OpenMoHAA client and server features are implemented and functional.
Build compiles cleanly. All checklist items verified.
```

Only say this when you are GENUINELY confident. If in doubt, dig deeper.

## Build & Test
```bash
cd openmohaa && rm -f .sconsign.dblite && scons platform=linux target=template_debug -j$(nproc) dev_build=yes
```

## Key References
- `.github/copilot-instructions.md` — full architecture docs
- `openmohaa/AGENTS.md` — agent conventions and gotchas  
- `openmohaa/TASKS.md` — implementation log (READ THE END for latest state)
- `code/godot/` — all Godot glue code
- `code/client/` — upstream client code (reference for expected behaviour)
- `code/fgame/` — upstream game logic (reference for entity/script behaviour)
- `code/cgame/` — upstream client game (reference for effects/HUD/view)
- `code/qcommon/` — core engine (reference for VFS, networking, memory)
