#include "MoHAARunner.h"
#include "godot_bsp_mesh.h"
#include "godot_skel_model.h"
#include "godot_shader_props.h"
#include <godot_cpp/variant/utility_functions.hpp>
#include <godot_cpp/classes/input.hpp>
#include <godot_cpp/classes/input_event_key.hpp>
#include <godot_cpp/classes/input_event_mouse_motion.hpp>
#include <godot_cpp/classes/input_event_mouse_button.hpp>
#include <godot_cpp/variant/basis.hpp>
#include <godot_cpp/variant/vector3.hpp>
#include <godot_cpp/variant/transform3d.hpp>
#include <godot_cpp/classes/box_mesh.hpp>
#include <godot_cpp/classes/sphere_mesh.hpp>
#include <godot_cpp/classes/standard_material3d.hpp>
#include <godot_cpp/classes/omni_light3d.hpp>
#include <godot_cpp/classes/rendering_server.hpp>
#include <godot_cpp/classes/canvas_layer.hpp>
#include <godot_cpp/classes/control.hpp>
#include <godot_cpp/classes/image.hpp>
#include <godot_cpp/classes/image_texture.hpp>
#include <godot_cpp/classes/texture_rect.hpp>
#include <godot_cpp/classes/sky.hpp>
#include <godot_cpp/classes/cubemap.hpp>
#include <godot_cpp/classes/shader.hpp>
#include <godot_cpp/classes/shader_material.hpp>
#include <godot_cpp/classes/display_server.hpp>
#include <cstdio>
#include <cstring>
#include <cmath>
#include <cstdlib>
#include <unordered_set>
#include <setjmp.h>

// From register_types.cpp — track engine lifecycle across module boundary
extern void Godot_SetEngineInitialized(bool v);

extern "C" {
    // Core engine entry points
    void Com_Init(char *commandLine);
    void Com_Frame(void);
    void Com_Shutdown(void);
    void Z_MarkShutdown(void);

    // Pre-init steps from sys_main.c / sys_unix.c that main() normally calls
    void Sys_PlatformInit(void);
    void Sys_SetBinaryPath(const char *path);
    void Sys_SetDefaultInstallPath(const char *path);
    void CON_Init(void);
    void NET_Init(void);
    int  Sys_Milliseconds(void);

    // Command buffer
    void Cbuf_AddText(const char *text);
    void Cbuf_ExecuteText(int exec_when, const char *text);

    // Server state — from server.h (we only read these, never write)
    // serverState_t enum: SS_DEAD=0, SS_LOADING=1, SS_LOADING2=2, SS_GAME=3
    typedef struct {
        int state;   // serverState_t — first field of server_t
        // rest of struct omitted; we only need 'state'
    } server_t_partial;

    // serverStatic_t — we access mapName and iNumClients
    // These are at known offsets in the struct. To avoid depending on
    // the full struct layout, we declare extern accessor functions instead.
    int  Godot_GetServerState(void);
    const char *Godot_GetMapName(void);
    int  Godot_GetPlayerCount(void);

    // VFS accessors (Task 4.1) — from godot_vfs_accessors.c
    long Godot_VFS_ReadFile(const char *qpath, void **out_buffer);
    void Godot_VFS_FreeFile(void *buffer);
    int  Godot_VFS_FileExists(const char *qpath);
    char **Godot_VFS_ListFiles(const char *directory, const char *extension, int *out_count);
    void Godot_VFS_FreeFileList(char **list);
    const char *Godot_VFS_GetGamedir(void);

    // Input bridge (Phase 6) — from godot_input_bridge.c
    int  Godot_InjectKeyEvent(int godot_key, int down);
    void Godot_InjectCharEvent(int unicode);
    void Godot_InjectMouseMotion(int dx, int dy);
    void Godot_InjectMouseButton(int godot_button, int down);

    // Renderer / camera bridge (Phase 7a) — from godot_renderer.c
    int  Godot_Renderer_HasNewFrame(void);
    void Godot_Renderer_ClearNewFrame(void);
    int  Godot_Renderer_GetFrameCount(void);
    void Godot_Renderer_GetViewOrigin(float *out);
    void Godot_Renderer_GetViewAxis(float *out);
    void Godot_Renderer_GetFov(float *fov_x, float *fov_y);
    void Godot_Renderer_GetRenderSize(int *w, int *h);
    void Godot_Renderer_GetFarplane(float *distance, float *bias, float *color, int *cull);
    const char *Godot_Renderer_GetWorldMapName(void);
    int  Godot_Renderer_IsWorldMapLoaded(void);

    // Entity/light bridge (Phase 7e) — from godot_renderer.c
    int  Godot_Renderer_GetEntityCount(void);
    int  Godot_Renderer_GetEntity(int index,
                                  float *origin, float *axis, float *out_scale,
                                  int *hModel, int *entityNumber,
                                  unsigned char *rgba, int *renderfx);
    void Godot_Renderer_GetEntityBeam(int index,
                                      float *from, float *to, float *diameter);
    int  Godot_Renderer_GetDlightCount(void);
    void Godot_Renderer_GetDlight(int index,
                                  float *origin, float *intensity,
                                  float *r, float *g, float *b, int *type);

    // Poly bridge (Phase 16) — from godot_renderer.c
    int  Godot_Renderer_GetPolyCount(void);
    int  Godot_Renderer_GetPoly(int index, int *hShader,
                                float *positions, float *texcoords,
                                unsigned char *colors, int maxVerts);

    // Sprite entity data (Phase 16) — from godot_renderer.c
    void Godot_Renderer_GetEntitySprite(int index, float *radius,
                                        float *rotation, int *customShader);

    // 2D overlay bridge (Phase 7h) — from godot_renderer.c
    int  Godot_Renderer_Get2DCmdCount(void);
    int  Godot_Renderer_Get2DCmd(int index,
                                 int *type,
                                 float *x, float *y, float *w, float *h,
                                 float *s1, float *t1, float *s2, float *t2,
                                 float *color, int *shader);
    const char *Godot_Renderer_GetShaderName(int handle);
    int  Godot_Renderer_GetShaderCount(void);
    int  Godot_Renderer_RegisterShader(const char *name);
    void Godot_Renderer_GetVidSize(int *w, int *h);
    /* Phase 52 remap uses Godot_Renderer_GetShaderRemap declared below */

    // Sound bridge (Phase 8) — from godot_sound.c
    int  Godot_Sound_GetSfxCount(void);
    const char *Godot_Sound_GetSfxName(int index);
    int  Godot_Sound_GetSfxHandle(int index);
    int  Godot_Sound_FindSfxIndex(int handle);
    int  Godot_Sound_GetEventCount(void);
    int  Godot_Sound_GetEvent(int index, float *origin, int *entnum,
                              int *channel, int *sfxHandle, float *volume,
                              float *minDist, float *maxDist, float *pitch,
                              int *streamed, char *nameOut, int nameLen);
    void Godot_Sound_ClearEvents(void);
    int  Godot_Sound_GetLoopCount(void);
    void Godot_Sound_GetLoop(int index, float *origin, float *velocity,
                             int *sfxHandle, float *volume, float *minDist,
                             float *maxDist, float *pitch, int *flags);
    void Godot_Sound_GetListener(float *origin, float *axis, int *entnum);
    int  Godot_Sound_GetMusicAction(void);
    const char *Godot_Sound_GetMusicName(void);
    float Godot_Sound_GetMusicVolume(void);
    float Godot_Sound_GetMusicFadeTime(void);
    void Godot_Sound_ClearMusicAction(void);

    // Phase 49-51: New sound accessors
    int   Godot_Sound_GetEntityPosition(int entnum, float *origin, float *velocity);
    float Godot_Sound_GetFadeTime(void);
    float Godot_Sound_GetFadeTarget(void);
    int   Godot_Sound_GetFadeActive(void);
    void  Godot_Sound_ClearFade(void);
    int   Godot_Sound_GetReverbType(void);
    float Godot_Sound_GetReverbLevel(void);
    int   Godot_Sound_GetPlayingCount(void);
    int   Godot_Sound_GetPlaying(int index, int *channel, int *sfxHandle,
                                  char *name, int nameLen);
    void  Godot_Sound_MarkStopped(int channel);
    int   Godot_Sound_GetMusicMood(int *current, int *fallback);
    int   Godot_Sound_GetTriggeredAction(void);
    const char *Godot_Sound_GetTriggeredName(void);
    int   Godot_Sound_GetTriggeredLoopCount(void);
    int   Godot_Sound_GetTriggeredOffset(void);
    void  Godot_Sound_ClearTriggeredAction(void);
    int   Godot_Sound_FindSfxIndex(int handle);

    // Model bridge (Phase 9) — from godot_renderer.c + godot_skel_model_accessors.cpp
    void *Godot_Model_GetTikiPtr(int hModel);
    int   Godot_Model_GetType(int hModel);
    int   Godot_Model_Register(const char *name);
    const char *Godot_Model_GetName(int hModel);

    // Client diagnostics (Phase 6 debug) — from godot_client_accessors.cpp
    int  Godot_Client_GetState(void);
    int  Godot_Client_GetKeyCatchers(void);
    int  Godot_Client_GetGuiMouse(void);
    int  Godot_Client_GetStartStage(void);
    void Godot_Client_GetMousePos(int *mx, int *my);
    void Godot_Client_SetGameInputMode(void);
    void Godot_Client_SetKeyCatchers(int catchers);
    int  Godot_Client_GetPaused(void);
    void Godot_Client_ForceUnpause(void);

    // Cinematic bridge (Phase 11) — from godot_renderer.c
    int  Godot_Renderer_IsCinematicActive(void);
    int  Godot_Renderer_GetCinematicFrame(const unsigned char **out_data,
                                          int *out_width, int *out_height);
    void Godot_Renderer_SetCinematicInactive(void);

    // Skeletal animation bridge (Phase 13) — from godot_renderer.c + godot_skel_model_accessors.cpp
    int   Godot_Renderer_GetEntityAnim(int index,
                                        void **outTiki, int *outEntityNumber,
                                        void *outFrameInfo, int *outBoneTag,
                                        float *outBoneQuat, float *outActionWeight,
                                        float *outScale);
    void *Godot_Skel_PrepareBones(void *tikiPtr, int entityNumber,
                                   const void *frameInfo, const int *bone_tag,
                                   const float *bone_quat, float actionWeight,
                                   int *outBoneCount);
    int   Godot_Skel_SkinSurface(void *tikiPtr, int meshIndex, int surfIndex,
                                  const void *boneCache, int boneCount,
                                  float *outPositions, float *outNormals);
    int   Godot_Skel_GetMeshCount(void *tikiPtr);
    float Godot_Skel_GetScale(void *tikiPtr);
    void  Godot_Skel_GetOrigin(void *tikiPtr, float *out);
    int   Godot_Skel_GetSurfaceCount(void *tikiPtr, int meshIndex);
    int   Godot_Skel_GetSurfaceInfo(void *tikiPtr, int meshIndex, int surfIndex,
                                     int *numVerts, int *numTriangles,
                                     char *surfName, int surfNameLen,
                                     char *shaderName, int shaderNameLen);
    int   Godot_Skel_GetSurfaceVertices(void *tikiPtr, int meshIndex, int surfIndex,
                                         float *positions, float *normals, float *texcoords);
    int   Godot_Skel_GetSurfaceIndices(void *tikiPtr, int meshIndex, int surfIndex,
                                        int *indices);

    // Phase 35: Entity parenting — from godot_renderer.c
    int   Godot_Renderer_GetEntityParent(int index);

    // Phase 268: Entity lighting origin — from godot_renderer.c
    void  Godot_Renderer_GetEntityLightingOrigin(int index, float *out);

    // Phase 26: Shader remap query — from godot_renderer.c
    const char *Godot_Renderer_GetShaderRemap(const char *shaderName);

    // Phase 24: Swipe effect accessor — from godot_renderer.c
    int   Godot_Renderer_GetSwipeData(float *thisTime, float *life,
                                      int *hShader, int *numPoints);
    void  Godot_Renderer_GetSwipePoint(int index, float *point1, float *point2,
                                       float *time);

    // Phase 25: Terrain mark accessor — from godot_renderer.c
    int   Godot_Renderer_GetTerrainMarkCount(void);
    void  Godot_Renderer_GetTerrainMark(int index, int *hShader, int *numVerts,
                                        int *terrainIndex, int *renderfx);
    void  Godot_Renderer_GetTerrainMarkVert(int markIndex, int vertIndex,
                                            float *xyz, float *st,
                                            unsigned char *rgba);

    // Phase 32: Scissor state — from godot_renderer.c
    void  Godot_Renderer_GetScissor(int *x, int *y, int *width, int *height);

    // Phase 33: Background image accessor — from godot_renderer.c
    int   Godot_Renderer_GetBackground(int *cols, int *rows, int *bgr,
                                       const unsigned char **data);
}

// ──────────────────────────────────────────────
//  Error / quit interception (Task 2.5.2)
// ──────────────────────────────────────────────

// Jump buffer for recovering from Sys_Error / Sys_Quit under Godot
static jmp_buf godot_error_jmpbuf;
static bool    godot_jmpbuf_valid = false;

static bool    godot_has_fatal_error = false;
static char    godot_error_message[1024] = {0};
static bool    godot_quit_requested = false;

// Called from patched Sys_Error in sys_main.c
extern "C" void Godot_SysError(const char *error) {
    strncpy(godot_error_message, error, sizeof(godot_error_message) - 1);
    godot_error_message[sizeof(godot_error_message) - 1] = '\0';
    godot_has_fatal_error = true;

    if (godot_jmpbuf_valid) {
        longjmp(godot_error_jmpbuf, 1);
    }
    // If no jmpbuf is set up, we can't recover — log and hope for the best
    fprintf(stderr, "[MoHAA] FATAL ERROR (no recovery point): %s\n", error);
}

// Called from patched Sys_Quit in sys_main.c
extern "C" void Godot_SysQuit(void) {
    godot_quit_requested = true;

    if (godot_jmpbuf_valid) {
        longjmp(godot_error_jmpbuf, 2);
    }
    fprintf(stderr, "[MoHAA] Quit requested (no recovery point)\n");
}

// ──────────────────────────────────────────────
//  Godot print redirect
// ──────────────────────────────────────────────

static bool g_godot_ready = false;

extern "C" void Godot_SysPrint(const char *msg) {
    if (g_godot_ready) {
        // Strip trailing newline for cleaner Godot output
        godot::String s(msg);
        if (s.ends_with("\n")) {
            s = s.substr(0, s.length() - 1);
        }
        godot::UtilityFunctions::print(s);
    } else {
        // Before Godot is fully ready, fall back to stdout
        fputs(msg, stdout);
    }
}

// ──────────────────────────────────────────────
//  MoHAARunner implementation
// ──────────────────────────────────────────────

// ── Coordinate conversion helpers (Phase 7a) ──
//
// id Tech 3 (MOHAA): X = Forward, Y = Left, Z = Up  (right-handed, Z-up)
// Godot 4:           X = Right,   Y = Up,   -Z = Forward  (right-handed, Y-up)
//
// Point conversion:
//   Godot.x = -idTech.y
//   Godot.y =  idTech.z
//   Godot.z = -idTech.x
//
// The same formula applies to direction vectors.

static inline Vector3 id_to_godot_point(float ix, float iy, float iz) {
    return Vector3(-iy, iz, -ix);
}

// MOHAA uses Q3-era map units where 1 unit ≈ 1 inch.
// Godot's default units are metres.  We scale by 1/39.37 (inches → metres)
// so geometry and player speed feel correct.
static constexpr float MOHAA_UNIT_SCALE = 1.0f / 39.37f;

static inline Vector3 id_to_godot_position(float ix, float iy, float iz) {
    return Vector3(-iy * MOHAA_UNIT_SCALE, iz * MOHAA_UNIT_SCALE, -ix * MOHAA_UNIT_SCALE);
}

static inline float clamp01(float v) {
    if (v < 0.0f) return 0.0f;
    if (v > 1.0f) return 1.0f;
    return v;
}

MoHAARunner::MoHAARunner() {
}

