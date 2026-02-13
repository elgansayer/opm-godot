# Agent Task 05: UI & Menu System

## Objective
Implement the full MOHAA UI/menu system within Godot: main menu rendering, menu input routing, drop-down console, server browser, options menus, loading screens, scoreboard, team/weapon selection, chat display, and UI sound effects. The engine's `uilib/` already compiles and manages `.urc` (UI Resource) files — this task routes its rendering and input through Godot.

## Starting Point
Read `.github/copilot-instructions.md`, `openmohaa/AGENTS.md`, and `openmohaa/TASKS.md`. The engine's UI framework (`code/uilib/`) is compiled into the monolithic build and processes `.urc` files from pk3 archives. It generates 2D draw calls that flow through `godot_renderer.c`'s 2D command buffer (`gr_2d_cmds[]`). `MoHAARunner.cpp::update_2d_overlay()` already renders these as HUD elements. `godot_client_accessors.cpp` exposes `keyCatchers`, `in_guimouse`, and `paused` state.

The key insight: the engine's uilib ALREADY handles menu logic, layout, widget state, and serialisation. Your job is to ensure its rendering output reaches Godot correctly and its input comes from Godot correctly.

## Scope — Phases 46–55, 57–58

### Phase 46: Menu Background Rendering
- `GR_DrawBackground` in `godot_renderer.c` captures raw background image data
- Render captured background as fullscreen `TextureRect` on a dedicated `CanvasLayer`
- Handle loading screen backgrounds and menu backgrounds
- Detect when `re.DrawBackground` is called vs. when it's not (toggle visibility)

### Phase 47: Main Menu Display
- The engine's UI system calls `GR_DrawStretchPic`, `GR_DrawBox`, `GR_DrawString` for menu rendering
- These already flow into `gr_2d_cmds[]` buffer
- Ensure menu-specific 2D commands render correctly (proper layering, text alignment)
- Verify `.urc` file loading from pk3 via engine VFS
- Handle menu transitions (fade in/out)

### Phase 48: Menu Input Routing
- When `KEYCATCH_UI` is set (check via `godot_client_accessors.cpp`), route ALL input to UI system
- Mouse cursor: render custom cursor sprite from `gfx/2d/` or `ui/` directory (read from VFS)
- Forward mouse position to engine's `UI_MouseEvent()` via input bridge
- Forward key presses to engine's `UI_KeyEvent()` via input bridge
- When UI is active, suppress game input (movement, look)

### Phase 49: Console Overlay
- MOHAA drop-down console (activated by `~` / backtick key)
- `KEYCATCH_CONSOLE` flag routes keyboard to console input
- Console rendering comes through 2D command buffer as text + background
- Ensure console background renders as semi-transparent overlay
- Handle console scrolling (Page Up/Down), command history (Up/Down arrows)
- Console text input already works via `SE_CHAR` events from input bridge

### Phase 50: Server Browser UI
- GameSpy master server query is handled by engine code (`code/gamespy/`)
- Server list rendering (server name, map, players, ping, game type)
- These render as UI text/list widgets via the 2D command buffer
- Handle server info request/response display
- Handle "Connect" action from the UI (sends `connect <ip>` command)

### Phase 51: Options Menu
- Video, audio, controls, game options submenus
- Cvar binding to UI sliders/checkboxes (engine uilib handles this)
- Key binding UI: capture next keypress when rebinding
- Apply/Cancel/Default button handling
- Ensure slider positions, checkboxes, and text fields render correctly

### Phase 52: Loading Screen
- Map loading progress rendering
- Loading tip text rotation
- Loading background image (screenshot or loading art)
- Handle `SCR_DrawLoading` / `SCR_UpdateScreen` during `CL_MapLoading`
- Engine calls `GR_DrawStretchPic` + `GR_DrawBox` for progress bar — ensure these render during load

### Phase 53: Scoreboard
- In-game scoreboard (Tab key or engine-triggered)
- Player names, kills, deaths, ping columns
- Team colours for team game modes
- Renders through 2D command buffer when active

### Phase 54: Team Selection / Weapon Selection
- Team selection menu (Allies/Axis/Auto/Spectator)
- Weapon selection submenu
- These are engine UI dialogs rendered via uilib
- Ensure correct keyboard/mouse navigation

### Phase 55: Chat & Message Display
- In-game chat messages (T = team, Y = all → `messagemode` / `messagemode2`)
- Kill feed / obituary messages at top of screen
- Centre-print messages (objectives, hints) via `CG_CenterPrint`
- All render through 2D command buffer — ensure text is legible and positioned correctly

### Phase 57–58: UI Polish & Edge Cases
- Modal dialog boxes (quit confirmation, disconnect confirmation)
- Mouse cursor clamping to window bounds when UI is active
- UI sound effects (click, hover) — routed through sound system
- Handle all `UI_*` commands that flow through the UI system
- Graceful handling of missing UI assets (fallback to coloured rectangles)

