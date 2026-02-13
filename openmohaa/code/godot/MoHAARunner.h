#ifndef MOHAARUNNER_H
#define MOHAARUNNER_H

#include <godot_cpp/classes/node.hpp>
#include <godot_cpp/classes/node3d.hpp>
#include <godot_cpp/classes/camera3d.hpp>
#include <godot_cpp/classes/environment.hpp>
#include <godot_cpp/classes/world_environment.hpp>
#include <godot_cpp/classes/directional_light3d.hpp>
#include <godot_cpp/classes/omni_light3d.hpp>
#include <godot_cpp/classes/mesh_instance3d.hpp>
#include <godot_cpp/classes/array_mesh.hpp>
#include <godot_cpp/classes/standard_material3d.hpp>
#include <godot_cpp/classes/canvas_layer.hpp>
#include <godot_cpp/classes/control.hpp>
#include <godot_cpp/classes/audio_stream_player.hpp>
#include <godot_cpp/classes/audio_stream_player3d.hpp>
#include <godot_cpp/classes/audio_stream_wav.hpp>
#include <godot_cpp/classes/audio_stream_mp3.hpp>
#include <godot_cpp/classes/audio_listener3d.hpp>
#include <godot_cpp/core/class_db.hpp>
#include <godot_cpp/variant/packed_byte_array.hpp>
#include <godot_cpp/variant/packed_string_array.hpp>
#include <godot_cpp/classes/input_event.hpp>
#include <godot_cpp/classes/image_texture.hpp>
#include <godot_cpp/classes/texture_rect.hpp>

#include <vector>
#include <unordered_map>

// ── Defensive module integration (compile-time guards) ──
// Each agent's module is conditionally included only if it exists,
// allowing MoHAARunner to compile regardless of which agents have merged.
#if __has_include("godot_music.h")
#include "godot_music.h"
#define HAS_MUSIC_MODULE 1
#endif

#if __has_include("godot_shader_material.h")
#include "godot_shader_material.h"
#define HAS_SHADER_MATERIAL_MODULE 1
#endif

#if __has_include("godot_weather.h")
#include "godot_weather.h"
#define HAS_WEATHER_MODULE 1
#endif

#if __has_include("godot_vertex_deform.h")
#include "godot_vertex_deform.h"
#define HAS_VERTEX_DEFORM_MODULE 1
#endif

#if __has_include("godot_mesh_cache.h")
#include "godot_mesh_cache.h"
#define HAS_MESH_CACHE_MODULE 1
#endif

#if __has_include("godot_entity_lighting.h")
#include "godot_entity_lighting.h"
#define HAS_ENTITY_LIGHTING_MODULE 1
#endif

#if __has_include("godot_weapon_viewport.h")
#include "godot_weapon_viewport.h"
#define HAS_WEAPON_VIEWPORT_MODULE 1
#endif

#if __has_include("godot_ui_system.h")
#include "godot_ui_system.h"
#define HAS_UI_SYSTEM_MODULE 1
#endif

#if __has_include("godot_ui_input.h")
#include "godot_ui_input.h"
#define HAS_UI_INPUT_MODULE 1
#endif

#if __has_include("godot_vfx.h")
#include "godot_vfx.h"
#define HAS_VFX_MODULE 1
#endif

#if __has_include("godot_screen_effects.h")
#include "godot_screen_effects.h"
#define HAS_SCREEN_EFFECTS_MODULE 1
#endif

#if __has_include("godot_game_accessors.h")
#include "godot_game_accessors.h"
#define HAS_GAME_ACCESSORS_MODULE 1
#endif

#if __has_include("godot_network_accessors.h")
#include "godot_network_accessors.h"
#define HAS_NETWORK_ACCESSORS_MODULE 1
#endif

#if __has_include("godot_pvs.h")
#include "godot_pvs.h"
#define HAS_PVS_MODULE 1
#endif

#if __has_include("godot_debug_render.h")
#include "godot_debug_render.h"
#define HAS_DEBUG_RENDER_MODULE 1
#endif

#if __has_include("godot_shadow.h")
#include "godot_shadow.h"
#define HAS_SHADOW_MODULE 1
#endif

using namespace godot;

// ── Game flow state machine (Phase 261) ──
// Tracks the high-level game state for title screen, menus, gameplay, etc.
enum class GameFlowState {
    BOOT,               // Engine just initialised, no map loaded yet
    TITLE_SCREEN,       // Showing title/splash screen
    MAIN_MENU,          // Engine main menu active
    LOADING,            // Map is loading (SS_LOADING / SS_LOADING2)
    IN_GAME,            // Map loaded and playing (SS_GAME)
    PAUSED,             // In-game but paused (single-player)
    MISSION_COMPLETE,   // End-of-mission detected
    DISCONNECTED,       // Disconnected from server / map unloaded
};

class MoHAARunner : public Node {
    GDCLASS(MoHAARunner, Node)

private:
    bool initialized = false;
    String basepath;   // Path to game data (main/, pak files, etc.)
    String startup_args = "+set dedicated 0 +set developer 1"; // Pre-Com_Init cvar args