MoHAARunner::~MoHAARunner() {
    if (initialized) {
        Com_Shutdown();
        /* Mark zone allocator as shut down.  Global C++ destructors
           (e.g. ~con_arrayset for Event::commandList) run after this
           during exit() and must not call Z_Free on stale zone data. */
        Z_MarkShutdown();
        initialized = false;
        Godot_SetEngineInitialized(false);
    } else {
        /* Even if not initialized, mark shutdown as safety net */
        Z_MarkShutdown();
    }

    // ── Module shutdown hooks (defensive) ──
#ifdef HAS_WEAPON_VIEWPORT_MODULE
    Godot_WeaponViewport::get().destroy();
#endif
#ifdef HAS_SPEAKER_ENTITIES_MODULE
    Godot_Speakers_Shutdown();
#endif
#ifdef HAS_UBERSOUND_MODULE
    Godot_Ubersound_Shutdown();
#endif
#ifdef HAS_MESH_CACHE_MODULE
    Godot_MeshCache::get().clear();
    Godot_MaterialCache::get().clear();
#endif
#ifdef HAS_SHADER_MATERIAL_MODULE
    Godot_Shader_ClearCache();
#endif

    g_godot_ready = false;
}

void MoHAARunner::_bind_methods() {
    // Engine lifecycle
    godot::ClassDB::bind_method(godot::D_METHOD("is_engine_initialized"), &MoHAARunner::is_engine_initialized);
    godot::ClassDB::bind_method(godot::D_METHOD("get_basepath"), &MoHAARunner::get_basepath);
    godot::ClassDB::bind_method(godot::D_METHOD("set_basepath", "path"), &MoHAARunner::set_basepath);
    godot::ClassDB::bind_method(godot::D_METHOD("get_startup_args"), &MoHAARunner::get_startup_args);
    godot::ClassDB::bind_method(godot::D_METHOD("set_startup_args", "args"), &MoHAARunner::set_startup_args);

    // Commands
    godot::ClassDB::bind_method(godot::D_METHOD("execute_command", "command"), &MoHAARunner::execute_command);
    godot::ClassDB::bind_method(godot::D_METHOD("load_map", "map_name"), &MoHAARunner::load_map);

    // Server status (Task 2.5.3)
    godot::ClassDB::bind_method(godot::D_METHOD("is_map_loaded"), &MoHAARunner::is_map_loaded);
    godot::ClassDB::bind_method(godot::D_METHOD("get_current_map"), &MoHAARunner::get_current_map);
    godot::ClassDB::bind_method(godot::D_METHOD("get_player_count"), &MoHAARunner::get_player_count);
    godot::ClassDB::bind_method(godot::D_METHOD("get_server_state"), &MoHAARunner::get_server_state);
    godot::ClassDB::bind_method(godot::D_METHOD("get_server_state_string"), &MoHAARunner::get_server_state_string);

    // VFS access (Task 4.1)
    godot::ClassDB::bind_method(godot::D_METHOD("vfs_read_file", "qpath"), &MoHAARunner::vfs_read_file);
    godot::ClassDB::bind_method(godot::D_METHOD("vfs_file_exists", "qpath"), &MoHAARunner::vfs_file_exists);
    godot::ClassDB::bind_method(godot::D_METHOD("vfs_list_files", "directory", "extension"), &MoHAARunner::vfs_list_files);
    godot::ClassDB::bind_method(godot::D_METHOD("vfs_get_gamedir"), &MoHAARunner::vfs_get_gamedir);

    // Input control (Phase 6)
    godot::ClassDB::bind_method(godot::D_METHOD("set_mouse_captured", "captured"), &MoHAARunner::set_mouse_captured);
    godot::ClassDB::bind_method(godot::D_METHOD("is_mouse_captured"), &MoHAARunner::is_mouse_captured);
    godot::ClassDB::bind_method(godot::D_METHOD("set_hud_visible", "visible"), &MoHAARunner::set_hud_visible);
    godot::ClassDB::bind_method(godot::D_METHOD("is_hud_visible"), &MoHAARunner::is_hud_visible);

    // Game flow state (Phase 261)
    godot::ClassDB::bind_method(godot::D_METHOD("get_game_flow_state"), &MoHAARunner::get_game_flow_state);
    godot::ClassDB::bind_method(godot::D_METHOD("get_game_flow_state_string"), &MoHAARunner::get_game_flow_state_string);

    // New game flow (Phase 262)
    godot::ClassDB::bind_method(godot::D_METHOD("start_new_game", "difficulty"), &MoHAARunner::start_new_game);
    godot::ClassDB::bind_method(godot::D_METHOD("set_difficulty", "difficulty"), &MoHAARunner::set_difficulty);

    // Save / load game (Phase 264)
    godot::ClassDB::bind_method(godot::D_METHOD("quick_save"), &MoHAARunner::quick_save);
    godot::ClassDB::bind_method(godot::D_METHOD("quick_load"), &MoHAARunner::quick_load);
    godot::ClassDB::bind_method(godot::D_METHOD("save_game", "slot_name"), &MoHAARunner::save_game);
    godot::ClassDB::bind_method(godot::D_METHOD("load_game", "slot_name"), &MoHAARunner::load_game);
    godot::ClassDB::bind_method(godot::D_METHOD("get_save_list"), &MoHAARunner::get_save_list);

    // Multiplayer helpers (Phases 265-266)
    godot::ClassDB::bind_method(godot::D_METHOD("list_available_maps"), &MoHAARunner::list_available_maps);
    godot::ClassDB::bind_method(godot::D_METHOD("start_server", "map", "gametype", "max_clients"), &MoHAARunner::start_server);
    godot::ClassDB::bind_method(godot::D_METHOD("connect_to_server", "address"), &MoHAARunner::connect_to_server);
    godot::ClassDB::bind_method(godot::D_METHOD("disconnect_from_server"), &MoHAARunner::disconnect_from_server);

    // Multiplayer server browser + hosting (Phase 263)
    godot::ClassDB::bind_method(godot::D_METHOD("host_server", "map", "maxplayers", "gametype"), &MoHAARunner::host_server);
    godot::ClassDB::bind_method(godot::D_METHOD("refresh_server_list"), &MoHAARunner::refresh_server_list);
    godot::ClassDB::bind_method(godot::D_METHOD("refresh_lan"), &MoHAARunner::refresh_lan);
    godot::ClassDB::bind_method(godot::D_METHOD("get_server_count"), &MoHAARunner::get_server_count);

    // Settings helpers (Phases 267-270)
    godot::ClassDB::bind_method(godot::D_METHOD("set_audio_volume", "master", "music", "dialog"), &MoHAARunner::set_audio_volume);
    godot::ClassDB::bind_method(godot::D_METHOD("set_video_fullscreen", "fullscreen"), &MoHAARunner::set_video_fullscreen);
    godot::ClassDB::bind_method(godot::D_METHOD("set_video_resolution", "width", "height"), &MoHAARunner::set_video_resolution);
    godot::ClassDB::bind_method(godot::D_METHOD("set_network_rate", "preset"), &MoHAARunner::set_network_rate);

    // Menu control (Phase 261)
    godot::ClassDB::bind_method(godot::D_METHOD("open_main_menu"), &MoHAARunner::open_main_menu);
    godot::ClassDB::bind_method(godot::D_METHOD("close_menu"), &MoHAARunner::close_menu);

    // Properties
    ADD_PROPERTY(godot::PropertyInfo(godot::Variant::STRING, "basepath"), "set_basepath", "get_basepath");
    ADD_PROPERTY(godot::PropertyInfo(godot::Variant::STRING, "startup_args"), "set_startup_args", "get_startup_args");
    ADD_PROPERTY(godot::PropertyInfo(godot::Variant::BOOL, "hud_visible"), "set_hud_visible", "is_hud_visible");

    // Signals (Task 2.5.4)
    ADD_SIGNAL(godot::MethodInfo("engine_error", godot::PropertyInfo(godot::Variant::STRING, "message")));
    ADD_SIGNAL(godot::MethodInfo("map_loaded", godot::PropertyInfo(godot::Variant::STRING, "map_name")));
    ADD_SIGNAL(godot::MethodInfo("map_unloaded"));
    ADD_SIGNAL(godot::MethodInfo("engine_shutdown_requested"));
    ADD_SIGNAL(godot::MethodInfo("game_flow_state_changed", godot::PropertyInfo(godot::Variant::INT, "new_state")));
}

bool MoHAARunner::is_engine_initialized() const {
    return initialized;
}

godot::String MoHAARunner::get_basepath() const {
    return basepath;
}

void MoHAARunner::set_basepath(const godot::String &p_path) {
    basepath = p_path;
}

void MoHAARunner::set_startup_args(const godot::String &p_args) {
    if (initialized) {
        UtilityFunctions::printerr("[MoHAA] set_startup_args ignored after init.");
        return;
    }
    startup_args = p_args;
}

godot::String MoHAARunner::get_startup_args() const {
    return startup_args;
}

// ──────────────────────────────────────────────
//  3D scene setup (Phase 7a)
// ──────────────────────────────────────────────

void MoHAARunner::setup_3d_scene() {
    // Create a Node3D root for all 3D content
    game_world = memnew(Node3D);
    game_world->set_name("GameWorld");
    add_child(game_world);

    // Camera3D — driven by engine refdef_t each frame
    camera = memnew(Camera3D);
    camera->set_name("EngineCamera");
    camera->set_fov(80.0);   // will be overridden by engine fov_y
    camera->set_near(0.05);  // 2 inches in id units → ~5cm
    camera->set_far(8000.0 * MOHAA_UNIT_SCALE);  // ~200 metres
    camera->set_keep_aspect_mode(Camera3D::KEEP_HEIGHT);
    camera->set_current(true);
    game_world->add_child(camera);

    // Basic directional light so geometry is visible once we have meshes
    sun_light = memnew(DirectionalLight3D);
    sun_light->set_name("SunLight");
    // Aim roughly downward at 45° — a temporary placeholder
    sun_light->set_rotation(Vector3(Math::deg_to_rad(-45.0), Math::deg_to_rad(30.0), 0.0));
    sun_light->set_shadow_mode(DirectionalLight3D::SHADOW_PARALLEL_4_SPLITS);
    sun_light->set_param(Light3D::PARAM_ENERGY, 1.0);
    game_world->add_child(sun_light);

    // WorldEnvironment with basic ambient light
    world_env = memnew(WorldEnvironment);
    world_env->set_name("WorldEnv");
    Ref<Environment> env;
    env.instantiate();
    env->set_background(Environment::BG_COLOR);
    env->set_bg_color(Color(0.4, 0.5, 0.6));   // light grey-blue sky
    env->set_ambient_source(Environment::AMBIENT_SOURCE_COLOR);
    env->set_ambient_light_color(Color(0.3, 0.3, 0.3));
    env->set_ambient_light_energy(0.5);

    // Phase 81: MOHAA's GL1 renderer has no tonemapping — it outputs
    // texture × lightmap directly to the framebuffer.  Use LINEAR
    // tonemapper with exposure 1.0 to avoid any colour distortion.
    env->set_tonemapper(Environment::TONE_MAPPER_LINEAR);
    env->set_tonemap_exposure(1.0);
    env->set_tonemap_white(1.0);
    world_env->set_environment(env);
    game_world->add_child(world_env);

    UtilityFunctions::print("[MoHAA] 3D scene created (Camera3D + light + environment).");

    // ── Phase 62: Create weapon SubViewport for first-person weapon rendering ──
#ifdef HAS_WEAPON_VIEWPORT_MODULE
    {
        int vp_w = 1280, vp_h = 720;  // Default; will be resized when window size is known
        Godot_WeaponViewport::get().create(this, camera, vp_w, vp_h);
        UtilityFunctions::print("[MoHAA] Weapon SubViewport created.");
    }
#endif
}

// ──────────────────────────────────────────────
//  Camera update (Phase 7a)
// ──────────────────────────────────────────────

void MoHAARunner::update_camera() {
    if (!camera) return;
    if (!Godot_Renderer_HasNewFrame()) return;

    // Read viewpoint from the engine's last RenderScene call
    float origin[3];
    float axis[9];  // viewaxis[0..2], each 3 floats
    float fov_x, fov_y;

    Godot_Renderer_GetViewOrigin(origin);
    Godot_Renderer_GetViewAxis(axis);
    Godot_Renderer_GetFov(&fov_x, &fov_y);
    Godot_Renderer_ClearNewFrame();

    // ── Position ──
    // Convert from id Tech 3 coords (inches) to Godot coords (metres)
    Vector3 pos = id_to_godot_position(origin[0], origin[1], origin[2]);
    camera->set_global_position(pos);

    // ── Orientation ──
    // Engine viewaxis[0] = forward, [1] = left, [2] = up  (in id coords)
    // Convert each axis direction vector to Godot coordinates
    // (direction vectors: no scale, just coordinate swap)
    float *fwd = &axis[0];  // viewaxis[0]
    float *lft = &axis[3];  // viewaxis[1]
    float *up  = &axis[6];  // viewaxis[2]

    Vector3 forward_g = id_to_godot_point(fwd[0], fwd[1], fwd[2]);
    Vector3 left_g    = id_to_godot_point(lft[0], lft[1], lft[2]);
    Vector3 up_g      = id_to_godot_point(up[0],  up[1],  up[2]);

    // Godot Basis columns: x = right, y = up, z = back
    // right = -left,  back = -forward
    Vector3 right_g = -left_g;
    Vector3 back_g  = -forward_g;

    Basis basis(right_g, up_g, back_g);
    camera->set_global_transform(Transform3D(basis, pos));

    // ── FOV ──
    // Engine provides vertical fov_y in degrees; Godot's Camera3D.fov
    // is vertical FOV when keep_aspect == KEEP_HEIGHT
    if (fov_y > 1.0f && fov_y < 170.0f) {
        camera->set_fov((double)fov_y);
    }

    // ── Far plane (fog distance) ──
    float fp_dist = 0.0f;
    float fp_bias = 0.0f;
    float fp_color[3] = {0, 0, 0};
    int   fp_cull = 0;
    Godot_Renderer_GetFarplane(&fp_dist, &fp_bias, fp_color, &fp_cull);
    if (fp_dist > 0.0f) {
        camera->set_far((double)(fp_dist * MOHAA_UNIT_SCALE));

        // ── Fog rendering ──
        // MOHAA uses GL_LINEAR fog: FOG_START = farplane_bias,
        // FOG_END = farplane_distance.  Godot 4.2 only has exponential
        // density fog (no depth_begin/depth_end).  We approximate the
        // linear [bias, distance] range with a conservative density:
        //   density = 1.0 / (distance_metres)
        // This gives ~63% fog at the far plane and ~16% at the bias
        // point.  The trade-off (some fog before the bias point) is
        // unavoidable with exponential-only fog, but far better than
        // the old 2.3/dist formula which produced 90% fog at the far
        // plane and ~34% at the bias point — making distant geometry
        // appear fully white.
        Ref<Environment> env = world_env->get_environment();
        if (env.is_valid()) {
            float fog_dist = fp_dist * MOHAA_UNIT_SCALE;
            if (fog_dist < 1.0f) fog_dist = 1.0f;
            // Conservative density: ~63% fog at far plane, ~16% at bias
            float density = 1.0f / fog_dist;
            env->set_fog_enabled(true);
            env->set_fog_light_color(Color(fp_color[0], fp_color[1], fp_color[2]));
            env->set_fog_density(density);
            env->set_fog_sky_affect(1.0f);
        }
    } else {
        // No fog configured — disable and use default far plane
        Ref<Environment> env = world_env->get_environment();
        if (env.is_valid() && env->is_fog_enabled()) {
            env->set_fog_enabled(false);
        }
    }
}

// ──────────────────────────────────────────────
//  BSP world loading (Phase 7b)
// ──────────────────────────────────────────────

