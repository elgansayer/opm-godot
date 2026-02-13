/*
 * godot_ubersound.cpp — Ubersound / sound alias parser for the OpenMoHAA
 * GDExtension.
 *
 * Parses ubersound .scr files from the VFS to build a sound-alias lookup
 * table.  Each alias maps a logical name to one or more concrete WAV/MP3
 * filenames plus optional parameters (volume, distance, pitch, channel,
 * subtitle flag).
 *
 * The ubersound .scr format (simplified):
 *   aliascache <alias_name> <sound_file> [soundparms <vol> <minDist> <maxDist> <pitch> <channel>]
 *   alias      <alias_name> <sound_file> [soundparms ...]
 *
 * When multiple entries share the same alias name, they form a random
 * group — Godot_Ubersound_Resolve picks one at random.
 *
 * Phase 45 — Audio Completeness.
 */

#include "godot_ubersound.h"

#include <cstring>
#include <cstdlib>
#include <cstdio>
#include <vector>
#include <string>
#include <unordered_map>

/* ------------------------------------------------------------------ */
/*  C accessors for VFS (avoids engine header collisions)             */
/* ------------------------------------------------------------------ */

extern "C" {
    long  Godot_VFS_ReadFile(const char *qpath, void **out_buffer);
    void  Godot_VFS_FreeFile(void *buffer);
    char **Godot_VFS_ListFiles(const char *directory, const char *extension,
                               int *out_count);
    void  Godot_VFS_FreeFileList(char **list);
}

/* ================================================================== */
/*  Internal data structures                                           */
/* ================================================================== */

/* One concrete sound variant inside an alias group. */
struct UbersoundEntry {
    std::string path;       /* e.g. "sound/weapons/m1_fire1.wav" */
    float       volume;     /* 0 = use default */
    float       minDist;    /* 0 = use default */
    float       maxDist;    /* 0 = use default */
    float       pitch;      /* 0 = use default (1.0) */
    int         channel;    /* -1 = not specified */
    bool        subtitle;   /* true if flagged for subtitle display */
};

/* Alias group — one or more entries sharing the same logical name. */
struct UbersoundAlias {
    std::string                name;
    std::vector<UbersoundEntry> entries;
};

/* ================================================================== */
/*  Module state                                                       */
/* ================================================================== */

static std::unordered_map<std::string, UbersoundAlias> s_aliases;
static bool s_loaded = false;
static unsigned int s_random_seed = 1;

/* Simple deterministic PRNG (avoids pulling in <random>) */
static unsigned int ubersound_rand(void)
{
    s_random_seed = s_random_seed * 1103515245u + 12345u;
    return (s_random_seed >> 16) & 0x7FFF;
}

/* ================================================================== */
/*  Token parser — simple whitespace-delimited tokeniser               */
/* ================================================================== */

static const char *skip_whitespace(const char *p)
{
    while (*p && (*p == ' ' || *p == '\t' || *p == '\r')) p++;
    return p;
}

/*
 * Parse the next whitespace-delimited token.
 * Returns a pointer past the token, or NULL if end-of-line / end-of-string.
 */
static const char *parse_token(const char *p, char *out, int out_len)
{
    p = skip_whitespace(p);
    if (!*p || *p == '\n' || *p == '/' ) return nullptr;

    /* Handle quoted strings */
    if (*p == '"') {
        p++;
        int i = 0;
        while (*p && *p != '"' && *p != '\n' && i < out_len - 1) {
            out[i++] = *p++;
        }
        out[i] = '\0';
        if (*p == '"') p++;
        return p;
    }

    int i = 0;
    while (*p && *p != ' ' && *p != '\t' && *p != '\r' && *p != '\n'
           && i < out_len - 1) {
        out[i++] = *p++;
    }
    out[i] = '\0';
    return p;
}

/* ================================================================== */
/*  Parse a single .scr file                                           */
/* ================================================================== */

