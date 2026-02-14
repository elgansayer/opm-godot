# Agent Task 51: Save/Load Game Integration

## Objective
Implement save and load game support bridging the engine's native save system with Godot's player flow. The engine already implements `SV_SaveGame`/`SV_LoadGame` (in `code/server/sv_save.c`) — this agent wires the Godot-side UI triggers and state management.

## Files to CREATE
- `code/godot/godot_save_accessors.c` — C accessor for save/load operations
- `code/godot/godot_save_accessors.h` — Header

## Files to MODIFY
- `code/godot/MoHAARunner.cpp` — quick save/load key handling, save slot UI support

## DO NOT MODIFY
- `code/server/sv_save.c` (engine save implementation)
- `code/server/sv_init.c` (map loading)
- `code/godot/godot_ui_system.cpp` (owned by other agent)

## Implementation

### 1. Save accessors (`godot_save_accessors.c`)
```c
#include "godot_save_accessors.h"

#ifdef GODOT_GDEXTENSION
#include "../qcommon/qcommon.h"

void Godot_Save_QuickSave(void) {
    Cbuf_ExecuteText(EXEC_APPEND, "savegame quick\n");
}

void Godot_Save_QuickLoad(void) {
    Cbuf_ExecuteText(EXEC_APPEND, "loadgame quick\n");
}

void Godot_Save_SaveToSlot(int slot) {
    char cmd[64];
    snprintf(cmd, sizeof(cmd), "savegame slot%d\n", slot);
    Cbuf_ExecuteText(EXEC_APPEND, cmd);
}

void Godot_Save_LoadFromSlot(int slot) {
    char cmd[64];
    snprintf(cmd, sizeof(cmd), "loadgame slot%d\n", slot);
    Cbuf_ExecuteText(EXEC_APPEND, cmd);
}

int Godot_Save_SlotExists(int slot) {
    char path[256];
    snprintf(path, sizeof(path), "save/slot%d/", slot);
    // Check if directory exists via engine FS
    return FS_FileExists(path) ? 1 : 0;
}
#endif
```

### 2. Header (`godot_save_accessors.h`)
```c
#pragma once
#ifdef __cplusplus
extern "C" {
#endif

void Godot_Save_QuickSave(void);
void Godot_Save_QuickLoad(void);
void Godot_Save_SaveToSlot(int slot);
void Godot_Save_LoadFromSlot(int slot);
int  Godot_Save_SlotExists(int slot);

#ifdef __cplusplus
}
#endif
```

### 3. MoHAARunner key handling
In `_unhandled_input()`, handle F5/F9 for quick save/load:
```cpp
#if __has_include("godot_save_accessors.h")
#define HAS_SAVE_MODULE
#include "godot_save_accessors.h"
#endif

// In _unhandled_input():
#ifdef HAS_SAVE_MODULE
if (event->is_action_pressed("ui_quick_save")) {
    Godot_Save_QuickSave();
} else if (event->is_action_pressed("ui_quick_load")) {
    Godot_Save_QuickLoad();
}
#endif
```

### 4. Add to SConstruct
Ensure `godot_save_accessors.c` is in the main source list.

## Build Verification
```bash
cd openmohaa && scons platform=linux target=template_debug -j$(nproc) dev_build=yes
```

## Documentation
Append `## Phase 262: Save/Load Game Integration ✅` to `TASKS.md`.
