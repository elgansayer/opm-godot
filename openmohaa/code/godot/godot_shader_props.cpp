/* godot_shader_props.cpp — MOHAA .shader file parser for transparency properties
 *
 * Reads scripts/shaderlist.txt from the engine VFS, loads each listed
 * .shader file, and extracts transparency-related directives:
 *   - alphaFunc GT0 / LT128 / GE128
 *   - blendFunc blend / add / filter / GL_SRC_ALPHA ...
 *   - surfaceparm trans
 *   - cull none / front / twosided / disable
 *
 * Results cached in an unordered_map for O(1) lookup by shader name.
 */

#include "godot_shader_props.h"

#include <cstring>
#include <cctype>
#include <string>
#include <unordered_map>
#include <vector>

#include <godot_cpp/variant/utility_functions.hpp>

using namespace godot;

/* ===================================================================
 *  VFS accessor — extern "C" linkage to engine
 * ================================================================ */
extern "C" {
    long Godot_VFS_ReadFile(const char *qpath, void **out_buffer);
    void Godot_VFS_FreeFile(void *buffer);
}

/* ===================================================================
 *  Internal state
 * ================================================================ */
static std::unordered_map<std::string, GodotShaderProps> s_shader_props;

/* ===================================================================
 *  String helpers
 * ================================================================ */

/* Case-insensitive string comparison for shader keywords */
static bool str_ieq(const char *a, const char *b) {
    while (*a && *b) {
        if (tolower((unsigned char)*a) != tolower((unsigned char)*b))
            return false;
        a++;
        b++;
    }
    return *a == *b;
}

/* Skip whitespace (not newlines) */
static const char *skip_ws(const char *p) {
    while (*p == ' ' || *p == '\t') p++;
    return p;
}

/* Read next whitespace-delimited token into buf, return pointer past it */
static const char *read_token(const char *p, char *buf, int bufsize) {
    p = skip_ws(p);
    int i = 0;
    while (*p && *p != ' ' && *p != '\t' && *p != '\n' && *p != '\r' &&
           *p != '{' && *p != '}' && i < bufsize - 1) {
        buf[i++] = *p++;
    }
    buf[i] = '\0';
    return p;
}

/* Skip to end of line */
static const char *skip_line(const char *p) {
    while (*p && *p != '\n') p++;
    if (*p == '\n') p++;
    return p;
}

/* Skip whitespace including newlines */
static const char *skip_all_ws(const char *p) {
    while (*p == ' ' || *p == '\t' || *p == '\n' || *p == '\r') p++;
    return p;
}

/* ===================================================================
 *  Shader parser
 *
 *  MOHAA shader files follow the Quake 3 .shader format:
 *
 *    shader/name
 *    {
 *        surfaceparm trans
 *        cull none
 *        {
 *            map textures/foo.tga
 *            blendFunc GL_SRC_ALPHA GL_ONE_MINUS_SRC_ALPHA
 *            alphaFunc GE128
 *        }
 *    }
 *
 *  We extract properties from both the outer block (surfaceparm, cull)
 *  and inner stage blocks (blendFunc, alphaFunc).  We only need the
 *  properties from the FIRST stage for transparency classification.
 * ================================================================ */

/* Classify blendFunc from src/dst tokens */
static GodotShaderTransparency classify_blend(const char *src, const char *dst) {
    /* Shorthand forms */
    if (str_ieq(src, "blend"))  return SHADER_ALPHA_BLEND;
    if (str_ieq(src, "add"))    return SHADER_ADDITIVE;
    if (str_ieq(src, "filter")) return SHADER_MULTIPLICATIVE;

    /* Full GL_* forms */
    if (str_ieq(src, "GL_SRC_ALPHA") && str_ieq(dst, "GL_ONE_MINUS_SRC_ALPHA"))
        return SHADER_ALPHA_BLEND;
    if (str_ieq(src, "GL_ONE") && str_ieq(dst, "GL_ONE"))
        return SHADER_ADDITIVE;
    if (str_ieq(src, "GL_DST_COLOR") && str_ieq(dst, "GL_ZERO"))
        return SHADER_MULTIPLICATIVE;
    /* GL_ONE GL_ZERO = opaque (default) */
    if (str_ieq(src, "GL_ONE") && str_ieq(dst, "GL_ZERO"))
        return SHADER_OPAQUE;
    /* GL_ZERO GL_SRC_COLOR = filter (alternate form) */
    if (str_ieq(src, "GL_ZERO") && str_ieq(dst, "GL_SRC_COLOR"))
        return SHADER_MULTIPLICATIVE;

    /* Anything with GL_SRC_ALPHA as source is alpha-blended */
    if (str_ieq(src, "GL_SRC_ALPHA"))
        return SHADER_ALPHA_BLEND;
    /* GL_ONE as source with non-ONE dest is likely additive */
    if (str_ieq(src, "GL_ONE"))
        return SHADER_ADDITIVE;

    /* Default: treat as alpha blend if we can't classify */
    return SHADER_ALPHA_BLEND;
}

