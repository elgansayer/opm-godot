# Agent Task 45: Wire Mesh + Material Cache into Entity Updates

## Objective
Integrate Agent 4's mesh cache (`Godot_MeshCache`) and material cache (`Godot_MaterialCache`) into MoHAARunner's `update_entities()` to eliminate redundant ArrayMesh rebuilds for animated skeletal entities.

## Files to MODIFY
- `code/godot/MoHAARunner.cpp` — `update_entities()` and `_process()` methods

## What Exists
- `godot_mesh_cache.cpp/.h` provides:
  - `Godot_MeshCache::get().lookup(key)` → `Ref<ArrayMesh>` or nullptr
  - `Godot_MeshCache::get().store(key, mesh, frame_num)`
  - `Godot_MeshCache::get().evict_stale(frame_num)`
- `MaterialCacheKey` and `Godot_MaterialCache::get()` with same pattern
- `EntityMeshCacheKey`: hModel, 4 frame info slots, LOD level

## Implementation

### 1. Build cache key from entity state
In `update_entities()`, for each skeletal entity:
```cpp
#ifdef HAS_MESH_CACHE_MODULE
    EntityMeshCacheKey cache_key = {};
    cache_key.hModel = entity.hModel;
    for (int f = 0; f < 4; f++) {
        cache_key.frame_index[f] = entity.frameInfo[f].index;
        cache_key.frame_weight[f] = entity.frameInfo[f].weight;
    }
    cache_key.lod_level = /* computed from distance */;
    
    Ref<ArrayMesh> cached_mesh = Godot_MeshCache::get().lookup(cache_key);
    if (cached_mesh.is_valid()) {
        mesh_instance->set_mesh(cached_mesh);
        // Skip expensive CPU skinning rebuild
    } else {
        // Build mesh normally (existing code)
        Ref<ArrayMesh> new_mesh = /* existing build code */;
        Godot_MeshCache::get().store(cache_key, new_mesh, frame_counter);
        mesh_instance->set_mesh(new_mesh);
    }
#endif
```

### 2. Material cache
For each entity material:
```cpp
#ifdef HAS_MESH_CACHE_MODULE
    MaterialCacheKey mat_key = {};
    mat_key.shader_handle = shader_handle;
    memcpy(mat_key.rgba, entity.shaderRGBA, 4);
    mat_key.blend_mode = detected_blend_mode;
    
    Ref<Material> cached_mat = Godot_MaterialCache::get().lookup(mat_key);
    if (!cached_mat.is_valid()) {
        cached_mat = /* create material normally */;
        Godot_MaterialCache::get().store(mat_key, cached_mat, frame_counter);
    }
    mesh_instance->surface_set_material(0, cached_mat);
#endif
```

### 3. Eviction in _process()
```cpp
#ifdef HAS_MESH_CACHE_MODULE
    static int frame_counter = 0;
    frame_counter++;
    Godot_MeshCache::get().evict_stale(frame_counter);
    Godot_MaterialCache::get().evict_stale(frame_counter);
#endif
```

### 4. Clear on map change
In world unload:
```cpp
#ifdef HAS_MESH_CACHE_MODULE
    Godot_MeshCache::get().clear();
    Godot_MaterialCache::get().clear();
#endif
```

### 5. LOD integration
```cpp
#ifdef HAS_MESH_CACHE_MODULE
    float dist_inches = camera_origin_id.distance_to(entity_origin_id);
    int lod = Godot_Skel_SelectLodLevel(tiki_handle, dist_inches);
    cache_key.lod_level = lod;
#endif
```

## Build Verification
```bash
cd openmohaa && scons platform=linux target=template_debug -j$(nproc) dev_build=yes
```

## Documentation
Append `## Phase 267: Cache Integration ✅` to `TASKS.md`.
