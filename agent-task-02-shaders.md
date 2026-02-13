# Agent Task 02: Multi-Stage Shader & Material System

## Objective
Implement full MOHAA shader rendering parity: multi-stage shaders, `rgbGen`/`alphaGen` wave functions, `animMap` texture sequences, `tcGen environment`/`vector`/`lightmap`, and Godot `ShaderMaterial` generation. This replaces the current single-stage `StandardMaterial3D` approach with proper multi-pass shader compositing.

## Starting Point
Read `.github/copilot-instructions.md`, `openmohaa/AGENTS.md`, and `openmohaa/TASKS.md` for full context. `godot_shader_props.cpp/.h` currently parses `.shader` files and extracts basic properties (transparency, blend mode, cull, tcMod, skybox). It only reads the first texture stage. Many MOHAA shaders have 2+ stages (base + lightmap + detail) with per-stage `rgbGen`, `alphaGen`, `tcGen`, and `tcMod` directives.

## Scope — Phases 66–68, 71–72

### Phase 66: Multi-Stage Shader Parsing & Rendering
- Extend `godot_shader_props.cpp` to parse ALL stages from `.shader` files, not just the first
- Each stage has: `map <texture>`, `blendFunc`, `rgbGen`, `alphaGen`, `tcGen`, `tcMod`, `clampMap`, `animMap`
- Store stages in a `std::vector<ShaderStage>` per shader definition
- Generate Godot shader code (GLSL-like `.gdshader`) that composites multiple stages
- Create a function `Godot_Shader_BuildMaterial(shader_handle)` → returns `Ref<ShaderMaterial>` with correct multi-stage compositing
- Handle common patterns: base texture + lightmap multiply, base + detail additive, base + glow additive

### Phase 67: Environment Mapping (`tcGen environment`)
- Implement view-dependent UV generation for reflective surfaces
- Compute environment UVs from view direction and surface normal in Godot shader code
- `tcGen environment` generates UVs as: `s = reflect.x * 0.5 + 0.5; t = reflect.y * 0.5 + 0.5`
- Apply as a shader stage that can be composited with other stages

### Phase 68: Animated Texture Sequences (`animMap`)
- Parse `animMap <fps> <tex1> <tex2> ...` directives
- Load all frames at init, store in the shader stage data
- Generate shader code that cycles frames by elapsed time (`TIME` uniform)
- Expose animation time to shader via material uniform updated per-frame

### Phase 71: `rgbGen wave` / `alphaGen wave`
- Implement wave functions: `sin`, `triangle`, `square`, `sawtooth`, `inversesawtooth`
- `rgbGen wave <func> <base> <amplitude> <phase> <frequency>` — modulates RGB per frame
- `alphaGen wave <func> <base> <amplitude> <phase> <frequency>` — modulates alpha per frame
- Generate GLSL wave function code in the `.gdshader`
- Also handle: `rgbGen identity`, `rgbGen identityLighting`, `rgbGen vertex`, `rgbGen entity`, `rgbGen oneMinusEntity`, `rgbGen lightingDiffuse`
- Also handle: `alphaGen portal <dist>`, `alphaGen entity`, `alphaGen oneMinusEntity`, `alphaGen vertex`

### Phase 72: `tcGen lightmap` / `tcGen vector`
- `tcGen lightmap` — use lightmap UV coordinates (UV2 channel) for this stage
- `tcGen vector ( <sx> <sy> <sz> ) ( <tx> <ty> <tz> )` — project UVs from world-space position using two direction vectors
- Generate correct UV selection in shader code per stage

## Files You OWN (create or primarily modify)

### New files to create
| File | Purpose |
|------|---------|
| `code/godot/godot_shader_material.cpp` | Multi-stage shader → Godot ShaderMaterial builder |
| `code/godot/godot_shader_material.h` | Public API: `Godot_Shader_BuildMaterial()`, stage structs |

### Existing files you may modify
| File | What to change |
|------|----------------|
| `code/godot/godot_shader_props.cpp` | Extend parser to extract ALL stages (not just first), add `rgbGen`/`alphaGen`/`tcGen`/`animMap` parsing |
| `code/godot/godot_shader_props.h` | Add `ShaderStage` struct with per-stage properties, extend `ShaderProps` to hold `std::vector<ShaderStage>` |