void MoHAARunner::check_world_load() {
    if (!game_world) return;

    // Check if the renderer has flagged a new world map
    if (!Godot_Renderer_IsWorldMapLoaded()) {
        // World unloaded — remove existing BSP mesh
        if (bsp_map_node) {
            bsp_map_node->queue_free();
            bsp_map_node = nullptr;
            static_model_root = nullptr;  // child of bsp_map_node, freed with it
            loaded_bsp_name = "";
            GodotSkelModelCache::get().clear();  // Invalidate model cache
            skel_mesh_cache.clear();              // Phase 60: Clear skinned mesh cache
            tinted_mat_cache.clear();             // Phase 61: Clear tinted material cache
#ifdef HAS_MESH_CACHE_MODULE
            Godot_MeshCache::get().clear();
            Godot_MaterialCache::get().clear();
#endif
#ifdef HAS_SHADER_MATERIAL_MODULE
            Godot_Shader_ClearCache();
#endif
#ifdef HAS_SPEAKER_ENTITIES_MODULE
            Godot_Speakers_Shutdown();
#endif
            UtilityFunctions::print("[MoHAA] BSP world unloaded.");
        }
        return;
    }

    const char *map_path = Godot_Renderer_GetWorldMapName();
    if (!map_path || !map_path[0]) return;

    String new_bsp(map_path);
    if (new_bsp == loaded_bsp_name) return;  // Same map already loaded

    // Remove old BSP mesh if any
    if (bsp_map_node) {
        bsp_map_node->queue_free();
        bsp_map_node = nullptr;
        Godot_BSP_Unload();
    }

    // Load new BSP geometry
    UtilityFunctions::print(String("[MoHAA] Loading BSP world: ") + new_bsp);

    Node3D *map_node = Godot_BSP_LoadWorld(map_path);
    if (map_node) {
        game_world->add_child(map_node);
        bsp_map_node = map_node;
        loaded_bsp_name = new_bsp;
        UtilityFunctions::print("[MoHAA] BSP world added to scene.");

        // Instantiate static TIKI models from BSP data
        load_static_models();
        UtilityFunctions::print(String("[MoHAA] Static models loaded for: ") + new_bsp);

        // Load skybox cubemap from sky shader (Phase 12)
        load_skybox();
        UtilityFunctions::print(String("[MoHAA] Loading load_skybox: ") + new_bsp);

        // ── Module hooks for world load (defensive) ──
#ifdef HAS_WEATHER_MODULE
        Godot_Weather_Init(game_world);
            // Phase 63+64: Combined lightgrid + dynamic light sampling
            float lr, lg, lb;
            float sample_origin[3] = { origin[0], origin[1], origin[2] };
            Godot_EntityLight_Combined(sample_origin, 4 /* max dlights per entity */, &lr, &lg, &lb);
            light_mul = Color(lr, lg, lb, 1.0f);
        }
#else
        {
            float ambient[3] = {1.0f, 1.0f, 1.0f};
            float directed[3] = {0.0f, 0.0f, 0.0f};
            float ldir[3] = {0.0f, 0.0f, 1.0f};
            float point[3] = { origin[0], origin[1], origin[2] };
            int lit = Godot_BSP_LightForPoint(point, ambient, directed, ldir);
            if (lit) {
                light_mul = Color(clamp01(ambient[0] + directed[0] * 0.5f),
                                  clamp01(ambient[1] + directed[1] * 0.5f),
                                  clamp01(ambient[2] + directed[2] * 0.5f),
                                  1.0f);
            }
        }
#endif
        bool has_light_tint = fabsf(light_mul.r - 1.0f) > 0.02f ||
                              fabsf(light_mul.g - 1.0f) > 0.02f ||
                              fabsf(light_mul.b - 1.0f) > 0.02f;
        bool has_tint  = (rgba[0] != 255 || rgba[1] != 255 || rgba[2] != 255);
        bool has_alpha = (rgba[3] < 255) || (renderfx & 0x0400);
        if (has_tint || has_alpha || has_light_tint) {
            Ref<Mesh> mesh = mi->get_mesh();
            if (mesh.is_valid()) {
                // Phase 61: Quantise light to 4-bit and combine with RGBA for cache key
                uint8_t lr = (uint8_t)(light_mul.r * 15.0f + 0.5f);
                uint8_t lg = (uint8_t)(light_mul.g * 15.0f + 0.5f);
                uint8_t lb = (uint8_t)(light_mul.b * 15.0f + 0.5f);
                uint32_t light_q = ((uint32_t)lr << 8) | ((uint32_t)lg << 4) | lb;

                Color tint(rgba[0] / 255.0f, rgba[1] / 255.0f,
                           rgba[2] / 255.0f, rgba[3] / 255.0f);
                int sc = mesh->get_surface_count();
                for (int s = 0; s < sc; s++) {
                    // Build tinted material cache key:
                    //   hModel(16b) | surfIdx(4b) | rgba_q(16b=4×4b) | light_q(12b) = 48 bits
                    uint8_t rq = rgba[0] >> 4, gq = rgba[1] >> 4;
                    uint8_t bq = rgba[2] >> 4, aq = rgba[3] >> 4;
                    uint64_t tint_key = ((uint64_t)(hModel & 0xFFFF) << 32) |
                                        ((uint64_t)(s & 0xF) << 28) |
                                        ((uint64_t)rq << 24) |
                                        ((uint64_t)gq << 20) |
                                        ((uint64_t)bq << 16) |
                                        ((uint64_t)aq << 12) |
                                        (uint64_t)(light_q & 0xFFF);

                    auto tint_it = tinted_mat_cache.find(tint_key);
                    if (tint_it != tinted_mat_cache.end()) {
                        mi->set_surface_override_material(s, tint_it->second);
                    } else {
                        Ref<Material> base_mat = mi->get_surface_override_material(s);
                        if (base_mat.is_null())
                            base_mat = mesh->surface_get_material(s);

                        Ref<StandardMaterial3D> smat = base_mat;
                        if (smat.is_valid()) {
                            Ref<StandardMaterial3D> dup = smat->duplicate();
                            Color existing = dup->get_albedo();
                            dup->set_albedo(Color(existing.r * tint.r * light_mul.r,
                                                   existing.g * tint.g * light_mul.g,
                                                   existing.b * tint.b * light_mul.b,
                                                   existing.a * tint.a));
                            if (has_alpha) {
                                dup->set_transparency(BaseMaterial3D::TRANSPARENCY_ALPHA);
                            }
                            tinted_mat_cache[tint_key] = dup;
                            mi->set_surface_override_material(s, dup);
                        }
                    }
                }
            }
        }

        mi->set_visible(true);
        entity_cache_keys[i] = key;
    }

    // Hide excess pool meshes from previous frame
    for (int i = ent_count; i < active_entity_count; i++) {
        if (i < (int)entity_meshes.size()) {
            entity_meshes[i]->set_visible(false);
        }
    }

    active_entity_count = ent_count;

    // ── Phase 35: Entity parenting — apply parent transforms ──
    // After all entities are positioned, composite children's transforms
    // with their parent entity's world transform.
    for (int i = 0; i < ent_count; i++) {
        int parentIdx = Godot_Renderer_GetEntityParent(i);
        if (parentIdx < 0 || parentIdx >= ent_count) continue;
        // parentIdx is by entity number — find the matching entity in the list
        // by searching for the entity whose entityNumber matches parentIdx
        MeshInstance3D *child = entity_meshes[i];
        if (!child->is_visible()) continue;

        // The parentIdx from the renderer is the entity number, not the
        // array index. Search for matching entity in the scene list.
        MeshInstance3D *parent = nullptr;
        for (int j = 0; j < ent_count; j++) {
            if (j == i) continue;
            float pOrig[3], pAxis[9], pScale;
            int pModel, pEntNum, pRfx;
            unsigned char pRgba[4];
            Godot_Renderer_GetEntity(j, pOrig, pAxis, &pScale,
                                     &pModel, &pEntNum, pRgba, &pRfx);
            if (pEntNum == parentIdx) {
                parent = entity_meshes[j];
                break;
            }
        }

        if (parent && parent->is_visible()) {
            // Apply parent's world transform to child
            Transform3D parent_xform = parent->get_global_transform();
            Transform3D child_xform  = child->get_global_transform();
            // Child's position is already in world space — make it relative
            // to parent by compositing the transforms
            child->set_global_transform(parent_xform * child_xform);
        }
    }
}

void MoHAARunner::update_dlights() {
    if (!game_world) return;

    int dl_count = Godot_Renderer_GetDlightCount();

    // Log dlight count once when first lights appear
    static bool logged_dlight_count = false;
    if (!logged_dlight_count && dl_count > 0) {
        UtilityFunctions::print(String("[MoHAA] Dynamic lights in frame: ") +
                                String::num_int64(dl_count));
        logged_dlight_count = true;
    }

    // Grow the dynamic light pool if needed
    while ((int)dlight_nodes.size() < dl_count) {
        OmniLight3D *light = memnew(OmniLight3D);
        light->set_name(String("DLight_") + String::num_int64((int64_t)dlight_nodes.size()));
        light->set_visible(false);
        light->set_param(Light3D::PARAM_ATTENUATION, 1.5);  // smoother falloff
        game_world->add_child(light);
        dlight_nodes.push_back(light);
    }

    for (int i = 0; i < dl_count; i++) {
        float origin[3], intensity = 0.0f;
        float r = 1.0f, g = 1.0f, b = 1.0f;
        int type = 0;

        Godot_Renderer_GetDlight(i, origin, &intensity, &r, &g, &b, &type);

        OmniLight3D *light = dlight_nodes[i];
        Vector3 pos = id_to_godot_position(origin[0], origin[1], origin[2]);
        light->set_global_position(pos);
        light->set_color(Color(r, g, b));
        // Convert intensity from id units to Godot energy + range
        float range_metres = intensity * MOHAA_UNIT_SCALE;
        light->set_param(Light3D::PARAM_RANGE, range_metres);
        light->set_param(Light3D::PARAM_ENERGY, 2.0);
        light->set_visible(true);
    }

    // Hide excess lights from previous frame
    for (int i = dl_count; i < active_dlight_count; i++) {
        if (i < (int)dlight_nodes.size()) {
            dlight_nodes[i]->set_visible(false);
        }
    }

    active_dlight_count = dl_count;
}

// ──────────────────────────────────────────────
//  Poly/particle rendering (Phase 16)
// ──────────────────────────────────────────────

void MoHAARunner::update_polys() {
    if (!game_world) return;

    int poly_count = Godot_Renderer_GetPolyCount();

    // Log poly count once
    static bool logged_poly_count = false;
    if (!logged_poly_count && poly_count > 0) {
        UtilityFunctions::print(String("[MoHAA] Polys in frame: ") +
                                String::num_int64(poly_count));
        logged_poly_count = true;
    }

    if (poly_count == 0 && active_poly_count == 0) return;

    // Create poly container on first use
    if (!poly_root) {
        poly_root = memnew(Node3D);
        poly_root->set_name("Polys");
        game_world->add_child(poly_root);
    }

    // Grow mesh pool if needed
    while ((int)poly_meshes.size() < poly_count) {
        MeshInstance3D *mi = memnew(MeshInstance3D);
        mi->set_name(String("Poly_") + String::num_int64((int64_t)poly_meshes.size()));
        mi->set_visible(false);
        poly_root->add_child(mi);
        poly_meshes.push_back(mi);
    }

    for (int i = 0; i < poly_count; i++) {
        int hShader = 0;
        float positions[4 * 3];    // max 4 verts (quads)
        float texcoords[4 * 2];
        unsigned char colors[4 * 4];

        int numVerts = Godot_Renderer_GetPoly(i, &hShader,
                                               positions, texcoords,
                                               colors, 4);

        MeshInstance3D *mi = poly_meshes[i];

        if (numVerts < 3) {
            mi->set_visible(false);
            continue;
        }

        // Clamp to 4 max (quads is the common case)
        if (numVerts > 4) numVerts = 4;

        // Build an ArrayMesh triangle fan from the poly vertices
        PackedVector3Array gPos;
        PackedVector2Array gUV;
        PackedColorArray   gCol;
        PackedInt32Array   gIdx;

        gPos.resize(numVerts);
        gUV.resize(numVerts);
        gCol.resize(numVerts);

        for (int v = 0; v < numVerts; v++) {
            gPos.set(v, id_to_godot_position(
                positions[v*3+0], positions[v*3+1], positions[v*3+2]));
            gUV.set(v, Vector2(texcoords[v*2+0], texcoords[v*2+1]));
            gCol.set(v, Color(colors[v*4+0] / 255.0f,
                              colors[v*4+1] / 255.0f,
                              colors[v*4+2] / 255.0f,
                              colors[v*4+3] / 255.0f));
        }

        // Triangle fan: 0‒1‒2, 0‒2‒3, ...
        int numTris = numVerts - 2;
        gIdx.resize(numTris * 3);
        for (int t = 0; t < numTris; t++) {
            gIdx.set(t*3+0, 0);
            gIdx.set(t*3+1, t + 1);
            gIdx.set(t*3+2, t + 2);
        }

        Array arrays;
        arrays.resize(Mesh::ARRAY_MAX);
        arrays[Mesh::ARRAY_VERTEX] = gPos;
        arrays[Mesh::ARRAY_TEX_UV] = gUV;
        arrays[Mesh::ARRAY_COLOR]  = gCol;
        arrays[Mesh::ARRAY_INDEX]  = gIdx;

        Ref<ArrayMesh> mesh;
        mesh.instantiate();
        mesh->add_surface_from_arrays(Mesh::PRIMITIVE_TRIANGLES, arrays);
        mi->set_mesh(mesh);

        // Material: textured + vertex colour + alpha blend, double-sided
        Ref<StandardMaterial3D> mat;
        mat.instantiate();
        mat->set_cull_mode(BaseMaterial3D::CULL_DISABLED);
        mat->set_transparency(BaseMaterial3D::TRANSPARENCY_ALPHA);
        mat->set_flag(BaseMaterial3D::FLAG_ALBEDO_FROM_VERTEX_COLOR, true);
        mat->set_shading_mode(BaseMaterial3D::SHADING_MODE_UNSHADED);
        mat->set_flag(BaseMaterial3D::FLAG_DISABLE_DEPTH_TEST, false);
        mat->set_depth_draw_mode(BaseMaterial3D::DEPTH_DRAW_DISABLED);

        // Try to apply the poly's shader texture
        if (hShader > 0) {
            Ref<ImageTexture> tex = get_shader_texture(hShader);
            if (tex.is_valid()) {
                mat->set_texture(BaseMaterial3D::TEXTURE_ALBEDO, tex);
            }
        }

        mi->set_surface_override_material(0, mat);
        mi->set_visible(true);
    }

    // Hide excess polys from previous frame
    for (int i = poly_count; i < active_poly_count; i++) {
        if (i < (int)poly_meshes.size()) {
            poly_meshes[i]->set_visible(false);
        }
    }

    active_poly_count = poly_count;
}

// ──────────────────────────────────────────────
//  Swipe effects (Phase 24)
// ──────────────────────────────────────────────

void MoHAARunner::update_swipe_effects() {
    if (!game_world) return;

    float thisTime, life;
    int hShader, numPoints;
    if (!Godot_Renderer_GetSwipeData(&thisTime, &life, &hShader, &numPoints) || numPoints < 2) {
        if (swipe_mesh) swipe_mesh->set_visible(false);
        return;
    }

    // Create container on first use
    if (!swipe_root) {
        swipe_root = memnew(Node3D);
        swipe_root->set_name("SwipeEffects");
        game_world->add_child(swipe_root);
    }
    if (!swipe_mesh) {
        swipe_mesh = memnew(MeshInstance3D);
        swipe_mesh->set_name("SwipeTrail");
        swipe_root->add_child(swipe_mesh);
    }

    // Build a triangle strip mesh from swipe points
    PackedVector3Array gPos;
    PackedVector2Array gUV;
    PackedInt32Array   gIdx;
    gPos.resize(numPoints * 2);
    gUV.resize(numPoints * 2);

    for (int i = 0; i < numPoints; i++) {
        float p1[3], p2[3], time;
        Godot_Renderer_GetSwipePoint(i, p1, p2, &time);

        Vector3 gp1 = id_to_godot_position(p1[0], p1[1], p1[2]);
        Vector3 gp2 = id_to_godot_position(p2[0], p2[1], p2[2]);
        float t = (float)i / (float)(numPoints - 1);

        gPos.set(i * 2,     gp1);
        gPos.set(i * 2 + 1, gp2);
        gUV.set(i * 2,     Vector2(t, 0));
        gUV.set(i * 2 + 1, Vector2(t, 1));
    }

    // Triangle indices for the strip
    for (int i = 0; i < numPoints - 1; i++) {
        int base = i * 2;
        gIdx.push_back(base);
        gIdx.push_back(base + 1);
        gIdx.push_back(base + 2);
        gIdx.push_back(base + 1);
        gIdx.push_back(base + 3);
        gIdx.push_back(base + 2);
    }

    Array arrays;
    arrays.resize(Mesh::ARRAY_MAX);
    arrays[Mesh::ARRAY_VERTEX] = gPos;
    arrays[Mesh::ARRAY_TEX_UV] = gUV;
    arrays[Mesh::ARRAY_INDEX]  = gIdx;

    Ref<ArrayMesh> smesh;
    smesh.instantiate();
    smesh->add_surface_from_arrays(Mesh::PRIMITIVE_TRIANGLES, arrays);
    swipe_mesh->set_mesh(smesh);

    // Material: alpha-blended, unshaded, double-sided
    Ref<StandardMaterial3D> mat;
    mat.instantiate();
    mat->set_cull_mode(BaseMaterial3D::CULL_DISABLED);
    mat->set_transparency(BaseMaterial3D::TRANSPARENCY_ALPHA);
    mat->set_shading_mode(BaseMaterial3D::SHADING_MODE_UNSHADED);
    if (hShader > 0) {
        Ref<ImageTexture> tex = get_shader_texture(hShader);
        if (tex.is_valid()) {
            mat->set_texture(BaseMaterial3D::TEXTURE_ALBEDO, tex);
        }
    }
    swipe_mesh->set_surface_override_material(0, mat);
    swipe_mesh->set_global_transform(Transform3D());
    swipe_mesh->set_visible(true);
}

