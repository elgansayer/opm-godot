/*
 * stubs.cpp — Residual stubs for the Godot GDExtension build.
 *
 * With the full client + server build, most stubs that were here
 * previously are now provided by real code:
 *   CL_*       → code/client/cl_main.cpp, cl_keys.cpp, cl_scrn.cpp, etc.
 *   Key_*      → code/client/cl_keys.cpp
 *   SCR_*      → code/client/cl_scrn.cpp
 *   IN_*       → code/godot/godot_input.c
 *   S_*        → code/godot/godot_sound.c
 *   GetRefAPI  → code/godot/godot_renderer.c
 *
 * What remains here:
 *   - Sys_GetGameAPI / Sys_GetCGameAPI (monolithic DLL loading)
 *   - Sys misc stubs (platform functions not needed under Godot)
 *   - VM stubs
 *   - Renderer-thread stubs
 *   - Clipboard / registry stubs
 *   - UpdateChecker stubs (avoids pulling in cURL / json / threads)
 *   - Cursor / mouse stubs (replaces SDL mouse code)
 */

#include "../qcommon/q_shared.h"
#include "../qcommon/qcommon.h"

// sys_loadlib.h must be inside extern "C" to match C linkage of Sys_LoadDll
// (defined in sys_main.c which is compiled as C).
extern "C" {
#include "../sys/sys_loadlib.h"
}

#include <cstring>

// ──────────────────────────────────────────────
//  UpdateChecker stubs — the real implementation in sys_update_checker.cpp
//  pulls in cURL, json.hpp, and std::thread which we don't need under Godot.
//  We provide a minimal matching class so the global symbol resolves.
// ──────────────────────────────────────────────
#include "../sys/sys_update_checker.h"

// Provide the global that other TUs reference via `extern UpdateChecker updateChecker`.
UpdateChecker updateChecker;

void Sys_UpdateChecker_Init()  {}
void Sys_UpdateChecker_Process() {}
void Sys_UpdateChecker_Shutdown() {}

// UpdateChecker member functions — stubs
UpdateChecker::UpdateChecker() : lastMajor(0), lastMinor(0), lastPatch(0), versionChecked(false), thread(NULL) {}
UpdateChecker::~UpdateChecker() {}
void UpdateChecker::Init() {}
void UpdateChecker::Process() {}
void UpdateChecker::Shutdown() {}
void UpdateChecker::CheckInitClientThread() {}
bool UpdateChecker::CanHaveRequestThread() const { return false; }
void UpdateChecker::SetLatestVersion(int, int, int) {}
bool UpdateChecker::CheckNewVersion() const { return false; }
bool UpdateChecker::CheckNewVersion(int& major, int& minor, int& patch) const { return false; }

// UpdateCheckerThread — minimal stubs
UpdateCheckerThread::UpdateCheckerThread() : handle(NULL), osThread(NULL), requestThreadIsActive(qfalse), shouldBeActive(qfalse) {}
UpdateCheckerThread::~UpdateCheckerThread() {}
void UpdateCheckerThread::Init() {}
void UpdateCheckerThread::Shutdown() {}
bool UpdateCheckerThread::IsRoutineActive() const { return false; }
void UpdateCheckerThread::InitClient() {}
void UpdateCheckerThread::ShutdownClient() {}
bool UpdateCheckerThread::ParseVersionNumber(const char*, int&, int&, int&) const { return false; }
void UpdateCheckerThread::DoRequest() {}
void UpdateCheckerThread::RequestThread() {}

