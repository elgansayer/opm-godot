/* godot_shader_props.cpp — MOHAA .shader file parser
 *
 * Scans ALL .shader files in scripts/ via FS_ListFiles (mirroring the real
 * engine's ScanAndLoadShaderFiles) and extracts shader properties into
 * GodotShaderProps structs for Godot-side material creation.
 *
 * This parser uses the engine's own COM_ParseExt() tokeniser (from
 * code/qcommon/q_shared.c) to guarantee identical parsing behaviour with
 * the real renderer's tr_shader.c.  The control flow mirrors ParseShader()
 * and ParseStage() exactly, writing into our lighter-weight structs instead
 * of the renderer's internal shader_t / shaderStage_t.
 *
 * The loading process mirrors ScanAndLoadShaderFiles():
 *   1. FS_ListFiles("scripts", ".shader") to find all shader files
 *   2. Load each file via VFS
 *   3. Concatenate into one large buffer (reverse order, like the engine)
 *   4. COM_Compress() to strip comments and normalise whitespace
 *   5. Walk through with COM_ParseExt() parsing shader definitions
 *
 * Results cached in an unordered_map for O(1) lookup by shader name.
 */

#include "godot_shader_props.h"

#include <cstring>
#include <cctype>
#include <cstdlib>
#include <string>
#include <unordered_map>
#include <vector>

#include <godot_cpp/variant/utility_functions.hpp>

using namespace godot;

/* ===================================================================
 *  Engine function declarations — extern "C" linkage
 *
 *  These are all defined in code/qcommon/q_shared.c and linked into
 *  our monolithic .so.  We declare them here rather than including
 *  engine headers to avoid macro/type conflicts with godot-cpp.
 * ================================================================ */
extern "C" {
    /* VFS accessors (godot_vfs_accessors.c) */
    long Godot_VFS_ReadFile(const char *qpath, void **out_buffer);
    void Godot_VFS_FreeFile(void *buffer);
    char **Godot_VFS_ListFiles(const char *directory, const char *extension, int *out_count);
    void Godot_VFS_FreeFileList(char **list);

    /* Engine tokeniser (q_shared.c) — qboolean is typedef int */
    char *COM_ParseExt(char **data_p, int allowLineBreaks);
    void  SkipRestOfLine(char **data);
    int   COM_Compress(char *data_p);
    int   Q_stricmp(const char *s1, const char *s2);
    int   Q_stricmpn(const char *s1, const char *s2, unsigned long n);
    void  Q_strncpyz(char *dest, const char *src, unsigned long destsize);
}

/* ===================================================================
 *  Internal state
 * ================================================================ */
static std::unordered_map<std::string, GodotShaderProps> s_shader_props;

/* ===================================================================
 *  Classification helpers
 * ================================================================ */

/* Classify blendFunc from src/dst tokens into our transparency enum */
static GodotShaderTransparency classify_blend(const char *src, const char *dst) {
    /* Shorthand forms */
    if (!Q_stricmp(src, "blend"))   return SHADER_ALPHA_BLEND;
    if (!Q_stricmp(src, "add"))     return SHADER_ADDITIVE;
    if (!Q_stricmp(src, "filter"))  return SHADER_MULTIPLICATIVE;

    /* Full GL_* forms */
    if (!Q_stricmp(src, "GL_SRC_ALPHA") && !Q_stricmp(dst, "GL_ONE_MINUS_SRC_ALPHA"))
        return SHADER_ALPHA_BLEND;
    if (!Q_stricmp(src, "GL_ONE") && !Q_stricmp(dst, "GL_ONE"))
        return SHADER_ADDITIVE;
    if (!Q_stricmp(src, "GL_DST_COLOR") && !Q_stricmp(dst, "GL_ZERO"))
        return SHADER_MULTIPLICATIVE;
    if (!Q_stricmp(src, "GL_ONE") && !Q_stricmp(dst, "GL_ZERO"))
        return SHADER_OPAQUE;
    if (!Q_stricmp(src, "GL_ZERO") && !Q_stricmp(dst, "GL_SRC_COLOR"))
        return SHADER_MULTIPLICATIVE;

    /* Anything with GL_SRC_ALPHA as source is alpha-blended */
    if (!Q_stricmp(src, "GL_SRC_ALPHA"))
        return SHADER_ALPHA_BLEND;
    /* GL_ONE as source with non-ONE dest is likely additive */
    if (!Q_stricmp(src, "GL_ONE"))
        return SHADER_ADDITIVE;

    /* Default: treat as alpha blend if we can't classify */
    return SHADER_ALPHA_BLEND;
}

/* Classify transparency from stored per-stage blend factors.
 * Called post-parse to determine overall shader transparency
 * from stage 0's blend function (matching Q3's SortNewShader logic:
 * if stage 0 has no blendFunc → opaque, regardless of later stages). */
static GodotShaderTransparency classify_blend_factors(MohaaBlendFactor src,
                                                       MohaaBlendFactor dst)
{
    if (src == BLEND_SRC_ALPHA && dst == BLEND_ONE_MINUS_SRC_ALPHA)
        return SHADER_ALPHA_BLEND;
    if (src == BLEND_ONE && dst == BLEND_ONE)
        return SHADER_ADDITIVE;
    if (src == BLEND_DST_COLOR && dst == BLEND_ZERO)
        return SHADER_MULTIPLICATIVE;
    if (src == BLEND_ONE && dst == BLEND_ZERO)
        return SHADER_OPAQUE;
    if (src == BLEND_ZERO && dst == BLEND_SRC_COLOR)
        return SHADER_MULTIPLICATIVE;
    if (src == BLEND_SRC_ALPHA)
        return SHADER_ALPHA_BLEND;
    if (src == BLEND_ONE)
        return SHADER_ADDITIVE;
    return SHADER_ALPHA_BLEND;
}

