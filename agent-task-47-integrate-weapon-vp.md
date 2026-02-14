# Agent Task 47: Wire Weapon SubViewport for First-Person Entities

## Objective
Integrate Agent 4's weapon viewport system (`godot_weapon_viewport.cpp`) into MoHAARunner so first-person weapon models render in a separate SubViewport with correct depth (RF_FIRST_PERSON + RF_DEPTHHACK).

## Files to MODIFY
- `code/godot/MoHAARunner.cpp` — `setup_3d_scene()`, `update_entities()`, `_process()`

## What Exists
- `godot_weapon_viewport.cpp/.h` provides:
  - `Godot_WeaponViewport::get().create(parent, camera, width, height)`
  - `Godot_WeaponViewport::get().sync_camera()`
  - `Godot_WeaponViewport::get().get_weapon_root()` → Node3D*
  - `Godot_WeaponViewport::get().destroy()`
  - `Godot_WeaponViewport::get().resize(w, h)`

## Implementation

### 1. In setup_3d_scene()
```cpp
#ifdef HAS_WEAPON_VIEWPORT_MODULE
    Vector2i viewport_size = get_viewport()->get_visible_rect().size;
    Godot_WeaponViewport::get().create(this, camera, 
                                        viewport_size.x, viewport_size.y);
#endif
```

### 2. In update_entities()
For each entity, check render flags:
```cpp
    const int RF_FIRST_PERSON = 0x04;
    const int RF_DEPTHHACK = 0x08;
    
    Node3D *parent_node = entity_root; // default: world entities
    
#ifdef HAS_WEAPON_VIEWPORT_MODULE
    if (entity.renderfx & (RF_FIRST_PERSON | RF_DEPTHHACK)) {
        parent_node = Godot_WeaponViewport::get().get_weapon_root();
    }
#endif
    
    // Reparent MeshInstance3D to correct parent
    if (mesh_instance->get_parent() != parent_node) {
        if (mesh_instance->get_parent()) {
            mesh_instance->get_parent()->remove_child(mesh_instance);
        }
        parent_node->add_child(mesh_instance);
    }
```

### 3. In _process()
```cpp
#ifdef HAS_WEAPON_VIEWPORT_MODULE
    Godot_WeaponViewport::get().sync_camera();
#endif
```

### 4. On shutdown / world unload
```cpp
#ifdef HAS_WEAPON_VIEWPORT_MODULE
    Godot_WeaponViewport::get().destroy();
#endif
```

### 5. Viewport resize handling
In `_notification(int what)` or resize callback:
```cpp
#ifdef HAS_WEAPON_VIEWPORT_MODULE
    if (what == NOTIFICATION_RESIZED) {
        Vector2i new_size = get_viewport()->get_visible_rect().size;
        Godot_WeaponViewport::get().resize(new_size.x, new_size.y);
    }
#endif
```

## Build Verification
```bash
cd openmohaa && scons platform=linux target=template_debug -j$(nproc) dev_build=yes
```

## Documentation
Append `## Phase 269: Weapon Viewport Integration ✅` to `TASKS.md`.
