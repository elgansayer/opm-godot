# Agent Task 22: RoQ Cinematic Playback Stub

## Objective
Implement Phase 56: detect when the engine tries to play a RoQ cinematic video, display a black screen with "Press ESC to skip" text, and handle the skip input. Full RoQ decoding is optional; the stub ensures the engine doesn't crash and gameplay proceeds.

## Files to Create (EXCLUSIVE)
- `code/godot/godot_cinematic.cpp` — Cinematic playback stub/handler
- `code/godot/godot_cinematic.h` — Public API

## Files to Modify (append only)
- `code/godot/stubs.cpp` — Add any missing `CIN_*` function stubs if not already present

## Implementation

### 1. Cinematic state detection
The engine calls `SCR_DrawCinematic()` which calls `CIN_DrawCinematic()` and `GR_DrawStretchRaw()`. In `godot_renderer.c`, `GR_DrawStretchRaw()` is already stubbed. We detect cinematic state by checking if `GR_DrawStretchRaw` was called this frame.

Add to `godot_renderer.c` (via accessor pattern):
```c
// In godot_cinematic.cpp or separate accessor
extern "C" int Godot_Cinematic_IsPlaying(void);
```

Actually — add a flag in the existing render capture: when `GR_DrawStretchRaw()` is called, set `gr_cinematic_active = 1`. Reset to 0 at start of each frame (`GR_BeginFrame`).

### 2. Public API
```cpp
void Godot_Cinematic_Init(godot::Node *parent);
void Godot_Cinematic_Update(float delta);
void Godot_Cinematic_Shutdown(void);
bool Godot_Cinematic_IsActive(void);
```

### 3. Visual display
- `CanvasLayer` (z_index=200, above everything)
- Fullscreen black `ColorRect`
- "Press ESC to skip" label centred at bottom (small white text, alpha pulse)
- Only visible when `Godot_Cinematic_IsPlaying()` returns true
- Hidden when cinematic ends (flag clears)

### 4. Skip handling
- When ESC pressed during cinematic, inject `SE_KEY` event for K_ESCAPE
- Engine's cinematic code handles the rest (`SCR_StopCinematic`)

### 5. Optional: actual RoQ frame decoding
If time permits, capture the raw pixel data from `GR_DrawStretchRaw(x, y, w, h, cols, rows, data, client, dirty)`:
- `data` is RGB pixel array, `cols × rows`
- Create `Image::create(cols, rows, false, FORMAT_RGB8, data)`
- Display on a `TextureRect`
This is stretch goal — the stub alone is sufficient.

## Build Verification
```bash
cd openmohaa && scons platform=linux target=template_debug -j$(nproc) dev_build=yes
```

## Documentation
Append `## Phase 56: Cinematic Playback Stub ✅` to `TASKS.md`.

## DO NOT MODIFY
- `MoHAARunner.cpp` / `MoHAARunner.h`
- `godot_renderer.c` (add accessor function only if needed, or read existing gr_ variables via extern)
