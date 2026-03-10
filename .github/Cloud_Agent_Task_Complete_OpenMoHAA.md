# Cloud Agent Task: Complete OpenMoHAA → Godot Port

## Objective
Continue building the OpenMoHAA-to-Godot GDExtension port until we have a **fully playable, 1:1 compatible** MOHAA client and server running entirely within Godot 4.2. The final product must:

1. Launch and play Medal of Honor: Allied Assault single-player campaigns (AA, Spearhead, Breakthrough)
2. Host and join multiplayer servers compatible with existing OpenMoHAA clients
3. Connect to existing OpenMoHAA servers as a client
4. Load all original assets (pk3, BSP, TIK, SCR, shader, WAV, MP3) identically to upstream OpenMoHAA
5. Render at visual parity with the OpenMoHAA GL1 renderer
6. Play all audio (effects, music, voice, ambient) at parity
7. Support full game UI (main menu, server browser, options, loading screens)

## Starting Point
Phases 1–38 are complete. Read `.github/copilot-instructions.md` and `openmohaa/TASKS.md` for full context. Read `openmohaa/AGENTS.md` for agent-specific directives.

## How to Work
1. **Read the instructions first:** `.github/copilot-instructions.md`, `openmohaa/AGENTS.md`, `openmohaa/TASKS.md`
2. **Build after every change:** `cd openmohaa && scons platform=linux target=template_debug -j$(nproc) dev_build=yes`
3. **If build fails**, fix it before moving on. Delete `.sconsign.dblite` if headers changed.
4. **Document each phase** in `openmohaa/TASKS.md` with the same format as existing phases.
5. **Commit after each phase** with message format: `Phase N: Brief description`
6. **All engine file changes** must be wrapped in `#ifdef GODOT_GDEXTENSION` / `#endif`
7. **Never bypass the engine VFS** — all asset I/O through `FS_*` functions
8. **Test compilation constantly** — no game assets needed for build verification

## Phase Plan

Work through these phases sequentially. Each phase should compile cleanly before moving to the next. Group related work but keep individual phases small enough to verify independently.

---

### Block A: Audio Completeness (Phases 39–45)

**Phase 39: Music Playback — OGG/MP3 Streaming**
- `godot_sound.c` already captures `MUSIC_NewSoundtrack`, `MUSIC_UpdateVolume`, `MUSIC_StopAllSongs` state
- Load music files from VFS (`.mp3` in `sound/music/`), create `AudioStreamMP3` or `AudioStreamOGGVorbis`
- Implement music state machine: play, stop, pause, crossfade, volume control
- Create dedicated `AudioStreamPlayer` (non-positional) for music playback
- Handle `MUSIC_UpdateMusicVolume` and `MUSIC_StopAllSongs` commands

**Phase 40: Ambient Sound Loops**
- Improve looping sound management — currently basic, needs proper start/stop/update cycle
- Handle `S_AddLoopingSound` with correct attenuation model (linear vs inverse distance)
- Implement `S_StopLoopingSound` cleanup
- Match MOHAA's sound distance falloff curves

**Phase 41: Sound Channels & Priority**
- MOHAA uses 32+ sound channels with priority-based eviction
- Implement channel priority system matching `snd_dma.c` logic
- Handle `S_StartLocalSound` vs `S_StartSound` (2D vs 3D) routing
- Implement sound entity tracking (sounds attached to entities move with them)

**Phase 42: Sound Shader/Alias System**
- MOHAA has a `sound/` alias system where `.scr` or ubersound files define sound aliases
- Parse `ubersound.scr` and `uberdialog.scr` for sound alias → actual file mappings
- Handle random sound selection from alias groups
- Handle subtitle/dialogue flags

**Phase 43: MPEG Audio Decoding**
- Some MOHAA sounds are MP3-encoded within WAV containers (WAVE format tag 0x0055)
- Detect MP3-in-WAV and decode appropriately
- Handle `AudioStreamMP3` creation from VFS data

**Phase 44: Speaker Entity Sounds**
- `func_speaker` entities emit ambient sounds at fixed positions
- Parse entity key `noise` for sound file, `wait`/`random` for timing
- Create persistent `AudioStreamPlayer3D` nodes for speaker entities