/* Parse a single shader definition starting after the opening '{' */
static void parse_shader_body(const char *p, const char *end, GodotShaderProps *props) {
    int brace_depth = 1;
    int stage_depth = 0;
    bool first_stage = true;

    char token[256];

    while (p < end && brace_depth > 0) {
        p = skip_all_ws(p);
        if (p >= end) break;

        /* Handle comments */
        if (p[0] == '/' && p[1] == '/') {
            p = skip_line(p);
            continue;
        }

        /* Track brace depth */
        if (*p == '{') {
            brace_depth++;
            if (brace_depth == 2) {
                stage_depth++;
                props->num_stages = stage_depth;  /* Phase 69: track stage count */
            }
            p++;
            continue;
        }
        if (*p == '}') {
            if (brace_depth == 2) {
                /* Closing a stage */
                first_stage = false;
            }
            brace_depth--;
            p++;
            continue;
        }

        /* Read directive */
        p = read_token(p, token, sizeof(token));
        if (!token[0]) {
            p = skip_line(p);
            continue;
        }

        /* ── Outer block directives (brace_depth == 1) ── */
        if (brace_depth == 1) {
            if (str_ieq(token, "surfaceparm")) {
                p = read_token(p, token, sizeof(token));
                if (str_ieq(token, "trans")) {
                    /* Mark as potentially transparent (will be upgraded
                       to ALPHA_BLEND if no explicit alphaFunc/blendFunc) */
                    if (props->transparency == SHADER_OPAQUE)
                        props->transparency = SHADER_ALPHA_BLEND;
                } else if (str_ieq(token, "portal")) {
                    props->is_portal = true;
                } else if (str_ieq(token, "sky")) {
                    props->is_sky = true;
                }
            } else if (str_ieq(token, "cull")) {
                p = read_token(p, token, sizeof(token));
                if (str_ieq(token, "none") || str_ieq(token, "twosided") ||
                    str_ieq(token, "disable")) {
                    props->cull = SHADER_CULL_NONE;
                } else if (str_ieq(token, "front")) {
                    props->cull = SHADER_CULL_FRONT;
                } else {
                    props->cull = SHADER_CULL_BACK;
                }
            } else if (str_ieq(token, "skyParms")) {
                /* skyParms <envBasename> <cloudHeight> <innerBox>
                 * e.g. skyParms env/m5l2 512 - */
                char env_basename[64];
                p = read_token(p, env_basename, sizeof(env_basename));
                if (env_basename[0] && !str_ieq(env_basename, "-")) {
                    strncpy(props->sky_env, env_basename, sizeof(props->sky_env) - 1);
                    props->sky_env[sizeof(props->sky_env) - 1] = '\0';
                }
                props->is_sky = true;
            } else if (str_ieq(token, "deformVertexes") || str_ieq(token, "deformvertexes")) {
                /* Phase 63: deformVertexes <type> ... */
                p = read_token(p, token, sizeof(token));
                props->has_deform = true;
                if (str_ieq(token, "wave")) {
                    props->deform_type = 0;
                    char div_v[64], func[64], base_v[64], amp[64], phase[64], freq[64];
                    p = read_token(p, div_v, sizeof(div_v));
                    p = read_token(p, func, sizeof(func));  /* sin/triangle/square/sawtooth */
                    p = read_token(p, base_v, sizeof(base_v));
                    p = read_token(p, amp, sizeof(amp));
                    p = read_token(p, phase, sizeof(phase));
                    p = read_token(p, freq, sizeof(freq));
                    props->deform_div = (float)atof(div_v);
                    props->deform_base = (float)atof(base_v);
                    props->deform_amplitude = (float)atof(amp);
                    props->deform_phase = (float)atof(phase);
                    props->deform_frequency = (float)atof(freq);
                } else if (str_ieq(token, "bulge")) {
                    props->deform_type = 1;
                    char bw[64], bh[64], bs[64];
                    p = read_token(p, bw, sizeof(bw));
                    p = read_token(p, bh, sizeof(bh));
                    p = read_token(p, bs, sizeof(bs));
                    props->deform_base = (float)atof(bw);
                    props->deform_amplitude = (float)atof(bh);
                    props->deform_frequency = (float)atof(bs);
                } else if (str_ieq(token, "move")) {
                    props->deform_type = 2;
                    /* move <x> <y> <z> <func> <base> <amp> <phase> <freq> */
                    char mx[64], my[64], mz[64], func[64], base_v[64], amp[64], phase[64], freq[64];
                    p = read_token(p, mx, sizeof(mx));
                    p = read_token(p, my, sizeof(my));
                    p = read_token(p, mz, sizeof(mz));
                    p = read_token(p, func, sizeof(func));
                    p = read_token(p, base_v, sizeof(base_v));
                    p = read_token(p, amp, sizeof(amp));
                    p = read_token(p, phase, sizeof(phase));
                    p = read_token(p, freq, sizeof(freq));
                    props->deform_base = (float)atof(base_v);
                    props->deform_amplitude = (float)atof(amp);
                    props->deform_phase = (float)atof(phase);
                    props->deform_frequency = (float)atof(freq);
                } else if (str_ieq(token, "autosprite")) {
                    props->deform_type = 3;
                } else if (str_ieq(token, "autosprite2")) {
                    props->deform_type = 4;
                }
            } else if (str_ieq(token, "sort")) {
                /* Phase 67: sort hint */
                p = read_token(p, token, sizeof(token));
                if (str_ieq(token, "portal")) props->sort_key = 1;
                else if (str_ieq(token, "sky")) props->sort_key = 2;
                else if (str_ieq(token, "opaque")) props->sort_key = 3;
                else if (str_ieq(token, "banner")) props->sort_key = 6;
                else if (str_ieq(token, "underwater")) props->sort_key = 8;
                else if (str_ieq(token, "additive")) props->sort_key = 9;
                else if (str_ieq(token, "nearest")) props->sort_key = 16;
                else props->sort_key = atoi(token);
            } else if (str_ieq(token, "nomipmaps")) {
                /* Phase 68 */
                props->no_mipmaps = true;
            } else if (str_ieq(token, "nopicmip")) {
                /* Phase 68 */
                props->no_picmip = true;
            } else if (str_ieq(token, "fogParms") || str_ieq(token, "fogparms")) {
                /* Phase 70: fogParms ( <r> <g> <b> ) <distance> */
                p = skip_ws(p);
                if (*p == '(') p++;
                char rv[64], gv[64], bv[64], dv[64];
                p = read_token(p, rv, sizeof(rv));
                p = read_token(p, gv, sizeof(gv));
                p = read_token(p, bv, sizeof(bv));
                p = skip_ws(p);
                if (*p == ')') p++;
                p = read_token(p, dv, sizeof(dv));
                props->has_fog = true;
                props->fog_color[0] = (float)atof(rv);
                props->fog_color[1] = (float)atof(gv);
                props->fog_color[2] = (float)atof(bv);
                props->fog_distance = (float)atof(dv);
            }
        }

        /* ── Stage directives (brace_depth == 2) ── */
        if (brace_depth == 2) {
            /* Phase 69: count stages */
            if (first_stage && !token[0]) { /* handled via brace tracking */ }

            if (str_ieq(token, "alphaFunc")) {
                p = read_token(p, token, sizeof(token));
                props->transparency = SHADER_ALPHA_TEST;
                if (str_ieq(token, "GT0")) {
                    props->alpha_threshold = 0.01f;
                } else if (str_ieq(token, "LT128")) {
                    props->alpha_threshold = 0.5f;
                } else if (str_ieq(token, "GE128")) {
                    props->alpha_threshold = 0.5f;
                } else {
                    props->alpha_threshold = 0.5f;
                }
            } else if (str_ieq(token, "blendFunc")) {
                char src_tok[64], dst_tok[64];
                p = read_token(p, src_tok, sizeof(src_tok));
                dst_tok[0] = '\0';

                /* Check for shorthand forms (single token: blend/add/filter) */
                if (str_ieq(src_tok, "blend") || str_ieq(src_tok, "add") ||
                    str_ieq(src_tok, "filter")) {
                    GodotShaderTransparency t = classify_blend(src_tok, "");
                    /* Only upgrade, never downgrade from alphaFunc */
                    if (props->transparency != SHADER_ALPHA_TEST)
                        props->transparency = t;
                } else {
                    /* Full form: blendFunc GL_SRC GL_DST */
                    p = read_token(p, dst_tok, sizeof(dst_tok));
                    GodotShaderTransparency t = classify_blend(src_tok, dst_tok);
                    if (props->transparency != SHADER_ALPHA_TEST)
                        props->transparency = t;
                }
            } else if (str_ieq(token, "animMap") || str_ieq(token, "animmap")) {
                /* Phase 61: animMap <freq> <tex1> <tex2> ... */
                char freq_val[64];
                p = read_token(p, freq_val, sizeof(freq_val));
                props->animmap_freq = (float)atof(freq_val);
                props->has_animmap = true;
                props->animmap_num_frames = 0;

                /* Read texture names until end of line */
                while (props->animmap_num_frames < 8) {
                    p = skip_ws(p);
                    if (!*p || *p == '\n' || *p == '\r') break;
                    char frame_name[64];
                    p = read_token(p, frame_name, sizeof(frame_name));
                    if (!frame_name[0]) break;
                    strncpy(props->animmap_frames[props->animmap_num_frames],
                            frame_name, 63);
                    props->animmap_frames[props->animmap_num_frames][63] = '\0';
                    props->animmap_num_frames++;
                }
            } else if (str_ieq(token, "tcGen") || str_ieq(token, "tcgen")) {
                /* Phase 62: tcGen environment */
                p = read_token(p, token, sizeof(token));
                if (str_ieq(token, "environment") || str_ieq(token, "environmentmodel")) {
                    props->tcgen_environment = true;
                }
            } else if (str_ieq(token, "rgbGen") || str_ieq(token, "rgbgen")) {
                /* Phase 64: rgbGen */
                p = read_token(p, token, sizeof(token));
                if (str_ieq(token, "identity") || str_ieq(token, "identityLighting")) {
                    props->rgbgen_type = 0;
                } else if (str_ieq(token, "vertex") || str_ieq(token, "exactVertex") ||
                           str_ieq(token, "lightingDiffuse")) {
                    props->rgbgen_type = 1;
                } else if (str_ieq(token, "wave")) {
                    props->rgbgen_type = 2;
                    char func[64], base_v[64], amp[64], freq[64], phase[64];
                    p = read_token(p, func, sizeof(func));
                    p = read_token(p, base_v, sizeof(base_v));
                    p = read_token(p, amp, sizeof(amp));
                    p = read_token(p, phase, sizeof(phase));
                    p = read_token(p, freq, sizeof(freq));
                    props->rgbgen_wave_base  = (float)atof(base_v);
                    props->rgbgen_wave_amp   = (float)atof(amp);
                    props->rgbgen_wave_phase = (float)atof(phase);
                    props->rgbgen_wave_freq  = (float)atof(freq);
                } else if (str_ieq(token, "entity")) {
                    props->rgbgen_type = 3;
                } else if (str_ieq(token, "const") || str_ieq(token, "constant")) {
                    props->rgbgen_type = 4;
                    /* const ( r g b ) */
                    p = skip_ws(p);
                    if (*p == '(') p++;
                    char rv[64], gv[64], bv[64];
                    p = read_token(p, rv, sizeof(rv));
                    p = read_token(p, gv, sizeof(gv));
                    p = read_token(p, bv, sizeof(bv));
                    p = skip_ws(p);
                    if (*p == ')') p++;
                    props->rgbgen_const[0] = (float)atof(rv);
                    props->rgbgen_const[1] = (float)atof(gv);
                    props->rgbgen_const[2] = (float)atof(bv);
                }
            } else if (str_ieq(token, "alphaGen") || str_ieq(token, "alphagen")) {
                /* Phase 65: alphaGen */
                p = read_token(p, token, sizeof(token));
                if (str_ieq(token, "identity")) {
                    props->alphagen_type = 0;
                } else if (str_ieq(token, "vertex")) {
                    props->alphagen_type = 1;
                } else if (str_ieq(token, "wave")) {
                    props->alphagen_type = 2;
                    char func[64], base_v[64], amp[64], phase[64], freq[64];
                    p = read_token(p, func, sizeof(func));
                    p = read_token(p, base_v, sizeof(base_v));
                    p = read_token(p, amp, sizeof(amp));
                    p = read_token(p, phase, sizeof(phase));
                    p = read_token(p, freq, sizeof(freq));
                    props->alphagen_wave_base  = (float)atof(base_v);
                    props->alphagen_wave_amp   = (float)atof(amp);
                    props->alphagen_wave_phase = (float)atof(phase);
                    props->alphagen_wave_freq  = (float)atof(freq);
                } else if (str_ieq(token, "entity")) {
                    props->alphagen_type = 3;
                } else if (str_ieq(token, "const") || str_ieq(token, "constant")) {
                    props->alphagen_type = 4;
                    char av[64];
                    p = read_token(p, av, sizeof(av));
                    props->alphagen_const = (float)atof(av);
                }
            } else if (str_ieq(token, "tcMod") || str_ieq(token, "tcmod")) {
                /* Phase 36 + 66: Parse tcMod directives for UV animation */
                p = read_token(p, token, sizeof(token));
                if (str_ieq(token, "scroll")) {
                    char sval[64], tval[64];
                    p = read_token(p, sval, sizeof(sval));
                    p = read_token(p, tval, sizeof(tval));
                    props->tcmod_scroll_s = (float)atof(sval);
                    props->tcmod_scroll_t = (float)atof(tval);
                    props->has_tcmod = true;
                } else if (str_ieq(token, "rotate")) {
                    char rval[64];
                    p = read_token(p, rval, sizeof(rval));
                    props->tcmod_rotate = (float)atof(rval);
                    props->has_tcmod = true;
                } else if (str_ieq(token, "scale")) {
                    char sval[64], tval[64];
                    p = read_token(p, sval, sizeof(sval));
                    p = read_token(p, tval, sizeof(tval));
                    props->tcmod_scale_s = (float)atof(sval);
                    props->tcmod_scale_t = (float)atof(tval);
                    props->has_tcmod = true;
                } else if (str_ieq(token, "turb")) {
                    /* turb <base> <amplitude> <phase> <freq> */
                    char base_v[64], amp[64], phase[64], freq[64];
                    p = read_token(p, base_v, sizeof(base_v));
                    p = read_token(p, amp, sizeof(amp));
                    p = read_token(p, phase, sizeof(phase));
                    p = read_token(p, freq, sizeof(freq));
                    props->tcmod_turb_amp  = (float)atof(amp);
                    props->tcmod_turb_freq = (float)atof(freq);
                    props->has_tcmod = true;
                } else if (str_ieq(token, "stretch")) {
                    /* Phase 66: tcMod stretch <func> <base> <amp> <phase> <freq> */
                    char func[64], base_v[64], amp[64], phase[64], freq[64];
                    p = read_token(p, func, sizeof(func));
                    p = read_token(p, base_v, sizeof(base_v));
                    p = read_token(p, amp, sizeof(amp));
                    p = read_token(p, phase, sizeof(phase));
                    p = read_token(p, freq, sizeof(freq));
                    props->has_tcmod_stretch = true;
                    props->tcmod_stretch_base  = (float)atof(base_v);
                    props->tcmod_stretch_amp   = (float)atof(amp);
                    props->tcmod_stretch_phase = (float)atof(phase);
                    props->tcmod_stretch_freq  = (float)atof(freq);
                    props->has_tcmod = true;
                }
            }
        }

        p = skip_line(p);
    }
}