// ──────────────────────────────────────────────
//  Terrain mark decals (Phase 25)
// ──────────────────────────────────────────────

void MoHAARunner::update_terrain_marks() {
    if (!game_world) return;

    int markCount = Godot_Renderer_GetTerrainMarkCount();
    if (markCount <= 0) {
        for (int i = 0; i < active_terrain_mark_count; i++) {
            if (i < (int)terrain_mark_meshes.size())
                terrain_mark_meshes[i]->set_visible(false);
        }
        active_terrain_mark_count = 0;
        return;
    }

    // Create container on first use
    if (!terrain_mark_root) {
        terrain_mark_root = memnew(Node3D);
        terrain_mark_root->set_name("TerrainMarks");
        game_world->add_child(terrain_mark_root);
    }

    // Grow pool
    while ((int)terrain_mark_meshes.size() < markCount) {
        MeshInstance3D *mi = memnew(MeshInstance3D);
        mi->set_name(String("TerrainMark_") + String::num_int64((int64_t)terrain_mark_meshes.size()));
        mi->set_visible(false);
        terrain_mark_root->add_child(mi);
        terrain_mark_meshes.push_back(mi);
    }

    for (int m = 0; m < markCount; m++) {
        int hShader = 0, numVerts = 0, terrainIndex = 0, renderfx = 0;
        Godot_Renderer_GetTerrainMark(m, &hShader, &numVerts, &terrainIndex, &renderfx);

        MeshInstance3D *mi = terrain_mark_meshes[m];
        if (numVerts < 3) {
            mi->set_visible(false);
            continue;
        }

        // Build polygon mesh from terrain mark vertices
        PackedVector3Array gPos;
        PackedVector2Array gUV;
        PackedColorArray   gCol;
        PackedInt32Array   gIdx;
        gPos.resize(numVerts);
        gUV.resize(numVerts);
        gCol.resize(numVerts);

        for (int v = 0; v < numVerts; v++) {
            float xyz[3], st[2];
            unsigned char rgba[4];
            Godot_Renderer_GetTerrainMarkVert(m, v, xyz, st, rgba);
            gPos.set(v, id_to_godot_position(xyz[0], xyz[1], xyz[2]));
            gUV.set(v, Vector2(st[0], st[1]));
            gCol.set(v, Color(rgba[0] / 255.0f, rgba[1] / 255.0f,
                              rgba[2] / 255.0f, rgba[3] / 255.0f));
        }

        // Fan triangulation
        for (int v = 1; v < numVerts - 1; v++) {
            gIdx.push_back(0);
            gIdx.push_back(v);
            gIdx.push_back(v + 1);
        }

        Array arrays;
        arrays.resize(Mesh::ARRAY_MAX);
        arrays[Mesh::ARRAY_VERTEX] = gPos;
        arrays[Mesh::ARRAY_TEX_UV] = gUV;
        arrays[Mesh::ARRAY_COLOR]  = gCol;
        arrays[Mesh::ARRAY_INDEX]  = gIdx;

        Ref<ArrayMesh> tmesh;
        tmesh.instantiate();
        tmesh->add_surface_from_arrays(Mesh::PRIMITIVE_TRIANGLES, arrays);
        mi->set_mesh(tmesh);

        // Material
        Ref<StandardMaterial3D> mat;
        mat.instantiate();
        mat->set_cull_mode(BaseMaterial3D::CULL_DISABLED);
        mat->set_transparency(BaseMaterial3D::TRANSPARENCY_ALPHA);
        mat->set_shading_mode(BaseMaterial3D::SHADING_MODE_UNSHADED);
        mat->set_flag(BaseMaterial3D::FLAG_ALBEDO_FROM_VERTEX_COLOR, true);
        if (hShader > 0) {
            Ref<ImageTexture> tex = get_shader_texture(hShader);
            if (tex.is_valid()) {
                mat->set_texture(BaseMaterial3D::TEXTURE_ALBEDO, tex);
            }
        }
        mi->set_surface_override_material(0, mat);
        mi->set_global_transform(Transform3D());
        mi->set_visible(true);
    }

    for (int i = markCount; i < active_terrain_mark_count; i++) {
        if (i < (int)terrain_mark_meshes.size())
            terrain_mark_meshes[i]->set_visible(false);
    }
    active_terrain_mark_count = markCount;
}

// ──────────────────────────────────────────────
//  Shader UV animation (Phase 36)
// ──────────────────────────────────────────────

void MoHAARunner::update_shader_animations(double delta) {
    shader_anim_time += delta;

    // Iterate over BSP world mesh surfaces and apply tcMod scroll offset
    if (!bsp_map_node) return;

    // Walk MeshInstance3D children of bsp_map_node
    for (int c = 0; c < bsp_map_node->get_child_count(); c++) {
        MeshInstance3D *mi = Object::cast_to<MeshInstance3D>(bsp_map_node->get_child(c));
        if (!mi) continue;

        Ref<Mesh> mesh = mi->get_mesh();
        if (!mesh.is_valid()) continue;

        for (int s = 0; s < mesh->get_surface_count(); s++) {
            Ref<Material> base = mi->get_surface_override_material(s);
            if (base.is_null()) base = mesh->surface_get_material(s);

            Ref<StandardMaterial3D> smat = base;
            if (!smat.is_valid()) continue;

            // Check resource metadata for shader name (stored during BSP build)
            String shader_name = smat->get_meta("shader_name", "");
            if (shader_name.is_empty()) continue;

            CharString cs = shader_name.ascii();
            const GodotShaderProps *sp = Godot_ShaderProps_Find(cs.get_data());
            if (!sp) continue;

            // Apply UV tcMod animation: scroll + turb
            if (sp->has_tcmod) {
                float offS = 0.0f;
                float offT = 0.0f;
                if (sp->tcmod_scroll_s != 0.0f || sp->tcmod_scroll_t != 0.0f) {
                    offS += fmodf((float)(sp->tcmod_scroll_s * shader_anim_time), 1.0f);
                    offT += fmodf((float)(sp->tcmod_scroll_t * shader_anim_time), 1.0f);
                }
                if (sp->tcmod_turb_amp != 0.0f && sp->tcmod_turb_freq != 0.0f) {
                    float t = (float)(shader_anim_time * sp->tcmod_turb_freq);
                    offS += sinf(t) * sp->tcmod_turb_amp;
                    offT += cosf(t) * sp->tcmod_turb_amp;
                }
                smat->set_uv1_offset(Vector3(offS, offT, 0.0f));

                if (sp->tcmod_rotate != 0.0f) {
                    smat->set_uv1_offset(Vector3(offS, offT, Math::deg_to_rad((float)(sp->tcmod_rotate * shader_anim_time))));
                }
            }

            // Phase 55: animMap frame swap
            if (sp->has_animmap && sp->animmap_num_frames > 0 && sp->animmap_freq > 0.0f) {
                int shader_handle = -1;
                int shader_count = Godot_Renderer_GetShaderCount();
                for (int sh = 1; sh < shader_count; sh++) {
                    const char *sn = Godot_Renderer_GetShaderName(sh);
                    if (sn && shader_name == String(sn)) {
                        shader_handle = sh;
                        break;
                    }
                }

                if (shader_handle > 0) {
                    auto it_info = animmap_info.find(shader_handle);
                    if (it_info == animmap_info.end()) {
                        AnimMapInfo info;
                        info.freq = sp->animmap_freq;
                        info.num_frames = sp->animmap_num_frames;
                        animmap_info[shader_handle] = info;

                        std::vector<Ref<ImageTexture>> frames;
                        for (int fi = 0; fi < sp->animmap_num_frames; fi++) {
                            Ref<ImageTexture> frame_tex;
                            int frame_handle = -1;
                            for (int sh = 1; sh < shader_count; sh++) {
                                const char *sn = Godot_Renderer_GetShaderName(sh);
                                if (sn && String(sn) == String(sp->animmap_frames[fi])) {
                                    frame_handle = sh;
                                    break;
                                }
                            }
                            if (frame_handle > 0) {
                                frame_tex = get_shader_texture(frame_handle);
                            }
                            frames.push_back(frame_tex);
                        }
                        animmap_frames[shader_handle] = frames;
                    }

                    auto it_frames = animmap_frames.find(shader_handle);
                    auto it_anim   = animmap_info.find(shader_handle);
                    if (it_frames != animmap_frames.end() && it_anim != animmap_info.end()) {
                        const AnimMapInfo &ai = it_anim->second;
                        if (ai.num_frames > 0 && (int)it_frames->second.size() >= ai.num_frames) {
                            int frame_idx = (int)floor(shader_anim_time * ai.freq) % ai.num_frames;
                            if (frame_idx < 0) frame_idx += ai.num_frames;
                            Ref<ImageTexture> ftex = it_frames->second[frame_idx];
                            if (ftex.is_valid()) {
                                smat->set_texture(BaseMaterial3D::TEXTURE_ALBEDO, ftex);
                            }
                        }
                    }
                }
            }

            // Phase 56/57: runtime rgbGen/alphaGen wave animation
            if (sp->rgbgen_type == 2 || sp->alphagen_type == 2) {
                Color a = smat->get_albedo();
                if (sp->rgbgen_type == 2) {
                    float v = sp->rgbgen_wave_base +
                              sp->rgbgen_wave_amp * sinf((float)(shader_anim_time * sp->rgbgen_wave_freq + sp->rgbgen_wave_phase));
                    v = clamp01(v);
                    a.r = v; a.g = v; a.b = v;
                }
                if (sp->alphagen_type == 2) {
                    float alpha = sp->alphagen_wave_base +
                                  sp->alphagen_wave_amp * sinf((float)(shader_anim_time * sp->alphagen_wave_freq + sp->alphagen_wave_phase));
                    a.a = clamp01(alpha);
                    if (a.a < 0.999f) {
                        smat->set_transparency(BaseMaterial3D::TRANSPARENCY_ALPHA);
                    }
                }
                smat->set_albedo(a);
            }
        }
    }
}

// ──────────────────────────────────────────────
//  2D HUD overlay (Phase 7h)
// ──────────────────────────────────────────────

Ref<ImageTexture> MoHAARunner::get_shader_texture(int shader_handle) {
    // Check cache
    auto it = shader_textures.find(shader_handle);
    if (it != shader_textures.end()) {
        return it->second;
    }

    // Look up shader name (Phase 52: apply shader remap if active)
    const char *raw_name = Godot_Renderer_GetShaderName(shader_handle);
    const char *remapped = Godot_Renderer_GetShaderRemap(raw_name);
    const char *name = (remapped && remapped[0]) ? remapped : raw_name;
    if (!name || !name[0]) {
        shader_textures[shader_handle] = Ref<ImageTexture>();
        return Ref<ImageTexture>();
    }

    // ── Determine the actual texture image path(s) to try ──
    // Mirrors R_FindShader: first look up the shader definition in parsed
    // .shader script files.  If a definition exists, the first non-lightmap
    // stage's "map" directive gives the real texture path.  If no definition
    // is found, try using the shader name itself as a texture file path
    // (the fallback R_FindShader uses for implicit shaders).
    const char *texture_paths[4] = { NULL, NULL, NULL, NULL };
    int num_texture_paths = 0;

    const GodotShaderProps *sp = Godot_ShaderProps_Find(name);
    if (sp && sp->stage_count > 0) {
        /* Select the best diffuse texture: skip lightmap, $whiteimage,
         * and environment map stages (tcGen environment = reflections).
         * Fall back to the first non-lightmap stage if only env stages exist. */
        const char *fallback = NULL;
        for (int st = 0; st < sp->stage_count && num_texture_paths == 0; st++) {
            if (sp->stages[st].isLightmap) continue;
            if (!sp->stages[st].map[0]) continue;
            if (strcmp(sp->stages[st].map, "$lightmap") == 0) continue;
            if (strcmp(sp->stages[st].map, "$whiteimage") == 0) continue;
            if (!fallback) fallback = sp->stages[st].map;
            if (sp->stages[st].tcGen == STAGE_TCGEN_ENVIRONMENT) continue;
            texture_paths[num_texture_paths++] = sp->stages[st].map;
        }
        if (num_texture_paths == 0 && fallback) {
            texture_paths[num_texture_paths++] = fallback;
        }
    }

    // Always also try the shader name itself (works for implicit shaders
    // where the name IS the texture path without extension)
    if (num_texture_paths == 0 || strcmp(texture_paths[0], name) != 0) {
        texture_paths[num_texture_paths++] = name;
    }

    // ── Try loading each candidate path via VFS ──
    Ref<ImageTexture> tex;
    const char *extensions[] = { "", ".tga", ".jpg", ".png", NULL };

    for (int tp = 0; tp < num_texture_paths && tex.is_null(); tp++) {
        for (int ext_i = 0; extensions[ext_i]; ext_i++) {
            char path[256];
            snprintf(path, sizeof(path), "%s%s", texture_paths[tp], extensions[ext_i]);

            void *buf = NULL;
            long len = Godot_VFS_ReadFile(path, &buf);
            if (len > 0 && buf) {
                PackedByteArray pba;
                pba.resize(len);
                memcpy(pba.ptrw(), buf, len);
                Godot_VFS_FreeFile(buf);
                buf = NULL;

                Ref<Image> img;
                img.instantiate();
                Error err;

                // Detect format by magic bytes
                const uint8_t *data = pba.ptr();
                if (len > 2 && data[0] == 0xFF && data[1] == 0xD8) {
                    err = img->load_jpg_from_buffer(pba);
                } else if (len > 3 && data[0] == 0x89 && data[1] == 'P') {
                    err = img->load_png_from_buffer(pba);
                } else {
                    // Try TGA first, then JPEG
                    err = img->load_tga_from_buffer(pba);
                    if (err != OK) {
                        err = img->load_jpg_from_buffer(pba);
                    }
                }

                if (err == OK && !img->is_empty()) {
                    img->generate_mipmaps();
                    tex = ImageTexture::create_from_image(img);
                    break;
                }
            }
            if (buf) Godot_VFS_FreeFile(buf);
        }
    }

    shader_textures[shader_handle] = tex;
    return tex;
}

