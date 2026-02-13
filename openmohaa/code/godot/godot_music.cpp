/*
 * godot_music.cpp — Music playback manager for the OpenMoHAA GDExtension.
 *
 * Uses two AudioStreamPlayer nodes for crossfade support.  Music files
 * are loaded from the engine VFS (sound/music/*.mp3) as raw bytes and
 * wrapped in Godot AudioStreamMP3 resources.
 *
 * Phase 42 — Audio Completeness.
 */

#include "godot_music.h"

#include <godot_cpp/classes/node.hpp>
#include <godot_cpp/classes/audio_stream_player.hpp>
#include <godot_cpp/classes/audio_stream_mp3.hpp>
#include <godot_cpp/variant/packed_byte_array.hpp>
#include <godot_cpp/variant/utility_functions.hpp>
#include <godot_cpp/variant/string.hpp>

#include <cstring>
#include <cmath>

/* ------------------------------------------------------------------ */
/*  C accessors — declared here to avoid engine header collisions     */
/* ------------------------------------------------------------------ */

extern "C" {
    /* godot_sound.c — music state */
    int         Godot_Sound_GetMusicAction(void);
    const char *Godot_Sound_GetMusicName(void);
    float       Godot_Sound_GetMusicVolume(void);
    float       Godot_Sound_GetMusicFadeTime(void);
    void        Godot_Sound_ClearMusicAction(void);
    int         Godot_Sound_GetMusicMood(int *current, int *fallback);

    /* godot_sound.c — triggered music */
    int         Godot_Sound_GetTriggeredAction(void);
    const char *Godot_Sound_GetTriggeredName(void);
    int         Godot_Sound_GetTriggeredLoopCount(void);
    int         Godot_Sound_GetTriggeredOffset(void);
    void        Godot_Sound_ClearTriggeredAction(void);

    /* godot_vfs_accessors.c */
    long Godot_VFS_ReadFile(const char *qpath, void **out_buffer);
    void Godot_VFS_FreeFile(void *buffer);
    int  Godot_VFS_FileExists(const char *qpath);
}

/* Music action constants (must match godot_sound.c) */
#define GR_MUSIC_NONE   0
#define GR_MUSIC_PLAY   1
#define GR_MUSIC_STOP   2
#define GR_MUSIC_VOLUME 3

/* Triggered action constants (must match godot_sound.c) */
#define GR_TRIG_NONE    0
#define GR_TRIG_SETUP   1
#define GR_TRIG_START   2
#define GR_TRIG_STOP    3
#define GR_TRIG_PAUSE   4
#define GR_TRIG_UNPAUSE 5

/* Maximum file path length (matches engine MAX_QPATH). */
#define MUSIC_MAX_PATH 256

using namespace godot;

/* ================================================================== */
/*  Internal state                                                     */
/* ================================================================== */

static Node *s_parent = nullptr;

/* Two players for crossfade support.  Index 0 = primary, 1 = secondary. */
static AudioStreamPlayer *s_players[2]  = { nullptr, nullptr };
static int                s_active_idx  = 0;    /* which player is current */

/* Triggered music uses a separate player. */
static AudioStreamPlayer *s_triggered_player = nullptr;

static char  s_current_track[MUSIC_MAX_PATH] = {0};
static float s_master_volume   = 1.0f;
static float s_target_volume   = 1.0f;
static float s_current_volume  = 1.0f;
static float s_fade_duration   = 0.0f;
static float s_fade_elapsed    = 0.0f;
static bool  s_fading          = false;
static bool  s_initialised     = false;

/* ================================================================== */
/*  Helpers                                                            */
/* ================================================================== */

/*
 * Convert a linear volume (0–1) to Godot's dB scale.
 * Godot AudioStreamPlayer uses dB, where 0 dB = full volume.
 * We clamp the minimum to -80 dB (effectively silent).
 */
static float linear_to_db(float linear)
{
    if (linear <= 0.0001f) return -80.0f;
    return 20.0f * log10f(linear);
}

/*
 * Try to load a music file from the VFS.
 * Tries several path variants:
 *   1. The name as-is
 *   2. "sound/music/<name>.mp3"
 *   3. "sound/music/<name>"
 *
 * Returns a Ref<AudioStreamMP3> or null on failure.
 */
