# Agent Task 50: Game Flow State Machine (Boot → Menu → Game)

## Objective
Implement the full game flow state machine in MoHAARunner that tracks the game's lifecycle from engine boot through menus to gameplay and back. The enum and skeleton already exist (`GameFlowState` in MoHAARunner.h) — this agent fills in the logic.

## Files to MODIFY
- `code/godot/MoHAARunner.cpp` — `update_game_flow_state()` method

## What Exists
```cpp
enum class GameFlowState {
    BOOT, TITLE_SCREEN, MAIN_MENU, LOADING, IN_GAME,
    PAUSED, MISSION_COMPLETE, DISCONNECTED
};
```
- `update_game_flow_state()` is called each frame in `_process()` (already wired)
- Server state accessors: `Godot_Server_GetState()` (SS_DEAD=0, SS_LOADING=1, SS_GAME=3)
- Client state accessors: `Godot_Client_GetState()` (CA_DISCONNECTED through CA_ACTIVE)
- UI state: `Godot_UI_Update()` returns menu/console/loading state

## Implementation

### 1. State transitions
```cpp
void MoHAARunner::update_game_flow_state() {
    int sv_state = Godot_Server_GetState();
    int cl_state = Godot_Client_GetState();
    
    switch (game_flow_state) {
    case GameFlowState::BOOT:
        // Engine just started — wait for main menu or auto-map
        if (cl_state >= CA_CONNECTED || sv_state >= SS_LOADING) {
            game_flow_state = GameFlowState::LOADING;
        } else if (/* UI keyCatchers has KEYCATCH_UI */) {
            game_flow_state = GameFlowState::MAIN_MENU;
        }
        break;
        
    case GameFlowState::MAIN_MENU:
        if (sv_state >= SS_LOADING) {
            game_flow_state = GameFlowState::LOADING;
        }
        break;
        
    case GameFlowState::LOADING:
        if (sv_state == SS_GAME && cl_state >= CA_ACTIVE) {
            game_flow_state = GameFlowState::IN_GAME;
        }
        break;
        
    case GameFlowState::IN_GAME:
        if (sv_state == SS_DEAD) {
            game_flow_state = GameFlowState::DISCONNECTED;
        } else if (/* cl_paused */) {
            game_flow_state = GameFlowState::PAUSED;
        }
        break;
        
    case GameFlowState::PAUSED:
        if (!/* cl_paused */) {
            game_flow_state = GameFlowState::IN_GAME;
        }
        break;
        
    case GameFlowState::DISCONNECTED:
        game_flow_state = GameFlowState::MAIN_MENU;
        break;
    }
}
```

### 2. State-dependent behaviour
- **BOOT**: Show engine initialisation messages, hide 3D scene
- **MAIN_MENU**: Show cursor, accept UI input, hide game world
- **LOADING**: Show loading screen, progress bar
- **IN_GAME**: Capture mouse, render game world, process entities
- **PAUSED**: Show pause menu, freeze entity updates
- **DISCONNECTED**: Clean up game world, return to menu

### 3. Expose to GDScript
Add `get_game_state()` method bound via `ClassDB::bind_method`:
```cpp
int MoHAARunner::get_game_state() const {
    return static_cast<int>(game_flow_state);
}
```

### 4. State-change signals
Emit Godot signals on state transitions:
```cpp
ADD_SIGNAL(MethodInfo("game_state_changed", PropertyInfo(Variant::INT, "new_state")));
// emit in update_game_flow_state() when state changes
```

## Build Verification
```bash
cd openmohaa && scons platform=linux target=template_debug -j$(nproc) dev_build=yes
```

## Documentation
Append `## Phase 261: Game Flow State Machine ✅` to `TASKS.md`.