/* Parse a GL blend factor token into MohaaBlendFactor enum */
static MohaaBlendFactor parse_blend_factor(const char *tok) {
    if (!Q_stricmp(tok, "GL_ONE"))                    return BLEND_ONE;
    if (!Q_stricmp(tok, "GL_ZERO"))                   return BLEND_ZERO;
    if (!Q_stricmp(tok, "GL_SRC_ALPHA"))              return BLEND_SRC_ALPHA;
    if (!Q_stricmp(tok, "GL_ONE_MINUS_SRC_ALPHA"))    return BLEND_ONE_MINUS_SRC_ALPHA;
    if (!Q_stricmp(tok, "GL_DST_COLOR"))              return BLEND_DST_COLOR;
    if (!Q_stricmp(tok, "GL_SRC_COLOR"))              return BLEND_SRC_COLOR;
    if (!Q_stricmp(tok, "GL_ONE_MINUS_DST_COLOR"))    return BLEND_ONE_MINUS_DST_COLOR;
    if (!Q_stricmp(tok, "GL_ONE_MINUS_SRC_COLOR"))    return BLEND_ONE_MINUS_SRC_COLOR;
    if (!Q_stricmp(tok, "GL_DST_ALPHA"))              return BLEND_DST_ALPHA;
    if (!Q_stricmp(tok, "GL_ONE_MINUS_DST_ALPHA"))    return BLEND_ONE_MINUS_DST_ALPHA;
    return BLEND_ONE;
}

/* Parse a wave function name into MohaaWaveFunc enum */
static MohaaWaveFunc parse_wave_func(const char *tok) {
    if (!Q_stricmp(tok, "sin"))                return WAVE_SIN;
    if (!Q_stricmp(tok, "triangle"))           return WAVE_TRIANGLE;
    if (!Q_stricmp(tok, "square"))             return WAVE_SQUARE;
    if (!Q_stricmp(tok, "sawtooth"))           return WAVE_SAWTOOTH;
    if (!Q_stricmp(tok, "inversesawtooth"))    return WAVE_INVERSE_SAWTOOTH;
    return WAVE_SIN;
}

/* ===================================================================
 *  parse_stage — mirrors renderergl1/tr_shader.c::ParseStage()
 *
 *  Called after the opening '{' of a stage block has been consumed.
 *  Reads tokens until the matching '}' is found.
 * ================================================================ */
