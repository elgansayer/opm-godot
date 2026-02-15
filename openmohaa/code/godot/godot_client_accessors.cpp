/*
 * godot_client_accessors.cpp — Thin accessors for client-side state.
 *
 * Compiled as C++ to access cl_ui.h (which uses C++ bool).
 * All public functions use extern "C" linkage so MoHAARunner.cpp
 * can call them from its own extern "C" block.
 */

#include "../client/client.h"
#include "../client/cl_ui.h"

/* For accessing the paused cvar */
extern cvar_t *paused;

extern "C" {

int Godot_Client_GetState(void) {
    return (int)clc.state;
}

int Godot_Client_GetKeyCatchers(void) {
    return cls.keyCatchers;
}

int Godot_Client_GetGuiMouse(void) {
    return (int)in_guimouse;
}

int Godot_Client_GetStartStage(void) {
    return cls.startStage;
}

void Godot_Client_GetMousePos(int *mx, int *my) {
    if (mx) *mx = cl.mousex;
    if (my) *my = cl.mousey;
}

int Godot_Client_GetPaused(void) {
    return paused ? paused->integer : 0;
}

/*
 * Force the client into game-input mode by clearing the UI key catcher,
 * disabling GUI mouse, dismissing any open menus, and unpausing.
 * Called from MoHAARunner after map load and periodically during gameplay.
 *
 * Order matters: UI_ForceMenuOff → UI_FocusMenuIfExists may re-enable
 * in_guimouse via IN_MouseOn() if a persistent menu remains.
 * We call IN_MouseOff() last to guarantee freelook mode.
 */
void Godot_Client_SetGameInputMode(void) {
    cls.keyCatchers &= ~(KEYCATCH_UI | KEYCATCH_CONSOLE);
    UI_ForceMenuOff(true);
    /* IN_MouseOff sets in_guimouse = qfalse — must come AFTER
       UI_ForceMenuOff which may call IN_MouseOn internally. */
    IN_MouseOff();
    
    /* Force unpause — in single-player listen-server mode the engine
       may auto-pause when the UI/console was active. */
    if (paused && paused->integer) {
        Cvar_Set("paused", "0");
    }
}

void Godot_Client_SetKeyCatchers(int catchers) {
    cls.keyCatchers = catchers;
}

void Godot_Client_ForceUnpause(void) {
    if (paused && paused->integer) {
        Cvar_Set("paused", "0");
    }
    IN_MouseOff();
}

/* -------------------------------------------------------------------
 *  Phase 46–55: UI system accessors
 * ---------------------------------------------------------------- */

/*
 * Godot_Client_IsUIActive — Return 1 if the engine's UI system is
 *   currently capturing input (KEYCATCH_UI flag set).
 */
int Godot_Client_IsUIActive(void) {
    return (cls.keyCatchers & KEYCATCH_UI) ? 1 : 0;
}

/*
 * Godot_Client_IsConsoleVisible — Return 1 if the console is
 *   currently capturing input (KEYCATCH_CONSOLE flag set).
 */
int Godot_Client_IsConsoleVisible(void) {
    return (cls.keyCatchers & KEYCATCH_CONSOLE) ? 1 : 0;
}

/*
 * Godot_Client_IsMessageActive — Return 1 if the chat message input
 *   is active (KEYCATCH_MESSAGE flag set).
 */
int Godot_Client_IsMessageActive(void) {
    return (cls.keyCatchers & KEYCATCH_MESSAGE) ? 1 : 0;
}

/*
 * Godot_Client_GetUIMousePos — Retrieve the engine's UI mouse
 *   coordinates.  These are the same as cl.mousex/cl.mousey but
 *   with a semantic name for UI usage.
 */
void Godot_Client_GetUIMousePos(int *mx, int *my) {
    if (mx) *mx = cl.mousex;
    if (my) *my = cl.mousey;
}

/*
 * Godot_Client_IsAnyOverlayActive — Return 1 if any overlay is
 *   capturing input (UI, console, or message mode).
 */
int Godot_Client_IsAnyOverlayActive(void) {
    return (cls.keyCatchers & (KEYCATCH_UI | KEYCATCH_CONSOLE | KEYCATCH_MESSAGE)) ? 1 : 0;
}

/*
 * Godot_Client_SetMousePos — Set the engine's UI cursor position directly.
 *   Used when transitioning to UI mode to place the cursor at a sensible
 *   position (e.g. centre of screen) instead of (0,0).
 */
void Godot_Client_SetMousePos(int x, int y) {
    cl.mousex = x;
    cl.mousey = y;
}

/*
 * Godot_Client_IsUIStarted — Return 1 if the UI system has been
 *   initialised (CL_InitializeUI completed).
 */
int Godot_Client_IsUIStarted(void) {
    return cls.uiStarted ? 1 : 0;
}

/*
 * Godot_Client_IsMenuUp — Return 1 if a menu is currently on the stack.
 *   Wraps UI_MenuUp() for the Godot side.
 */
int Godot_Client_IsMenuUp(void) {
    return UI_MenuUp() ? 1 : 0;
}

} /* extern "C" */