**Phase 45: Sound Occlusion (Basic)**
- Basic line-of-sight check for sound occlusion using BSP trace
- Attenuate sounds blocked by solid BSP brushes
- Optional: skip if too complex, mark for future refinement

---

### Block B: UI & Menu System (Phases 46–58)

**Phase 46: Menu Background Rendering**
- `GR_DrawBackground` already captures raw image data in `godot_renderer.c`
- Render captured background as fullscreen `TextureRect` on `CanvasLayer`
- Handle loading screen backgrounds

**Phase 47: Main Menu Display**
- MOHAA main menu is driven by `.urc` (UI Resource) files in `ui/` directory
- The engine's `uilib/` code parses and manages these — it already compiles
- Route UI rendering through the 2D overlay system
- Ensure menu backgrounds, buttons, and text render correctly

**Phase 48: Menu Input Routing**
- When `KEYCATCH_UI` is set, route input to UI system instead of game
- Handle mouse cursor rendering (custom cursor from `gfx/2d/` or `ui/`)
- Implement click detection on UI elements
- Handle keyboard navigation (Tab, Enter, Escape)

**Phase 49: Console Overlay**
- MOHAA drop-down console (activated by `~` key)
- `KEYCATCH_CONSOLE` flag routes keyboard input to console
- Render console background, text history, input line
- Handle console scrolling, command history (up/down arrows)

**Phase 50: Server Browser UI**
- GameSpy master server query UI
- Server list rendering with ping, map, players, game type columns
- Handle server info requests and responses
- Connect-to-server action from UI

**Phase 51: Options Menu**
- Video, audio, controls, game options
- Cvar binding to UI sliders/checkboxes
- Key binding UI (press-a-key capture)
- Apply/cancel/default button handling

**Phase 52: Loading Screen**
- Map loading progress bar
- Tip text rotation during load
- Screenshot of previous map or loading image
- Handle `SCR_DrawLoading` / `SCR_UpdateScreen` during `CL_MapLoading`

**Phase 53: Scoreboard**
- In-game scoreboard (Tab key)
- Player names, kills, deaths, ping
- Team colours for team game modes
- Handle `CG_DrawScoreboard` rendering

**Phase 54: Team Selection / Weapon Selection**
- Team selection menu (Allies/Axis/Auto/Spectator)
- Weapon selection submenu
- Handle `ui_getplayermodel` and `ui_weaponselect` commands

**Phase 55: Chat & Message Display**
- In-game chat messages (T = team, Y = all)
- Kill feed / obituary messages
- Centre-print messages (objectives, hints)
- Handle `CG_CenterPrint`, `CG_ChatPrint`

**Phase 56: Cinematic Playback Stub**
- MOHAA has RoQ video playback for intro/cutscenes
- Implement stub or basic RoQ decoder
- Handle `CIN_PlayCinematic` / `CIN_StopCinematic`
- At minimum: skip cinematics gracefully without crashing

**Phase 58: UI Polish & Edge Cases**
- Handle all `UI_*` commands that flow through the UI system
- Modal dialog boxes (quit confirmation, disconnect confirmation)
- Mouse cursor clamping to window bounds
- UI sound effects (click, hover)

---

### Block C: Rendering Parity (Phases 59–85)

**Phase 59: Entity LOD System**
- Implement `skelHeaderGame_t.lodIndex[10]` distance-based LOD selection
- `pCollapse` / `pCollapseIndex` progressive mesh vertex collapse
- `lodControl_t` metric thresholds
- Reduce triangle count for distant entities

**Phase 60: Per-Entity Mesh Caching**
- Integrate `EntityCacheKey` from Phase 37 into `update_entities()`
- Cache `ArrayMesh` per (hModel, frameInfo, shaderRGBA) tuple
- Only rebuild mesh when animation state or shader changes
- Benchmark: measure frame time before/after

**Phase 61: Material Cache System**
- Cache `StandardMaterial3D` instances per shader name + properties
- Avoid per-frame material duplication for entity tinting/alpha
- Share materials across entities with identical shader state