static void parse_stage(char **text, GodotShaderProps *props, int stage_index,
                         bool first_stage)
{
    char *token;
    int cntBundle = 0;  /* Tracks which texture bundle we're in (mirrors tr_shader.c).
                         * Bundle 0 = primary (diffuse) texture.
                         * Bundle 1+ = secondary (usually $lightmap) via nextBundle.
                         * stg->map always holds the bundle-0 texture path. */

    MohaaShaderStage *stg = nullptr;
    if (stage_index >= 0 && stage_index < MOHAA_SHADER_STAGE_MAX) {
        stg = &props->stages[stage_index];
        memset(stg, 0, sizeof(MohaaShaderStage));
        stg->blendSrc = BLEND_ONE;
        stg->blendDst = BLEND_ZERO;
        stg->alphaConst = 1.0f;
        stg->rgbConst[0] = 1.0f;
        stg->rgbConst[1] = 1.0f;
        stg->rgbConst[2] = 1.0f;
        props->stage_count = stage_index + 1;
        props->num_stages = props->stage_count;
    }

    while (1) {
        token = COM_ParseExt(text, 1 /* qtrue */);
        if (!token[0]) {
            break;
        }
        if (token[0] == '}') {
            break;
        }

        /* ── nextBundle — MOHAA multi-texture pass separator ──
         * Mirrors tr_shader.c:1675.  Increments the texture bundle index.
         * After nextBundle, subsequent "map" directives apply to the next
         * texture unit (typically the lightmap).  We must NOT overwrite
         * stg->map (which holds the bundle-0 diffuse texture path). */
        if (!Q_stricmp(token, "nextBundle") || !Q_stricmp(token, "nextbundle"))
        {
            /* Optional parameter: "add" for GL_ADD multitexture env,
             * otherwise GL_MODULATE (mirrors engine). */
            token = COM_ParseExt(text, 0 /* qfalse — same line only */);
            /* token may be "add" or empty — we don't need the value. */
            cntBundle++;
            continue;
        }

        /* ── map <name> ── */
        /* Mirrors ParseStage's handling of "map", "clampmap", "clampmapx", "clampmapy" */
        if (!Q_stricmp(token, "map") || !Q_stricmpn(token, "clampmap", 8))
        {
            bool is_clamp = Q_stricmp(token, "map") != 0;
            token = COM_ParseExt(text, 0 /* qfalse */);
            if (stg) {
                if (cntBundle == 0) {
                    /* Bundle 0: primary (diffuse) texture */
                    Q_strncpyz(stg->map, token, sizeof(stg->map));
                    if (is_clamp)
                        stg->isClampMap = true;
                    if (!Q_stricmp(token, "$lightmap"))
                        stg->isLightmap = true;
                } else {
                    /* Bundle 1+: secondary texture (usually lightmap).
                     * Don't overwrite stg->map — keep the diffuse path.
                     * If this bundle is $lightmap, the stage is a combined
                     * diffuse+lightmap multi-texture pass, NOT a pure
                     * lightmap stage (isLightmap stays false).
                     * Record the fact for post-parse transparency analysis
                     * so blendFunc filter in this stage is recognised as
                     * lightmap modulation rather than transparent overlay. */
                    if (!Q_stricmp(token, "$lightmap"))
                        stg->hasNextBundleLightmap = true;
                }
            }
        }
        /* ── alphaFunc <func> ── */
        else if (!Q_stricmp(token, "alphaFunc"))
        {
            token = COM_ParseExt(text, 0);
            props->transparency = SHADER_ALPHA_TEST;
            float thresh = 0.5f;
            if (!Q_stricmp(token, "GT0"))
                thresh = 0.01f;
            props->alpha_threshold = thresh;
            if (stg) {
                stg->hasAlphaFunc = true;
                stg->alphaFuncThreshold = thresh;
            }
        }
        /* ── blendFunc <srcFactor> <dstFactor> | blend | add | filter | alphaadd ── */
        /* Per-stage blend data is recorded here; overall shader transparency
         * is determined post-parse from stage 0's blend (matching Q3's
         * SortNewShader: if stage 0 has no blendFunc → opaque). */
        else if (!Q_stricmp(token, "blendfunc") || !Q_stricmp(token, "blendFunc"))
        {
            token = COM_ParseExt(text, 0);
            if (!Q_stricmp(token, "blend") || !Q_stricmp(token, "add") ||
                !Q_stricmp(token, "filter") || !Q_stricmp(token, "alphaadd"))
            {
                /* Shorthand form — record per-stage blend factors */
                if (stg) {
                    stg->hasBlendFunc = true;
                    if (!Q_stricmp(token, "blend")) {
                        stg->blendSrc = BLEND_SRC_ALPHA;
                        stg->blendDst = BLEND_ONE_MINUS_SRC_ALPHA;
                    } else if (!Q_stricmp(token, "add")) {
                        stg->blendSrc = BLEND_ONE;
                        stg->blendDst = BLEND_ONE;
                    } else if (!Q_stricmp(token, "filter")) {
                        stg->blendSrc = BLEND_DST_COLOR;
                        stg->blendDst = BLEND_ZERO;
                    } else if (!Q_stricmp(token, "alphaadd")) {
                        stg->blendSrc = BLEND_SRC_ALPHA;
                        stg->blendDst = BLEND_ONE;
                    }
                }
            }
            else
            {
                /* Full form: blendFunc GL_SRC GL_DST */
                char src_tok[64];
                Q_strncpyz(src_tok, token, sizeof(src_tok));
                token = COM_ParseExt(text, 0);
                if (stg) {
                    stg->hasBlendFunc = true;
                    stg->blendSrc = parse_blend_factor(src_tok);
                    stg->blendDst = parse_blend_factor(token);
                }
            }
        }
        /* ── animMap / animMapOnce / animMapPhase <freq> [phase] <tex1> ... <texN> ── */
        /* Mirrors ParseStage's animMap handling */
        else if (!Q_stricmp(token, "animMap") || !Q_stricmp(token, "animMapOnce") ||
                 !Q_stricmp(token, "animMapPhase"))
        {
            bool phased = !Q_stricmp(token, "animMapPhase");

            token = COM_ParseExt(text, 0);
            float freq = (float)atof(token);

            if (phased) {
                token = COM_ParseExt(text, 0);
                /* phase value — not stored in our struct yet */
            }

            if (first_stage) {
                props->animmap_freq = freq;
                props->has_animmap = true;
                props->animmap_num_frames = 0;
            }

            int frame_count = 0;
            while (1) {
                token = COM_ParseExt(text, 0);
                if (!token[0])
                    break;
                if (first_stage && frame_count < 8) {
                    Q_strncpyz(props->animmap_frames[frame_count], token, 64);
                    props->animmap_num_frames = frame_count + 1;
                }
                if (stg && frame_count < MOHAA_SHADER_STAGE_MAX_ANIM_FRAMES) {
                    Q_strncpyz(stg->animMapFrames[frame_count], token, 64);
                }
                frame_count++;
            }
            if (stg) {
                stg->animMapFreq = freq;
                stg->animMapFrameCount = (frame_count < MOHAA_SHADER_STAGE_MAX_ANIM_FRAMES)
                                         ? frame_count : MOHAA_SHADER_STAGE_MAX_ANIM_FRAMES;
            }
        }
        /* ── tcGen <type> ── */
        /* In the engine, tcGen is per-bundle (stage->bundle[cntBundle].tcGen).
         * Only record it for bundle 0 — the primary texture unit.
         * We still consume parameters for all bundles to keep the parser
         * position correct. */
        else if (!Q_stricmp(token, "tcGen") || !Q_stricmp(token, "tcgen"))
        {
            token = COM_ParseExt(text, 0);
            if (!Q_stricmp(token, "environment") || !Q_stricmp(token, "environmentmodel"))
            {
                if (cntBundle == 0) {
                    if (first_stage) props->tcgen_environment = true;
                    if (stg) stg->tcGen = STAGE_TCGEN_ENVIRONMENT;
                }
            }
            else if (!Q_stricmp(token, "lightmap"))
            {
                if (cntBundle == 0 && stg) {
                    stg->tcGen = STAGE_TCGEN_LIGHTMAP;
                    stg->isLightmap = true;
                }
            }
            else if (!Q_stricmp(token, "vector"))
            {
                /* ( sx sy sz ) ( tx ty tz ) — always consume parameters */
                token = COM_ParseExt(text, 0);
                if (token[0] == '(') token = COM_ParseExt(text, 0);
                float sx = (float)atof(token);
                token = COM_ParseExt(text, 0);
                float sy = (float)atof(token);
                token = COM_ParseExt(text, 0);
                float sz = (float)atof(token);
                token = COM_ParseExt(text, 0);
                if (token[0] == ')') token = COM_ParseExt(text, 0);
                if (token[0] == '(') token = COM_ParseExt(text, 0);
                float tx = (float)atof(token);
                token = COM_ParseExt(text, 0);
                float ty = (float)atof(token);
                token = COM_ParseExt(text, 0);
                float tz = (float)atof(token);
                token = COM_ParseExt(text, 0);
                /* skip closing ) if present */

                if (cntBundle == 0 && stg) {
                    stg->tcGen = STAGE_TCGEN_VECTOR;
                    stg->tcGenVecS[0] = sx; stg->tcGenVecS[1] = sy; stg->tcGenVecS[2] = sz;
                    stg->tcGenVecT[0] = tx; stg->tcGenVecT[1] = ty; stg->tcGenVecT[2] = tz;
                }
            }
        }
        /* ── rgbGen <type> ── */
        else if (!Q_stricmp(token, "rgbGen") || !Q_stricmp(token, "rgbgen"))
        {
            token = COM_ParseExt(text, 0);
            if (!Q_stricmp(token, "identity"))
            {
                if (first_stage) props->rgbgen_type = 0;
                if (stg) stg->rgbGen = STAGE_RGBGEN_IDENTITY;
            }
            else if (!Q_stricmp(token, "identityLighting"))
            {
                if (first_stage) props->rgbgen_type = 0;
                if (stg) stg->rgbGen = STAGE_RGBGEN_IDENTITY_LIGHTING;
            }
            else if (!Q_stricmp(token, "vertex") || !Q_stricmp(token, "exactVertex"))
            {
                if (first_stage) props->rgbgen_type = 1;
                if (stg) stg->rgbGen = STAGE_RGBGEN_VERTEX;
            }
            else if (!Q_stricmp(token, "lightingDiffuse"))
            {
                if (first_stage) props->rgbgen_type = 1;
                if (stg) stg->rgbGen = STAGE_RGBGEN_LIGHTING_DIFFUSE;
            }
            else if (!Q_stricmp(token, "wave"))
            {
                char func_tok[64];
                token = COM_ParseExt(text, 0);
                Q_strncpyz(func_tok, token, sizeof(func_tok));
                token = COM_ParseExt(text, 0);
                float base = (float)atof(token);
                token = COM_ParseExt(text, 0);
                float amp = (float)atof(token);
                token = COM_ParseExt(text, 0);
                float phase = (float)atof(token);
                token = COM_ParseExt(text, 0);
                float freq = (float)atof(token);
                if (first_stage) {
                    props->rgbgen_type = 2;
                    props->rgbgen_wave_base  = base;
                    props->rgbgen_wave_amp   = amp;
                    props->rgbgen_wave_phase = phase;
                    props->rgbgen_wave_freq  = freq;
                }
                if (stg) {
                    stg->rgbGen = STAGE_RGBGEN_WAVE;
                    stg->rgbWave.func      = parse_wave_func(func_tok);
                    stg->rgbWave.base      = base;
                    stg->rgbWave.amplitude = amp;
                    stg->rgbWave.phase     = phase;
                    stg->rgbWave.frequency = freq;
                }
            }
            else if (!Q_stricmp(token, "entity"))
            {
                if (first_stage) props->rgbgen_type = 3;
                if (stg) stg->rgbGen = STAGE_RGBGEN_ENTITY;
            }
            else if (!Q_stricmp(token, "oneMinusEntity"))
            {
                if (first_stage) props->rgbgen_type = 3;
                if (stg) stg->rgbGen = STAGE_RGBGEN_ONE_MINUS_ENTITY;
            }
            else if (!Q_stricmp(token, "const") || !Q_stricmp(token, "constant"))
            {
                /* const ( r g b ) */
                token = COM_ParseExt(text, 0);
                if (token[0] == '(') token = COM_ParseExt(text, 0);
                float r = (float)atof(token);
                token = COM_ParseExt(text, 0);
                float g = (float)atof(token);
                token = COM_ParseExt(text, 0);
                float b = (float)atof(token);
                token = COM_ParseExt(text, 0);
                /* skip closing ) if present */
                if (first_stage) {
                    props->rgbgen_type = 4;
                    props->rgbgen_const[0] = r;
                    props->rgbgen_const[1] = g;
                    props->rgbgen_const[2] = b;
                }
                if (stg) {
                    stg->rgbGen = STAGE_RGBGEN_CONST;
                    stg->rgbConst[0] = r;
                    stg->rgbConst[1] = g;
                    stg->rgbConst[2] = b;
                }
            }
        }
        /* ── alphaGen <type> ── */
        else if (!Q_stricmp(token, "alphaGen") || !Q_stricmp(token, "alphagen"))
        {
            token = COM_ParseExt(text, 0);
            if (!Q_stricmp(token, "identity"))
            {
                if (first_stage) props->alphagen_type = 0;
                if (stg) stg->alphaGen = STAGE_ALPHAGEN_IDENTITY;
            }
            else if (!Q_stricmp(token, "vertex"))
            {
                if (first_stage) props->alphagen_type = 1;
                if (stg) stg->alphaGen = STAGE_ALPHAGEN_VERTEX;
            }
            else if (!Q_stricmp(token, "wave"))
            {
                char func_tok[64];
                token = COM_ParseExt(text, 0);
                Q_strncpyz(func_tok, token, sizeof(func_tok));
                token = COM_ParseExt(text, 0);
                float base = (float)atof(token);
                token = COM_ParseExt(text, 0);
                float amp = (float)atof(token);
                token = COM_ParseExt(text, 0);
                float phase = (float)atof(token);
                token = COM_ParseExt(text, 0);
                float freq = (float)atof(token);
                if (first_stage) {
                    props->alphagen_type = 2;
                    props->alphagen_wave_base  = base;
                    props->alphagen_wave_amp   = amp;
                    props->alphagen_wave_phase = phase;
                    props->alphagen_wave_freq  = freq;
                }
                if (stg) {
                    stg->alphaGen = STAGE_ALPHAGEN_WAVE;
                    stg->alphaWave.func      = parse_wave_func(func_tok);
                    stg->alphaWave.base      = base;
                    stg->alphaWave.amplitude = amp;
                    stg->alphaWave.phase     = phase;
                    stg->alphaWave.frequency = freq;
                }
            }
            else if (!Q_stricmp(token, "entity"))
            {
                if (first_stage) props->alphagen_type = 3;
                if (stg) stg->alphaGen = STAGE_ALPHAGEN_ENTITY;
            }
            else if (!Q_stricmp(token, "oneMinusEntity"))
            {
                if (first_stage) props->alphagen_type = 3;
                if (stg) stg->alphaGen = STAGE_ALPHAGEN_ONE_MINUS_ENTITY;
            }
            else if (!Q_stricmp(token, "portal"))
            {
                token = COM_ParseExt(text, 0);
                if (stg) {
                    stg->alphaGen = STAGE_ALPHAGEN_PORTAL;
                    stg->alphaPortalDist = (float)atof(token);
                }
            }
            else if (!Q_stricmp(token, "const") || !Q_stricmp(token, "constant"))
            {
                token = COM_ParseExt(text, 0);
                if (first_stage) {
                    props->alphagen_type = 4;
                    props->alphagen_const = (float)atof(token);
                }
                if (stg) {
                    stg->alphaGen = STAGE_ALPHAGEN_CONST;
                    stg->alphaConst = (float)atof(token);
                }
            }
        }
        /* ── tcMod <type> ── */
        else if (!Q_stricmp(token, "tcMod") || !Q_stricmp(token, "tcmod"))
        {
            token = COM_ParseExt(text, 0);
            if (!Q_stricmp(token, "scroll"))
            {
                token = COM_ParseExt(text, 0);
                float s = (float)atof(token);
                token = COM_ParseExt(text, 0);
                float t = (float)atof(token);
                if (first_stage) {
                    props->tcmod_scroll_s = s;
                    props->tcmod_scroll_t = t;
                    props->has_tcmod = true;
                }
                if (stg && stg->tcModCount < MOHAA_SHADER_STAGE_MAX_TCMODS) {
                    MohaaStageTcMod *tm = &stg->tcMods[stg->tcModCount++];
                    tm->type = TCMOD_SCROLL;
                    tm->params[0] = s;
                    tm->params[1] = t;
                }
            }
            else if (!Q_stricmp(token, "rotate"))
            {
                token = COM_ParseExt(text, 0);
                float r = (float)atof(token);
                if (first_stage) {
                    props->tcmod_rotate = r;
                    props->has_tcmod = true;
                }
                if (stg && stg->tcModCount < MOHAA_SHADER_STAGE_MAX_TCMODS) {
                    MohaaStageTcMod *tm = &stg->tcMods[stg->tcModCount++];
                    tm->type = TCMOD_ROTATE;
                    tm->params[0] = r;
                }
            }
            else if (!Q_stricmp(token, "scale"))
            {
                token = COM_ParseExt(text, 0);
                float s = (float)atof(token);
                token = COM_ParseExt(text, 0);
                float t = (float)atof(token);
                if (first_stage) {
                    props->tcmod_scale_s = s;
                    props->tcmod_scale_t = t;
                    props->has_tcmod = true;
                }
                if (stg && stg->tcModCount < MOHAA_SHADER_STAGE_MAX_TCMODS) {
                    MohaaStageTcMod *tm = &stg->tcMods[stg->tcModCount++];
                    tm->type = TCMOD_SCALE;
                    tm->params[0] = s;
                    tm->params[1] = t;
                }
            }
            else if (!Q_stricmp(token, "turb"))
            {
                token = COM_ParseExt(text, 0);
                float base = (float)atof(token);
                token = COM_ParseExt(text, 0);
                float amp = (float)atof(token);
                token = COM_ParseExt(text, 0);
                float phase = (float)atof(token);
                token = COM_ParseExt(text, 0);
                float freq = (float)atof(token);
                if (first_stage) {
                    props->tcmod_turb_amp  = amp;
                    props->tcmod_turb_freq = freq;
                    props->has_tcmod = true;
                }
                if (stg && stg->tcModCount < MOHAA_SHADER_STAGE_MAX_TCMODS) {
                    MohaaStageTcMod *tm = &stg->tcMods[stg->tcModCount++];
                    tm->type = TCMOD_TURB;
                    tm->params[0] = base;
                    tm->params[1] = amp;
                    tm->params[2] = phase;
                    tm->params[3] = freq;
                }
            }
            else if (!Q_stricmp(token, "stretch"))
            {
                char func_tok[64];
                token = COM_ParseExt(text, 0);
                Q_strncpyz(func_tok, token, sizeof(func_tok));
                token = COM_ParseExt(text, 0);
                float base = (float)atof(token);
                token = COM_ParseExt(text, 0);
                float amp = (float)atof(token);
                token = COM_ParseExt(text, 0);
                float phase = (float)atof(token);
                token = COM_ParseExt(text, 0);
                float freq = (float)atof(token);
                if (first_stage) {
                    props->has_tcmod_stretch = true;
                    props->tcmod_stretch_base  = base;
                    props->tcmod_stretch_amp   = amp;
                    props->tcmod_stretch_phase = phase;
                    props->tcmod_stretch_freq  = freq;
                    props->has_tcmod = true;
                }
                if (stg && stg->tcModCount < MOHAA_SHADER_STAGE_MAX_TCMODS) {
                    MohaaStageTcMod *tm = &stg->tcMods[stg->tcModCount++];
                    tm->type = TCMOD_STRETCH;
                    tm->wave.func      = parse_wave_func(func_tok);
                    tm->wave.base      = base;
                    tm->wave.amplitude = amp;
                    tm->wave.phase     = phase;
                    tm->wave.frequency = freq;
                }
            }
            else
            {
                /* Unknown tcMod variant — skip remaining parameters */
                SkipRestOfLine(text);
            }
        }
        /* ── Unknown stage directive — skip remaining parameters on this line ── */
        else
        {
            SkipRestOfLine(text);
        }
    }
}

