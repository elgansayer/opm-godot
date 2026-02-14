# Agent Task 27: TIKI Animation Event System

## Objective
Implement Phases 241-242: TIKI animation events — sound effects, particle effects, and other events triggered at specific animation frames. TIKI files define `server` and `client` event blocks that fire at exact frame numbers during skeleton animation playback.

## Files to Create (EXCLUSIVE)
- `code/godot/godot_animation_events.cpp` — Animation event parser + dispatcher
- `code/godot/godot_animation_events.h` — Public API
- `code/godot/godot_animation_event_accessors.c` — C accessor for TIKI event data

## Implementation

### 1. TIKI animation event format
TIKI files (`.tik`) contain animation entries like:
```
animations
{
  idle  models/human/animation_idle.skc
  {
    server
    {
      entry sound idle_breath snd_breath
    }
    client
    {
      10 sound idle_shuffle snd_shuffle
      20 footstep "grass"
    }
  }
}
```
- `entry` events fire when the animation starts
- `exit` events fire when the animation ends
- Numeric events fire at that frame number
- Event types: `sound`, `footstep`, `effect`, `bodyfall`, `tagspawn`

### 2. C accessor for TIKI event data
```c
int Godot_AnimEvent_GetEventCount(int tiki_handle, int anim_index);
void Godot_AnimEvent_GetEvent(int tiki_handle, int anim_index, int event_index,
                              int *frame_num,    // -1=entry, -2=exit, 0+=frame
                              char *type_buf,    // "sound", "footstep", etc
                              int type_buf_size,
                              char *param_buf,   // event parameter string
                              int param_buf_size);
```
This reads from the engine's `dtiki_t` structure which stores parsed animation commands.

### 3. Event dispatcher
```cpp
struct AnimEventState {
    int current_anim;
    int current_frame;
    int last_fired_frame;
    bool entry_fired;
};

void Godot_AnimEvents_Init(void);
void Godot_AnimEvents_Fire(int entity_index, int tiki_handle,
                           int anim_index, int current_frame,
                           const godot::Vector3 &entity_pos);
void Godot_AnimEvents_Shutdown(void);
```

### 4. Event type handlers
- `sound`: queue audio event (name → VFS path → engine sound system)
- `footstep`: lookup surface type at entity position → appropriate footstep sound
- `effect`: trigger VFX at entity position (document integration point with VFX agents)
- `bodyfall`: sound for NPC falling to ground
- Entry/exit events: fire once per animation transition

### 5. Frame tracking
- Track per-entity: last animation index + last fired frame
- When animation changes: fire exit events for old, entry events for new
- Fire frame events when `current_frame >= event_frame && last_fired_frame < event_frame`
- Handle animation looping (frame wraps to 0)

## Build Verification
```bash
cd openmohaa && scons platform=linux target=template_debug -j$(nproc) dev_build=yes
```

## Documentation
Append `## Phase 241-242: Animation Events ✅` to `TASKS.md`.

## DO NOT MODIFY
- `MoHAARunner.cpp` / `MoHAARunner.h`
- `godot_skel_model.cpp` / `godot_skel_model_accessors.cpp` (Agent 4 owns)
- `godot_sound.c` (Agent 1 owns)
