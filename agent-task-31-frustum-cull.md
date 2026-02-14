# Agent Task 31: Frustum Culling for Entities & Effects

## Objective
Implement Phase 258: camera frustum culling for entities and effects. Skip rendering any entity/effect whose bounding box is entirely outside the camera's view frustum. This reduces draw calls when many entities exist off-screen.

## Files to Create (EXCLUSIVE)
- `code/godot/godot_frustum_cull.cpp` — Frustum culling helpers
- `code/godot/godot_frustum_cull.h` — Public API

## Implementation

### 1. Public API
```cpp
void Godot_FrustumCull_Init(void);
void Godot_FrustumCull_UpdateCamera(godot::Camera3D *camera);

// Test if an AABB is visible in the current frustum
bool Godot_FrustumCull_TestAABB(const godot::AABB &bounds);

// Test if a sphere is visible in the current frustum
bool Godot_FrustumCull_TestSphere(const godot::Vector3 &center, float radius);

void Godot_FrustumCull_Shutdown(void);
```

### 2. Frustum extraction
Extract 6 frustum planes from Camera3D:
- Use `camera->get_camera_projection()` and `camera->get_camera_transform()` to build view-projection matrix
- Extract left, right, top, bottom, near, far planes from the combined matrix
- Store as `Plane` objects (Godot's built-in Plane class)

### 3. AABB test
- For each of the 6 frustum planes: find the AABB vertex most in the direction of the plane normal
- If that vertex is behind the plane: AABB is completely outside → return false
- If all planes pass: return true (potentially visible)
- Standard frustum-AABB intersection test

### 4. Sphere test
- For each plane: compute signed distance from sphere center to plane
- If distance < -radius for any plane: outside → return false
- Faster than AABB test for simple cases

### 5. Usage pattern (documented for integration agent)
```
In update_entities():
  for each entity in gr_entities[]:
    compute entity AABB (from model bounds + position)
    if !Godot_FrustumCull_TestAABB(aabb):
      skip this entity (don't create/update MeshInstance3D)
```

### 6. Stats
Track per-frame:
- entities tested, entities culled
- Available via `Godot_FrustumCull_GetStats(int *tested, int *culled)`

## Build Verification
```bash
cd openmohaa && scons platform=linux target=template_debug -j$(nproc) dev_build=yes
```

## Documentation
Append `## Phase 258: Frustum Culling ✅` to `TASKS.md`.

## DO NOT MODIFY
- `MoHAARunner.cpp` / `MoHAARunner.h`