    // Track server state for change detection (signals)
    int last_server_state = 0;   // SS_DEAD
    String last_map_name;

    // Game flow state machine (Phase 261)
    GameFlowState game_flow_state = GameFlowState::BOOT;
    void update_game_flow_state();  // Called each frame to advance the state machine

    // Input state (Phase 6)
    bool mouse_captured = false;  // Whether mouse is in relative/captured mode
    bool hud_visible = true;        // F9 toggles HUD overlay visibility

    // 3D scene nodes (Phase 7a — camera bridge)
    Node3D *game_world = nullptr;            // Root for all 3D content
    Camera3D *camera = nullptr;              // Driven by engine refdef_t each frame
    DirectionalLight3D *sun_light = nullptr;  // Basic directional light
    WorldEnvironment *world_env = nullptr;    // Ambient/fog environment

    // BSP world geometry (Phase 7b)
    Node3D *bsp_map_node = nullptr;          // Currently loaded BSP mesh tree
    String loaded_bsp_name;                  // Path of the currently loaded BSP

    // Static BSP models (Phase 10)
    Node3D *static_model_root = nullptr;     // Container for TIKI static models from BSP

    // Entity rendering (Phase 7e)
    Node3D *entity_root = nullptr;                        // Container for entity debug meshes
    std::vector<MeshInstance3D *> entity_meshes;           // Pooled debug mesh instances
    std::vector<OmniLight3D *> dlight_nodes;              // Pooled dynamic light nodes
    int active_entity_count = 0;                          // Entities visible this frame
    int active_dlight_count = 0;                          // Dynamic lights this frame

    // Poly/particle rendering (Phase 16)
    Node3D *poly_root = nullptr;                          // Container for poly meshes
    std::vector<MeshInstance3D *> poly_meshes;             // Pooled poly mesh instances
    int active_poly_count = 0;                            // Polys rendered this frame

    // Swipe effects (Phase 24)
    Node3D *swipe_root = nullptr;
    MeshInstance3D *swipe_mesh = nullptr;

    // Terrain marks (Phase 25)
    Node3D *terrain_mark_root = nullptr;
    std::vector<MeshInstance3D *> terrain_mark_meshes;
    int active_terrain_mark_count = 0;

    // Shader animation tracking (Phase 36)
    double shader_anim_time = 0.0;

    // AnimMap texture cycling (Phase 71)
    // shader_handle → vector of loaded texture frames
    std::unordered_map<int, std::vector<Ref<ImageTexture>>> animmap_frames;
    // shader_handle → {freq, num_frames}
    struct AnimMapInfo { float freq; int num_frames; };
    std::unordered_map<int, AnimMapInfo> animmap_info;

    // Sound entity position tracking (Phase 49 rendering side)
    // Sound fade state (Phase 50 rendering side)
    float sound_fade_elapsed = 0.0f;
    float sound_fade_duration = 0.0f;
    bool sound_fading = false;

    // Entity mesh caching (Phase 37, improved Phase 60)
    // Track per-entity state hash to avoid rebuilding meshes each frame
    struct EntityCacheKey {
        int hModel;
        int reType;
        int customShader;
        int frame;         // beam diameter / animation frame
        bool operator==(const EntityCacheKey &o) const {
            return hModel == o.hModel && reType == o.reType &&
                   customShader == o.customShader && frame == o.frame;
        }
    };
    std::vector<EntityCacheKey> entity_cache_keys;

    // Phase 60: Skeletal mesh caching by entity number + animation state hash
    struct SkelMeshCacheEntry {
        uint64_t anim_hash = 0;
        int mesh_surfaces = 0;             // surface count as a lightweight mesh identity
        Ref<ArrayMesh> mesh;
    };
    std::unordered_map<int, SkelMeshCacheEntry> skel_mesh_cache; // entityNumber → cached skinned mesh

    // Phase 61: Tinted material cache — avoid per-frame material duplication
    // Key = (hModel << 20) | (surfIdx << 12) | quantised_rgba
    std::unordered_map<uint64_t, Ref<StandardMaterial3D>> tinted_mat_cache;

    // 2D HUD overlay (Phase 7h)
    CanvasLayer *hud_layer = nullptr;                     // Overlay layer for 2D elements
    Control *hud_control = nullptr;                       // Control node for custom draw
    std::unordered_map<int, Ref<ImageTexture>> shader_textures; // shader handle → loaded texture

    // Audio bridge (Phase 8)
    Node3D *audio_root = nullptr;                                    // Container for audio player nodes
    AudioListener3D *audio_listener = nullptr;                       // 3D listener driven by engine camera
    std::vector<AudioStreamPlayer3D *> sfx_players_3d;               // Pool of 3D audio players
    std::vector<AudioStreamPlayer *>   sfx_players_2d;               // Pool of 2D audio players
    std::unordered_map<int, Ref<AudioStream>> sfx_cache;              // sfxHandle → loaded audio stream (WAV or MP3)
    // Looping sound tracking (Phase 40): key = composite of sfxHandle + quantised position
    std::unordered_map<int64_t, int> active_loops;                   // loop key → 3D player index
    int next_3d_player = 0;                                          // Round-robin index for 3D pool
    int next_2d_player = 0;                                          // Round-robin index for 2D pool
    static const int MAX_3D_PLAYERS = 32;
    static const int MAX_2D_PLAYERS = 16;