/* Parse all shader definitions in a shader file text buffer */
static int parse_shader_file(const char *text, int text_len) {
    const char *p = text;
    const char *end = text + text_len;
    int count = 0;
    char shader_name[256];

    while (p < end) {
        /* Skip whitespace and comments */
        p = skip_all_ws(p);
        if (p >= end) break;

        if (p[0] == '/' && p[1] == '/') {
            p = skip_line(p);
            continue;
        }

        /* Read shader name */
        p = read_token(p, shader_name, sizeof(shader_name));
        if (!shader_name[0]) {
            p = skip_line(p);
            continue;
        }

        /* Find opening brace */
        p = skip_all_ws(p);
        if (p >= end || *p != '{') {
            p = skip_line(p);
            continue;
        }
        p++; /* skip '{' */

        /* Initialise properties */
        GodotShaderProps props = {};
        props.transparency = SHADER_OPAQUE;
        props.alpha_threshold = 0.5f;
        props.cull = SHADER_CULL_BACK;
        props.is_portal = false;
        props.tcmod_scale_s = 1.0f;
        props.tcmod_scale_t = 1.0f;
        props.alphagen_const = 1.0f;
        props.rgbgen_const[0] = props.rgbgen_const[1] = props.rgbgen_const[2] = 1.0f;

        /* Parse body */
        parse_shader_body(p, end, &props);

        /* Skip to matching close brace */
        int depth = 1;
        while (p < end && depth > 0) {
            if (*p == '{') depth++;
            else if (*p == '}') depth--;
            p++;
        }

        /* Store result — only if shader has non-default properties */
        /* Actually, store all parsed shaders so we can distinguish
         * "shader not found" from "shader is opaque" */
        /* Lowercase the name for consistent lookup */
        std::string key(shader_name);
        for (auto &c : key) c = tolower((unsigned char)c);

        /* Don't overwrite — first definition wins (matches engine behaviour) */
        if (s_shader_props.find(key) == s_shader_props.end()) {
            s_shader_props[key] = props;
            count++;
        }
    }

    return count;
}