## Files You OWN (create or primarily modify)

### New files to create
| File | Purpose |
|------|---------|
| `code/godot/godot_ui_system.cpp` | UI rendering manager — background, cursor, menu state |
| `code/godot/godot_ui_system.h` | UI system API |
| `code/godot/godot_ui_input.cpp` | UI-specific input routing — mouse cursor, key forwarding |
| `code/godot/godot_ui_input.h` | UI input API |
| `code/godot/godot_console_accessors.c` | C accessor for console state (con_vislines, history, etc.) |

### Existing files you may modify
| File | What to change |
|------|----------------|
| `code/godot/godot_client_accessors.cpp` | Add accessors for UI mouse position, UI active state, console visible state. **Append new functions only.** |
| `code/godot/godot_input_bridge.c` | Add `Godot_InjectMousePosition(x, y)` for absolute mouse position in UI mode. **Append new function only.** |

## Files You Must NOT Touch
- `MoHAARunner.cpp` / `MoHAARunner.h` — do NOT modify. Document integration points.
- `godot_renderer.c` — READ the 2D command buffer and background data, do not modify capture logic.
- `godot_sound.c` — owned by Agent 1.
- `godot_shader_props.cpp/.h` — owned by Agent 2.
- `godot_bsp_mesh.cpp/.h` — owned by Agent 3.
- `godot_skel_model*.cpp` — owned by Agent 4.
- `SConstruct` — auto-discovers new files.

## Architecture Notes

### UI State Machine
```
States:
  UI_NONE       — game is active, no UI overlay
  UI_MAIN_MENU  — main menu active (KEYCATCH_UI set)
  UI_CONSOLE    — console overlay (KEYCATCH_CONSOLE set)
  UI_LOADING    — loading screen
  UI_SCOREBOARD — scoreboard overlay

Transitions detected by polling keyCatchers via godot_client_accessors.
```

### Mouse Cursor Rendering
```
When KEYCATCH_UI is set:
  1. Show custom cursor texture (loaded from VFS: "ui/mouse/cursor.tga" or similar)
  2. Position cursor at engine's UI mouse coordinates (cl.cgameMouseX/Y)
  3. Forward Godot mouse events as absolute position to engine UI system
  4. Set Godot mouse mode to MOUSE_MODE_VISIBLE
When KEYCATCH_UI is clear:
  1. Hide cursor
  2. Set Godot mouse mode to MOUSE_MODE_CAPTURED (for game input)
```

### Console Overlay
```
The engine renders console via SCR_DrawConsole → Con_DrawConsole which calls
GR_DrawStretchPic (background), GR_DrawSmallStringExt (text), GR_DrawBox (cursor).
These all flow into gr_2d_cmds[] — ensure they render on top of the game view
but below any modal dialogs.
```

### Loading Screen
```
During CL_MapLoading, the engine calls SCR_UpdateScreen() repeatedly.
Each call produces 2D commands for:
  - Background image (fullscreen GR_DrawStretchPic)
  - "Loading..." text
  - Progress bar (GR_DrawBox at growing width)
  - Tip text
Ensure MoHAARunner's 2D overlay processes these even during map load.
```

## Integration Points
Document in TASKS.md **"MoHAARunner Integration Required"** sections:
1. In `_process()`: call `Godot_UI_Update()` to manage cursor visibility, input mode toggling
2. In `_unhandled_input()`: check `Godot_UI_IsActive()` — if true, forward to UI input handler instead of game
3. In `update_2d_overlay()`: call `Godot_UI_RenderBackground()` before processing 2D commands
4. In `check_world_load()`: call `Godot_UI_OnMapLoad()` for loading screen management
5. Create a dedicated `CanvasLayer` for UI at higher z-index than HUD

## Build & Test
```bash
cd openmohaa && rm -f .sconsign.dblite && scons platform=linux target=template_debug -j$(nproc) dev_build=yes
```

## Documentation
Add Phase entries (46–55, 57–58) to `openmohaa/TASKS.md`.

## Merge Awareness
- You own `godot_client_accessors.cpp` — no other agent modifies it. Agents may READ your accessors.
- You share `godot_input_bridge.c` potentially with Agent 10 — **only APPEND new functions**, never modify existing ones.
- Agent 1 (Audio) may call your UI state queries to know when to play UI sounds.
- Agent 10 (Integration) wires your UI module into `MoHAARunner.cpp`.
- Engine `code/uilib/` files: you may add `#ifdef GODOT_GDEXTENSION` guards if needed for rendering hooks, but prefer using the existing 2D command buffer capture rather than modifying uilib code.
