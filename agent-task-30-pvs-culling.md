# Agent Task 30: PVS Culling from BSP Visdata

## Objective
Implement Phase 257: Potentially Visible Set culling using BSP visibility data. The BSP file contains precomputed visibility information that tells us which clusters of the map are visible from any given cluster. This dramatically reduces the number of surfaces/entities rendered.

## Files to Create (EXCLUSIVE)
- `code/godot/godot_pvs.cpp` — PVS culling system
- `code/godot/godot_pvs.h` — Public API
- `code/godot/godot_pvs_accessors.c` — C accessor for BSP vis data

## Implementation

### 1. BSP vis data structure
The BSP `LUMP_VISIBILITY` contains run-length-encoded bit vectors. For each cluster, you can test if another cluster is visible from it.

### 2. C accessor
```c
// Get the cluster number for a world position (id Tech coordinates)
int Godot_PVS_ClusterForPoint(float x, float y, float z);

// Test if cluster B is visible from cluster A
// Uses BSP vis data (run-length decoded)
int Godot_PVS_ClusterVisible(int source_cluster, int test_cluster);

// Get total number of clusters
int Godot_PVS_GetClusterCount(void);
```
Implementation: use engine's `CM_PointLeafnum()` → `CM_LeafCluster()` for cluster lookup, and `CM_ClusterPVS()` for the vis bit vector.

### 3. PVS manager
```cpp
void Godot_PVS_Init(void);
void Godot_PVS_Shutdown(void);

// Update camera cluster (call once per frame before entity updates)
void Godot_PVS_UpdateCamera(const godot::Vector3 &camera_pos);

// Test if a world position is potentially visible from current camera
bool Godot_PVS_IsVisible(const godot::Vector3 &position);

// Test by cluster directly
bool Godot_PVS_IsClusterVisible(int cluster);

// Get current camera cluster
int Godot_PVS_GetCameraCluster(void);
```

### 4. Coordinate conversion
- Input positions in Godot coordinates → convert to id Tech 3 coordinates for BSP lookup
- Godot→id: `id.x = -godot.z * 39.37`, `id.y = -godot.x * 39.37`, `id.z = godot.y * 39.37`

### 5. Caching
- Cache the current camera cluster
- Cache the decompressed PVS bit vector for the camera cluster
- Only re-decompress when camera cluster changes (not every frame)
- `r_lockpvs` cvar support: when set, freeze the PVS to current position (debug)

### 6. Integration points
Document for MoHAARunner integration agent:
- In `update_entities()`: skip entities where `!Godot_PVS_IsVisible(entity_pos)`
- In BSP surface rendering: skip surfaces in non-visible clusters
- In audio: optionally attenuate sounds from non-visible clusters

## Build Verification
```bash
cd openmohaa && scons platform=linux target=template_debug -j$(nproc) dev_build=yes
```

## Documentation
Append `## Phase 257: PVS Culling ✅` to `TASKS.md`.

## DO NOT MODIFY
- `MoHAARunner.cpp` / `MoHAARunner.h`
- `godot_bsp_mesh.cpp` (only read BSP data via accessor)
