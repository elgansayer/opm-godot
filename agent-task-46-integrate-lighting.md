# Agent Task 46: Wire Entity Lighting (Lightgrid + Dynamic Lights)

## Objective
Integrate Agent 4's entity lighting system (`godot_entity_lighting.cpp`) into MoHAARunner's `update_entities()` so entities are properly lit by the BSP lightgrid and dynamic lights (muzzle flashes, explosions).

## Files to MODIFY
- `code/godot/MoHAARunner.cpp` — `update_entities()` method

## What Exists
- `godot_entity_lighting.cpp/.h` provides:
  - `Godot_EntityLight_Sample(x, y, z, &r, &g, &b)` — lightgrid sampling at position (id coords)
  - `Godot_EntityLight_Dlights(x, y, z, &r, &g, &b)` — dynamic light accumulation
  - `Godot_EntityLight_Combined(x, y, z, &r, &g, &b)` — both combined, clamped
- Entity buffer provides: `renderfx` flags including `RF_LIGHTING_ORIGIN` (0x0080)
- When `RF_LIGHTING_ORIGIN` is set, sample light at `lightingOrigin` instead of render origin

## Implementation

### 1. In update_entities(), after mesh is assigned
```cpp
#ifdef HAS_ENTITY_LIGHTING_MODULE
    // Get entity origin in id Tech 3 coordinates (inches)
    float id_origin[3] = { /* entity origin from gr_entities */ };
    
    // Check RF_LIGHTING_ORIGIN flag
    if (entity.renderfx & 0x0080) { // RF_LIGHTING_ORIGIN
        id_origin[0] = entity.lightingOrigin[0];
        id_origin[1] = entity.lightingOrigin[1];
        id_origin[2] = entity.lightingOrigin[2];
    }
    
    float r, g, b;
    Godot_EntityLight_Combined(id_origin[0], id_origin[1], id_origin[2], &r, &g, &b);
    
    // Apply to material
    Ref<Material> mat = mesh_instance->get_surface_override_material(0);
    if (mat.is_valid()) {
        Ref<StandardMaterial3D> std_mat = Object::cast_to<StandardMaterial3D>(mat.ptr());
        if (std_mat.is_valid()) {
            std_mat->set_albedo(std_mat->get_albedo() * Color(r, g, b));
        }
        // For ShaderMaterial: set entity_color uniform
        Ref<ShaderMaterial> shd_mat = Object::cast_to<ShaderMaterial>(mat.ptr());
        if (shd_mat.is_valid()) {
            shd_mat->set_shader_parameter("entity_color", Color(r, g, b, 1.0));
        }
    }
#endif
```

### 2. Handle Godot OmniLight3D for dynamic lights
As an alternative to material modulation, create actual OmniLight3D nodes:
```cpp
// Read gr_dlights[] and create/update OmniLight3D pool
for (int i = 0; i < dlight_count; i++) {
    float origin[3], color[3], intensity;
    Godot_Renderer_GetDlight(i, origin, color, &intensity);
    // Convert to Godot coordinates
    // Set OmniLight3D position, colour, range from intensity
}
```

### 3. Important notes
- Lightgrid positions are in id Tech 3 coordinates (X=Forward, Y=Left, Z=Up, inches)
- Do NOT convert entity origin to Godot coords before passing to lighting functions
- The lighting functions return normalised RGB in [0, 1] range
- Apply as multiplicative modulation (not additive)

## Build Verification
```bash
cd openmohaa && scons platform=linux target=template_debug -j$(nproc) dev_build=yes
```

## Documentation
Append `## Phase 268: Entity Lighting Integration ✅` to `TASKS.md`.
