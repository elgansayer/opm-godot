# Agent Task 49: Wire Music + Sound Occlusion

## Objective
Integrate Agent 1's music system (`godot_music.cpp`) and sound occlusion (`godot_sound_occlusion.c`) into MoHAARunner's audio pipeline.

## Files to MODIFY
- `code/godot/MoHAARunner.cpp` — `_ready()`, `_process()`, `update_audio()`

## What Exists
- `godot_music.cpp/.h`: `Godot_Music_Init(void*)`, `Godot_Music_Update(float)`, `Godot_Music_Shutdown()`
- `godot_sound_occlusion.c/.h`: `Godot_Sound_IsOccluded(src, listener)` → int (0/1)
- `godot_ubersound.cpp/.h`: `Godot_Ubersound_Init()`, `Godot_Ubersound_Resolve(alias)` → filename
- `godot_speaker_entities.cpp/.h`: Speaker entity management

## Implementation

### 1. Music in _ready() — ALREADY DONE (fixed build error)
```cpp
#ifdef HAS_MUSIC_MODULE
    Godot_Music_Init(static_cast<void*>(this));
#endif
```

### 2. Music in _process()
The existing `Godot_Music_Update(delta)` call is already present under `#ifdef HAS_MUSIC_MODULE`.
Verify it works by checking that music state is polled from `godot_sound.c`.

### 3. Sound occlusion in update_audio()
For each 3D sound being played:
```cpp
    // Get listener position (camera position in id coords)
    float listener[3] = { /* camera origin in id coords */ };
    float source[3] = { /* sound source position in id coords */ };
    
    if (Godot_Sound_IsOccluded(source, listener)) {
        // Attenuate: reduce volume to 30% (occlusion factor)
        audio_player->set_volume_db(audio_player->get_volume_db() - 10.0f); // ~0.3x
    }
```

### 4. Ubersound alias resolution
When loading sounds, resolve aliases:
```cpp
    const char *resolved = Godot_Ubersound_Resolve(sound_alias);
    if (resolved && resolved[0]) {
        // Load resolved filename instead of alias
        sound_filename = resolved;
    }
```

### 5. Music volume from cvar
```cpp
#ifdef HAS_MUSIC_MODULE
    // Read s_musicvolume cvar and apply
    extern "C" float Godot_Sound_GetMusicVolume(void);
    Godot_Music_SetVolume(Godot_Sound_GetMusicVolume());
#endif
```

### 6. Cleanup in destructor
```cpp
#ifdef HAS_MUSIC_MODULE
    Godot_Music_Shutdown();
#endif
```

## Build Verification
```bash
cd openmohaa && scons platform=linux target=template_debug -j$(nproc) dev_build=yes
```

## Documentation
Append `## Phase 271: Audio Integration ✅` to `TASKS.md`.
