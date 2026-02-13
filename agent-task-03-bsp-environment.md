# Agent Task 03: BSP Environment, Fog, Water & Weather

## Objective
Implement BSP environment rendering features: vertex deformation (`deformVertexes`), portal surfaces, flare rendering, fog volumes, water surfaces, rain/snow weather particles, and fullbright/vertex-lit fallbacks. These are all world-geometry and environment effects that operate on BSP surfaces or spawn environmental particles.

## Starting Point
Read `.github/copilot-instructions.md`, `openmohaa/AGENTS.md`, and `openmohaa/TASKS.md`. `godot_bsp_mesh.cpp` currently parses BSP lumps (vertices, surfaces, patches, terrain) and builds `ArrayMesh` geometry. Global fog is handled in `MoHAARunner.cpp::update_camera()` via Godot's `Environment` fog. `godot_shader_props.cpp` (owned by Agent 2) provides shader property data.

## Scope — Phases 65, 69–70, 73–78

### Phase 65: Fullbright / Vertex-Lit Surface Fallback
- Some shaders have `surfaceparm nolightmap` — these should render fullbright (no lightmap multiply)
- Detect this flag in the shader properties (read from Agent 2's shader parser)
- In BSP mesh building, skip lightmap UV2 assignment for nolightmap surfaces
- Apply vertex colours directly if available, otherwise render at full brightness
- Add a C accessor `Godot_BSP_SurfaceHasLightmap(int surface_index)` if needed

### Phase 69: `deformVertexes` — Autosprite
- `deformVertexes autosprite` — billboard quads that always face camera
- `deformVertexes autosprite2` — axis-aligned billboards (rotate around longest axis)
- Parse these from shader definitions (coordinate with Agent 2's shader data structures)
- Implement as vertex shader code in generated Godot shaders OR as per-frame CPU transform
- For CPU approach: identify autosprite surfaces at load time, rebuild their vertices each frame facing camera

### Phase 70: `deformVertexes` — Wave / Bulge / Move
- `deformVertexes wave <div> <func> <base> <amp> <phase> <freq>` — sinusoidal displacement (flags, water, vegetation)
- `deformVertexes bulge <bulgeWidth> <bulgeHeight> <bulgeSpeed>` — model surface bulging
- `deformVertexes move <x> <y> <z> <func> <base> <amp> <phase> <freq>` — vertex translation
- Implement as Godot vertex shader code: pass deform parameters as uniforms
- Generate GLSL vertex shader snippets for each deform type

### Phase 73: Portal Surfaces
- `RT_PORTALSURFACE` entity type or `surfaceparm portal` surfaces = mirrors/portals
- Basic implementation: render as flat reflective surface using environment probe
- Advanced (optional): render from portal camera position via SubViewport
- At minimum: detect portal surfaces and render them distinctly (not invisible)

### Phase 74: Flare Rendering
- `MST_FLARE` surface type — lens flare sprites at light source positions
- Render as billboard quads with additive blending
- Fade with distance from camera
- Optional: occlusion check (cast ray to flare origin; hide if blocked by BSP)

### Phase 75: Volumetric Smoke & Dust
- `cg_volumetricsmoke.cpp` (in cgame) submits smoke polys via the renderer
- These arrive in the poly buffer (`gr_polys[]`) — already captured
- Ensure correct billboarding and alpha fade for smoke poly types
- Handle depth sorting for overlapping transparent smoke polys

### Phase 76: Rain & Snow Effects
- MOHAA uses server-side weather commands (`rain`, `snow`) that cgame processes
- Weather state is communicated via configstrings or entity state
- Implement as Godot `GPUParticles3D` — rain: vertical lines with splash; snow: drifting flakes
- Create `godot_weather.cpp/.h` that reads weather state from engine and manages particle nodes
- Add a C accessor to read current weather state from `cgs` (client game state)

### Phase 77: Water / Liquid Surfaces
- Water surfaces with `deformVertexes wave` (using Phase 70's implementation)
- Correct transparency from shader `surfaceparm trans` + blend mode
- Blue/green colour tinting from shader `rgbGen` or hardcoded water colour
- Ensure water surfaces sort correctly with other transparent geometry

### Phase 78: Fog Volumes (Per-Surface)
- `LUMP_FOGS` in BSP — fog regions with per-surface fog parameters
- Different from global fog (which is already in `update_camera()`)
- Each fog brush defines: colour, near distance, far distance, density
- Apply fog blending in shader code or via material property per affected surface
- Read fog lump data in `godot_bsp_mesh.cpp`

## Files You OWN (create or primarily modify)

### New files to create
| File | Purpose |
|------|---------|
| `code/godot/godot_vertex_deform.cpp` | Vertex deformation: autosprite, wave, bulge, move — GLSL generators |
| `code/godot/godot_vertex_deform.h` | Deform API: `Godot_Deform_GenerateShaderCode()`, deform type enums |
| `code/godot/godot_weather.cpp` | Rain/snow particle system manager |
| `code/godot/godot_weather.h` | Weather API: `Godot_Weather_Update()`, `Godot_Weather_Init()` |
| `code/godot/godot_weather_accessors.c` | C accessor for weather state from engine (cgs/configstrings) |

### Existing files you may modify
| File | What to change |
|------|----------------|
| `code/godot/godot_bsp_mesh.cpp` | Add fog lump parsing, fullbright surface detection, portal surface identification. **Add new functions only — do not restructure existing mesh building code.** |
| `code/godot/godot_bsp_mesh.h` | Add fog volume data structures, new function declarations |

## Files You Must NOT Touch
- `MoHAARunner.cpp` / `MoHAARunner.h` — do NOT modify. Document integration points.
- `godot_shader_props.cpp/.h` — owned by Agent 2. READ their headers for shader data.
- `godot_renderer.c` — not your domain.
- `godot_sound.c` — not your domain (Agent 1).
- `godot_skel_model*.cpp` — not your domain (Agent 4).
- `SConstruct` — auto-discovers new files.
- `stubs.cpp` — document needed stubs, don't modify.

## Architecture Notes

### Vertex Deform Shader Templates
Generate GLSL code as strings that can be inserted into Godot shaders:
```glsl
// deformVertexes wave
uniform float deform_div;
uniform float deform_base;
uniform float deform_amp;
uniform float deform_phase;
uniform float deform_freq;
void vertex() {
    float off = (VERTEX.x + VERTEX.y + VERTEX.z) * deform_div;
    float t = TIME * deform_freq + deform_phase + off;
    float wave = deform_base + deform_amp * sin(t * 6.283185);
    VERTEX += NORMAL * wave;
}
```

### Weather Particle Design
```
Rain: GPUParticles3D, volume around camera, velocity=(0, -10, 0),
      trail-mode lines, lifetime=1s, respawn at top of volume
Snow: GPUParticles3D, volume around camera, velocity=(drift, -2, drift),
      quad particles with snow texture, lifetime=3s
```

### Fog Volume Data
```cpp
struct BSPFogVolume {
    char shader[64];
    int brushNum;
    int visibleSide;
    float color[3];
    float depthForOpaque; // distance for full opacity
};
```

## Integration Points
Document in TASKS.md **"MoHAARunner Integration Required"** sections:
1. `Godot_Weather_Init()` should be called in `check_world_load()` after map load
2. `Godot_Weather_Update(delta)` should be called in `_process()` each frame
3. Vertex deform shader code needs to be injected into materials built by Agent 2's system
4. Fog volumes need to be applied to BSP surfaces during material creation
5. Fullbright detection should modify material creation in `check_world_load()`
6. Portal surfaces need special handling in entity rendering

## Build & Test
```bash
cd openmohaa && rm -f .sconsign.dblite && scons platform=linux target=template_debug -j$(nproc) dev_build=yes
```

## Documentation
Add Phase entries (65, 69–70, 73–78) to `openmohaa/TASKS.md`.

## Merge Awareness
- You exclusively own `godot_bsp_mesh.cpp/.h` — no other agent modifies these.
- Agent 2 (Shaders) owns `godot_shader_props.cpp/.h` — you READ their data structures but don't modify their files.
- Your vertex deform GLSL generators will be called by Agent 2's material builder — coordinate the API: `Godot_Deform_GenerateVertexShader(deform_type, params) → String`.
- Agent 9 (Rendering Polish) may read your fog volume data — keep the struct public in your header.
- Agent 10 (Integration) wires weather/fog into `MoHAARunner.cpp`.
