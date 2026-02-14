# Agent Task 24: Render Quality Cvars (r_picmip, AA, Texture Filtering)

## Objective
Implement Phase 82: map engine render quality cvars to Godot viewport/project settings. This includes texture quality (`r_picmip`), texture filtering mode (`r_texturemode`), anisotropic filtering, and anti-aliasing.

## Files to Create (EXCLUSIVE)
- `code/godot/godot_render_quality.cpp` — Render quality manager
- `code/godot/godot_render_quality.h` — Public API
- `code/godot/godot_render_quality_accessors.c` — C accessor for render cvars

## Implementation

### 1. C accessor for render cvars
```c
int Godot_RenderQuality_GetPicmip(void);        // r_picmip: 0-3
int Godot_RenderQuality_GetTextureMode(void);    // r_texturemode: GL_LINEAR_MIPMAP_LINEAR etc
int Godot_RenderQuality_GetAnisotropy(void);     // r_ext_texture_filter_anisotropic: 1-16
int Godot_RenderQuality_GetMultisample(void);    // r_ext_multisample: 0,2,4,8
```
Read from engine cvars via `Cvar_VariableIntegerValue()`.

### 2. Quality manager
```cpp
void Godot_RenderQuality_Init(void);
void Godot_RenderQuality_Apply(godot::Viewport *viewport);
void Godot_RenderQuality_Shutdown(void);
```

### 3. r_picmip → texture mipmap bias
- picmip 0: no bias (full quality)
- picmip 1: bias +1 (half resolution textures)
- picmip 2: bias +2 (quarter resolution)
- picmip 3: bias +3 (eighth resolution)
- Apply via `RenderingServer::texture_set_force_redraw_if_visible()` or global quality setting
- Godot 4.2: use `ProjectSettings::set_setting("rendering/textures/default_filters/texture_mipmap_bias", picmip)`

### 4. r_texturemode → filtering
- `GL_NEAREST`: nearest filtering
- `GL_LINEAR`: bilinear
- `GL_LINEAR_MIPMAP_LINEAR`: trilinear (default)
- Map to Godot `CanvasItem::TextureFilter` equivalent for 3D

### 5. Anisotropic filtering
- Map 1-16 to `ProjectSettings::set_setting("rendering/textures/default_filters/anisotropic_filtering_level", value)`

### 6. Anti-aliasing
- 0: disabled
- 2/4/8x: `viewport->set_msaa_3d(Viewport::MSAA_2X/4X/8X)`

### 7. Poll for changes
- Check cvars each second (not every frame)
- Only re-apply when values change

## Build Verification
```bash
cd openmohaa && scons platform=linux target=template_debug -j$(nproc) dev_build=yes
```

## Documentation
Append `## Phase 82: Render Quality Cvars ✅` to `TASKS.md`.

## DO NOT MODIFY
- `MoHAARunner.cpp` / `MoHAARunner.h`