/* ===================================================================
 *  parse_shader — mirrors renderergl1/tr_shader.c::ParseShader()
 *
 *  Called after the opening '{' of a shader definition has been consumed.
 *  Reads outer directives and stage blocks until the matching '}' is found.
 * ================================================================ */
static void parse_shader(char **text, GodotShaderProps *props)
{
    char *token;
    int stage_idx = 0;
    bool first_stage = true;

    while (1) {
        token = COM_ParseExt(text, 1 /* qtrue — cross line boundaries */);
        if (!token[0]) {
            break;
        }

        /* End of shader definition */
        if (token[0] == '}') {
            break;
        }

        /* Stage definition — opening brace */
        if (token[0] == '{') {
            parse_stage(text, props, stage_idx, first_stage);
            if (stage_idx == 0) first_stage = false;
            stage_idx++;
            continue;
        }

        /* ── Outer directives ── */

        /* Skip qer_ prefixed editor-only directives (mirrors ParseShader) */
        if (!Q_stricmpn(token, "qer", 3)) {
            SkipRestOfLine(text);
            continue;
        }
        /* Skip q3map_ prefixed compile-only directives (mirrors ParseShader) */
        if (!Q_stricmpn(token, "q3map", 5)) {
            SkipRestOfLine(text);
            continue;
        }

        if (!Q_stricmp(token, "surfaceParm") || !Q_stricmp(token, "surfaceparm"))
        {
            token = COM_ParseExt(text, 0);
            if (!Q_stricmp(token, "trans")) {
                /* surfaceParm trans is a BSP compiler flag (vis portals)
                 * with NO effect on runtime rendering transparency.
                 * Transparency is determined solely by stage blendFunc,
                 * matching R_FindShader / SortNewShader in the real
                 * renderer.  Do NOT set transparency here. */
                props->has_surfaceparm_trans = true;
            } else if (!Q_stricmp(token, "portal")) {
                props->is_portal = true;
            } else if (!Q_stricmp(token, "sky")) {
                props->is_sky = true;
            } else if (!Q_stricmp(token, "nolightmap")) {
                props->no_lightmap = true;
            }
        }
        else if (!Q_stricmp(token, "cull"))
        {
            token = COM_ParseExt(text, 0);
            if (!Q_stricmp(token, "none") || !Q_stricmp(token, "twosided") ||
                !Q_stricmp(token, "disable")) {
                props->cull = SHADER_CULL_NONE;
            } else if (!Q_stricmp(token, "front")) {
                props->cull = SHADER_CULL_FRONT;
            } else if (!Q_stricmp(token, "back") || !Q_stricmp(token, "backside") ||
                       !Q_stricmp(token, "backsided")) {
                props->cull = SHADER_CULL_BACK;
            } else {
                props->cull = SHADER_CULL_BACK;
            }
        }
        else if (!Q_stricmp(token, "skyParms") || !Q_stricmp(token, "skyparms"))
        {
            /* skyParms <envBasename> <cloudHeight> <innerBox> */
            token = COM_ParseExt(text, 0);
            if (token[0] && Q_stricmp(token, "-")) {
                Q_strncpyz(props->sky_env, token, sizeof(props->sky_env));
            }
            props->is_sky = true;
            SkipRestOfLine(text);
        }
        else if (!Q_stricmp(token, "deformVertexes") || !Q_stricmp(token, "deformvertexes"))
        {
            token = COM_ParseExt(text, 0);
            props->has_deform = true;
            if (!Q_stricmp(token, "wave"))
            {
                props->deform_type = 0;
                token = COM_ParseExt(text, 0);
                props->deform_div = (float)atof(token);
                COM_ParseExt(text, 0); /* wave func name — not stored */
                token = COM_ParseExt(text, 0);
                props->deform_base = (float)atof(token);
                token = COM_ParseExt(text, 0);
                props->deform_amplitude = (float)atof(token);
                token = COM_ParseExt(text, 0);
                props->deform_phase = (float)atof(token);
                token = COM_ParseExt(text, 0);
                props->deform_frequency = (float)atof(token);
            }
            else if (!Q_stricmp(token, "bulge"))
            {
                props->deform_type = 1;
                token = COM_ParseExt(text, 0);
                props->deform_base = (float)atof(token);
                token = COM_ParseExt(text, 0);
                props->deform_amplitude = (float)atof(token);
                token = COM_ParseExt(text, 0);
                props->deform_frequency = (float)atof(token);
            }
            else if (!Q_stricmp(token, "move"))
            {
                props->deform_type = 2;
                COM_ParseExt(text, 0); /* x */
                COM_ParseExt(text, 0); /* y */
                COM_ParseExt(text, 0); /* z */
                COM_ParseExt(text, 0); /* wave func */
                token = COM_ParseExt(text, 0);
                props->deform_base = (float)atof(token);
                token = COM_ParseExt(text, 0);
                props->deform_amplitude = (float)atof(token);
                token = COM_ParseExt(text, 0);
                props->deform_phase = (float)atof(token);
                token = COM_ParseExt(text, 0);
                props->deform_frequency = (float)atof(token);
            }
            else if (!Q_stricmp(token, "autosprite"))
            {
                props->deform_type = 3;
            }
            else if (!Q_stricmp(token, "autosprite2"))
            {
                props->deform_type = 4;
            }
            else
            {
                SkipRestOfLine(text);
            }
        }
        else if (!Q_stricmp(token, "sort"))
        {
            token = COM_ParseExt(text, 0);
            if (!Q_stricmp(token, "portal"))          props->sort_key = 1;
            else if (!Q_stricmp(token, "sky"))        props->sort_key = 2;
            else if (!Q_stricmp(token, "opaque"))     props->sort_key = 3;
            else if (!Q_stricmp(token, "banner"))     props->sort_key = 6;
            else if (!Q_stricmp(token, "underwater")) props->sort_key = 8;
            else if (!Q_stricmp(token, "additive"))   props->sort_key = 9;
            else if (!Q_stricmp(token, "nearest"))    props->sort_key = 16;
            else props->sort_key = atoi(token);
        }
        else if (!Q_stricmp(token, "nomipmaps"))
        {
            props->no_mipmaps = true;
        }
        else if (!Q_stricmp(token, "nopicmip"))
        {
            props->no_picmip = true;
        }
        else if (!Q_stricmp(token, "fogParms") || !Q_stricmp(token, "fogparms"))
        {
            /* fogParms ( <r> <g> <b> ) <distance>
             * Note: COM_ParseExt does NOT treat ( ) as single-char tokens
             * like { }, so they appear as part of the next token.  Use the
             * engine's pattern: try to parse a vector. */
            token = COM_ParseExt(text, 0);
            if (token[0] == '(') token = COM_ParseExt(text, 0);
            float r = (float)atof(token);
            token = COM_ParseExt(text, 0);
            float g = (float)atof(token);
            token = COM_ParseExt(text, 0);
            float b = (float)atof(token);
            token = COM_ParseExt(text, 0);
            if (token[0] == ')') token = COM_ParseExt(text, 0);
            float dist = (float)atof(token);
            props->has_fog = true;
            props->fog_color[0] = r;
            props->fog_color[1] = g;
            props->fog_color[2] = b;
            props->fog_distance = dist;
        }
        /* ── Known directives that we recognise but don't store ── */
        else if (!Q_stricmp(token, "polygonOffset") ||
                 !Q_stricmp(token, "entityMergable") ||
                 !Q_stricmp(token, "noMerge") ||
                 !Q_stricmp(token, "force32bit"))
        {
            /* No parameters to skip */
        }
        else if (!Q_stricmp(token, "portal"))
        {
            props->is_portal = true;
        }
        else if (!Q_stricmp(token, "portalsky"))
        {
            props->is_sky = true;
        }
        else if (!Q_stricmp(token, "spritegen") ||
                 !Q_stricmp(token, "spritescale") ||
                 !Q_stricmp(token, "light") ||
                 !Q_stricmp(token, "tesssize") ||
                 !Q_stricmp(token, "clampTime"))
        {
            SkipRestOfLine(text);
        }
        /* ── MOHAA #if / #else / #endif conditional blocks ── */
        else if (!Q_stricmp(token, "#if") || !Q_stricmp(token, "#if_not"))
        {
            /* For now, treat the condition as false: skip to #else or #endif.
             * This matches the engine's behaviour when the condition evaluates
             * to false (e.g. #if separate_env with r_textureDetails == 0). */
            int nested = 1;
            while (nested > 0) {
                token = COM_ParseExt(text, 1);
                if (!token[0]) break;
                if (!Q_stricmp(token, "#if") || !Q_stricmp(token, "#if_not"))
                    nested++;
                else if (!Q_stricmp(token, "#endif"))
                    nested--;
                else if (!Q_stricmp(token, "#else") && nested == 1) {
                    /* Take the else branch */
                    break;
                }
            }
        }
        else if (!Q_stricmp(token, "#else"))
        {
            /* We were in the true branch — skip to #endif */
            int nested = 1;
            while (nested > 0) {
                token = COM_ParseExt(text, 1);
                if (!token[0]) break;
                if (!Q_stricmp(token, "#if") || !Q_stricmp(token, "#if_not"))
                    nested++;
                else if (!Q_stricmp(token, "#endif"))
                    nested--;
            }
        }
        else if (!Q_stricmp(token, "#endif"))
        {
            /* Nothing to do */
        }
        /* ── Unknown outer directive — skip the rest of the line ── */
        else
        {
            SkipRestOfLine(text);
        }
    }
}