void MoHAARunner::update_2d_overlay() {
    int cmd_count = Godot_Renderer_Get2DCmdCount();
    if (cmd_count == 0 && !hud_layer) return;
    if (!hud_visible) return;  // F9 toggled off

    // Create HUD layer on first use
    if (!hud_layer) {
        hud_layer = memnew(CanvasLayer);
        hud_layer->set_layer(100);
        hud_layer->set_name("HUDLayer");
        add_child(hud_layer);

        hud_control = memnew(Control);
        hud_control->set_name("HUDControl");
        hud_control->set_anchors_preset(Control::PRESET_FULL_RECT);
        hud_layer->add_child(hud_control);

        static bool logged_hud = false;
        if (!logged_hud) {
            UtilityFunctions::print("[MoHAA] HUD overlay created.");
            logged_hud = true;
        }
    }

    if (cmd_count == 0) return;

    // Get the Control's canvas item RID for direct RenderingServer drawing
    RID ci = hud_control->get_canvas_item();
    RenderingServer *rs = RenderingServer::get_singleton();
    rs->canvas_item_clear(ci);

    // Phase 58: Draw captured background image during loading/screens
    {
        int cols = 0, rows = 0, bgr = 0;
        const unsigned char *bg_data = nullptr;
        if (Godot_Renderer_GetBackground(&cols, &rows, &bgr, &bg_data) &&
            cols > 0 && rows > 0 && bg_data && !Godot_Renderer_IsWorldMapLoaded()) {
            static Ref<ImageTexture> bg_tex;
            static Ref<Image> bg_img;

            PackedByteArray pixels;
            pixels.resize(cols * rows * 4);
            unsigned char *dst = pixels.ptrw();
            int src_stride = cols * 3;
            for (int y = 0; y < rows; y++) {
                const unsigned char *src_row = bg_data + y * src_stride;
                unsigned char *dst_row = dst + y * cols * 4;
                for (int x = 0; x < cols; x++) {
                    const unsigned char *s = src_row + x * 3;
                    unsigned char *d = dst_row + x * 4;
                    if (bgr) {
                        d[0] = s[2]; d[1] = s[1]; d[2] = s[0];
                    } else {
                        d[0] = s[0]; d[1] = s[1]; d[2] = s[2];
                    }
                    d[3] = 255;
                }
            }

            bg_img = Image::create_from_data(cols, rows, false, Image::FORMAT_RGBA8, pixels);
            if (bg_img.is_valid()) {
                if (bg_tex.is_null()) {
                    bg_tex = ImageTexture::create_from_image(bg_img);
                } else {
                    bg_tex->update(bg_img);
                }
            }

            if (bg_tex.is_valid()) {
                Vector2 vp = hud_control->get_size();
                Rect2 full(0.0f, 0.0f, vp.x, vp.y);
                rs->canvas_item_add_texture_rect(ci, full, bg_tex->get_rid());
            }
        }
    }

    // Engine uses glconfig.vidWidth × vidHeight coords — scale to actual viewport
    // Since we set vidWidth=640, vidHeight=480, all engine 2D coordinates
    // are in 640×480 virtual space (matching the original MOHAA design).
    int vid_w = 640, vid_h = 480;
    Godot_Renderer_GetVidSize(&vid_w, &vid_h);
    if (vid_w < 1) vid_w = 640;
    if (vid_h < 1) vid_h = 480;
    Vector2 viewport_size = hud_control->get_size();
    if (viewport_size.x < 1.0f || viewport_size.y < 1.0f) {
        viewport_size = Vector2(1280.0f, 720.0f);  // fallback
    }

    // Scale preserving aspect ratio — letterbox/pillarbox if needed
    float engine_aspect = (float)vid_w / (float)vid_h;
    float viewport_aspect = viewport_size.x / viewport_size.y;
    float scale_x, scale_y;
    float offset_x = 0.0f, offset_y = 0.0f;

    if (viewport_aspect > engine_aspect) {
        // Viewport is wider than engine — pillarbox (bars on sides)
        scale_y = viewport_size.y / (float)vid_h;
        scale_x = scale_y;  // uniform scaling
        offset_x = (viewport_size.x - (float)vid_w * scale_x) * 0.5f;
    } else {
        // Viewport is taller than engine — letterbox (bars top/bottom)
        scale_x = viewport_size.x / (float)vid_w;
        scale_y = scale_x;  // uniform scaling
        offset_y = (viewport_size.y - (float)vid_h * scale_y) * 0.5f;
    }

    float vid_area = (float)(vid_w * vid_h);

    for (int i = 0; i < cmd_count; i++) {
        int type, shader;
        float x, y, w, h, s1, t1, s2, t2, color[4];

        if (!Godot_Renderer_Get2DCmd(i, &type, &x, &y, &w, &h,
                                      &s1, &t1, &s2, &t2, color, &shader)) {
            continue;
        }

        // Skip fullscreen opaque fills — these are screen clears/backgrounds
        // that would cover the 3D view.  They belong behind the scene, not on top.
        if (type == 1 && w * h > vid_area * 0.5f && color[3] > 0.9f) {
            continue;
        }

        // Scale from engine coords to actual viewport (with aspect correction)
        Rect2 rect(offset_x + x * scale_x, offset_y + y * scale_y,
                   w * scale_x, h * scale_y);
        Color col(color[0], color[1], color[2], color[3]);

        if (type == 1) {
            // GR_2D_BOX — solid colour rectangle
            rs->canvas_item_add_rect(ci, rect, col);
        } else if (type == 2) {
            // GR_2D_SCISSOR — Phase 45: apply scissor/clip rectangle
            // w==0 && h==0 means "reset scissor" (full viewport)
            if (w > 0 && h > 0) {
                Rect2 clip(offset_x + x * scale_x, offset_y + y * scale_y,
                           w * scale_x, h * scale_y);
                rs->canvas_item_set_custom_rect(ci, true, clip);
            } else {
                rs->canvas_item_set_custom_rect(ci, false, Rect2());
            }
        } else if (type == 0 && shader > 0) {
            // GR_2D_STRETCHPIC — textured quad
            Ref<ImageTexture> tex = get_shader_texture(shader);
            if (tex.is_valid()) {
                RID tex_rid = tex->get_rid();
                float tw = (float)tex->get_width();
                float th = (float)tex->get_height();
                Rect2 src(s1 * tw, t1 * th, (s2 - s1) * tw, (t2 - t1) * th);
                rs->canvas_item_add_texture_rect_region(ci, rect, tex_rid, src, col);
            }
            // If texture not loaded, skip — don't draw opaque coloured rect fallback
        } else if (type == 0) {
            // StretchPic with no shader — only draw if not a large opaque fill
            if (w * h < vid_area * 0.5f || color[3] < 0.9f) {
                rs->canvas_item_add_rect(ci, rect, col);
            }
        }
    }

    static bool logged_2d = false;
    if (!logged_2d && cmd_count > 0) {
        UtilityFunctions::print(String("[MoHAA] 2D overlay: ") +
                                String::num_int64(cmd_count) + String(" draw commands"));
        // Dump first frame's 2D commands for debugging
        for (int dbg = 0; dbg < cmd_count && dbg < 20; dbg++) {
            int dtype, dshader;
            float dx, dy, dw, dh, ds1, dt1, ds2, dt2, dcol[4];
            if (Godot_Renderer_Get2DCmd(dbg, &dtype, &dx, &dy, &dw, &dh,
                                         &ds1, &dt1, &ds2, &dt2, dcol, &dshader)) {
                UtilityFunctions::print(String("[HUD cmd ") + String::num_int64(dbg) +
                    String("] type=") + String::num_int64(dtype) +
                    String(" rect=(") + String::num(dx, 0) + String(",") + String::num(dy, 0) +
                    String(",") + String::num(dw, 0) + String(",") + String::num(dh, 0) +
                    String(") col=(") + String::num(dcol[0], 2) + String(",") +
                    String::num(dcol[1], 2) + String(",") + String::num(dcol[2], 2) +
                    String(",") + String::num(dcol[3], 2) +
                    String(") shader=") + String::num_int64(dshader) +
                    String(" name=") + String(dshader > 0 ? Godot_Renderer_GetShaderName(dshader) : ""));
            }
        }
        logged_2d = true;
    }
}

// ──────────────────────────────────────────────
//  Audio bridge (Phase 8)
// ──────────────────────────────────────────────

void MoHAARunner::setup_audio() {
    if (!game_world) return;

    // Audio root container
    audio_root = memnew(Node3D);
    audio_root->set_name("AudioRoot");
    game_world->add_child(audio_root);

    // AudioListener3D — positioned at the camera
    audio_listener = memnew(AudioListener3D);
    audio_listener->set_name("Listener");
    audio_root->add_child(audio_listener);
    audio_listener->make_current();

    // Create 3D player pool
    for (int i = 0; i < MAX_3D_PLAYERS; i++) {
        AudioStreamPlayer3D *p = memnew(AudioStreamPlayer3D);
        p->set_name(String("SFX3D_") + String::num_int64(i));
        p->set_max_distance(2000.0f);  // ~78,000 engine units in metres
        p->set_attenuation_model(AudioStreamPlayer3D::ATTENUATION_INVERSE_DISTANCE);
        p->set_unit_size(1.0f);
        p->set_max_polyphony(1);
        audio_root->add_child(p);
        sfx_players_3d.push_back(p);
    }

    // Create 2D player pool (UI sounds, local sounds)
    for (int i = 0; i < MAX_2D_PLAYERS; i++) {
        AudioStreamPlayer *p = memnew(AudioStreamPlayer);
        p->set_name(String("SFX2D_") + String::num_int64(i));
        p->set_max_polyphony(1);
        add_child(p);  // 2D players live on this Node, not in 3D tree
        sfx_players_2d.push_back(p);
    }

    UtilityFunctions::print("[MoHAA] Audio bridge initialised: " +
                            String::num_int64(MAX_3D_PLAYERS) + " 3D + " +
                            String::num_int64(MAX_2D_PLAYERS) + " 2D players.");

    // Initialise player slot tracking (Phase 41)
    player_slot_info.resize(MAX_3D_PLAYERS);

    // Music player (Phase 17)
    music_player = memnew(AudioStreamPlayer);
    music_player->set_name("MusicPlayer");
    music_player->set_bus(StringName("Master"));
    add_child(music_player);
    UtilityFunctions::print("[MoHAA] Music player initialised.");

    // ── Phase 45: Initialise ubersound alias system ──
#ifdef HAS_UBERSOUND_MODULE
    Godot_Ubersound_Init();
    UtilityFunctions::print(String("[MoHAA] Ubersound initialised: ") +
                            String::num_int64(Godot_Ubersound_GetAliasCount()) + " aliases.");
#endif

    // ── Phase 48: Enable sound occlusion ──
#ifdef HAS_SOUND_OCCLUSION_MODULE
    Godot_SoundOcclusion_SetEnabled(1);
#endif
}

Ref<AudioStream> MoHAARunner::load_wav_from_vfs(int sfxHandle) {
    // Check cache first
    auto it = sfx_cache.find(sfxHandle);
    if (it != sfx_cache.end()) return it->second;

    // Look up name from the sound registry
    int idx = Godot_Sound_FindSfxIndex(sfxHandle);
    if (idx < 0) return Ref<AudioStream>();

    const char *snd_name = Godot_Sound_GetSfxName(idx);
    if (!snd_name || !snd_name[0]) return Ref<AudioStream>();

    // Try loading via VFS — sound files may or may not have "sound/" prefix
    void *buf = nullptr;
    long len = Godot_VFS_ReadFile(snd_name, &buf);

    // If that failed, try with "sound/" prefix
    if (len <= 0 && strncmp(snd_name, "sound/", 6) != 0) {
        char prefixed[256];
        snprintf(prefixed, sizeof(prefixed), "sound/%s", snd_name);
        len = Godot_VFS_ReadFile(prefixed, &buf);
    }

    // ── Phase 45: Try ubersound alias resolution if direct load failed ──
#ifdef HAS_UBERSOUND_MODULE
    if (len <= 0 && Godot_Ubersound_IsLoaded()) {
        char resolved_path[512];
        float vol, mindist, maxdist, pitch;
        int channel;
        if (Godot_Ubersound_Resolve(snd_name, resolved_path, sizeof(resolved_path),
                                     &vol, &mindist, &maxdist, &pitch, &channel)) {
            len = Godot_VFS_ReadFile(resolved_path, &buf);
            if (len <= 0 && strncmp(resolved_path, "sound/", 6) != 0) {
                char prefixed[512];
                snprintf(prefixed, sizeof(prefixed), "sound/%s", resolved_path);
                len = Godot_VFS_ReadFile(prefixed, &buf);
            }
        }
    }
#endif

    if (len <= 0 || !buf) {
        // Cache a null ref so we don't keep retrying
        sfx_cache[sfxHandle] = Ref<AudioStream>();
        return Ref<AudioStream>();
    }

    const unsigned char *data = (const unsigned char *)buf;

    // Check if this is a raw MP3 file (starts with ID3 tag or MP3 sync word)
    bool is_raw_mp3 = false;
    if (len >= 3 && data[0] == 'I' && data[1] == 'D' && data[2] == '3') {
        is_raw_mp3 = true;
    } else if (len >= 2 && data[0] == 0xFF && (data[1] & 0xE0) == 0xE0) {
        is_raw_mp3 = true;
    }

    if (is_raw_mp3) {
        PackedByteArray mp3_data;
        mp3_data.resize(len);
        memcpy(mp3_data.ptrw(), data, len);
        Godot_VFS_FreeFile(buf);

        Ref<AudioStreamMP3> mp3;
        mp3.instantiate();
        mp3->set_data(mp3_data);
        sfx_cache[sfxHandle] = mp3;
        return mp3;
    }

    // Parse WAV header — RIFF/WAVE format
    // Minimum: RIFF(4) + size(4) + WAVE(4) + fmt (8+16) + data(8) = 44 bytes
    if (len < 44 ||
        data[0] != 'R' || data[1] != 'I' || data[2] != 'F' || data[3] != 'F' ||
        data[8] != 'W' || data[9] != 'A' || data[10] != 'V' || data[11] != 'E') {
        Godot_VFS_FreeFile(buf);
        sfx_cache[sfxHandle] = Ref<AudioStream>();
        return Ref<AudioStream>();
    }

    // Find 'fmt ' chunk
    int fmt_offset = -1;
    int data_offset = -1;
    int data_size = 0;
    int pos = 12;

    while (pos + 8 <= (int)len) {
        int chunk_size = data[pos + 4] | (data[pos + 5] << 8) |
                         (data[pos + 6] << 16) | (data[pos + 7] << 24);

        if (data[pos] == 'f' && data[pos+1] == 'm' && data[pos+2] == 't' && data[pos+3] == ' ') {
            fmt_offset = pos + 8;
        } else if (data[pos] == 'd' && data[pos+1] == 'a' && data[pos+2] == 't' && data[pos+3] == 'a') {
            data_offset = pos + 8;
            data_size = chunk_size;
        }

        // Move to next chunk (align to 2 bytes)
        pos += 8 + ((chunk_size + 1) & ~1);
    }

    if (fmt_offset < 0 || data_offset < 0 || data_size <= 0) {
        Godot_VFS_FreeFile(buf);
        sfx_cache[sfxHandle] = Ref<AudioStream>();
        return Ref<AudioStream>();
    }

    // Read fmt chunk fields
    int audio_format = data[fmt_offset] | (data[fmt_offset + 1] << 8);
    int num_channels = data[fmt_offset + 2] | (data[fmt_offset + 3] << 8);
    int sample_rate  = data[fmt_offset + 4] | (data[fmt_offset + 5] << 8) |
                       (data[fmt_offset + 6] << 16) | (data[fmt_offset + 7] << 24);
    int bits_per_sample = data[fmt_offset + 14] | (data[fmt_offset + 15] << 8);

    // Phase 43: Handle MP3-in-WAV (format tag 0x0055)
    if (audio_format == 0x0055) {
        // Clamp data_size to available data
        if (data_offset + data_size > (int)len) {
            data_size = (int)len - data_offset;
        }
        // The data chunk contains raw MP3 frames
        PackedByteArray mp3_data;
        mp3_data.resize(data_size);
        memcpy(mp3_data.ptrw(), &data[data_offset], data_size);
        Godot_VFS_FreeFile(buf);

        Ref<AudioStreamMP3> mp3;
        mp3.instantiate();
        mp3->set_data(mp3_data);
        sfx_cache[sfxHandle] = mp3;
        return mp3;
    }

    // Support PCM (1) and IMA-ADPCM (17)
    AudioStreamWAV::Format godot_format;
    if (audio_format == 1) {
        // PCM
        if (bits_per_sample == 8)
            godot_format = AudioStreamWAV::FORMAT_8_BITS;
        else if (bits_per_sample == 16)
            godot_format = AudioStreamWAV::FORMAT_16_BITS;
        else {
            Godot_VFS_FreeFile(buf);
            sfx_cache[sfxHandle] = Ref<AudioStream>();
            return Ref<AudioStream>();
        }
    } else if (audio_format == 17) {
        godot_format = AudioStreamWAV::FORMAT_IMA_ADPCM;
    } else {
        // Unsupported format
        Godot_VFS_FreeFile(buf);
        sfx_cache[sfxHandle] = Ref<AudioStream>();
        return Ref<AudioStream>();
    }

    // Clamp data_size to available data
    if (data_offset + data_size > (int)len) {
        data_size = (int)len - data_offset;
    }

    // Build Godot AudioStreamWAV
    Ref<AudioStreamWAV> wav;
    wav.instantiate();
    wav->set_format(godot_format);
    wav->set_mix_rate(sample_rate);
    wav->set_stereo(num_channels >= 2);
    wav->set_loop_mode(AudioStreamWAV::LOOP_DISABLED);

    // Copy PCM data into PackedByteArray
    PackedByteArray pcm_data;
    pcm_data.resize(data_size);
    memcpy(pcm_data.ptrw(), &data[data_offset], data_size);
    wav->set_data(pcm_data);

    Godot_VFS_FreeFile(buf);

    // Cache it
    sfx_cache[sfxHandle] = wav;

    return wav;
}