## Files You Must NOT Touch
- `MoHAARunner.cpp` / `MoHAARunner.h` — do NOT modify. Document integration points.
- `godot_renderer.c` — not your domain.
- `godot_sound.c` — not your domain (Agent 1).
- `godot_bsp_mesh.cpp/.h` — not your domain (Agent 3).
- `godot_skel_model*.cpp/.h` — not your domain (Agent 4).
- `SConstruct` — auto-discovers new files in `code/godot/`.
- `stubs.cpp` — document needed stubs, don't modify.

## Architecture Notes

### Shader Stage Structure
```cpp
struct ShaderStage {
    char map[MAX_QPATH];        // texture path or "$lightmap"
    int blendSrc, blendDst;     // GL blend factors → Godot equivalents
    char rgbGen[64];            // "identity", "vertex", "wave sin 0 1 0 1", "entity", etc.
    char alphaGen[64];          // "portal 256", "wave sin ...", "entity", etc.
    char tcGen[64];             // "base", "lightmap", "environment", "vector ..."
    char tcMod[4][128];         // up to 4 tcMod directives per stage
    int tcModCount;
    float animMapFreq;          // animMap frequency (0 = not animated)
    char animMapFrames[8][MAX_QPATH]; // animMap frame textures
    int animMapFrameCount;
    bool isClampMap;            // clampMap vs map
    bool isLightmap;            // stage uses $lightmap
};
```

### Godot Shader Code Generation
Generate `.gdshader` code as a string, create `Shader` resource, set on `ShaderMaterial`:
```gdshader
shader_type spatial;
render_mode blend_mix, unshaded;  // or blend_add, etc.
uniform sampler2D stage0_tex;
uniform sampler2D stage1_tex;  // $lightmap or detail
uniform float time_offset;
void fragment() {
    vec4 s0 = texture(stage0_tex, UV);
    vec4 s1 = texture(stage1_tex, UV2);  // lightmap uses UV2
    ALBEDO = s0.rgb * s1.rgb * 2.0;     // overbright multiply
    ALPHA = s0.a;
}
```

### Wave Function GLSL Template
```glsl
float wave_sin(float base, float amp, float phase, float freq, float t) {
    return base + amp * sin((t * freq + phase) * 6.283185);
}
float wave_triangle(float base, float amp, float phase, float freq, float t) {
    float p = fract(t * freq + phase);
    return base + amp * (p < 0.5 ? p * 4.0 - 1.0 : 3.0 - p * 4.0);
}
// ... square, sawtooth, inversesawtooth
```

## Integration Points
Provide in your TASKS.md a **"MoHAARunner Integration Required"** section listing:
1. Where `Godot_Shader_BuildMaterial(handle)` should be called instead of the current `StandardMaterial3D` creation
2. How animated shaders need `TIME` uniform updates each frame (currently done in `update_shader_animations()`)
3. Any new material cache invalidation needed

The current material creation happens in several places in `MoHAARunner.cpp`:
- `check_world_load()` — BSP surface materials
- `update_entities()` — entity materials
- `update_polys()` — poly/particle materials
- `get_shader_texture()` — texture lookup helper

Your module should be a drop-in replacement callable from those locations.

## Build & Test
```bash
cd openmohaa && rm -f .sconsign.dblite && scons platform=linux target=template_debug -j$(nproc) dev_build=yes
```
Must compile cleanly. No game assets needed for compilation.

## Documentation
Add Phase entries (66–68, 71–72) to `openmohaa/TASKS.md`. Include a **"MoHAARunner Integration Required"** section per phase.

## Merge Awareness
- You exclusively own `godot_shader_props.cpp/.h` — no other agent modifies these.
- Agent 3 (BSP/Environment) reads your headers to apply materials to surfaces — keep the public API stable.
- Agent 4 (Entity Rendering) reads your headers for entity materials.
- Agent 9 (Rendering Polish) may add gamma/overbright corrections — your shader generation should expose hooks for this (e.g. `uniform float overbright_factor`).
- Agent 10 (Integration) will wire your material builder into `MoHAARunner.cpp`.
