/* godot_shader_props.h — Shader transparency / blend property lookup
 *
 * Parses MOHAA/Q3-style .shader script files from the engine VFS and
 * provides a lookup table mapping shader names to their transparency
 * and cull properties.  Used by the BSP mesh builder and entity
 * material creation to apply correct Godot material transparency.
 *
 * The parser reads scripts/shaderlist.txt to discover which .shader
 * files to load, then extracts alphaFunc, blendFunc, surfaceparm trans,
 * and cull directives from each shader definition.
 */

#ifndef GODOT_SHADER_PROPS_H
#define GODOT_SHADER_PROPS_H

/* ── Transparency classification ── */
enum GodotShaderTransparency {
    SHADER_OPAQUE = 0,
    SHADER_ALPHA_TEST,       /* alphaFunc GT0/LT128/GE128 → ALPHA_SCISSOR */
    SHADER_ALPHA_BLEND,      /* blendFunc blend / GL_SRC_ALPHA GL_ONE_MINUS_SRC_ALPHA → TRANSPARENCY_ALPHA */
    SHADER_ADDITIVE,         /* blendFunc add / GL_ONE GL_ONE → BLEND_MODE_ADD */
    SHADER_MULTIPLICATIVE,   /* blendFunc filter / GL_DST_COLOR GL_ZERO → BLEND_MODE_MUL */
};

/* ── Cull mode ── */
enum GodotShaderCull {
    SHADER_CULL_BACK  = 0,   /* default: back-face culling */
    SHADER_CULL_FRONT = 1,   /* cull front */
    SHADER_CULL_NONE  = 2,   /* cull none / cull twosided / cull disable */
};

/* ── Per-shader properties ── */
struct GodotShaderProps {
    GodotShaderTransparency transparency;
    float alpha_threshold;   /* for SHADER_ALPHA_TEST: 0.01 (GT0), 0.5 (GE128/LT128) */
    GodotShaderCull cull;
    bool is_portal;          /* surfaceparm portal — skip rendering */
    bool is_sky;             /* surfaceparm sky */
    bool no_lightmap;        /* surfaceparm nolightmap — render fullbright */
    char sky_env[64];        /* skyParms env basename (e.g. "env/m5l2") */

    /* Phase 36: tcMod scroll/rotate/scale animation parameters */
    float tcmod_scroll_s;    /* texcoord S scroll speed (units/sec) */
    float tcmod_scroll_t;    /* texcoord T scroll speed (units/sec) */
    float tcmod_rotate;      /* texcoord rotation speed (degrees/sec) */
    float tcmod_scale_s;     /* texcoord S scale factor (1.0 = no change) */
    float tcmod_scale_t;     /* texcoord T scale factor (1.0 = no change) */
    float tcmod_turb_amp;    /* turbulence amplitude */
    float tcmod_turb_freq;   /* turbulence frequency */
    bool  has_tcmod;         /* true if any tcMod directive was found */

    /* Phase 61: animMap — animated texture sequence */
    float animmap_freq;             /* frames per second */
    int   animmap_num_frames;       /* number of textures in sequence */
    char  animmap_frames[8][64];    /* up to 8 texture names */
    bool  has_animmap;

    /* Phase 62: tcGen environment — cubic environment mapping */
    bool  tcgen_environment;

    /* Phase 63: deformVertexes */
    bool  has_deform;
    int   deform_type;              /* 0=wave, 1=bulge, 2=move, 3=autosprite, 4=autosprite2 */
    float deform_div;               /* wave divisor */
    float deform_base;
    float deform_amplitude;
    float deform_frequency;
    float deform_phase;

    /* Phase 64: rgbGen */
    int   rgbgen_type;              /* 0=identity, 1=vertex, 2=wave, 3=entity, 4=const */
    float rgbgen_wave_base;
    float rgbgen_wave_amp;
    float rgbgen_wave_freq;
    float rgbgen_wave_phase;
    float rgbgen_const[3];

    /* Phase 65: alphaGen */
    int   alphagen_type;            /* 0=identity, 1=vertex, 2=wave, 3=entity, 4=const */
    float alphagen_wave_base;
    float alphagen_wave_amp;
    float alphagen_wave_freq;
    float alphagen_wave_phase;
    float alphagen_const;

    /* Phase 66: tcMod stretch */
    bool  has_tcmod_stretch;
    float tcmod_stretch_base;
    float tcmod_stretch_amp;
    float tcmod_stretch_freq;
    float tcmod_stretch_phase;

    /* Phase 67: sort hint */
    int   sort_key;                 /* 0=default, 1-16 explicit sort order */

    /* Phase 68: nomipmaps / nopicmip */
    bool  no_mipmaps;
    bool  no_picmip;

    /* Phase 69: multi-stage count (first stage is primary) */
    int   num_stages;

    /* Phase 70: fog parameters */
    bool  has_fog;
    float fog_color[3];
    float fog_distance;
};

/* ── API ── */

/*
 * Parse all .shader files listed in scripts/shaderlist.txt and build
 * the internal lookup table.  Safe to call multiple times (clears
 * previous data).  Uses the engine VFS for file access.
 */
void Godot_ShaderProps_Load();

/*
 * Release all parsed shader data.
 */
void Godot_ShaderProps_Unload();

/*
 * Look up properties for a shader by name.
 * Returns nullptr if the shader has no .shader definition (treat as opaque).
 */
const GodotShaderProps *Godot_ShaderProps_Find(const char *shader_name);

/*
 * Returns the number of parsed shader definitions.
 */
int Godot_ShaderProps_Count();

/*
 * Returns the skyParms env basename for the first sky shader found,
 * or nullptr if no sky shader was parsed.  E.g. "env/m5l2".
 */
const char *Godot_ShaderProps_GetSkyEnv();

#endif /* GODOT_SHADER_PROPS_H */