extern "C" {

// ──────────────────────────────────────────────
//  Sys — Game DLL loading (monolithic build)
//  Instead of dlopen, we call GetGameAPI / GetCGameAPI directly.
// ──────────────────────────────────────────────

// Forward-declare the game exports
typedef struct game_export_s game_export_t;
typedef struct game_import_s game_import_t;
extern game_export_t *GetGameAPI(game_import_t *import);

// Forward-declare the cgame export.
// NOTE: cgame is NOT compiled in the monolithic build (it shares corepp/
// with fgame but needs CGAME_DLL, which conflicts with GAME_DLL).
// Returning NULL makes the client skip cgame initialisation for now.
// A future phase will compile cgame separately or provide real stubs.

// cgame is compiled as a separate .so because it shares corepp/ with fgame
// but needs CGAME_DLL.  We load it via the engine's Sys_LoadDll (dlopen).
static void *cgame_library = NULL;

void *Sys_GetGameAPI(void *parms) {
    return (void *)GetGameAPI((game_import_t *)parms);
}

void Sys_UnloadGame(void) {
    Com_Printf("GDExtension: Sys_UnloadGame (monolithic, no-op)\n");
}

void *Sys_GetCGameAPI(void *parms) {
    typedef void *(*GetCGameAPI_t)(void);
    GetCGameAPI_t getCGameAPI;
    const char *gamename = "cgame.so";

    if (cgame_library) {
        Com_Printf("GDExtension: Sys_GetCGameAPI — already loaded\n");
        return NULL;
    }

    /* Try fs_homedatapath/game/, fs_basepath/game/, and fs_homepath/game/ */
    {
        char libPath[1024];
        const char *gameDir = Cvar_VariableString("fs_game");
        const char *paths[3];
        int i;

        if (!gameDir || !*gameDir) gameDir = "main";

        paths[0] = Cvar_VariableString("fs_homedatapath");
        paths[1] = Cvar_VariableString("fs_basepath");
        paths[2] = Cvar_VariableString("fs_homepath");

        for (i = 0; i < 3 && !cgame_library; i++) {
            if (paths[i] && *paths[i]) {
                Com_sprintf(libPath, sizeof(libPath), "%s/%s/%s", paths[i], gameDir, gamename);
                Com_Printf("GDExtension: trying cgame at \"%s\"...\n", libPath);
                cgame_library = Sys_LoadLibrary(libPath);
            }
        }
    }

    if (!cgame_library) {
        cgame_library = Sys_LoadDll(gamename, 0);
    }

    if (!cgame_library) {
        Com_Printf("GDExtension: Sys_GetCGameAPI — could not load %s, running without cgame\n", gamename);
        return NULL;
    }

    Com_Printf("GDExtension: Sys_GetCGameAPI(%s) — loaded OK\n", gamename);

    getCGameAPI = (GetCGameAPI_t)Sys_LoadFunction(cgame_library, "GetCGameAPI");
    if (!getCGameAPI) {
        Com_Printf("GDExtension: GetCGameAPI symbol not found in %s\n", gamename);
        Sys_UnloadLibrary(cgame_library);
        cgame_library = NULL;
        return NULL;
    }

    return (void *)getCGameAPI();
}

void Sys_UnloadCGame(void) {
    if (cgame_library) {
        // Do NOT dlclose cgame.so.  Template instantiations in corepp/
        // (e.g. con_arrayset<command_t>::DeleteTable) may have been
        // resolved via ELF symbol interposition to cgame.so's copies.
        // If we dlclose, those code pages become unmapped, and the main
        // .so's global C++ destructors SIGSEGV when they run at exit().
        // Leaving the handle open is harmless — the OS reclaims
        // everything at process exit (or Godot editor reload).
        Com_Printf("GDExtension: Sys_UnloadCGame — keeping cgame.so mapped (safe teardown)\n");
        cgame_library = NULL;
    }
}

// ──────────────────────────────────────────────
//  UI stubs — referenced by common.c when DEDICATED is undef'd.
//  These will be real once the UI system is fully wired.
// ──────────────────────────────────────────────

qboolean UI_GameCommand(void) {
    return qfalse;
}

void UI_ClearResource(void) {
}

// ──────────────────────────────────────────────
//  Sys — Misc system stubs
// ──────────────────────────────────────────────

void Sys_ShowConsole(int visLevel, qboolean quitOnClose) {
}

void Sys_CloseMutex(void) {
}

void Sys_InitEx(void) {
}

void Sys_ShutdownEx(void) {
}

void Sys_ProcessBackgroundTasks(void) {
}

// Registry stubs (Windows-origin, called on all platforms in some paths)
qboolean SaveRegistryInfo(qboolean user, const char *pszName, void *pvBuf, long lSize) {
    return qfalse;
}

qboolean LoadRegistryInfo(qboolean user, const char *pszName, void *pvBuf, long *plSize) {
    return qfalse;
}

qboolean IsFirstRun(void) {
    return qfalse;
}

qboolean IsNewConfig(void) {
    return qfalse;
}

qboolean IsSafeMode(void) {
    return qfalse;
}

void ClearNewConfigFlag(void) {
}

void RecoverLostAutodialData(void) {
}

// VM stubs
void VM_Forced_Unload_Start(void) {
}

void VM_Forced_Unload_Done(void) {
}

// Renderer-thread stubs (SMP rendering not used under Godot)
qboolean GLimp_SpawnRenderThread(void (*function)(void)) {
    return qfalse;
}

void *GLimp_RendererSleep(void) {
    return NULL;
}

void GLimp_FrontEndSleep(void) {
}

void GLimp_WakeRenderer(void *data) {
}

// Clipboard stubs
const char *Sys_GetWholeClipboard(void) {
    return NULL;
}

void Sys_SetClipboard(const char *contents) {
}

// ──────────────────────────────────────────────
//  Sys misc
// ──────────────────────────────────────────────

void Sys_DebugPrint(const char *msg) {
    Com_Printf("%s", msg);
}

void Sys_PrintBackTrace(void) {
}

void Sys_LV_CL_ConvertString(char *dest, const char *src, int maxlen) {
    if (dest && src) {
        strncpy(dest, src, maxlen);
        dest[maxlen - 1] = '\0';
    }
}

void Sys_LV_ConvertString(char *dest, const char *src, int maxlen) {
    if (dest && src) {
        strncpy(dest, src, maxlen);
        dest[maxlen - 1] = '\0';
    }
}

// Thread priority stubs
void SetBelowNormalThreadPriority(void) {}
void SetNormalThreadPriority(void) {}

// CL_CDKeyValidate — the original client validates CD keys
qboolean CL_CDKeyValidate(const char *key, const char *checksum) {
    return qtrue;
}

// R_ImageExists — referenced by some shared code paths
qboolean R_ImageExists(const char *name) {
    return qfalse;
}

// ──────────────────────────────────────────────
//  Cursor / mouse stubs — replace SDL mouse code (sdl_mouse.c)
//  that is not compiled in the Godot build.
// ──────────────────────────────────────────────

void IN_GetMousePosition(int *x, int *y) {
    if (x) *x = 0;
    if (y) *y = 0;
}

qboolean IN_SetCursorFromImage(const byte *pic, int width, int height, pCursorFree cursorFreeFn) {
    return qfalse;
}

void IN_FreeCursor(void) {
}

qboolean IN_IsCursorActive(void) {
    return qfalse;
}

// ──────────────────────────────────────────────
//  Sys_PumpMessageLoop — replaces SDL event pump (not used under Godot)
// ──────────────────────────────────────────────

void Sys_PumpMessageLoop(void) {
}

} // extern "C"