/* ===================================================================
 *  Public API
 * ================================================================ */

void Godot_ShaderProps_Load() {
    s_shader_props.clear();

    /* ── Read shaderlist.txt ── */
    void *list_raw = nullptr;
    long list_len = Godot_VFS_ReadFile("scripts/shaderlist.txt", &list_raw);

    std::vector<std::string> shader_files;

    if (list_len > 0 && list_raw) {
        const char *p = (const char *)list_raw;
        const char *end = p + list_len;
        char name[256];

        while (p < end) {
            p = skip_all_ws(p);
            if (p >= end) break;

            /* Read shader file basename */
            int i = 0;
            while (p < end && *p != '\n' && *p != '\r' && *p != ' ' &&
                   *p != '\t' && i < 255) {
                name[i++] = *p++;
            }
            name[i] = '\0';
            p = skip_line(p);

            if (name[0] && name[0] != '/' && name[0] != '#') {
                shader_files.push_back(std::string("scripts/") + name + ".shader");
            }
        }
        Godot_VFS_FreeFile(list_raw);
    }

    /* ── Parse each shader file ── */
    int total_defs = 0;
    int files_loaded = 0;

    for (const auto &path : shader_files) {
        void *raw = nullptr;
        long len = Godot_VFS_ReadFile(path.c_str(), &raw);
        if (len <= 0 || !raw) continue;

        int n = parse_shader_file((const char *)raw, (int)len);
        total_defs += n;
        files_loaded++;

        Godot_VFS_FreeFile(raw);
    }

    UtilityFunctions::print(String("[ShaderProps] Loaded ") +
                            String::num_int64(files_loaded) + " shader files, " +
                            String::num_int64(total_defs) + " definitions. " +
                            String::num_int64(shader_files.size()) + " listed.");
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