void MoHAARunner::update_audio(double delta) {
    if (!audio_root) return;

    // -- 1. Update listener position from engine camera --
    {
        float lo[3], la[9];
        int lent;
        Godot_Sound_GetListener(lo, la, &lent);
        Vector3 listener_pos = id_to_godot_position(lo[0], lo[1], lo[2]);
        if (audio_listener) {
            audio_listener->set_global_position(listener_pos);
            Vector3 fwd = id_to_godot_point(la[0], la[1], la[2]);
            Vector3 lft = id_to_godot_point(la[3], la[4], la[5]);
            Vector3 up  = id_to_godot_point(la[6], la[7], la[8]);
            Vector3 right = -lft;
            Vector3 back  = -fwd;
            Basis b(right.normalized(), up.normalized(), back.normalized());
            audio_listener->set_global_transform(Transform3D(b, listener_pos));
        }
    }

    // -- 2. Process one-shot sound events --
    int evt_count = Godot_Sound_GetEventCount();
    for (int i = 0; i < evt_count; i++) {
        float origin[3];
        int entnum, channel, sfxHandle, streamed;
        float volume, minDist, maxDist, pitch;
        char name[256];

        int type = Godot_Sound_GetEvent(i, origin, &entnum, &channel,
                                        &sfxHandle, &volume, &minDist,
                                        &maxDist, &pitch, &streamed,
                                        name, sizeof(name));

        if (type == 3) {
            for (auto *p : sfx_players_3d) { if (p->is_playing()) p->stop(); }
            for (auto *p : sfx_players_2d) { if (p->is_playing()) p->stop(); }
            active_loops.clear();
            continue;
        }
        if (type == 2) continue;
        if (sfxHandle <= 0) continue;

        Ref<AudioStream> wav = load_wav_from_vfs(sfxHandle);
        if (wav.is_null()) continue;

        if (type == 0) {
            // Phase 41: Try to evict a player on the same entity+channel first
            int pi = -1;
            if (entnum > 0 && channel > 0) {
                for (int s = 0; s < MAX_3D_PLAYERS; s++) {
                    if (player_slot_info[s].in_use &&
                        player_slot_info[s].entnum == entnum &&
                        player_slot_info[s].channel == channel) {
                        pi = s;
                        break;
                    }
                }
            }
            if (pi < 0) {
                // Fallback: find an idle player, then round-robin
                for (int s = 0; s < MAX_3D_PLAYERS; s++) {
                    int idx = (next_3d_player + s) % MAX_3D_PLAYERS;
                    if (!sfx_players_3d[idx]->is_playing()) {
                        pi = idx;
                        break;
                    }
                }
                if (pi < 0) {
                    pi = next_3d_player;
                }
                next_3d_player = (pi + 1) % MAX_3D_PLAYERS;
            }
            AudioStreamPlayer3D *p = sfx_players_3d[pi];
            p->set_stream(wav);
            Vector3 pos = id_to_godot_position(origin[0], origin[1], origin[2]);
            p->set_global_position(pos);
            float vol_db = (volume > 0.001f) ? (20.0f * log10f(volume)) : -80.0f;
#ifdef HAS_SOUND_OCCLUSION_MODULE
            {
                // Phase 48: Apply sound occlusion attenuation for 3D sounds
                float lo[3], la[9]; int lent;
                Godot_Sound_GetListener(lo, la, &lent);
                float occ = Godot_SoundOcclusion_Check(lo[0], lo[1], lo[2],
                                                        origin[0], origin[1], origin[2]);
                if (occ < 1.0f) {
                    vol_db += 20.0f * log10f(occ > 0.001f ? occ : 0.001f);
                }
            }
#endif
            p->set_volume_db(vol_db);
            p->set_pitch_scale(pitch > 0.01f ? pitch : 1.0f);
            float max_m = (maxDist > 0) ? (maxDist * MOHAA_UNIT_SCALE) : 50.0f;
            p->set_max_distance(max_m);
            float unit_m = (minDist > 0) ? (minDist * MOHAA_UNIT_SCALE) : 1.0f;
            p->set_unit_size(unit_m);
            p->play();
            player_slot_info[pi] = {entnum, channel, true};
        } else if (type == 1) {
            AudioStreamPlayer *p = sfx_players_2d[next_2d_player];
            next_2d_player = (next_2d_player + 1) % MAX_2D_PLAYERS;
            p->set_stream(wav);
            float vol_db = (volume > 0.001f) ? (20.0f * log10f(volume)) : -80.0f;
            p->set_volume_db(vol_db);
            p->set_pitch_scale(pitch > 0.01f ? pitch : 1.0f);
            p->play();
        }
    }
    Godot_Sound_ClearEvents();

    // -- 3. Update looping sounds (Phase 40: position-aware tracking) --
    int loop_count = Godot_Sound_GetLoopCount();
    // Build a composite key = sfxHandle * 65537 + quantised position hash
    // This allows the same sfxHandle to loop at multiple positions
    auto make_loop_key = [](int sfxHandle, float ox, float oy, float oz) -> int64_t {
        // Quantise to 128-unit grid for stable matching across frames
        int qx = (int)(ox / 128.0f);
        int qy = (int)(oy / 128.0f);
        int qz = (int)(oz / 128.0f);
        int64_t posHash = ((int64_t)(qx & 0xFFF)) | ((int64_t)(qy & 0xFFF) << 12) | ((int64_t)(qz & 0xFFF) << 24);
        return ((int64_t)sfxHandle << 36) | posHash;
    };
    std::unordered_map<int64_t, int> new_loops_64;

    for (int i = 0; i < loop_count; i++) {
        float origin[3], velocity[3];
        int sfxHandle, flags;
        float volume, minDist, maxDist, pitch;
        Godot_Sound_GetLoop(i, origin, velocity, &sfxHandle, &volume,
                            &minDist, &maxDist, &pitch, &flags);
        if (sfxHandle <= 0) continue;
        int64_t lkey = make_loop_key(sfxHandle, origin[0], origin[1], origin[2]);
        new_loops_64[lkey] = i;

        auto it = active_loops.find(lkey);
        if (it != active_loops.end()) {
            int pi = it->second;
            if (pi >= 0 && pi < MAX_3D_PLAYERS) {
                AudioStreamPlayer3D *p = sfx_players_3d[pi];
                Vector3 pos = id_to_godot_position(origin[0], origin[1], origin[2]);
                p->set_global_position(pos);
                float vol_db = (volume > 0.001f) ? (20.0f * log10f(volume)) : -80.0f;
                p->set_volume_db(vol_db);
            }
        } else {
            Ref<AudioStream> wav = load_wav_from_vfs(sfxHandle);
            if (wav.is_null()) continue;
            // Phase 43: Handle looping for both WAV and MP3 streams
            Ref<AudioStream> loop_stream;
            Ref<AudioStreamWAV> wav_ref = wav;
            Ref<AudioStreamMP3> mp3_ref = wav;
            if (wav_ref.is_valid()) {
                Ref<AudioStreamWAV> loop_wav = wav_ref->duplicate();
                if (loop_wav.is_valid()) {
                    loop_wav->set_loop_mode(AudioStreamWAV::LOOP_FORWARD);
                    loop_wav->set_loop_begin(0);
                    int total_samples = 0;
                    PackedByteArray d = loop_wav->get_data();
                    int bps = (loop_wav->get_format() == AudioStreamWAV::FORMAT_16_BITS) ? 2 : 1;
                    int ch = loop_wav->is_stereo() ? 2 : 1;
                    if (bps > 0 && ch > 0) total_samples = d.size() / (bps * ch);
                    loop_wav->set_loop_end(total_samples);
                    loop_stream = loop_wav;
                }
            } else if (mp3_ref.is_valid()) {
                Ref<AudioStreamMP3> loop_mp3 = mp3_ref->duplicate();
                if (loop_mp3.is_valid()) {
                    loop_mp3->set_loop(true);
                    loop_stream = loop_mp3;
                }
            }
            if (loop_stream.is_null()) loop_stream = wav;
            int pi = next_3d_player;
            next_3d_player = (next_3d_player + 1) % MAX_3D_PLAYERS;
            AudioStreamPlayer3D *p = sfx_players_3d[pi];
            p->set_stream(loop_stream);
            Vector3 pos = id_to_godot_position(origin[0], origin[1], origin[2]);
            p->set_global_position(pos);
            float vol_db = (volume > 0.001f) ? (20.0f * log10f(volume)) : -80.0f;
            p->set_volume_db(vol_db);
            p->set_pitch_scale(pitch > 0.01f ? pitch : 1.0f);
            float max_m = (maxDist > 0) ? (maxDist * MOHAA_UNIT_SCALE) : 50.0f;
            p->set_max_distance(max_m);
            float unit_m = (minDist > 0) ? (minDist * MOHAA_UNIT_SCALE) : 1.0f;
            p->set_unit_size(unit_m);
            p->play();
            active_loops[lkey] = pi;
        }
    }

    for (auto it = active_loops.begin(); it != active_loops.end(); ) {
        if (new_loops_64.find(it->first) == new_loops_64.end()) {
            int pi = it->second;
            if (pi >= 0 && pi < MAX_3D_PLAYERS) sfx_players_3d[pi]->stop();
            it = active_loops.erase(it);
        } else {
            ++it;
        }
    }

    // -- 4. Music playback (Phase 17) --
    if (music_player) {
        int music_action = Godot_Sound_GetMusicAction();
        if (music_action != 0) {
            if (music_action == 1) {
                const char *mus_name_raw = Godot_Sound_GetMusicName();
                String name_str(mus_name_raw ? mus_name_raw : "");
                if (name_str.length() > 0 && name_str != current_music_name) {
                    String mus_base = name_str;
                    if (mus_base.begins_with("sound/")) mus_base = mus_base.substr(6);
                    if (!mus_base.begins_with("music/")) mus_base = "music/" + mus_base;
                    if (mus_base.ends_with(".mus")) mus_base = mus_base.substr(0, mus_base.length() - 4);
                    String mus_vfs_path = mus_base + ".mus";

                    void *mus_buf = nullptr;
                    long mus_len = Godot_VFS_ReadFile(mus_vfs_path.utf8().get_data(), &mus_buf);
                    UtilityFunctions::print("[MoHAA] Music: read .mus '" + mus_vfs_path + "' len=" + String::num_int64(mus_len));

                    String track_path;
                    bool should_loop = false;
                    float mus_volume = 1.0f;

                    if (mus_len > 0 && mus_buf) {
                        String mus_text = String::utf8((const char *)mus_buf, mus_len);
                        String base_dir;
                        String track_file;
                        PackedStringArray mlines = mus_text.split("\n");
                        for (int li = 0; li < mlines.size(); li++) {
                            String line = mlines[li].strip_edges();
                            if (line.begins_with("path ")) {
                                base_dir = line.substr(5).strip_edges();
                            } else if (line.begins_with("normal ") && !line.begins_with("!normal")) {
                                track_file = line.substr(7).strip_edges();
                            } else if (line.begins_with("!normal volume ")) {
                                mus_volume = line.substr(15).strip_edges().to_float();
                            } else if (line == "!normal loop") {
                                should_loop = true;
                            }
                        }
                        if (track_file.length() > 0) {
                            if (base_dir.length() > 0) {
                                track_path = base_dir + "/" + track_file;
                            } else {
                                track_path = "sound/music/" + track_file;
                            }
                        }
                        Godot_VFS_FreeFile(mus_buf);
                    } else {
                        if (mus_buf) Godot_VFS_FreeFile(mus_buf);
                        track_path = "sound/" + mus_base + ".mp3";
                    }

                    if (track_path.length() > 0) {
                        void *mp3_buf = nullptr;
                        long mp3_len = Godot_VFS_ReadFile(track_path.utf8().get_data(), &mp3_buf);
                        if (mp3_len > 0 && mp3_buf) {
                            PackedByteArray mp3_data;
                            mp3_data.resize(mp3_len);
                            memcpy(mp3_data.ptrw(), mp3_buf, mp3_len);
                            Godot_VFS_FreeFile(mp3_buf);

                            Ref<AudioStreamMP3> stream;
                            stream.instantiate();
                            stream->set_data(mp3_data);
                            stream->set_loop(should_loop);

                            music_player->set_stream(stream);
                            float vol_db = (mus_volume > 0.001f) ? (20.0f * log10f(mus_volume)) : -80.0f;
                            music_player->set_volume_db(vol_db);
                            music_target_volume = mus_volume;
                            music_player->play();
                            current_music_name = name_str;
                            UtilityFunctions::print("[MoHAA] Music: playing '" + track_path +
                                "' (loop=" + String(should_loop ? "yes" : "no") +
                                ", vol=" + String::num(mus_volume, 2) + ")");
                        } else {
                            if (mp3_buf) Godot_VFS_FreeFile(mp3_buf);
                            UtilityFunctions::print("[MoHAA] Music: track not found: " + track_path);
                        }
                    }
                }
            } else if (music_action == 2) {
                if (music_player->is_playing()) music_player->stop();
                current_music_name = "";
                UtilityFunctions::print("[MoHAA] Music: stopped.");
            } else if (music_action == 3) {
                // Phase 39: Smooth volume fading using fadeTime
                float new_vol = Godot_Sound_GetMusicVolume();
                float fade_time = Godot_Sound_GetMusicFadeTime();
                if (fade_time > 0.01f) {
                    // Start a gradual fade
                    music_fade_from = music_target_volume;
                    music_fade_to = new_vol;
                    music_fade_duration = fade_time;
                    music_fade_elapsed = 0.0f;
                    music_fading = true;
                } else {
                    // Instant volume change
                    music_target_volume = new_vol;
                    float vol_db = (new_vol > 0.001f) ? (20.0f * log10f(new_vol)) : -80.0f;
                    music_player->set_volume_db(vol_db);
                    music_fading = false;
                }
            }
            Godot_Sound_ClearMusicAction();
        }

        // Phase 39: Per-frame music volume fade interpolation
        if (music_fading && music_fade_duration > 0.0f) {
            float dt = (float)delta;
            music_fade_elapsed += dt;
            float t = music_fade_elapsed / music_fade_duration;
            if (t >= 1.0f) {
                t = 1.0f;
                music_fading = false;
            }
            float cur_vol = music_fade_from + (music_fade_to - music_fade_from) * t;
            music_target_volume = cur_vol;
            float vol_db = (cur_vol > 0.001f) ? (20.0f * log10f(cur_vol)) : -80.0f;
            music_player->set_volume_db(vol_db);
        }
    }

    // -- 5. Sound fade (Phase 50) --
    if (Godot_Sound_GetFadeActive()) {
        float fade_time = Godot_Sound_GetFadeTime();
        if (fade_time > 0.0f) {
            sound_fade_duration = fade_time;
            sound_fade_elapsed = 0.0f;
            sound_fading = true;
        }
        Godot_Sound_ClearFade();
    }

    // -- 6. Triggered music (Phase 51) --
    if (music_player) {
        int trig_action = Godot_Sound_GetTriggeredAction();
        if (trig_action > 0) {
            if (trig_action == 2) {  /* START */
                const char *trig_name = Godot_Sound_GetTriggeredName();
                if (trig_name && trig_name[0]) {
                    String trig_str(trig_name);
                    /* Try to load as MP3 from VFS */
                    void *mp3_buf = nullptr;
                    long mp3_len = Godot_VFS_ReadFile(trig_str.utf8().get_data(), &mp3_buf);
                    if (mp3_len > 0 && mp3_buf) {
                        PackedByteArray mp3_data;
                        mp3_data.resize(mp3_len);
                        memcpy(mp3_data.ptrw(), mp3_buf, mp3_len);
                        Godot_VFS_FreeFile(mp3_buf);

                        Ref<AudioStreamMP3> stream;
                        stream.instantiate();
                        stream->set_data(mp3_data);
                        stream->set_loop(Godot_Sound_GetTriggeredLoopCount() != 0);
                        music_player->set_stream(stream);
                        music_player->play();
                        UtilityFunctions::print("[MoHAA] Triggered music: playing '" + trig_str + "'");
                    } else {
                        if (mp3_buf) Godot_VFS_FreeFile(mp3_buf);
                    }
                }
            } else if (trig_action == 3) {  /* STOP */
                if (music_player->is_playing()) music_player->stop();
            } else if (trig_action == 4) {  /* PAUSE */
                music_player->set_stream_paused(true);
            } else if (trig_action == 5) {  /* UNPAUSE */
                music_player->set_stream_paused(false);
            }
            Godot_Sound_ClearTriggeredAction();
        }
    }

    // -- 7. Log sound stats once --
    static bool logged_audio = false;
    if (!logged_audio && evt_count > 0) {
        int sfx_count = Godot_Sound_GetSfxCount();
        UtilityFunctions::print(String("[MoHAA] Audio: ") +
            String::num_int64(sfx_count) + String(" sounds registered, ") +
            String::num_int64(evt_count) + String(" events this frame, ") +
            String::num_int64(loop_count) + String(" loops active."));
        logged_audio = true;
    }
}

// ──────────────────────────────────────────────
//  Cinematic bridge (Phase 11)
// ──────────────────────────────────────────────

