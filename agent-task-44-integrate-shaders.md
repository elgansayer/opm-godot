# Agent Task 44: Wire ShaderMaterial into BSP Surface Loading

## Objective
Integrate Agent 2's `Godot_Shader_BuildMaterial()` into MoHAARunner's `check_world_load()` so BSP world surfaces use proper multi-stage ShaderMaterials instead of simple StandardMaterial3D.

## Files to MODIFY (you OWN these changes in MoHAARunner.cpp)
- `code/godot/MoHAARunner.cpp` — Replace material creation in `check_world_load()` / BSP surface loading

## What Exists
- `godot_shader_material.cpp/.h` provides `Godot_Shader_BuildMaterial(const char *shader_name)` → returns `Ref<ShaderMaterial>` or empty ref
- `godot_shader_props.cpp/.h` provides `Godot_Shader_ParseProps(const char *name)` → `GodotShaderProps` struct
- Currently, BSP surfaces use `StandardMaterial3D` with single texture + optional lightmap

## Implementation

### 1. Find the BSP surface material creation code
In MoHAARunner.cpp, locate where BSP surfaces get their materials during world load. This is likely in `check_world_load()` → helper functions that build MeshInstance3D from BSP data.

### 2. Add ShaderMaterial path
```cpp
#ifdef HAS_SHADER_MATERIAL_MODULE
    Ref<ShaderMaterial> shader_mat = Godot_Shader_BuildMaterial(shader_name);
    if (shader_mat.is_valid()) {
        // Set texture uniforms
        shader_mat->set_shader_parameter("stage0_tex", texture);
        if (has_lightmap) {
            shader_mat->set_shader_parameter("lightmap_tex", lightmap_texture);
        }
        mesh->surface_set_material(surface_idx, shader_mat);
    } else
#endif
    {
        // Existing StandardMaterial3D fallback
        // ... keep current code ...
    }
```

### 3. Texture uniform naming
The shader material expects these uniforms (from Agent 2's generated GLSL):
- `stage0_tex`, `stage1_tex`, ... — per-stage primary textures
- `stage0_frame0`, `stage0_frame1`, ... — animMap frame textures
- `overbright_factor` — float, default 2.0
- `entity_color` — vec4, default (1,1,1,1)

### 4. Clear shader cache on map change
In `unload_world()` or equivalent:
```cpp
#ifdef HAS_SHADER_MATERIAL_MODULE
    Godot_Shader_ClearCache();
#endif
```

### 5. Handle deformVertexes
If `GodotShaderProps` has `deform_type != 0`, the shader material already includes vertex deformation GLSL from Agent 3. No extra handling needed.

### 6. Coordinate with material cache
If Agent 4's material cache is available:
```cpp
#ifdef HAS_MESH_CACHE_MODULE
    // Check material cache before building
    MaterialCacheKey key = { shader_handle, {255,255,255,255}, blend_mode };
    Ref<Material> cached = Godot_MaterialCache::get().lookup(key);
    if (cached.is_valid()) {
        mesh->surface_set_material(surface_idx, cached);
    } else {
        // Build new material...
        Godot_MaterialCache::get().store(key, new_material, frame_number);
    }
#endif
```

## Build Verification
```bash
cd openmohaa && scons platform=linux target=template_debug -j$(nproc) dev_build=yes
```

## Documentation
Append `## Phase 266: ShaderMaterial Integration ✅` to `TASKS.md`.