/* ===================================================================
 *  Public API
 * ================================================================ */

void Godot_ShaderProps_Load() {
    s_shader_props.clear();

    /* ── Scan ALL .shader files in scripts/ (mirrors ScanAndLoadShaderFiles) ── */
    int numFiles = 0;
    char **fileList = Godot_VFS_ListFiles("scripts", ".shader", &numFiles);
    if (!fileList || numFiles <= 0) {
        UtilityFunctions::print("[ShaderProps] WARNING: no shader files found");
        return;
    }

    /* ── Load all shader file buffers ── */
    struct ShaderBuf { char *data; long len; };
    std::vector<ShaderBuf> buffers;
    buffers.reserve(numFiles);
    long total_len = 0;

    for (int i = 0; i < numFiles; i++) {
        char path[512];
        snprintf(path, sizeof(path), "scripts/%s", fileList[i]);

        void *raw = nullptr;
        long len = Godot_VFS_ReadFile(path, &raw);
        if (len <= 0 || !raw) continue;

        buffers.push_back({(char *)raw, len});
        total_len += len;
    }

    int files_loaded = (int)buffers.size();

    /* ── Concatenate into one large buffer (mirrors ScanAndLoadShaderFiles) ──
     * The engine concatenates in reverse order so that files loaded later
     * appear earlier in the buffer.  With first-definition-wins, this gives
     * later pk3 files higher priority — matching the engine's behaviour. */
    char *big_buf = (char *)malloc(total_len + files_loaded * 2 + 1);
    if (!big_buf) {
        for (auto &b : buffers) Godot_VFS_FreeFile(b.data);
        Godot_VFS_FreeFileList(fileList);
        return;
    }
    big_buf[0] = '\0';

    for (int i = (int)buffers.size() - 1; i >= 0; i--) {
        strcat(big_buf, "\n");
        strncat(big_buf, buffers[i].data, buffers[i].len);
        Godot_VFS_FreeFile(buffers[i].data);
    }

    Godot_VFS_FreeFileList(fileList);

    /* ── Strip comments and compress whitespace (mirrors engine) ── */
    COM_Compress(big_buf);

    /* ── Parse all shader definitions ──
     * This mirrors FindShadersInShaderText() + the per-shader parse path. */
    char *p = big_buf;
    int total_defs = 0;

    while (1) {
        char *token = COM_ParseExt(&p, 1 /* qtrue */);
        if (!token[0]) break;

        /* token is the shader name.
         * COM_ParseExt returns a pointer to a static buffer — copy it. */
        char shader_name[256];
        Q_strncpyz(shader_name, token, sizeof(shader_name));

        /* Expect opening brace */
        token = COM_ParseExt(&p, 1);
        if (token[0] != '{') {
            /* Malformed shader — skip */
            continue;
        }

        /* Initialise properties with defaults */
        GodotShaderProps props = {};
        props.transparency = SHADER_OPAQUE;
        props.alpha_threshold = 0.5f;
        props.cull = SHADER_CULL_BACK;
        props.is_portal = false;
        props.tcmod_scale_s = 1.0f;
        props.tcmod_scale_t = 1.0f;
        props.alphagen_const = 1.0f;
        props.rgbgen_const[0] = props.rgbgen_const[1] = props.rgbgen_const[2] = 1.0f;

        /* Parse the shader body (reads until matching '}') */
        parse_shader(&p, &props);

        /* ── Post-parse transparency classification ──
         * Match Q3's SortNewShader logic: check the first non-lightmap
         * stage's blendFunc.  If it has no blendFunc (GL_ONE/GL_ZERO),
         * the shader is opaque regardless of later stages.
         *
         * Extended: also skip tcGen environment stages (reflections) to
         * find the actual diffuse stage.  This handles 3-stage glass
         * shaders: env map → alpha-blended window → lightmap.
         *
         * Always run if we have stages — the stage blendFunc analysis
         * is the authoritative source for transparency classification
         * (matching the real renderer's SortNewShader).  alphaFunc
         * is preserved since it's set from stage parsing. */
        if (props.transparency != SHADER_ALPHA_TEST && props.stage_count > 0) {
            /* Detect whether a lightmap stage exists — either as a
             * dedicated $lightmap stage (standard Q3 two-pass) OR as a
             * nextBundle $lightmap within a combined multi-texture stage
             * (MOHAA single-pass pattern). */
            bool has_lightmap_stage = false;
            for (int s = 0; s < props.stage_count; s++) {
                if (props.stages[s].isLightmap || props.stages[s].hasNextBundleLightmap) {
                    has_lightmap_stage = true;
                    break;
                }
            }

            /* Find the first non-lightmap, non-environment stage with
             * a blendFunc — this is the best candidate for transparency
             * classification.  Fall back to the first non-lightmap stage
             * with a blendFunc if no better candidate exists. */
            int best = -1;
            int fallback_nl = -1;
            for (int s = 0; s < props.stage_count; s++) {
                if (props.stages[s].isLightmap) continue;
                if (!props.stages[s].hasBlendFunc) {
                    /* First non-lightmap stage with no blendFunc: if it's
                     * not an environment stage, the shader is opaque
                     * (standard Q3 rule). If it IS env, skip and continue. */
                    if (props.stages[s].tcGen != STAGE_TCGEN_ENVIRONMENT) {
                        break;  /* Opaque — stop searching */
                    }
                    continue;
                }
                /* Has blendFunc */
                if (fallback_nl < 0) fallback_nl = s;
                if (props.stages[s].tcGen == STAGE_TCGEN_ENVIRONMENT) continue;
                best = s;
                break;
            }
            if (best < 0) best = fallback_nl;

            if (best >= 0) {
                MohaaBlendFactor bs = props.stages[best].blendSrc;
                MohaaBlendFactor bd = props.stages[best].blendDst;
                bool is_filter = (bs == BLEND_DST_COLOR && bd == BLEND_ZERO) ||
                                 (bs == BLEND_ZERO && bd == BLEND_SRC_COLOR);
                if (has_lightmap_stage && is_filter) {
                    /* Multi-pass lightmap → stays OPAQUE */
                } else {
                    props.transparency = classify_blend_factors(bs, bd);
                }
            }
        }

        /* Lowercase the name for consistent lookup */
        std::string key(shader_name);
        for (auto &c : key) c = tolower((unsigned char)c);

        /* Don't overwrite — first definition wins (matches engine behaviour) */
        if (s_shader_props.find(key) == s_shader_props.end()) {
            s_shader_props[key] = props;
            total_defs++;
        }
    }

    free(big_buf);

    /* ── Diagnostic: count transparency classifications ── */
    {
        int n_opaque = 0, n_alpha_test = 0, n_alpha_blend = 0;
        int n_additive = 0, n_multiplicative = 0;
        for (auto &kv : s_shader_props) {
            switch (kv.second.transparency) {
                case SHADER_OPAQUE:        n_opaque++; break;
                case SHADER_ALPHA_TEST:    n_alpha_test++; break;
                case SHADER_ALPHA_BLEND:   n_alpha_blend++; break;
                case SHADER_ADDITIVE:      n_additive++; break;
                case SHADER_MULTIPLICATIVE: n_multiplicative++; break;
            }
        }
        UtilityFunctions::print(String("[ShaderProps] Transparency: ") +
            String::num_int64(n_opaque) + " opaque, " +
            String::num_int64(n_alpha_test) + " alphaTest, " +
            String::num_int64(n_alpha_blend) + " alphaBlend, " +
            String::num_int64(n_additive) + " additive, " +
            String::num_int64(n_multiplicative) + " multiplicative");
        /* Log some example multiplicative shaders for diagnosis */
        if (n_multiplicative > 0) {
            int logged = 0;
            for (auto &kv : s_shader_props) {
                if (kv.second.transparency == SHADER_MULTIPLICATIVE && logged < 10) {
                    const char *lm_info = "no-lm";
                    for (int s2 = 0; s2 < kv.second.stage_count; s2++) {
                        if (kv.second.stages[s2].isLightmap) { lm_info = "lm-stage"; break; }
                        if (kv.second.stages[s2].hasNextBundleLightmap) { lm_info = "nb-lm"; break; }
                    }
                    UtilityFunctions::print(String("[ShaderProps]   MUL: ") +
                        String(kv.first.c_str()) + " stages=" +
                        String::num_int64(kv.second.stage_count) +
                        " " + String(lm_info));
                    logged++;
                }
            }
        }
    }

    UtilityFunctions::print(String("[ShaderProps] Loaded ") +
                            String::num_int64(files_loaded) + " shader files (" +
                            String::num_int64(numFiles) + " found), " +
                            String::num_int64(total_defs) + " definitions.");
}

void Godot_ShaderProps_Unload() {
    s_shader_props.clear();
}

const GodotShaderProps *Godot_ShaderProps_Find(const char *shader_name) {
    if (!shader_name || !shader_name[0]) return nullptr;

    /* Lowercase for lookup */
    std::string key(shader_name);
    for (auto &c : key) c = tolower((unsigned char)c);

    auto it = s_shader_props.find(key);
    if (it != s_shader_props.end())
        return &it->second;

    return nullptr;
}

int Godot_ShaderProps_Count() {
    return (int)s_shader_props.size();
}

const char *Godot_ShaderProps_GetSkyEnv() {
    for (const auto &pair : s_shader_props) {
        if (pair.second.is_sky && pair.second.sky_env[0])
            return pair.second.sky_env;
    }
    return nullptr;
}
