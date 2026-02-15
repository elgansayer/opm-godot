# Benchmark Rationale: Shadow Blob Optimization

## Overview
This document explains the performance optimization applied to `MoHAARunner::update_shadow_blobs` in `openmohaa/code/godot/MoHAARunner.cpp`.

## The Issue
The original implementation of `update_shadow_blobs` allocated a new `ArrayMesh` object every frame for every active shadow blob entity:

```cpp
// Old code inside per-entity loop:
Ref<ArrayMesh> smesh;
smesh.instantiate(); // <--- Allocation every frame
smesh->add_surface_from_arrays(Mesh::PRIMITIVE_TRIANGLES, arrays);
mi->set_mesh(smesh);
```

While Godot's `Ref<>` counting handles memory cleanup efficiently, creating and destroying generic Godot objects (which involves RID allocation in the RenderingServer) hundreds of times per second (e.g. 10 shadows * 60 FPS = 600 allocations/sec) adds unnecessary overhead to the CPU and the rendering thread.

## The Optimization
The `MeshInstance3D` objects (`mi`) in `MoHAARunner` are pooled and reused across frames. We can leverage this to reuse the `ArrayMesh` assigned to them as well.

The optimized code checks if the mesh instance already has a valid `ArrayMesh`. If so, it clears the surfaces and re-adds the new geometry. If not (first use), it allocates it.

```cpp
// New code:
Ref<ArrayMesh> smesh = mi->get_mesh();
if (smesh.is_valid()) {
    smesh->clear_surfaces(); // <--- Reuse existing RID
} else {
    smesh.instantiate();
    mi->set_mesh(smesh);
}
smesh->add_surface_from_arrays(Mesh::PRIMITIVE_TRIANGLES, arrays);
```

## Measurement and Impact
Direct FPS measurement is not feasible in the current headless CI/agent environment without running the full game loop. However, this change is a standard optimization pattern in game development ("avoid allocations in the hot path").

### Theoretical Improvements:
1.  **Reduced Heap Allocations:** Eliminates `new ArrayMesh` calls per shadow per frame.
2.  **Reduced RenderingServer Pressure:** Reusing the mesh means the underlying RID stays valid. Destroying and recreating RIDs (resources on the visual server) is more expensive than updating existing ones.
3.  **Stable Memory Usage:** Reduces memory churn/fragmentation.

This change is strictly better than the previous implementation with no change in visual output.