**Phase 62: Weapon Rendering via SubViewport**
- Replace `FLAG_DISABLE_DEPTH_TEST` hack for first-person weapons
- Render `RF_FIRST_PERSON` + `RF_DEPTHHACK` entities into a SubViewport
- Composite SubViewport over main view
- Proper self-occlusion for weapon models

**Phase 63: Dynamic Lightgrid Entity Lighting**
- Sample lightgrid at each entity's position
- Apply ambient + directed light as entity material modulation
- Use `Godot_BSP_LightForPoint()` (Phase 28) for ambient colour
- Apply to skeletal model and brush model entities

**Phase 64: Dynamic Lights on Entities**
- Apply `gr_dlights[]` to nearby entities
- Per-entity: find N closest dlights, compute attenuation
- Modulate entity material or use `OmniLight3D` nodes

**Phase 65: Fullbright/Vertex-Lit Surface Fallback**
- Some shaders have no lightmap stage — render fullbright
- Detect `surfaceparm nolightmap` in shader props
- Apply appropriate lighting model (vertex colours only, or fullbright)

**Phase 66: Multi-Stage Shader Rendering**
- Many MOHAA shaders have 2+ rendering stages (base + lightmap + detail)
- Parse all stages from .shader files, not just the first
- Composite stages via Godot shader code or multi-pass materials
- Handle `rgbGen`, `alphaGen`, `tcGen environment` per stage

**Phase 67: Environment Mapping (tcGen environment)**
- Reflective surfaces using view-dependent UV generation
- Compute environment map UVs from view direction and surface normal
- Apply as secondary texture or custom Godot shader

**Phase 68: Animated Texture Sequences (`animMap`)**
- Some shaders define `animMap <fps> <tex1> <tex2> ...`
- Load all frames, cycle by elapsed time
- Apply to material via custom shader or texture swap

**Phase 69: `deformVertexes` — Autosprite**
- `deformVertexes autosprite` — billboard quads always face camera
- `deformVertexes autosprite2` — axis-aligned billboards
- Transform vertices per-frame based on camera direction

**Phase 70: `deformVertexes` — Wave/Bulge/Move**
- `deformVertexes wave` — sinusoidal vertex displacement (flags, water)
- `deformVertexes bulge` — model surface bulging
- `deformVertexes move` — vertex translation over time

**Phase 71: `rgbGen wave` / `alphaGen wave`**
- Pulsing colour/alpha effects (lights, pickups, effects)
- Implement sin/triangle/square/sawtooth/inversesawtooth wave functions
- Apply as material modulation per frame

**Phase 72: `tcGen lightmap` / `tcGen vector`**
- Correct lightmap UV generation from surface properties
- `tcGen vector` — arbitrary UV projection

**Phase 73: Portal Surfaces**
- `RT_PORTALSURFACE` entity type — mirrors, portals
- Basic: render as flat coloured surface
- Advanced: SubViewport rendering from portal camera position

**Phase 74: Flare Rendering**
- `MST_FLARE` surface type — lens flare sprites at light positions
- Billboard quad with distance fade and occlusion check
- Additive blending

