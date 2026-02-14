# Agent Task 60: Rendering Parity Visual Audit

## Objective
Create a diagnostic overlay system that exposes rendering statistics and per-frame comparison data. This enables visual parity auditing between the Godot port and upstream OpenMoHAA by showing what the engine is sending vs what Godot is displaying.

## Files to CREATE
- `code/godot/godot_render_audit.cpp` — Render audit overlay + statistics
- `code/godot/godot_render_audit.h` — Header

## DO NOT MODIFY
- `code/godot/MoHAARunner.cpp` (only add 1 `#include` + `#ifdef` call)
- `code/godot/godot_renderer.c` (renderer stub is owned by other agent)
- `code/godot/godot_debug_render.cpp` (owned by agent-task-26)

## Implementation

### 1. Render audit system (`godot_render_audit.cpp`)
```cpp
#include "godot_render_audit.h"
#include <godot_cpp/classes/label.hpp>
#include <godot_cpp/classes/canvas_layer.hpp>

// Statistics tracked per frame:
struct RenderAuditStats {
    int entities_submitted;      // From gr_entities count
    int entities_rendered;       // Actually turned into MeshInstance3D
    int entities_culled;         // Skipped by PVS or frustum
    int surfaces_total;          // BSP surfaces
    int surfaces_visible;        // After PVS culling
    int triangles_world;         // World mesh tris
    int triangles_entities;      // Entity mesh tris
    int draw_calls_2d;           // HUD overlay commands
    int textures_loaded;         // Unique textures in cache
    int shaders_active;          // Shaders with active tcMod
    int polys_submitted;         // Effect polys
    int marks_active;            // Active decals
    float frame_time_ms;         // Frame budget
};

static RenderAuditStats g_audit_stats = {};

void Godot_RenderAudit_BeginFrame(void) {
    memset(&g_audit_stats, 0, sizeof(g_audit_stats));
}

void Godot_RenderAudit_RecordEntity(int submitted, int rendered, int culled) {
    g_audit_stats.entities_submitted += submitted;
    g_audit_stats.entities_rendered += rendered;
    g_audit_stats.entities_culled += culled;
}

// ... more recording functions ...

void Godot_RenderAudit_UpdateOverlay(godot::CanvasLayer *overlay) {
    // Build multi-line text with all stats
    // Display as a Label in top-right corner
    // Toggle with cvar: r_showaudit
}
```

### 2. Header (`godot_render_audit.h`)
```cpp
#pragma once

#ifdef __cplusplus
extern "C" {
#endif

void Godot_RenderAudit_BeginFrame(void);
void Godot_RenderAudit_RecordEntity(int submitted, int rendered, int culled);
void Godot_RenderAudit_RecordSurfaces(int total, int visible);
void Godot_RenderAudit_RecordTriangles(int world, int entities);
void Godot_RenderAudit_SetFrameTime(float ms);

#ifdef __cplusplus
}

namespace godot { class CanvasLayer; }
void Godot_RenderAudit_UpdateOverlay(godot::CanvasLayer *overlay);
void Godot_RenderAudit_Init(godot::CanvasLayer *parent);
void Godot_RenderAudit_Cleanup(void);
```

### 3. Statistics sources
Read from existing renderer stub buffers:
- `gr_entity_count` → entities_submitted
- `gr_2d_cmd_count` → draw_calls_2d
- `gr_poly_count` → polys_submitted
- `gr_shader_count` → textures/shaders

### 4. Cvar toggle
Check `r_speeds` cvar (already exists in engine) to enable/disable the overlay.

## Build Verification
```bash
cd openmohaa && scons platform=linux target=template_debug -j$(nproc) dev_build=yes
```

## Documentation
Append `## Phase 272: Rendering Parity Audit Overlay ✅` to `TASKS.md`.
