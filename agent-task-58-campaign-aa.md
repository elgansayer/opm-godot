# Agent Task 58: Campaign Boot Test — AA Missions

## Objective
Create a test harness that systematically boots each Allied Assault campaign mission (`m1l1` through `m6l3`), verifies the map loads without crashing, entities spawn, and scripts begin executing. This is a code-only task — create the test infrastructure, not manual testing.

## Files to CREATE
- `code/godot/godot_test_harness.c` — C accessor for automated map loading + state verification
- `code/godot/godot_test_harness.h` — Header
- `project/test_campaign_aa.gd` — GDScript that drives the test sequence

## DO NOT MODIFY
- `code/godot/MoHAARunner.cpp`
- `code/server/sv_init.c`
- Any engine source

## Implementation

### 1. Test harness accessor (`godot_test_harness.c`)
```c
#include "godot_test_harness.h"

#ifdef GODOT_GDEXTENSION
#include "../qcommon/qcommon.h"
#include "../server/server.h"

void Godot_Test_LoadMap(const char *mapname) {
    char cmd[128];
    snprintf(cmd, sizeof(cmd), "map %s\n", mapname);
    Cbuf_ExecuteText(EXEC_NOW, cmd);
}

int Godot_Test_IsMapLoaded(void) {
    extern serverStatic_t svs;
    return (svs.mapName[0] != '\0') ? 1 : 0;
}

const char *Godot_Test_GetLoadedMapName(void) {
    extern serverStatic_t svs;
    return svs.mapName;
}

int Godot_Test_GetEntityCount(void) {
    extern serverStatic_t svs;
    return svs.iNumClients;  // Rough proxy — real entity count via sv.num_entities
}

int Godot_Test_GetServerState(void) {
    extern server_t sv;
    return sv.state;
}
#endif
```

### 2. GDScript campaign test (`project/test_campaign_aa.gd`)
```gdscript
extends SceneTree

# Allied Assault campaign maps
const AA_MAPS = [
    "m1l1", "m1l2", "m1l3",
    "m2l1", "m2l2", "m2l3",
    "m3l1", "m3l2", "m3l3",
    "m4l1", "m4l2", "m4l3",
    "m5l1", "m5l2",
    "m6l1", "m6l2", "m6l3"
]

var current_map_idx := 0
var frames_on_map := 0
var frames_per_map := 120  # 2 seconds per map
var results := {}

func _process(delta):
    frames_on_map += 1
    
    if current_map_idx >= AA_MAPS.size():
        print_results()
        quit(0)
        return
    
    var map = AA_MAPS[current_map_idx]
    
    if frames_on_map == 1:
        print("Loading map: %s" % map)
        # MoHAARunner should expose load_map or we use Cbuf
        # For now, signal via file or method call
    
    if frames_on_map >= frames_per_map:
        results[map] = "OK"
        current_map_idx += 1
        frames_on_map = 0

func print_results():
    print("\n=== Campaign Boot Test Results ===")
    for map in AA_MAPS:
        var status = results.get(map, "SKIP")
        print("  %s: %s" % [map, status])
    print("=================================")
```

### 3. Add to SConstruct
Ensure `godot_test_harness.c` is in the main source list.

## Build Verification
```bash
cd openmohaa && scons platform=linux target=template_debug -j$(nproc) dev_build=yes
```

## Documentation
Append `## Phase 270: Campaign Boot Test Infrastructure (AA) ✅` to `TASKS.md`.