**Phase 75: Volumetric Smoke & Dust**
- `cg_volumetricsmoke.cpp` submits smoke polys
- Billboarded particle quads with alpha fade
- Correct depth sorting (painter's algorithm or alpha-sorted)

**Phase 76: Rain & Snow Effects**
- Weather particle systems driven by cgame
- Rain: vertical line particles with splash on impact
- Snow: drifting particle system

**Phase 77: Water/Liquid Surfaces**
- Water surfaces with wave deformation (`deformVertexes wave`)
- Correct transparency and colour tinting
- Optional: basic reflection via environment probe or SubViewport

**Phase 78: Fog Volumes**
- Per-surface fog (different from global fog)
- `LUMP_FOGS` — volumetric fog regions
- Fog distance fade per surface

**Phase 79: Shadow Projection**
- MOHAA uses projected shadow blobs (mark fragments on ground)
- Already partially handled by mark fragment system (Phase 17)
- Ensure shadow marks appear under all player/NPC entities

**Phase 80: Lightmap Styles**
- Some BSP versions support multiple lightmap styles per surface
- Handle lightmap style switching for switchable lights

**Phase 81: Gamma/Overbright Correction**
- Match MOHAA's gamma ramp (`r_gamma` cvar)
- Overbright bit handling (lightmap shift)
- Apply via Environment tonemap or post-processing

**Phase 82: Anti-Aliasing & Rendering Quality**
- Expose `r_picmip`, `r_texturemode` equivalent settings
- Texture filtering (bilinear, trilinear, anisotropic) matching engine cvars
- MSAA or FXAA via Godot's built-in settings

**Phase 83: Draw Distance / Far Plane**
- `r_znear`, `r_zfar` matching
- Fog-based far plane culling
- `farplane_cull` integration

**Phase 84: Debug Rendering Options**
- `r_showtris` — wireframe overlay
- `r_shownormals` — normal vectors
- `r_lockpvs` — freeze PVS for debugging
- `r_speeds` — render statistics overlay

**Phase 85: Render Performance Audit**
- Profile frame times with `OS::get_singleton()->get_ticks_usec()`
- Identify top 5 bottlenecks
- Batch static geometry where possible
- Reduce draw calls via merged meshes

---

### Block D: Game Logic Parity (Phases 86–120)

**Phase 86: Player Movement Physics**
- Verify `bg_pmove.cpp` produces identical movement in Godot
- Test: walking, running, sprinting, crouching, jumping, prone
- Ensure `sv_fps` and framerate-independent movement

**Phase 87: Weapon Mechanics**
- Fire, reload, switch, drop, pickup
- Bullet spread, recoil, damage falloff
- Melee attacks (knife, bayonet)
- Verify weapon scripts execute correctly

**Phase 88: Hit Detection & Damage**
- Trace-based hitscan weapons via BSP + entity collision
- Area damage (grenades, explosions, artillery)
- Locational damage (headshots, limb damage)

**Phase 91: Game Modes — Free For All**
- IMplament ALL game modes support.


**Phase 95: Map Scripting**
- `.scr` scripts controlling  level flow
-  All scripting should work

**Phase 96: Single Player — Cutscenes**
- Scripted camera movements
- NPC dialogue and animations
- Letterbox mode (cinematic bars)

**Phase 97: Single Player — AI Companions**
- Friendly NPC pathfinding and following
- Squad commands
- AI combat alongside player

**Phase 98: Single Player — Checkpoints & Saves**
- Save/load game state
- Checkpoint auto-save
- Serialise entity state, script state, player state

**Phase 99: Inventory & Item System**
- Health packs, ammo, grenades
- Pickup entity interaction
- Inventory limits and stacking

**Phase 100: Door/Mover/Elevator Entities**
- `func_door`, `func_rotating`, `func_plat`
- Brush model movement with collision
- Sound triggers, wait times, damage on block

**Phases 101–110: Entity Types Audit**
- Systematically verify every entity type in `code/fgame/`:
  - 101: `trigger_*` entities (hurt, push, teleport, relay)
  - 102: `func_*` entities (breakable, explodable, vehicle)
  - 103: `info_*` entities (spawn points, teleport destinations)
  - 104: `light_*` and `misc_*` entities
  - 105: `weapon_*` pickup entities
  - 106: `worldspawn` and global settings
  - 107: `path_*` waypoint/spline entities
  - 108: `script_*` entities (script origins, models)
  - 109: `animate_*` entities (animated scene objects)
  - 110: Custom MOHAA entity types (turret, bed, chair)

**Phases 111–115: Script Engine Verification**
- 111: Verify all Morfuse built-in commands execute correctly
- 112: Test complex script thread management (waitthread, waittill)
- 113: Event system (`waittill animdone`, `damaged`, `trigger`)
- 114: Script-driven entity spawning and modification
- 115: Timer and scheduled event accuracy

**Phases 116–120: Physics & Collision**
- 116: BSP clip model collision (player vs world)
- 117: Entity vs entity collision (pushers, triggers)
- 118: Projectile physics (grenade arcs, rocket travel)
- 119: Water physics (swimming, diving, water damage)
- 120: Fall damage, world damage volumes

---

### Block E: Networking & Multiplayer (Phases 121–155)

**Phase 121: Network Initialisation**
- Verify `NET_Init()` functions under Godot
- UDP socket creation and management
- Handle Godot's networking alongside engine networking

**Phase 122: Server Hosting**
- `sv_maxclients`, `sv_hostname`, `sv_mapRotation`
- Listen server mode (client + server in one process)
- Dedicated server mode (headless)

**Phase 123: Client Connection Flow**
- `connect <ip>` command
- Challenge/response handshake
- `clientConnect` → `gamestate` → `snapshot` pipeline

**Phase 124: Snapshot System**
- Delta-compressed entity snapshots
- Verify `SV_BuildClientSnapshot` → `CL_ParseSnapshot` pipeline
- Entity baseline and delta encoding

**Phase 125: Client Prediction**
- `CL_PredictPlayerState` — run pmove locally
- Prediction error correction (snap-back handling)
- Verify prediction matches server authoritative state

**Phase 126: Lag Compensation**
- `sv_antilag` — server-side hit detection with client timestamps
- Verify trace-back and hit validation
- Handle high-ping player fairness

**Phase 127: Reliable Commands**
- `clc_clientCommand` / `svc_serverCommand` reliable delivery
- Command overflow handling
- Config string updates
UI

**Phase 129: Master Server Registration**
- GameSpy heartbeat protocol
- Server info response to master queries
- Server browser compatibility

**Phase 130: Connection Robustness**
- Timeout handling, reconnect logic
- Network error recovery (packet loss, out-of-order)
- `cl_timeout`, `sv_timeout` enforcement

**Phases 131–140: Protocol Compatibility Testing**
- 131: Test with OpenMoHAA dedicated server (our client → their server)
- 132: Test with OpenMoHAA client (their client → our server)
- 133: Protocol version negotiation
- 134: Game version matching (AA vs SH vs BT)
- 135: Cross-version compatibility edge cases
- 136: Large player count testing (16, 32, 64 players)
- 137: Map rotation and mid-match map changes
- 138: Vote system (callvote, vote)
- 139: Admin commands (rcon)
- 140: Spectator mode

**Phases 141–150: Network Edge Cases**
- 141: NAT traversal and port forwarding
- 142: IPv4 and IPv6 support
- 143: Rate limiting (`rate`, `snaps`, `cl_maxpackets`)
- 144: Packet fragmentation for large snapshots
- 145: Server-side cheat detection (server authoritative)
- 146: Client disconnect cleanup
- 147: Server crash recovery
- 148: Multiple simultaneous games (different ports)
- 149: RCON (remote console) password authentication
- 150: Status query protocol (server info, player info)

**Phases 151–155: Network Performance**
- 151: Bandwidth profiling
- 152: Snapshot size optimisation
- 153: Entity visibility culling (PVS-based snapshot building)
- 154: Server tick rate stability
- 155: Client interpolation smoothness

---


### Block I: Visual Polish & Effects (Phases 221–260)

**Phase 221: Particle System**
- Convert cgame particle effects to Godot `GPUParticles3D`
- Smoke, fire, sparks, blood, debris, water splash
- Match particle counts and behaviour

**Phase 222: Impact Effects**
- Bullet impact on different surfaces (metal spark, wood chip, dirt puff)
- Surface type detection from BSP shader flags
- Decal + particle + sound per impact type

**Phase 223: Explosion Effects**
- Grenade, torpedo, artillery explosions
- Expanding fireball, smoke trail, debris
- Camera shake on nearby explosions

**Phase 224: Muzzle Flash**
- Per-weapon muzzle flash sprite/model
- Light flash (`gr_dlights`) at barrel position
- Shell casing ejection

**Phase 225: Blood & Gore Effects**
- Hit confirmation blood spray
- Surface blood decals
- Death animations

**Phase 226: Environmental Effects**
- Dust motes in sunbeams
- Fireflies, embers, falling leaves
- Map-specific ambient particles

**Phase 227: Screen Effects**
- Damage flash (red tint on hit)
- Underwater colour/distortion
- Flash-bang/stun effects
- Pain flinch (view kick)

**Phase 228: Tracers**
- Bullet tracer rendering for automatic weapons
- Correct tracer spacing (every Nth shot)
- Tracer colour by weapon type

**Phase 229: Shell Casings**
- Brass/clip ejection models
- Physics bounce (simplified)
- Fade-out and cleanup timer

**Phase 230: Debris System**
- Breakable objects produce debris models
- Rubble, glass shards, wood splinters
- Physics interaction (bounce, slide)

**Phases 231–240: Surface-Specific Effects**
- 231: Metal surfaces — sparks, ricochet sound
- 232: Wood surfaces — splinter effect, thud sound
- 233: Stone/concrete — chip effect, dust puff
- 234: Dirt/sand — dust cloud, impact sound
- 235: Water — splash, ripple
- 236: Glass — shatter effect, breaking sound
- 237: Flesh — blood effects
- 238: Foliage — leaf disturbance
- 239: Snow — snow puff
- 240: Custom surface types from MOHAA shaders

**Phases 241–250: Animation Polish**
- 241: Smooth animation blending between states
- 242: Animation event sounds (footsteps, gear rattling)
- 243: Third-person weapon animations
- 244: First-person reload animations
- 245: Death animation selection by damage type/direction
- 246: Pain animations and flinch
- 247: Jump/land animations
- 248: Prone transition animations
- 249: Ladder climbing animation
- 250: Swimming animation

**Phases 251–260: Rendering Refinement**
- 251: Correct draw order for transparent surfaces
- 252: Alpha-sorted entity rendering
- 253: Additive blending effects (explosions, flares)
- 254: Correct fog interaction with transparent surfaces
- 255: Skybox rotation for time-of-day maps
- 256: Correct lightmap gamma across all maps
- 257: BSP visibility culling (full PVS)
- 258: Frustum culling for entities and effects
- 259: Occlusion culling (optional, using Godot built-in)
- 260: Final visual parity audit against OpenMoHAA GL1

---

### Block J: Full Game Flow (Phases 261–300)

**Phase 261: Title Screen**
- MOHAA animated logo intro
- Press any key to continue
- Transition to main menu

**Phase 262: New Game Flow**
- Difficulty selection
- Mission briefing screens
- Map loading with briefing text

**Phase 263: Mission Completion**
- End-of-mission statistics
- Medal awards
- Transition to next mission

**Phase 264: Save/Load Game**
- Full game state serialisation
- Save slot management
- Quick save/quick load (F5/F9)

**Phase 265: Multiplayer Quick Match**
- Server browser → sort by ping → join
- Quick match (auto-find best server)
- Recent servers list

**Phase 266: Create Server**
- Map selection, game mode, player limit
- Server cvars configuration
- Start server + auto-join as client

**Phase 267: Key Bindings**
- Default key layout matching MOHAA
- Rebindable controls
- Mouse sensitivity, invert look

**Phase 268: Audio Settings**
- Master volume, effects volume, music volume, dialogue volume
- Sound quality (sample rate, channels)
- Hardware/software mixer selection

**Phase 269: Video Settings**
- Resolution, fullscreen/windowed
- Quality presets (low, medium, high, custom)
- Individual quality settings (textures, effects, draw distance)

**Phase 270: Network Settings**
- Connection speed presets
- Rate, snaps, maxpackets
- Netgraph display toggle

**Phases 271–280: Campaign Playthrough Testing**
- 271: Mission 1 — North Africa (Arzew)
- 272: Mission 2 — North Africa (continued)
- 273: Mission 3 — Norway
- 274: Mission 4 — Omaha Beach
- 275: Mission 5 — Bocage
- 276: Mission 6 — Fort Schmerzen
- 277: SH Campaign start to finish
- 278: BT Campaign start to finish
- 279: All scripted sequences execute correctly
- 280: All objectives completable

**Phases 281–290: Multiplayer Mode Testing**
- 281: FFA — full match with bots
- 282: TDM — full match with bots
- 283: Objective — full round
- 284: Liberation — full round
- 285: Demolition — full round
- 286: Round restart logic
- 287: Map voting
- 288: Warm-up period
- 289: Overtime/sudden death
- 290: Match end and map rotation

**Phases 291–300: Integration Testing**
- 291: 30-minute play session without crashes
- 292: 4-player LAN game stability
- 293: All stock maps load (54 maps)
- 294: All stock models render (158+ TIKI)
- 295: All stock sounds play (367+ registered)
- 296: All stock shaders apply correctly (3030+)
- 297: Frame rate profiling (target: 60 FPS)
- 298: Memory usage profiling (target: <1 GB)
- 299: Load time profiling (target: <30s per map)
- 300: Final build + full test pass

---

### Block K: Parity Verification (Phases 301–350)

**Phases 301–310: Rendering Parity**
- 301: Screenshot comparison: mohdm1 — OpenMoHAA vs Godot port
- 302: Screenshot comparison: mohdm2
- 303: Screenshot comparison: mohdm3–mohdm7
- 304: Screenshot comparison: single-player maps (m1l1–m6l3)
- 305: Lighting comparison (lightmaps, dynamic lights)
- 306: Shader effect comparison (tcMod, deform, blend)
- 307: HUD element comparison (health, ammo, compass)
- 308: Font rendering comparison
- 309: Skybox comparison
- 310: Fog rendering comparison

**Phases 311–320: Audio Parity**
- 311: Weapon sound comparison (all weapons)
- 312: Ambient sound comparison (water, wind, machinery)
- 313: Music playback comparison
- 314: Impact sound comparison (all surface types)
- 315: UI sound comparison (menu clicks, transitions)
- 316: Voice/dialogue comparison
- 317: 3D positional audio comparison
- 318: Sound distance attenuation comparison
- 319: Sound priority/channel comparison under load
- 320: Music transition comparison

**Phases 321–330: Gameplay Parity**
- 321: Movement speed comparison (walk, run, sprint, crouch, prone)
- 322: Jump height and distance comparison
- 323: Weapon damage values comparison
- 324: Weapon rate of fire comparison
- 325: Weapon spread pattern comparison
- 326: Grenade physics comparison (arc, bounce, fuse)
- 327: Health/armour values comparison
- 328: Entity spawn timing comparison
- 329: Script execution timing comparison
- 330: AI behaviour comparison

**Phases 331–340: Network Parity**
- 331: Snapshot size comparison
- 332: Network bandwidth comparison
- 333: Client prediction accuracy comparison
- 334: Hit registration accuracy comparison
- 335: Server tickrate comparison
- 336: Client interpolation smoothness comparison
- 337: Reconnect behaviour comparison
- 338: Server browser data comparison
- 339: RCON compatibility
- 340: Protocol version compatibility

**Phases 341–350: Stress & Edge Cases**
- 341: Max entity stress test parity
- 342: Max player count parity
- 343: Max effects count parity
- 344: Rapid fire weapon stress parity
- 345: Explosion chain reaction parity
- 346: Vehicle destruction sequence parity
- 347: Large-scale AI battle parity (SP)
- 348: Memory usage under stress parity
- 349: Error handling parity (missing assets, bad commands)
- 350: Clean shutdown parity

---

## Success Criteria
The project is complete when:
1. All 54 stock MOHAA maps load and render at visual parity with OpenMoHAA GL1
2. The full AA single-player campaign is playable start to finish
3. All multiplayer game modes function with correct rules
4. A Godot-port client can join an OpenMoHAA server and play normally
5. An OpenMoHAA client can join a Godot-port server and play normally
6. Performance is ≥60 FPS on mid-range hardware
7. Builds are available for Linux, Windows, and macOS
8. Zero known crashes under normal gameplay conditions

## Working Rules
- **One phase at a time.** Complete it, test it, commit it, document it.
- **Build after every change.** Compilation errors block all progress.
- **Existing patterns are law.** Follow the `#ifdef GODOT_GDEXTENSION`, C accessor, and buffer capture patterns established in Phases 1–38.
- **Never break what works.** Each phase must preserve all previous functionality.
- **When stuck, read the code.** The upstream OpenMoHAA source (`code/client/`, `code/fgame/`, `code/cgame/`) is the authoritative reference for how things should work.