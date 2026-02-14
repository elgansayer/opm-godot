# Agent Task 26: Debug Rendering (r_showtris, r_shownormals, r_speeds)

## Objective
Implement Phase 84: debug rendering overlays controlled by engine cvars. These are developer tools for diagnosing rendering issues.

## Files to Create (EXCLUSIVE)
- `code/godot/godot_debug_render.cpp` — Debug rendering system
- `code/godot/godot_debug_render.h` — Public API
- `code/godot/godot_debug_render_accessors.c` — C accessor for debug cvars

## Implementation

### 1. C accessor
```c
int Godot_Debug_GetShowTris(void);      // r_showtris: 0=off, 1=wireframe, 2=wireframe+solid
int Godot_Debug_GetShowNormals(void);   // r_shownormals: 0=off, 1=show normals
int Godot_Debug_GetSpeeds(void);        // r_speeds: 0=off, 1=show stats
int Godot_Debug_GetLockPVS(void);       // r_lockpvs: 0=off, 1=freeze PVS
int Godot_Debug_GetDrawBBox(void);      // r_showbbox (custom): 0=off, 1=show entity bounds
```

### 2. Debug render manager
```cpp
void Godot_DebugRender_Init(godot::Node *parent);
void Godot_DebugRender_Update(float delta);
void Godot_DebugRender_Shutdown(void);
```

### 3. r_showtris (wireframe overlay)
- When enabled: set viewport debug draw to `Viewport::DEBUG_DRAW_WIREFRAME`
- Access viewport via `parent->get_viewport()`
- When disabled: restore to `Viewport::DEBUG_DRAW_DISABLED`
- Track previous state to avoid redundant calls

### 4. r_speeds (stats overlay)
- When enabled: display text overlay on a `CanvasLayer` (z_index=150)
- Show per-frame stats:
  - FPS
  - Entity count (total / skeletal / static)
  - Mesh cache size + hit rate (read from `Godot_MeshCache` if available)
  - Draw call estimate
  - Polygon count estimate
- Use `Label` node with monospace font
- Update every 10 frames (not every frame) for readability

### 5. r_shownormals
- When enabled: for each visible entity MeshInstance3D, overlay normal lines
- Use `ImmediateMesh` or `MeshInstance3D` with line primitives
- Normal length: 0.1m, colour: blue
- Performance concern: only render for entities within 20m of camera
- Pool of ImmediateMesh nodes (max 32)

### 6. r_showbbox (optional)
- When enabled: draw wireframe boxes around entity bounding boxes
- Use `ImmediateMesh` with `PRIMITIVE_LINES`
- Green for static, yellow for dynamic entities

## Build Verification
```bash
cd openmohaa && scons platform=linux target=template_debug -j$(nproc) dev_build=yes
```

## Documentation
Append `## Phase 84: Debug Rendering ✅` to `TASKS.md`.

## DO NOT MODIFY
- `MoHAARunner.cpp` / `MoHAARunner.h`
- `godot_mesh_cache.cpp` (only read stats via public API)