    // Sound channel tracking for priority eviction (Phase 41)
    // Tracks which entity+channel is using each 3D player slot
    struct PlayerSlotInfo {
        int entnum = -1;
        int channel = -1;
        bool in_use = false;
    };
    std::vector<PlayerSlotInfo> player_slot_info;                    // Size = MAX_3D_PLAYERS

    // Music playback (Phase 17, improved Phase 39)
    AudioStreamPlayer *music_player = nullptr;                       // Background music player
    String current_music_name;                                       // Currently playing soundtrack name
    float music_target_volume = 1.0f;                                // Target volume for fading
    // Smooth fade state (Phase 39)
    float music_fade_from = 1.0f;                                    // Volume at fade start (linear)
    float music_fade_to = 1.0f;                                      // Volume at fade end (linear)
    float music_fade_duration = 0.0f;                                // Total fade time (seconds)
    float music_fade_elapsed = 0.0f;                                 // Elapsed fade time (seconds)
    bool music_fading = false;                                       // Whether a fade is in progress

    void setup_audio();                                              // Create audio player pools
    void update_audio(double delta);                                 // Process sound events + loops
    Ref<AudioStream> load_wav_from_vfs(int sfxHandle);                // Load WAV/MP3 via engine VFS

    // Cinematic display (Phase 11)
    CanvasLayer *cin_layer = nullptr;                                // Overlay for cinematic video
    TextureRect *cin_rect = nullptr;                                 // Fullscreen texture rect
    Ref<ImageTexture> cin_texture;                                   // Cinematic frame texture
    bool cin_was_active = false;                                     // Track state transitions

    void setup_cinematic();                                          // Create cinematic display nodes
    void update_cinematic();                                         // Update cinematic frame display

    void setup_3d_scene();    // Create Camera3D, light, environment
    void update_camera();     // Read engine viewpoint and update Camera3D
    void check_world_load();  // Load BSP geometry if a new map was loaded
    void load_static_models(); // Register and instantiate static TIKI models from BSP
    void update_entities();   // Read captured entities and update debug meshes
    void update_dlights();    // Read captured dynamic lights and update OmniLight3D
    void update_polys();      // Render captured polys (particles, effects)
    void update_swipe_effects(); // Render swipe trails (Phase 24)
    void update_terrain_marks(); // Render terrain mark decals (Phase 25)
    void update_shader_animations(double delta); // Animate tcMod scrolling (Phase 36)
    void update_2d_overlay(); // Read 2D draw commands and queue redraw
    Ref<ImageTexture> get_shader_texture(int shader_handle); // Lazily load shader textures
    void load_skybox();  // Load skybox cubemap from BSP sky shader (Phase 12)

protected:
    static void _bind_methods();

public:
    MoHAARunner();
    ~MoHAARunner();

    void _ready() override;
    void _process(double delta) override;
    void _unhandled_input(const Ref<InputEvent> &p_event) override;

    // Engine lifecycle
    bool is_engine_initialized() const;
    String get_basepath() const;
    void set_basepath(const String &p_path);

    // Input control (Phase 6)
    void set_mouse_captured(bool p_captured);
    bool is_mouse_captured() const;
    void set_hud_visible(bool p_visible);
    bool is_hud_visible() const;

    // Startup config
    void set_startup_args(const String &p_args);
    String get_startup_args() const;

    // Commands
    void execute_command(const String &p_command);
    void load_map(const String &p_map_name);

    // Server status (Task 2.5.3)
    bool is_map_loaded() const;
    String get_current_map() const;
    int get_player_count() const;
    int get_server_state() const;
    String get_server_state_string() const;

    // VFS access (Task 4.1) — read files from the engine's pk3/search-path VFS
    PackedByteArray vfs_read_file(const String &p_qpath) const;
    bool vfs_file_exists(const String &p_qpath) const;
    PackedStringArray vfs_list_files(const String &p_directory, const String &p_extension) const;
    String vfs_get_gamedir() const;

    // Game flow state (Phase 261)
    int get_game_flow_state() const;
    String get_game_flow_state_string() const;

    // New game flow (Phase 262)
    void start_new_game(int difficulty);
    void set_difficulty(int difficulty);

    // Save / load game (Phase 264)
    void quick_save();
    void quick_load();
    void save_game(const String &p_slot_name);
    void load_game(const String &p_slot_name);
    PackedStringArray get_save_list() const;

    // Multiplayer helpers (Phases 265-266)
    PackedStringArray list_available_maps() const;
    void start_server(const String &p_map, const String &p_gametype, int max_clients);
    void connect_to_server(const String &p_address);
    void disconnect_from_server();

    // Settings helpers (Phases 267-270)
    void set_audio_volume(float master, float music, float dialog);
    void set_video_fullscreen(bool fullscreen);
    void set_video_resolution(int width, int height);
    void set_network_rate(const String &p_preset);

    // Main menu control (Phase 261)
    void open_main_menu();
    void close_menu();
};

#endif