static Ref<AudioStreamMP3> load_music_from_vfs(const char *name)
{
    if (!name || !name[0]) return Ref<AudioStreamMP3>();

    /* Build candidate paths */
    char paths[4][MUSIC_MAX_PATH];
    int  path_count = 0;

    /* 1. As-is */
    strncpy(paths[path_count], name, MUSIC_MAX_PATH - 1);
    paths[path_count][MUSIC_MAX_PATH - 1] = '\0';
    path_count++;

    /* 2. "sound/music/<name>.mp3" */
    if (strstr(name, "sound/") == nullptr && strstr(name, ".mp3") == nullptr) {
        snprintf(paths[path_count], MUSIC_MAX_PATH, "sound/music/%s.mp3", name);
        path_count++;
    }

    /* 3. "sound/music/<name>" */
    if (strstr(name, "sound/") == nullptr) {
        snprintf(paths[path_count], MUSIC_MAX_PATH, "sound/music/%s", name);
        path_count++;
    }

    /* 4. With .mp3 appended if missing */
    if (strstr(name, ".mp3") == nullptr) {
        snprintf(paths[path_count], MUSIC_MAX_PATH, "%s.mp3", name);
        path_count++;
    }

    for (int i = 0; i < path_count; i++) {
        void *buf = nullptr;
        long  len = Godot_VFS_ReadFile(paths[i], &buf);
        if (len <= 0 || !buf) continue;

        /* Wrap the raw bytes into a PackedByteArray */
        PackedByteArray pba;
        pba.resize(len);
        memcpy(pba.ptrw(), buf, (size_t)len);
        Godot_VFS_FreeFile(buf);

        /* Create AudioStreamMP3 */
        Ref<AudioStreamMP3> stream;
        stream.instantiate();
        stream->set_data(pba);

        UtilityFunctions::print(
            String("[GodotMusic] Loaded music: ") + String(paths[i]) +
            String(" (") + String::num_int64(len) + String(" bytes)"));
        return stream;
    }

    UtilityFunctions::print(
        String("[GodotMusic] WARNING: Could not load music '") +
        String(name) + String("'"));
    return Ref<AudioStreamMP3>();
}

/*
 * Start playing a track on the given player.
 */
static void play_track(AudioStreamPlayer *player, const char *name)
{
    if (!player || !name || !name[0]) return;

    Ref<AudioStreamMP3> stream = load_music_from_vfs(name);
    if (stream.is_null()) return;

    stream->set_loop(true);
    player->set_stream(stream);
    player->set_volume_db(linear_to_db(s_current_volume * s_master_volume));
    player->play();
}

/* ================================================================== */
/*  Public API                                                         */
/* ================================================================== */

extern "C" void Godot_Music_Init(void *parent_node)
{
    if (s_initialised) return;
    if (!parent_node) return;

    s_parent = reinterpret_cast<Node *>(parent_node);

    /* Create the two crossfade players */
    for (int i = 0; i < 2; i++) {
        s_players[i] = memnew(AudioStreamPlayer);
        s_players[i]->set_name(String("MusicPlayer") + String::num_int64(i));
        s_players[i]->set_bus(StringName("Master"));
        s_parent->add_child(s_players[i]);
    }

    /* Create the triggered-music player */
    s_triggered_player = memnew(AudioStreamPlayer);
    s_triggered_player->set_name(String("TriggeredMusicPlayer"));
    s_triggered_player->set_bus(StringName("Master"));
    s_parent->add_child(s_triggered_player);

    s_active_idx     = 0;
    s_current_track[0] = '\0';
    s_master_volume  = 1.0f;
    s_target_volume  = 1.0f;
    s_current_volume = 1.0f;
    s_fading         = false;
    s_initialised    = true;

    UtilityFunctions::print("[GodotMusic] Initialised");
}

extern "C" void Godot_Music_Shutdown(void)
{
    if (!s_initialised) return;

    for (int i = 0; i < 2; i++) {
        if (s_players[i]) {
            s_players[i]->stop();
            if (s_players[i]->get_parent()) {
                s_players[i]->get_parent()->remove_child(s_players[i]);
            }
            memdelete(s_players[i]);
            s_players[i] = nullptr;
        }
    }

    if (s_triggered_player) {
        s_triggered_player->stop();
        if (s_triggered_player->get_parent()) {
            s_triggered_player->get_parent()->remove_child(s_triggered_player);
        }
        memdelete(s_triggered_player);
        s_triggered_player = nullptr;
    }

    s_parent        = nullptr;
    s_initialised   = false;
    s_current_track[0] = '\0';

    UtilityFunctions::print("[GodotMusic] Shutdown");
}