void MoHAARunner::setup_cinematic() {
    /* Cinematic layer sits above the HUD (layer 11) so it covers everything
     * when a video is playing. */
    cin_layer = memnew(CanvasLayer);
    cin_layer->set_name("CinematicLayer");
    cin_layer->set_layer(11);
    add_child(cin_layer);

    cin_rect = memnew(TextureRect);
    cin_rect->set_name("CinematicRect");
    cin_rect->set_anchors_preset(Control::PRESET_FULL_RECT);
    cin_rect->set_stretch_mode(TextureRect::STRETCH_KEEP_ASPECT_CENTERED);
    cin_rect->set_expand_mode(TextureRect::EXPAND_IGNORE_SIZE);
    cin_layer->add_child(cin_rect);

    // Hidden by default — shown when cinematic is playing
    cin_layer->set_visible(false);

    UtilityFunctions::print("[MoHAA] Cinematic display initialised.");
}

void MoHAARunner::update_cinematic() {
    int active = Godot_Renderer_IsCinematicActive();

    if (active) {
        const unsigned char *data = nullptr;
        int w = 0, h = 0;

        if (Godot_Renderer_GetCinematicFrame(&data, &w, &h) && data && w > 0 && h > 0) {
            /* Build an Image from the raw RGBA data. The engine decoder
             * outputs 32-bit RGBA (samplesPerPixel=4 in cl_cin.cpp). */
            PackedByteArray pba;
            int byte_count = w * h * 4;
            pba.resize(byte_count);
            memcpy(pba.ptrw(), data, byte_count);

            Ref<Image> img = Image::create_from_data(w, h, false, Image::FORMAT_RGBA8, pba);
            if (img.is_valid()) {
                if (cin_texture.is_null()) {
                    cin_texture = ImageTexture::create_from_image(img);
                } else {
                    cin_texture->update(img);
                }
                cin_rect->set_texture(cin_texture);
            }
        }

        if (!cin_was_active) {
            cin_layer->set_visible(true);
            /* Hide the HUD and 3D world while cinematic is playing */
            if (hud_layer) hud_layer->set_visible(false);
            if (game_world) game_world->set_visible(false);
            UtilityFunctions::print("[MoHAA] Cinematic started.");
            cin_was_active = true;
        }
    } else if (cin_was_active) {
        /* Cinematic has ended — hide overlay, restore world + HUD */
        cin_layer->set_visible(false);
        if (game_world) game_world->set_visible(true);
        if (hud_layer && hud_visible) hud_layer->set_visible(true);
        cin_texture.unref();
        cin_was_active = false;
        Godot_Renderer_SetCinematicInactive();
        UtilityFunctions::print("[MoHAA] Cinematic ended.");
    }
}

void MoHAARunner::_ready() {
    if (initialized) {
        return;
    }

    g_godot_ready = true;

    UtilityFunctions::print("[MoHAA] Initialising engine...");

    // ── Pre-init (mirrors what main() does in sys_main.c) ──
    Sys_PlatformInit();
    Sys_Milliseconds();  // establish time base

    // Resolve base path: property > environment > cwd
    godot::String resolved_base = basepath;
    if (resolved_base.is_empty()) {
        // Try MOHAA_BASEPATH environment variable
        const char *env = getenv("MOHAA_BASEPATH");
        if (env && env[0]) {
            resolved_base = godot::String(env);
        } else {
            resolved_base = ".";
        }
    }

    godot::CharString bp = resolved_base.utf8();
    Sys_SetBinaryPath(bp.get_data());
    Sys_SetDefaultInstallPath(bp.get_data());

    CON_Init();

    // Build command line — full client + dedicated/listen server configurable.
    char cmdline[1024];
    snprintf(cmdline, sizeof(cmdline),
        "%s +set fs_basepath \"%s\"",
        startup_args.utf8().get_data(), bp.get_data());

    // Set up error recovery point before calling into engine
    godot_has_fatal_error = false;
    godot_quit_requested = false;
    godot_jmpbuf_valid = true;

    int jmpval = setjmp(godot_error_jmpbuf);
    if (jmpval != 0) {
        godot_jmpbuf_valid = false;
        if (godot_has_fatal_error) {
            godot::String err_msg(godot_error_message);
            UtilityFunctions::printerr(godot::String("[MoHAA] FATAL ERROR during init: ") + err_msg);
            emit_signal("engine_error", err_msg);
            godot_has_fatal_error = false;
        } else if (godot_quit_requested) {
            UtilityFunctions::print("[MoHAA] Engine quit during init.");
            emit_signal("engine_shutdown_requested");
            godot_quit_requested = false;
        }
        initialized = false;
        return;
    }

    Com_Init(cmdline);
    NET_Init();

    godot_jmpbuf_valid = false;
    initialized = true;
    Godot_SetEngineInitialized(true);

    // Initialize state tracking
    last_server_state = Godot_GetServerState();
    last_map_name = "";

    // Create 3D scene nodes (Phase 7a — camera bridge)
    setup_3d_scene();

    // Create audio player pools (Phase 8 — sound bridge)
    setup_audio();

    // Create cinematic video display (Phase 11 — cinematic bridge)
    setup_cinematic();

    // Initialise game flow state (Phase 261)
    game_flow_state = GameFlowState::BOOT;

    // ── Module init hooks (defensive — only called if module exists) ──
#ifdef HAS_MUSIC_MODULE
    Godot_Music_Init(static_cast<void*>(this));
#endif
#ifdef HAS_VFX_MODULE
    Godot_VFX_Init(game_world);
#endif

    UtilityFunctions::print("[MoHAA] Engine initialised.");
}

void MoHAARunner::_process(double delta) {
    if (!initialized) {
        return;
    }

    // Set up error recovery point
    godot_has_fatal_error = false;
    godot_quit_requested = false;
    godot_jmpbuf_valid = true;

    int jmpval = setjmp(godot_error_jmpbuf);
    if (jmpval != 0) {
        godot_jmpbuf_valid = false;
        if (godot_has_fatal_error) {
            godot::String err_msg(godot_error_message);
            UtilityFunctions::printerr(godot::String("[MoHAA] FATAL ERROR: ") + err_msg);
            emit_signal("engine_error", err_msg);
            godot_has_fatal_error = false;
        } else if (godot_quit_requested) {
            UtilityFunctions::print("[MoHAA] Engine shutdown requested.");
            emit_signal("engine_shutdown_requested");
            godot_quit_requested = false;
        }
        initialized = false;
        Godot_SetEngineInitialized(false);
        return;
    }

    Com_Frame();
    godot_jmpbuf_valid = false;

    // ── Phase 85: Begin per-frame render statistics ──
#ifdef HAS_MESH_CACHE_MODULE
    Godot_RenderStats_BeginFrame();
#endif

    // ── Phase 48: Poll UI state from engine keyCatchers ──
#ifdef HAS_UI_SYSTEM_MODULE
    Godot_UI_Update();
    // Toggle mouse cursor visibility based on UI state
    if (Godot_UI_ShouldShowCursor()) {
        if (mouse_captured) {
            Input::get_singleton()->set_mouse_mode(Input::MOUSE_MODE_VISIBLE);
            mouse_captured = false;
        }
    } else {
        if (!mouse_captured) {
            Input::get_singleton()->set_mouse_mode(Input::MOUSE_MODE_CAPTURED);
            mouse_captured = true;
        }
    }
#endif

    // ── Update 3D camera from engine viewpoint (Phase 7a) ──
    update_camera();

    // ── Load BSP world geometry if a new map was loaded (Phase 7b) ──
    check_world_load();

    // ── Phase 62: Sync weapon viewport camera each frame ──
#ifdef HAS_WEAPON_VIEWPORT_MODULE
    if (Godot_WeaponViewport::get().is_created()) {
        Godot_WeaponViewport::get().sync_camera();
    }
#endif

    // ── Update entity debug meshes from captured render data (Phase 7e) ──
    update_entities();
    update_dlights();
    update_polys();
    update_swipe_effects();     // Phase 24: swipe/melee trails
    update_terrain_marks();     // Phase 25: terrain mark decals
    update_shader_animations(delta);  // Phase 36: tcMod scroll/rotate

    // ── Update 2D HUD overlay from captured draw commands (Phase 7h) ──
    update_2d_overlay();

    // ── Update audio from captured sound events (Phase 8) ──
    update_audio(delta);

    // ── Phase 47: Update speaker entity sounds ──
#ifdef HAS_SPEAKER_ENTITIES_MODULE
    Godot_Speakers_Update((float)delta);
#endif

    // ── Update cinematic video display (Phase 11) ──
    update_cinematic();

    // ── Module update hooks (defensive — only called if module exists) ──
#ifdef HAS_MUSIC_MODULE
    Godot_Music_Update(delta);
#endif
#ifdef HAS_WEATHER_MODULE
    Godot_Weather_Update(camera ? camera->get_global_position() : Vector3(), static_cast<float>(delta));
#endif
#ifdef HAS_VFX_MODULE
    Godot_VFX_Update(delta);
#endif
#ifdef HAS_DEBUG_RENDER_MODULE
    Godot_DebugRender_Update(delta);
#endif

    // ── Phase 60/61: Evict stale mesh and material cache entries ──
#ifdef HAS_MESH_CACHE_MODULE
    {
        static uint64_t frame_counter = 0;
        frame_counter++;
        Godot_MeshCache::get().evict_stale(frame_counter);
        Godot_MaterialCache::get().evict_stale(frame_counter);
    }
#endif

    // ── Phase 85: End per-frame render statistics ──
#ifdef HAS_MESH_CACHE_MODULE
    Godot_RenderStats_EndFrame();
#endif

    // ── Update game flow state machine (Phase 261) ──
    update_game_flow_state();

    // ── Enforce gameplay input mode each frame ──
    // The engine's UI system can re-enable in_guimouse or set keyCatchers
    // via menu code, focus changes, etc.  When we're in gameplay mode
    // (mouse captured), ensure the engine is in freelook mode.
    if (mouse_captured && !cin_was_active) {
        int gui_mouse = Godot_Client_GetGuiMouse();
        int paused_val = Godot_Client_GetPaused();
        int catchers = Godot_Client_GetKeyCatchers();

        // Force freelook if GUI mouse or pause is active
        if (gui_mouse || paused_val || (catchers & 0x3)) {
            Godot_Client_ForceUnpause();
            // Only clear catchers if not in console mode (allow tilde to open console)
            if (catchers & 0x2) {  // KEYCATCH_UI
                Godot_Client_SetGameInputMode();
            }

            static int input_fix_count = 0;
            if (input_fix_count < 5) {
                UtilityFunctions::print(String("[MoHAA] Input fix: cleared guiMouse=") +
                    String::num_int64(gui_mouse) + String(" paused=") +
                    String::num_int64(paused_val) + String(" catchers=0x") +
                    String::num_int64(catchers, 16));
                input_fix_count++;
            }
        }
    }

    // ── State change detection for signals (Task 2.5.4) ──
    if (initialized) {
        int cur_state = Godot_GetServerState();
        const char *cur_map_raw = Godot_GetMapName();
        godot::String cur_map(cur_map_raw ? cur_map_raw : "");

        // Detect map loaded: state transitioned to SS_GAME (3) with a valid map name
        if (cur_state == 3 && last_server_state != 3 && !cur_map.is_empty()) {
            UtilityFunctions::print(godot::String("[MoHAA] Map loaded: ") + cur_map);

            // Dump client diagnostics once after map load
            int cl_state = Godot_Client_GetState();
            int catchers = Godot_Client_GetKeyCatchers();
            int gui_mouse = Godot_Client_GetGuiMouse();
            int start_stage = Godot_Client_GetStartStage();
            int mx, my;
            Godot_Client_GetMousePos(&mx, &my);
            UtilityFunctions::print(String("[MoHAA] Client: state=") + String::num_int64(cl_state) +
                String(" keyCatchers=0x") + String::num_int64(catchers, 16) +
                String(" guiMouse=") + String::num_int64(gui_mouse) +
                String(" startStage=") + String::num_int64(start_stage) +
                String(" mousePos=(") + String::num_int64(mx) + String(",") + String::num_int64(my) + String(")"));

            // Clear UI/console catchers and enable game input mode
            if (catchers & 0x3) {  // KEYCATCH_CONSOLE(1) | KEYCATCH_UI(2)
                Godot_Client_SetGameInputMode();
                int new_catchers = Godot_Client_GetKeyCatchers();
                int new_gui = Godot_Client_GetGuiMouse();
                UtilityFunctions::print("[MoHAA] Cleared UI/console key catchers — game input active. Now: catchers=0x" +
                    String::num_int64(new_catchers, 16) + "  =" + String::num_int64(new_gui));
            }

            emit_signal("map_loaded", cur_map);
        }
        
        // Detect map unloaded: was in SS_GAME, now not
        else if (last_server_state == 3 && cur_state != 3) {
            UtilityFunctions::print("[MoHAA] Map unloaded.");
            emit_signal("map_unloaded");
        }

        last_server_state = cur_state;
        last_map_name = cur_map;
    }
}

// ──────────────────────────────────────────────
//  Commands
// ──────────────────────────────────────────────

void MoHAARunner::execute_command(const godot::String &p_command) {
    if (!initialized) {
        UtilityFunctions::printerr("[MoHAA] Engine not initialized, cannot execute command.");
        return;
    }
    godot::CharString cmd = p_command.utf8();
    Cbuf_AddText(cmd.get_data());
    Cbuf_AddText("\n");
}

void MoHAARunner::load_map(const godot::String &p_map_name) {
    if (!initialized) {
        UtilityFunctions::printerr("[MoHAA] Engine not initialized, cannot load map.");
        return;
    }
    UtilityFunctions::print(godot::String("[MoHAA] Loading map: ") + p_map_name);
    godot::String cmd = godot::String("map ") + p_map_name;
    execute_command(cmd);
}

// ──────────────────────────────────────────────
//  Server status (Task 2.5.3)
// ──────────────────────────────────────────────

bool MoHAARunner::is_map_loaded() const {
    if (!initialized) return false;
    return Godot_GetServerState() == 3;  // SS_GAME
}

godot::String MoHAARunner::get_current_map() const {
    if (!initialized) return "";
    const char *name = Godot_GetMapName();
    return godot::String(name ? name : "");
}

int MoHAARunner::get_player_count() const {
    if (!initialized) return 0;
    return Godot_GetPlayerCount();
}

int MoHAARunner::get_server_state() const {
    if (!initialized) return 0;
    return Godot_GetServerState();
}

godot::String MoHAARunner::get_server_state_string() const {
    switch (get_server_state()) {
        case 0: return "dead";
        case 1: return "loading";
        case 2: return "loading2";
        case 3: return "game";
        default: return "unknown";
    }
}

// ──────────────────────────────────────────────
//  VFS access (Task 4.1)
// ──────────────────────────────────────────────

godot::PackedByteArray MoHAARunner::vfs_read_file(const godot::String &p_qpath) const {
    godot::PackedByteArray result;
    if (!initialized) {
        UtilityFunctions::printerr("[MoHAA] Engine not initialised, cannot read VFS file.");
        return result;
    }

    godot::CharString path = p_qpath.utf8();
    void *buffer = nullptr;
    long len = Godot_VFS_ReadFile(path.get_data(), &buffer);

    if (len < 0 || !buffer) {
        return result;  // File not found — return empty array
    }

    result.resize(len);
    memcpy(result.ptrw(), buffer, len);
    Godot_VFS_FreeFile(buffer);
    return result;
}

bool MoHAARunner::vfs_file_exists(const godot::String &p_qpath) const {
    if (!initialized) return false;
    godot::CharString path = p_qpath.utf8();
    return Godot_VFS_FileExists(path.get_data()) != 0;
}

godot::PackedStringArray MoHAARunner::vfs_list_files(const godot::String &p_directory, const godot::String &p_extension) const {
    godot::PackedStringArray result;
    if (!initialized) {
        UtilityFunctions::printerr("[MoHAA] Engine not initialised, cannot list VFS files.");
        return result;
    }

    godot::CharString dir = p_directory.utf8();
    godot::CharString ext = p_extension.utf8();
    int count = 0;
    char **list = Godot_VFS_ListFiles(dir.get_data(), ext.get_data(), &count);

    if (!list) return result;

    for (int i = 0; i < count; i++) {
        if (list[i]) {
            result.push_back(godot::String(list[i]));
        }
    }

    Godot_VFS_FreeFileList(list);
    return result;
}

godot::String MoHAARunner::vfs_get_gamedir() const {
    if (!initialized) return "";
    const char *dir = Godot_VFS_GetGamedir();
    return godot::String(dir ? dir : "");
}

// ──────────────────────────────────────────────
//  Input bridge (Phase 6)
// ──────────────────────────────────────────────

void MoHAARunner::set_mouse_captured(bool p_captured) {
    mouse_captured = p_captured;
    Input *input = Input::get_singleton();
    if (!input) return;

    if (p_captured) {
        input->set_mouse_mode(Input::MOUSE_MODE_CAPTURED);
    } else {
        input->set_mouse_mode(Input::MOUSE_MODE_VISIBLE);
    }
}

