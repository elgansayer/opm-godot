# Agent Task 01: Audio Completeness

## Objective
Implement full audio parity with OpenMoHAA: music playback, advanced sound channels, ubersound/alias system, MP3-in-WAV decoding, speaker entities, and basic sound occlusion.

## Starting Point
Read `.github/copilot-instructions.md`, `openmohaa/AGENTS.md`, and `openmohaa/TASKS.md` for full project context. Phases 1–38 are complete. Basic 3D positional audio already works — `godot_sound.c` captures `S_StartSound`, `S_AddLoopingSound`, and `MUSIC_*` state. `MoHAARunner.cpp::update_audio()` plays sounds through an `AudioStreamPlayer3D` pool.

## Scope — Phases 39–45

### Phase 39: Music Playback — OGG/MP3 Streaming
- `godot_sound.c` already captures `MUSIC_NewSoundtrack`, `MUSIC_UpdateVolume`, `MUSIC_StopAllSongs`
- Create `godot_music.cpp` + `godot_music.h` — a standalone music manager module
- Load music files from VFS (`sound/music/*.mp3`) via `Godot_VFS_ReadFile`
- Create `AudioStreamMP3` from raw VFS bytes
- Implement music state machine: play, stop, pause, crossfade, volume control
- Handle `MUSIC_UpdateMusicVolume`, `MUSIC_StopAllSongs`, `MUSIC_FreeAllSongs`
- Handle the MOHAA music system's concept of current/fallback tracks

### Phase 40: Ambient Sound Loops
- Improve `S_AddLoopingSound` / `S_StopLoopingSound` management
- Implement proper attenuation model (linear distance falloff matching MOHAA)
- Handle entity-attached looping sounds (sound position updates with entity)
- Clean up orphaned loops when entities are removed

### Phase 41: Sound Channels & Priority
- MOHAA uses 32+ channels with priority-based eviction
- Implement priority system matching `snd_dma.c` logic (read `code/client/snd_dma.c` for reference even though it's excluded from build)
- `S_StartLocalSound` → 2D player, `S_StartSound` → 3D player
- Sounds attached to entities should track entity position each frame

### Phase 42: Sound Alias / Ubersound System
- MOHAA defines sound aliases in `ubersound.scr` and `uberdialog.scr` (in `sound/` directories inside pk3)
- Parse these files (simple key-value format) to build alias → actual filename mappings
- Handle random sound selection from alias groups (e.g. multiple footstep variants)
- Handle subtitle/dialogue flags in alias entries
- Create `godot_ubersound.cpp` + `godot_ubersound.h`

### Phase 43: MP3-in-WAV Decoding
- Some MOHAA `.wav` files use WAVE format tag `0x0055` (MPEG audio inside WAV container)
- In the existing `load_wav_from_vfs()` in `MoHAARunner.cpp`, detect this tag
- When detected, extract the MPEG payload and create `AudioStreamMP3` instead of `AudioStreamWAV`
- Handle both standard PCM WAV and MP3-in-WAV transparently

### Phase 44: Speaker Entity Sounds
- `func_speaker` entities in BSP maps emit ambient sounds at fixed positions
- Parse entity key `noise` for sound file, `wait`/`random` for timing
- Create persistent `AudioStreamPlayer3D` nodes for speaker entities during map load
- Handle start/stop based on entity trigger state

### Phase 45: Sound Occlusion (Basic)
- Basic line-of-sight check for sound attenuation
- Use BSP trace (via a C accessor calling `CM_BoxTrace` or `SV_Trace`) to check if sound origin is occluded from listener
- Attenuate occluded sounds by a fixed factor (e.g. 0.3×)
- Skip if too complex — mark as optional and document limitations

## Files You OWN (create or primarily modify)

### New files to create
| File | Purpose |
|------|---------|
| `code/godot/godot_music.cpp` | Music playback manager — loads MP3 from VFS, state machine |
| `code/godot/godot_music.h` | Music manager C++ header |
| `code/godot/godot_ubersound.cpp` | Ubersound/alias parser — reads `.scr` alias files |
| `code/godot/godot_ubersound.h` | Ubersound parser header |
| `code/godot/godot_sound_occlusion.c` | BSP trace for sound occlusion (C, accesses engine internals) |

### Existing files you may modify
| File | What to change |
|------|----------------|
| `code/godot/godot_sound.c` | Add/improve music state capture, loop tracking, channel metadata. **Only modify the music/loop sections** — do not restructure the existing `S_StartSound` capture. |

## Files You Must NOT Touch
- `MoHAARunner.cpp` — do NOT modify. Provide your API via headers and document integration points below.
- `MoHAARunner.h` — do NOT modify.
- `godot_renderer.c` — not your domain.
- `godot_shader_props.cpp/.h` — not your domain.
- `godot_bsp_mesh.cpp/.h` — not your domain.
- `godot_skel_model*.cpp/.h` — not your domain.
- `SConstruct` — new `.c`/`.cpp` files in `code/godot/` are auto-discovered by the recursive `add_sources()`.
- `stubs.cpp` — if you need a new stub, document it in your TASKS.md entry; another agent handles stubs.

## Integration Points
Your modules must be usable from `MoHAARunner.cpp` WITHOUT modifying it now. Provide:
1. **C-linkage accessor functions** in your `.h` files (e.g. `extern "C" void Godot_Music_Update(float delta);`)
2. A clear section in your TASKS.md entry titled **"MoHAARunner Integration Required"** listing:
   - New `#include` lines needed
   - New member variables needed in the class
   - New calls needed in `_process()`, `setup_audio()`, `update_audio()`, or `check_world_load()`
3. Keep all Godot-side code (using godot-cpp headers) inside your new `.cpp` files with appropriate includes.

## Build & Test
```bash
cd openmohaa && rm -f .sconsign.dblite && scons platform=linux target=template_debug -j$(nproc) dev_build=yes
```
Must compile cleanly. No game assets are needed for compilation.

## Documentation
Add new Phase entries (39–45) to `openmohaa/TASKS.md` following the existing format. Each phase entry should include:
- Task checkboxes
- Key technical details section
- Files modified/created list
- A **"MoHAARunner Integration Required"** section

## Merge Awareness
- **You share `godot_sound.c`** with no other agent — it is yours exclusively.
- Other agents may read your headers to understand the sound API — keep them clean.
- The Integration agent (Agent 10) will wire your modules into `MoHAARunner.cpp` later.
- If you need engine state (e.g. entity positions for sound tracking), add a new C accessor file rather than including engine headers in godot-cpp code.
