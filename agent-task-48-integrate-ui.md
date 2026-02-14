# Agent Task 48: Wire UI System + Input Routing

## Objective
Integrate Agent 5's UI system (`godot_ui_system.cpp`, `godot_ui_input.cpp`) into MoHAARunner so menus work correctly with proper input routing and mouse cursor management.

## Files to MODIFY
- `code/godot/MoHAARunner.cpp` — `_process()`, `_unhandled_input()`, `update_2d_overlay()`

## What Exists
- `godot_ui_system.cpp/.h` provides:
  - `Godot_UI_Update()` → polls keyCatchers, returns UI state enum
  - `Godot_UI_HasBackground()` / `Godot_UI_GetBackgroundData()` — menu background
  - `Godot_UI_ShouldShowCursor()` — cursor visibility
  - `Godot_UI_ShouldCaptureInput()` — route input to UI vs game
  - `Godot_UI_IsLoading()` — map load in progress
  - `Godot_UI_OnMapLoad()` — notify UI of map load start
- `godot_ui_input.cpp/.h` provides:
  - `Godot_UI_HandleKeyEvent(key, pressed)`
  - `Godot_UI_HandleCharEvent(unicode_char)`
  - `Godot_UI_HandleMouseButton(button, pressed)`
  - `Godot_UI_HandleMouseMotion(x, y)`

## Implementation

### 1. In _process() — UI state polling
```cpp
#ifdef HAS_UI_SYSTEM_MODULE
    int ui_state = Godot_UI_Update();
    
    // Mouse cursor management
    if (Godot_UI_ShouldShowCursor()) {
        Input::get_singleton()->set_mouse_mode(Input::MOUSE_MODE_VISIBLE);
    } else {
        Input::get_singleton()->set_mouse_mode(Input::MOUSE_MODE_CAPTURED);
    }
#endif
```

### 2. In _unhandled_input() — input routing
```cpp
void MoHAARunner::_unhandled_input(const Ref<InputEvent> &event) {
#ifdef HAS_UI_INPUT_MODULE
    if (Godot_UI_ShouldCaptureInput()) {
        // Route to UI system instead of game
        Ref<InputEventKey> key_event = event;
        if (key_event.is_valid()) {
            Godot_UI_HandleKeyEvent(key_event->get_keycode(), key_event->is_pressed());
            if (key_event->is_pressed() && key_event->get_unicode() > 0) {
                Godot_UI_HandleCharEvent(key_event->get_unicode());
            }
            get_viewport()->set_input_as_handled();
            return;
        }
        Ref<InputEventMouseButton> mb_event = event;
        if (mb_event.is_valid()) {
            Godot_UI_HandleMouseButton(mb_event->get_button_index(), mb_event->is_pressed());
            get_viewport()->set_input_as_handled();
            return;
        }
        Ref<InputEventMouseMotion> mm_event = event;
        if (mm_event.is_valid()) {
            Godot_UI_HandleMouseMotion(mm_event->get_position().x, mm_event->get_position().y);
            get_viewport()->set_input_as_handled();
            return;
        }
    }
#endif
    // ... existing game input handling ...
}
```

### 3. In update_2d_overlay() — menu background
```cpp
#ifdef HAS_UI_SYSTEM_MODULE
    if (Godot_UI_HasBackground()) {
        int width, height;
        const unsigned char *bg_data = Godot_UI_GetBackgroundData(&width, &height);
        if (bg_data && width > 0 && height > 0) {
            // Create/update fullscreen TextureRect with background image
            // ... Image::create_from_data(width, height, false, FORMAT_RGBA8, data) ...
        }
    }
#endif
```

### 4. In check_world_load() — loading notification
```cpp
#ifdef HAS_UI_SYSTEM_MODULE
    Godot_UI_OnMapLoad();
#endif
```

### 5. Mode transition — reset mouse position
```cpp
#ifdef HAS_UI_INPUT_MODULE
    // When transitioning between UI and game mode, reset mouse tracking
    extern "C" void Godot_ResetMousePosition(void);
    Godot_ResetMousePosition();
#endif
```

## Build Verification
```bash
cd openmohaa && scons platform=linux target=template_debug -j$(nproc) dev_build=yes
```

## Documentation
Append `## Phase 270: UI Integration ✅` to `TASKS.md`.