bool MoHAARunner::is_mouse_captured() const {
    return mouse_captured;
}

void MoHAARunner::set_hud_visible(bool p_visible) {
    hud_visible = p_visible;
    if (hud_layer) {
        hud_layer->set_visible(hud_visible);
    }
}

bool MoHAARunner::is_hud_visible() const {
    return hud_visible;
}

// ──────────────────────────────────────────────
//  Game flow state machine (Phase 261)
// ──────────────────────────────────────────────

void MoHAARunner::update_game_flow_state() {
    if (!initialized) return;

    int sv_state = Godot_GetServerState();
    int catchers = Godot_Client_GetKeyCatchers();
    GameFlowState new_state = game_flow_state;

    switch (game_flow_state) {
        case GameFlowState::BOOT:
            // After engine init, transition to TITLE_SCREEN
            // The engine opens the main menu UI automatically on boot
            if (catchers & 0x2) {  // KEYCATCH_UI active
                new_state = GameFlowState::MAIN_MENU;
            } else {
                new_state = GameFlowState::TITLE_SCREEN;
            }
            break;

        case GameFlowState::TITLE_SCREEN:
            // Any key press or UI activation moves to main menu
            if (catchers & 0x2) {  // KEYCATCH_UI
                new_state = GameFlowState::MAIN_MENU;
            } else if (sv_state == 1 || sv_state == 2) {  // SS_LOADING / SS_LOADING2
                new_state = GameFlowState::LOADING;
            }
            break;

        case GameFlowState::MAIN_MENU:
            if (sv_state == 1 || sv_state == 2) {  // SS_LOADING / SS_LOADING2
                new_state = GameFlowState::LOADING;
            } else if (sv_state == 3 && !(catchers & 0x2)) {  // SS_GAME, no UI
                new_state = GameFlowState::IN_GAME;
            }
            break;

        case GameFlowState::LOADING:
            if (sv_state == 3) {  // SS_GAME
                new_state = GameFlowState::IN_GAME;
            } else if (sv_state == 0) {  // SS_DEAD — load failed or disconnected
                new_state = GameFlowState::DISCONNECTED;
            }
            break;

        case GameFlowState::IN_GAME:
            if (sv_state != 3) {  // No longer in game
                if (sv_state == 1 || sv_state == 2) {
                    new_state = GameFlowState::LOADING;  // Map change
                } else {
                    new_state = GameFlowState::DISCONNECTED;
                }
            } else if (Godot_Client_GetPaused()) {
                new_state = GameFlowState::PAUSED;
            }
            break;

        case GameFlowState::PAUSED:
            if (!Godot_Client_GetPaused()) {
                new_state = GameFlowState::IN_GAME;
            }
            if (sv_state != 3) {
                new_state = GameFlowState::DISCONNECTED;
            }
            break;

        case GameFlowState::MISSION_COMPLETE:
            // Stay until a new map loads or menu opens
            if (sv_state == 1 || sv_state == 2) {
                new_state = GameFlowState::LOADING;
            } else if (catchers & 0x2) {
                new_state = GameFlowState::MAIN_MENU;
            }
            break;

        case GameFlowState::DISCONNECTED:
            if (catchers & 0x2) {  // KEYCATCH_UI
                new_state = GameFlowState::MAIN_MENU;
            } else if (sv_state == 1 || sv_state == 2) {
                new_state = GameFlowState::LOADING;
            } else if (sv_state == 3) {
                new_state = GameFlowState::IN_GAME;
            }
            break;
    }

    if (new_state != game_flow_state) {
        game_flow_state = new_state;
        emit_signal("game_flow_state_changed", (int)new_state);
    }
}

int MoHAARunner::get_game_flow_state() const {
    return (int)game_flow_state;
}

godot::String MoHAARunner::get_game_flow_state_string() const {
    switch (game_flow_state) {
        case GameFlowState::BOOT:             return "boot";
        case GameFlowState::TITLE_SCREEN:     return "title_screen";
        case GameFlowState::MAIN_MENU:        return "main_menu";
        case GameFlowState::LOADING:          return "loading";
        case GameFlowState::IN_GAME:          return "in_game";
        case GameFlowState::PAUSED:           return "paused";
        case GameFlowState::MISSION_COMPLETE: return "mission_complete";
        case GameFlowState::DISCONNECTED:     return "disconnected";
        default:                              return "unknown";
    }
}

// ──────────────────────────────────────────────
//  New game flow (Phase 262)
// ──────────────────────────────────────────────

void MoHAARunner::start_new_game(int difficulty) {
    if (!initialized) {
        UtilityFunctions::printerr("[MoHAA] Engine not initialised, cannot start new game.");
        return;
    }
    // Set difficulty cvar: 0 = easy, 1 = medium, 2 = hard
    char cmd[128];
    snprintf(cmd, sizeof(cmd), "set skill %d\n", difficulty);
    Cbuf_AddText(cmd);
    // Load the first Allied Assault mission
    Cbuf_AddText("map m1l1\n");
}

void MoHAARunner::set_difficulty(int difficulty) {
    if (!initialized) return;
    char cmd[64];
    snprintf(cmd, sizeof(cmd), "set skill %d\n", difficulty);
    Cbuf_AddText(cmd);
}

// ──────────────────────────────────────────────
//  Save / load game (Phase 264)
// ──────────────────────────────────────────────

void MoHAARunner::quick_save() {
    if (!initialized) return;
    Cbuf_AddText("savegame quick\n");
}

void MoHAARunner::quick_load() {
    if (!initialized) return;
    Cbuf_AddText("loadgame quick\n");
}

void MoHAARunner::save_game(const godot::String &p_slot_name) {
    if (!initialized) return;
    godot::CharString slot = p_slot_name.utf8();
    char cmd[256];
    snprintf(cmd, sizeof(cmd), "savegame %s\n", slot.get_data());
    Cbuf_AddText(cmd);
}

void MoHAARunner::load_game(const godot::String &p_slot_name) {
    if (!initialized) return;
    godot::CharString slot = p_slot_name.utf8();
    char cmd[256];
    snprintf(cmd, sizeof(cmd), "loadgame %s\n", slot.get_data());
    Cbuf_AddText(cmd);
}

godot::PackedStringArray MoHAARunner::get_save_list() const {
    godot::PackedStringArray result;
    if (!initialized) return result;

    // Save files are in fs_homepath/save/ — list .sav files via VFS
    int count = 0;
    char **list = Godot_VFS_ListFiles("save", ".sav", &count);
    if (!list) return result;

    for (int i = 0; i < count; i++) {
        if (list[i]) {
            result.push_back(godot::String(list[i]));
        }
    }
    Godot_VFS_FreeFileList(list);
    return result;
}

// ──────────────────────────────────────────────
//  Multiplayer helpers (Phases 265-266)
// ──────────────────────────────────────────────

godot::PackedStringArray MoHAARunner::list_available_maps() const {
    godot::PackedStringArray result;
    if (!initialized) return result;

    // BSP maps are in maps/ directory
    int count = 0;
    char **list = Godot_VFS_ListFiles("maps", ".bsp", &count);
    if (!list) return result;

    for (int i = 0; i < count; i++) {
        if (list[i]) {
            // Strip .bsp extension for cleaner display
            godot::String name(list[i]);
            if (name.ends_with(".bsp")) {
                name = name.substr(0, name.length() - 4);
            }
            result.push_back(name);
        }
    }
    Godot_VFS_FreeFileList(list);
    return result;
}

void MoHAARunner::start_server(const godot::String &p_map, const godot::String &p_gametype, int max_clients) {
    if (!initialized) return;
    godot::CharString map = p_map.utf8();
    godot::CharString gt = p_gametype.utf8();
    char cmd[512];
    snprintf(cmd, sizeof(cmd),
             "set g_gametype %s\nset sv_maxclients %d\nmap %s\n",
             gt.get_data(), max_clients, map.get_data());
    Cbuf_AddText(cmd);
}

void MoHAARunner::connect_to_server(const godot::String &p_address) {
    if (!initialized) return;
#ifdef HAS_MULTIPLAYER_MODULE
    Godot_MP_ConnectToServer(p_address.utf8().get_data());
#else
    godot::CharString addr = p_address.utf8();
    char cmd[256];
    snprintf(cmd, sizeof(cmd), "connect %s\n", addr.get_data());
    Cbuf_AddText(cmd);
#endif
}

void MoHAARunner::disconnect_from_server() {
    if (!initialized) return;
#ifdef HAS_MULTIPLAYER_MODULE
    Godot_MP_Disconnect();
#else
    Cbuf_AddText("disconnect\n");
#endif
}

// ──────────────────────────────────────────────
//  Multiplayer server browser + hosting (Phase 263)
// ──────────────────────────────────────────────

void MoHAARunner::host_server(const godot::String &p_map, int maxplayers, int gametype) {
    if (!initialized) return;
#ifdef HAS_MULTIPLAYER_MODULE
    Godot_MP_HostServer(p_map.utf8().get_data(), maxplayers, gametype);
#endif
}

void MoHAARunner::refresh_server_list() {
    if (!initialized) return;
#ifdef HAS_MULTIPLAYER_MODULE
    Godot_MP_RefreshServerList();
#endif
}

void MoHAARunner::refresh_lan() {
    if (!initialized) return;
#ifdef HAS_MULTIPLAYER_MODULE
    Godot_MP_RefreshLAN();
#endif
}

int MoHAARunner::get_server_count() const {
#ifdef HAS_MULTIPLAYER_MODULE
    return Godot_MP_GetServerCount();
#else
    return 0;
#endif
}

// ──────────────────────────────────────────────
//  Settings helpers (Phases 267-270)
// ──────────────────────────────────────────────

void MoHAARunner::set_audio_volume(float master, float music, float dialog) {
    if (!initialized) return;
    char cmd[256];
    snprintf(cmd, sizeof(cmd),
             "set s_volume %f\nset s_musicvolume %f\nset s_dialogvolume %f\n",
             master, music, dialog);
    Cbuf_AddText(cmd);
}

void MoHAARunner::set_video_fullscreen(bool fullscreen) {
    // This is a Godot-side setting, not an engine cvar
    DisplayServer *ds = DisplayServer::get_singleton();
    if (!ds) return;
    if (fullscreen) {
        ds->window_set_mode(DisplayServer::WINDOW_MODE_FULLSCREEN);
    } else {
        ds->window_set_mode(DisplayServer::WINDOW_MODE_WINDOWED);
    }
}

void MoHAARunner::set_video_resolution(int width, int height) {
    DisplayServer *ds = DisplayServer::get_singleton();
    if (!ds) return;
    ds->window_set_size(Vector2i(width, height));
}

void MoHAARunner::set_network_rate(const godot::String &p_preset) {
    if (!initialized) return;
    godot::CharString preset = p_preset.utf8();
    const char *p = preset.get_data();

    // Standard MOHAA rate presets
    if (strcmp(p, "modem") == 0) {
        Cbuf_AddText("set rate 4000\nset snaps 20\nset cl_maxpackets 30\n");
    } else if (strcmp(p, "isdn") == 0) {
        Cbuf_AddText("set rate 8000\nset snaps 30\nset cl_maxpackets 30\n");
    } else if (strcmp(p, "cable") == 0) {
        Cbuf_AddText("set rate 15000\nset snaps 40\nset cl_maxpackets 42\n");
    } else if (strcmp(p, "lan") == 0) {
        Cbuf_AddText("set rate 25000\nset snaps 40\nset cl_maxpackets 42\n");
    }
}

// ──────────────────────────────────────────────
//  Menu control (Phase 261)
// ──────────────────────────────────────────────

void MoHAARunner::open_main_menu() {
    if (!initialized) return;
    Cbuf_AddText("togglemenu 1\n");
}

void MoHAARunner::close_menu() {
    if (!initialized) return;
    Cbuf_AddText("togglemenu 0\n");
}

void MoHAARunner::_unhandled_input(const Ref<InputEvent> &p_event) {
    if (!initialized) return;

    // ── Phase 48: UI input routing ──
    // When the engine's UI is active (menus, console, chat), route input
    // through the UI handlers instead of direct engine injection.
#if defined(HAS_UI_INPUT_MODULE) && defined(HAS_UI_SYSTEM_MODULE)
    bool ui_captures = Godot_UI_ShouldCaptureInput() != 0;
#else
    bool ui_captures = false;
#endif

    // ── Keyboard events ──
    InputEventKey *key_event = Object::cast_to<InputEventKey>(p_event.ptr());
    if (key_event) {
        bool pressed = key_event->is_pressed();
        bool echo = key_event->is_echo();

        // F9 — toggle HUD overlay visibility (debug aid)
        if (pressed && !echo && key_event->get_keycode() == Key::KEY_F9) {
            hud_visible = !hud_visible;
            if (hud_layer) hud_layer->set_visible(hud_visible);
            UtilityFunctions::print(String("[MoHAA] HUD overlay ") + (hud_visible ? String("ON") : String("OFF")));
            return;
        }

        // Get the keycode (logical key, respects keyboard layout)
        int godot_key = (int)key_event->get_keycode();
        if (godot_key == 0) {
            // Fallback to physical keycode if logical is unavailable
            godot_key = (int)key_event->get_physical_keycode();
        }

        if (godot_key != 0) {
#ifdef HAS_UI_INPUT_MODULE
            if (ui_captures) {
                // Route key events through UI system (menus, console, chat)
                if (!echo) {
                    Godot_UI_HandleKeyEvent(godot_key, pressed ? 1 : 0);
                }
                // Route character events for text input (console, chat)
                if (pressed || echo) {
                    int64_t unicode = key_event->get_unicode();
                    if (unicode > 0) {
                        Godot_UI_HandleCharEvent((int)unicode);
                    }
                }
                return;
            }
#endif
            // Send SE_KEY for initial press and release (not for echoes)
            // The engine tracks key state internally and handles its own repeat.
            if (!echo) {
                int mapped = Godot_InjectKeyEvent(godot_key, pressed ? 1 : 0);

                // Debug: log first few key events
                static int key_debug_count = 0;
                if (key_debug_count < 10 && pressed) {
                    UtilityFunctions::print(String("[Input] key godot=") + String::num_int64(godot_key) +
                        String(" mapped=") + String::num_int64(mapped) +
                        String(" catchers=0x") + String::num_int64(Godot_Client_GetKeyCatchers(), 16) +
                        String(" guiMouse=") + String::num_int64(Godot_Client_GetGuiMouse()));
                    key_debug_count++;
                }
            }

            // Send SE_CHAR for text input on press + echo (for console/chat)
            if (pressed || echo) {
                int64_t unicode = key_event->get_unicode();
                if (unicode > 0) {
                    Godot_InjectCharEvent((int)unicode);
                }
            }
        }

        return;
    }

    // ── Mouse motion ──
    InputEventMouseMotion *motion_event = Object::cast_to<InputEventMouseMotion>(p_event.ptr());
    if (motion_event) {
#ifdef HAS_UI_INPUT_MODULE
        if (ui_captures) {
            // Route mouse motion to UI system for menu navigation
            Vector2 rel = motion_event->get_relative();
            Godot_UI_HandleMouseMotion((int)rel.x, (int)rel.y);
            return;
        }
#endif
        // Only forward mouse motion when captured (in-game mode)
        if (mouse_captured) {
            Vector2 rel = motion_event->get_relative();
            Godot_InjectMouseMotion((int)rel.x, (int)rel.y);
        }
        return;
    }

    // ── Mouse buttons ──
    InputEventMouseButton *button_event = Object::cast_to<InputEventMouseButton>(p_event.ptr());
    if (button_event) {
        int godot_button = (int)button_event->get_button_index();
        bool pressed = button_event->is_pressed();

#ifdef HAS_UI_INPUT_MODULE
        if (ui_captures) {
            // Route mouse buttons to UI system
            Godot_UI_HandleMouseButton(godot_button, pressed ? 1 : 0);
            return;
        }
#endif

        // Regular buttons: send press and release
        if (godot_button >= 1 && godot_button <= 3) {
            Godot_InjectMouseButton(godot_button, pressed ? 1 : 0);
        }
        // Extra buttons (thumb buttons)
        else if (godot_button == 8 || godot_button == 9) {
            Godot_InjectMouseButton(godot_button, pressed ? 1 : 0);
        }
        // Wheel events: Godot only fires pressed=true for wheel notches.
        // The engine expects a press immediately followed by a release.
        else if (godot_button >= 4 && godot_button <= 5) {
            if (pressed) {
                Godot_InjectMouseButton(godot_button, 1);  // press
                Godot_InjectMouseButton(godot_button, 0);  // release
            }
        }

        return;
    }
}