extern "C" void Godot_Music_Update(float delta)
{
    if (!s_initialised) return;

    /* ── Handle soundtrack music state ── */
    int action = Godot_Sound_GetMusicAction();
    if (action != GR_MUSIC_NONE) {
        switch (action) {
        case GR_MUSIC_PLAY: {
            const char *name = Godot_Sound_GetMusicName();
            if (name && name[0]) {
                /* If a different track, crossfade to it */
                if (strcmp(s_current_track, name) != 0) {
                    int old_idx = s_active_idx;
                    s_active_idx = 1 - s_active_idx;

                    play_track(s_players[s_active_idx], name);
                    strncpy(s_current_track, name, MUSIC_MAX_PATH - 1);
                    s_current_track[MUSIC_MAX_PATH - 1] = '\0';

                    /* Fade out old player */
                    float fade = Godot_Sound_GetMusicFadeTime();
                    if (fade > 0.01f && s_players[old_idx]->is_playing()) {
                        s_fade_duration = fade;
                        s_fade_elapsed  = 0.0f;
                        s_fading        = true;
                    } else {
                        s_players[old_idx]->stop();
                    }
                }
            }
            break;
        }
        case GR_MUSIC_STOP:
            for (int i = 0; i < 2; i++) {
                if (s_players[i]) s_players[i]->stop();
            }
            s_current_track[0] = '\0';
            s_fading = false;
            break;

        case GR_MUSIC_VOLUME: {
            float vol  = Godot_Sound_GetMusicVolume();
            float fade = Godot_Sound_GetMusicFadeTime();
            if (fade > 0.01f) {
                s_target_volume = vol;
                s_fade_duration = fade;
                s_fade_elapsed  = 0.0f;
                s_fading        = true;
            } else {
                s_current_volume = vol;
                s_target_volume  = vol;
                s_fading = false;
                if (s_players[s_active_idx]) {
                    s_players[s_active_idx]->set_volume_db(
                        linear_to_db(s_current_volume * s_master_volume));
                }
            }
            break;
        }
        }
        Godot_Sound_ClearMusicAction();
    }

    /* ── Handle crossfade / volume fade ── */
    if (s_fading && s_fade_duration > 0.0f) {
        s_fade_elapsed += delta;
        float t = s_fade_elapsed / s_fade_duration;
        if (t >= 1.0f) {
            t = 1.0f;
            s_fading = false;

            /* Stop the old player once fade completes */
            int old_idx = 1 - s_active_idx;
            if (s_players[old_idx] && s_players[old_idx]->is_playing()) {
                s_players[old_idx]->stop();
            }
        }

        /* Fade in the active player, fade out the old one */
        float active_vol = s_target_volume * t;

        if (s_players[s_active_idx]) {
            s_players[s_active_idx]->set_volume_db(
                linear_to_db(active_vol * s_master_volume));
        }
        int old_idx = 1 - s_active_idx;
        if (s_players[old_idx] && s_players[old_idx]->is_playing()) {
            float old_vol = s_current_volume * (1.0f - t);
            s_players[old_idx]->set_volume_db(
                linear_to_db(old_vol * s_master_volume));
        }

        if (!s_fading) {
            s_current_volume = s_target_volume;
        }
    }

    /* ── Handle triggered music ── */
    int trig_action = Godot_Sound_GetTriggeredAction();
    if (trig_action != GR_TRIG_NONE && s_triggered_player) {
        switch (trig_action) {
        case GR_TRIG_SETUP:
            /* Just store — don't auto-play */
            break;
        case GR_TRIG_START: {
            const char *tname = Godot_Sound_GetTriggeredName();
            if (tname && tname[0]) {
                Ref<AudioStreamMP3> stream = load_music_from_vfs(tname);
                if (stream.is_valid()) {
                    int loop_count = Godot_Sound_GetTriggeredLoopCount();
                    stream->set_loop(loop_count != 0);
                    s_triggered_player->set_stream(stream);
                    s_triggered_player->set_volume_db(
                        linear_to_db(s_master_volume));
                    s_triggered_player->play();
                }
            }
            break;
        }
        case GR_TRIG_STOP:
            s_triggered_player->stop();
            break;
        case GR_TRIG_PAUSE:
            s_triggered_player->set_stream_paused(true);
            break;
        case GR_TRIG_UNPAUSE:
            s_triggered_player->set_stream_paused(false);
            break;
        }
        Godot_Sound_ClearTriggeredAction();
    }
}

extern "C" void Godot_Music_SetVolume(float volume)
{
    s_master_volume = (volume < 0.0f) ? 0.0f : (volume > 1.0f) ? 1.0f : volume;
    if (s_initialised && s_players[s_active_idx]) {
        s_players[s_active_idx]->set_volume_db(
            linear_to_db(s_current_volume * s_master_volume));
    }
    if (s_initialised && s_triggered_player) {
        s_triggered_player->set_volume_db(
            linear_to_db(s_master_volume));
    }
}

extern "C" int Godot_Music_IsPlaying(void)
{
    if (!s_initialised) return 0;
    if (s_players[s_active_idx] && s_players[s_active_idx]->is_playing())
        return 1;
    if (s_triggered_player && s_triggered_player->is_playing())
        return 1;
    return 0;
}

extern "C" const char *Godot_Music_GetCurrentTrack(void)
{
    return s_current_track;
}
