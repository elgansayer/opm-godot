# Agent Task 59: Expansion Pack Test — Spearhead + Breakthrough

## Objective
Create test infrastructure that boots Spearhead (SH) and Breakthrough (BT) expansion maps, verifying `com_target_game` switching and expansion-specific pk3 search paths work correctly.

## Files to CREATE
- `project/test_campaign_sh.gd` — GDScript that tests SH maps
- `project/test_campaign_bt.gd` — GDScript that tests BT maps

## Files to MODIFY
- `code/godot/godot_test_harness.c` — add `Godot_Test_SetTargetGame()` function

## DO NOT MODIFY
- `code/qcommon/files.cpp` (VFS)
- `code/qcommon/common.c`
- `code/godot/MoHAARunner.cpp`

## Implementation

### 1. Add target game accessor to test harness
```c
// In godot_test_harness.c:
void Godot_Test_SetTargetGame(int game) {
    // game: 0=AA, 1=SH, 2=BT
    char cmd[64];
    snprintf(cmd, sizeof(cmd), "com_target_game %d\n", game);
    Cbuf_ExecuteText(EXEC_APPEND, cmd);
}

int Godot_Test_GetTargetGame(void) {
    cvar_t *cv = Cvar_FindVar("com_target_game");
    return cv ? cv->integer : 0;
}
```

### 2. Spearhead test maps (`project/test_campaign_sh.gd`)
```gdscript
extends SceneTree

const SH_MAPS = [
    "m1l1",   # Spearhead maps use same naming
    "m2l1",
    "m3l1",
]

# Similar structure to test_campaign_aa.gd but with:
# 1. Set com_target_game 1 first
# 2. Boot SH-specific maps
# 3. Verify mainta/ pk3 files are used
```

### 3. Breakthrough test maps (`project/test_campaign_bt.gd`)
```gdscript
extends SceneTree

const BT_MAPS = [
    "m1l1",
    "m2l1",
    "m3l1",
]

# Set com_target_game 2
# Verify maintt/ pk3 files are used
```

### 4. Update header
```c
// In godot_test_harness.h:
void Godot_Test_SetTargetGame(int game);
int  Godot_Test_GetTargetGame(void);
```

## Build Verification
```bash
cd openmohaa && scons platform=linux target=template_debug -j$(nproc) dev_build=yes
```

## Documentation
Append `## Phase 271: Expansion Pack Test Infrastructure (SH/BT) ✅` to `TASKS.md`.