static void parse_scr_file(const char *filepath)
{
    void *buf = nullptr;
    long  len = Godot_VFS_ReadFile(filepath, &buf);
    if (len <= 0 || !buf) return;

    /* Ensure null-terminated */
    char *text = (char *)malloc((size_t)len + 1);
    if (!text) {
        Godot_VFS_FreeFile(buf);
        return;
    }
    memcpy(text, buf, (size_t)len);
    text[len] = '\0';
    Godot_VFS_FreeFile(buf);

    const char *p = text;
    char token[512];
    char alias_name[512];
    char sound_path[512];

    while (*p) {
        /* Skip blank lines and comments */
        p = skip_whitespace(p);
        if (!*p) break;
        if (*p == '\n') { p++; continue; }
        if (*p == '/' && *(p + 1) == '/') {
            while (*p && *p != '\n') p++;
            if (*p == '\n') p++;
            continue;
        }

        /* Read command token */
        const char *next = parse_token(p, token, sizeof(token));
        if (!next) { /* skip to next line */
            while (*p && *p != '\n') p++;
            if (*p == '\n') p++;
            continue;
        }
        p = next;

        /* We only care about "alias" and "aliascache" commands */
        bool is_alias = (strcasecmp(token, "alias") == 0 ||
                         strcasecmp(token, "aliascache") == 0);
        if (!is_alias) {
            /* Skip the rest of the line */
            while (*p && *p != '\n') p++;
            if (*p == '\n') p++;
            continue;
        }

        /* Parse alias name */
        next = parse_token(p, alias_name, sizeof(alias_name));
        if (!next) {
            while (*p && *p != '\n') p++;
            if (*p == '\n') p++;
            continue;
        }
        p = next;

        /* Parse sound file path */
        next = parse_token(p, sound_path, sizeof(sound_path));
        if (!next) {
            while (*p && *p != '\n') p++;
            if (*p == '\n') p++;
            continue;
        }
        p = next;

        /* Build the entry with defaults */
        UbersoundEntry entry;
        entry.path    = sound_path;
        entry.volume  = 0.0f;
        entry.minDist = 0.0f;
        entry.maxDist = 0.0f;
        entry.pitch   = 0.0f;
        entry.channel = -1;
        entry.subtitle = false;

        /* Parse optional parameters on the same line */
        while (*p && *p != '\n') {
            next = parse_token(p, token, sizeof(token));
            if (!next) break;
            p = next;

            if (strcasecmp(token, "soundparms") == 0) {
                /* soundparms <vol> <minDist> <maxDist> <pitch> [channel] */
                char val[64];
                next = parse_token(p, val, sizeof(val));
                if (next) { entry.volume  = (float)atof(val); p = next; }
                next = parse_token(p, val, sizeof(val));
                if (next) { entry.minDist = (float)atof(val); p = next; }
                next = parse_token(p, val, sizeof(val));
                if (next) { entry.maxDist = (float)atof(val); p = next; }
                next = parse_token(p, val, sizeof(val));
                if (next) { entry.pitch   = (float)atof(val); p = next; }
                next = parse_token(p, val, sizeof(val));
                if (next) { entry.channel = atoi(val); p = next; }
            } else if (strcasecmp(token, "volume") == 0) {
                char val[64];
                next = parse_token(p, val, sizeof(val));
                if (next) { entry.volume = (float)atof(val); p = next; }
            } else if (strcasecmp(token, "mindist") == 0 ||
                       strcasecmp(token, "dist") == 0) {
                char val[64];
                next = parse_token(p, val, sizeof(val));
                if (next) { entry.minDist = (float)atof(val); p = next; }
            } else if (strcasecmp(token, "maxdist") == 0) {
                char val[64];
                next = parse_token(p, val, sizeof(val));
                if (next) { entry.maxDist = (float)atof(val); p = next; }
            } else if (strcasecmp(token, "pitch") == 0) {
                char val[64];
                next = parse_token(p, val, sizeof(val));
                if (next) { entry.pitch = (float)atof(val); p = next; }
            } else if (strcasecmp(token, "channel") == 0) {
                char val[64];
                next = parse_token(p, val, sizeof(val));
                if (next) { entry.channel = atoi(val); p = next; }
            } else if (strcasecmp(token, "subtitle") == 0 ||
                       strcasecmp(token, "dialog") == 0) {
                entry.subtitle = true;
            }
            /* Skip other unknown tokens silently */
        }
        if (*p == '\n') p++;

        /* Insert into the alias map */
        std::string key(alias_name);
        auto it = s_aliases.find(key);
        if (it == s_aliases.end()) {
            UbersoundAlias alias;
            alias.name = key;
            alias.entries.push_back(entry);
            s_aliases[key] = std::move(alias);
        } else {
            it->second.entries.push_back(entry);
        }
    }

    free(text);
}

/* ================================================================== */
/*  Public API                                                         */
/* ================================================================== */

extern "C" void Godot_Ubersound_Init(void)
{
    if (s_loaded) return;

    s_aliases.clear();
    s_random_seed = 42;

    /* Scan the ubersound/ directory for .scr files */
    int file_count = 0;
    char **files = Godot_VFS_ListFiles("ubersound", ".scr", &file_count);
    if (files && file_count > 0) {
        for (int i = 0; i < file_count; i++) {
            if (!files[i] || !files[i][0]) continue;

            char fullpath[512];
            snprintf(fullpath, sizeof(fullpath), "ubersound/%s", files[i]);
            parse_scr_file(fullpath);
        }
        Godot_VFS_FreeFileList(files);
    }

    /* Also try the standard ubersound.scr and uberdialog.scr in sound/ */
    parse_scr_file("sound/ubersound.scr");
    parse_scr_file("sound/uberdialog.scr");

    s_loaded = true;
}

extern "C" void Godot_Ubersound_Shutdown(void)
{
    s_aliases.clear();
    s_loaded = false;
}

extern "C" int Godot_Ubersound_Resolve(const char *alias,
                                       char *out_path, int out_len,
                                       float *out_volume,
                                       float *out_mindist,
                                       float *out_maxdist,
                                       float *out_pitch,
                                       int   *out_channel)
{
    if (!alias || !alias[0]) return 0;
    if (!s_loaded) return 0;

    auto it = s_aliases.find(std::string(alias));
    if (it == s_aliases.end()) return 0;

    const UbersoundAlias &a = it->second;
    if (a.entries.empty()) return 0;

    /* Pick a random entry from the group */
    size_t idx = 0;
    if (a.entries.size() > 1) {
        idx = ubersound_rand() % a.entries.size();
    }
    const UbersoundEntry &e = a.entries[idx];

    if (out_path && out_len > 0) {
        strncpy(out_path, e.path.c_str(), (size_t)(out_len - 1));
        out_path[out_len - 1] = '\0';
    }
    if (out_volume)  *out_volume  = e.volume;
    if (out_mindist) *out_mindist = e.minDist;
    if (out_maxdist) *out_maxdist = e.maxDist;
    if (out_pitch)   *out_pitch   = e.pitch;
    if (out_channel) *out_channel = e.channel;

    return 1;
}

extern "C" int Godot_Ubersound_GetAliasCount(void)
{
    return (int)s_aliases.size();
}

extern "C" int Godot_Ubersound_IsLoaded(void)
{
    return s_loaded ? 1 : 0;
}

extern "C" int Godot_Ubersound_HasAlias(const char *alias)
{
    if (!alias || !alias[0] || !s_loaded) return 0;
    return (s_aliases.find(std::string(alias)) != s_aliases.end()) ? 1 : 0;
}
