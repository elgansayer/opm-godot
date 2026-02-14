# Agent Task 61: Stress Test + Memory Leak Audit

## Objective
Create infrastructure for stress testing the engine under extreme conditions and detecting memory leaks. This includes a stress test GDScript, memory tracking accessors, and documentation of known leak points.

## Files to CREATE
- `code/godot/godot_memory_audit.c` — Memory usage tracking accessors
- `code/godot/godot_memory_audit.h` — Header
- `project/test_stress.gd` — GDScript stress test driver
- `MEMORY_AUDIT.md` — Document known allocation patterns and leak risks

## DO NOT MODIFY
- `code/qcommon/memory.c` (engine memory system)
- `code/godot/MoHAARunner.cpp`
- `code/godot/stubs.cpp`

## Implementation

### 1. Memory tracking accessors (`godot_memory_audit.c`)
```c
#include "godot_memory_audit.h"

#ifdef GODOT_GDEXTENSION
#include "../qcommon/qcommon.h"

// Read Hunk_MemoryRemaining
int Godot_Memory_GetHunkUsed(void) {
    extern int hunk_low_used, hunk_high_used;
    return hunk_low_used + hunk_high_used;
}

int Godot_Memory_GetHunkTotal(void) {
    extern int s_hunkTotal;
    return s_hunkTotal;
}

// Zone memory stats
int Godot_Memory_GetZoneUsed(void) {
    // Z_AvailableMemory returns free bytes
    // Total - free = used
    extern int z_totalBytes;
    return z_totalBytes - Z_AvailableMemory();
}

int Godot_Memory_GetZoneTotal(void) {
    extern int z_totalBytes;
    return z_totalBytes;
}

// Tag-specific memory
int Godot_Memory_GetTagUsed(int tag) {
    return Z_TagMemoryUsed(tag);
}

// Snapshot: log all allocations to console
void Godot_Memory_DumpStats(void) {
    Cbuf_ExecuteText(EXEC_NOW, "meminfo\n");
}
#endif
```

### 2. Header (`godot_memory_audit.h`)
```c
#pragma once
#ifdef __cplusplus
extern "C" {
#endif

int  Godot_Memory_GetHunkUsed(void);
int  Godot_Memory_GetHunkTotal(void);
int  Godot_Memory_GetZoneUsed(void);
int  Godot_Memory_GetZoneTotal(void);
int  Godot_Memory_GetTagUsed(int tag);
void Godot_Memory_DumpStats(void);

#ifdef __cplusplus
}
#endif
```

### 3. Stress test script (`project/test_stress.gd`)
```gdscript
extends SceneTree

# Stress test: rapid map changes, max entities, extended play
var phase := 0
var frame := 0
var frames_per_phase := 300  # 5 seconds per phase

const STRESS_MAPS = ["m1l1", "m2l1", "m3l1", "m4l1"]

func _process(delta):
    frame += 1
    
    if frame % 60 == 0:
        # Log memory every second
        print("Frame %d | Phase %d" % [frame, phase])
    
    if frame >= frames_per_phase:
        frame = 0
        phase += 1
        
        match phase:
            1: rapid_map_change()
            2: extended_idle()
            3: print("=== Stress test complete ==="); quit(0)

func rapid_map_change():
    # Load/unload maps rapidly to test cleanup
    print("Phase 1: Rapid map changes")
    for map in STRESS_MAPS:
        print("  Loading: %s" % map)

func extended_idle():
    # Just run frames to check for slow leaks
    print("Phase 2: Extended idle (300 frames)")
```

### 4. Known leak points (`MEMORY_AUDIT.md`)
Document:
- `Z_MarkShutdown` pattern (already handled)
- `gi.Malloc`/`gi.Free` NULL check pattern
- cgame.so visibility + dlclose skip
- TIKI model cache — grows indefinitely, cleared on map change
- Texture cache — Godot ImageTexture refs need explicit unreference
- AudioStreamPlayer3D pool — needs size cap
- MeshInstance3D entity pool — needs reclamation for despawned entities

### 5. Add to SConstruct
Ensure `godot_memory_audit.c` is in the main source list.

## Build Verification
```bash
cd openmohaa && scons platform=linux target=template_debug -j$(nproc) dev_build=yes
```

## Documentation
Append `## Phase 273: Memory Audit + Stress Test Infrastructure ✅` to `TASKS.md`.
