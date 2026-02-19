/* godot_pbr.cpp — PBR texture discovery and material enhancement
 *
 * Scans a configurable PBR asset directory for HD texture variants
 * (albedo, normal, roughness) that match engine texture paths.
 * Applies them to StandardMaterial3D instances to enable physically
 * based rendering with normal mapping and roughness.
 *
 * The PBR asset directory defaults to:
 *   {fs_homedatapath}/{gamedir}/zgodot_pbr_project/mohaa-hd-assets/
 *
 * Texture naming convention (from the convert.sh upscaler pipeline):
 *   {basename}_albedo.png     — AI-upscaled diffuse texture
 *   {basename}_normal-0.png   — Generated normal map (variant 0)
 *   {basename}_roughness.png  — Generated roughness map
 *
 * The base name is derived from the original texture filename without
 * extension.  Directory structure mirrors the engine VFS layout:
 *   textures/french/dyer.tga  →  textures/french/dyer_albedo.png
 */

#include "godot_pbr.h"

#include <godot_cpp/classes/dir_access.hpp>
#include <godot_cpp/classes/file_access.hpp>
#include <godot_cpp/classes/image.hpp>
#include <godot_cpp/variant/utility_functions.hpp>

#include <cstring>
#include <string>
#include <unordered_map>

using namespace godot;

extern "C" void Cvar_VariableStringBuffer(const char *var_name, char *buffer, int bufsize);

/* ── Engine accessor declarations (cannot include engine headers) ── */
extern "C" {
    const char *Godot_VFS_GetBasepath(void);
    const char *Godot_VFS_GetHomedatapath(void);
    const char *Godot_VFS_GetHomepath(void);
    const char *Godot_VFS_GetGamedir(void);
    int Godot_VFS_FileExists(const char *qpath);
}

/* ── Internal state ── */

/* PBR enabled flag — controlled by runtime toggle */
static bool s_pbr_enabled = true;
static bool s_pbr_procedural_normals_enabled = true;
static bool s_pbr_wet_heuristics_enabled = true;
static bool s_pbr_material_depth_enabled = true;
static bool s_pbr_material_depth_overdrive_enabled = false;
static float s_pbr_depth_normal_scale = 1.35f;
static float s_pbr_depth_roughness_mul = 1.0f;
static float s_pbr_depth_specular_mul = 1.0f;
static float s_pbr_depth_metallic_mul = 1.0f;

/* Root directory for PBR assets on the real filesystem */
static std::string s_pbr_root;

/* Map from normalised engine texture base path (no extension, lowercase)
 * to the filesystem paths of the PBR texture variants. */
struct PBRFilePaths {
    std::string albedo_path;
    std::string normal_path;
    std::string roughness_path;
    std::string emission_path;
};

static std::unordered_map<std::string, PBRFilePaths> s_pbr_paths;

/* Cached loaded PBR textures — lazily populated on first lookup */
static std::unordered_map<std::string, PBRTextureSet> s_pbr_cache;

/* Total discovered PBR sets */
static int s_pbr_count = 0;

static float clampf(float v, float lo, float hi) {
    if (v < lo) return lo;
    if (v > hi) return hi;
    return v;
}

/* Application counters for diagnostics */
static int s_pbr_applied = 0;
static int s_pbr_missed = 0;
static bool s_pbr_summary_printed = false;

/* ── Helpers ── */

/* Normalise a path: lowercase, strip extension, forward slashes */
static std::string normalise_key(const char *path) {
    if (!path || !path[0]) return "";

    std::string s(path);

    /* Forward slashes */
    for (auto &c : s) {
        if (c == '\\') c = '/';
    }

    /* Strip file extension */
    size_t dot = s.rfind('.');
    size_t slash = s.rfind('/');
    if (dot != std::string::npos && (slash == std::string::npos || dot > slash)) {
        s = s.substr(0, dot);
    }

    /* Lowercase */
    for (auto &c : s) {
        if (c >= 'A' && c <= 'Z') c += 32;
    }

    return s;
}

/* Load a PNG image from an absolute filesystem path.
 * Returns a valid ImageTexture or null ref on failure. */
static Ref<ImageTexture> load_png_from_disk(const String &abs_path) {
    Ref<FileAccess> f = FileAccess::open(abs_path, FileAccess::READ);
    if (!f.is_valid()) return Ref<ImageTexture>();

    int64_t len = f->get_length();
    if (len <= 0) return Ref<ImageTexture>();

    PackedByteArray buf = f->get_buffer(len);
    f->close();

    /* Validate it's actually a PNG (not a Git LFS pointer) */
    if (buf.size() < 8) return Ref<ImageTexture>();
    const uint8_t *data = buf.ptr();
    /* PNG magic: 89 50 4E 47 0D 0A 1A 0A */
    if (data[0] != 0x89 || data[1] != 0x50 || data[2] != 0x4E || data[3] != 0x47) {
        /* Not a real PNG — likely a Git LFS pointer file */
        return Ref<ImageTexture>();
    }

    Ref<Image> img;
    img.instantiate();
    Error err = img->load_png_from_buffer(buf);
    if (err != OK || img->is_empty()) return Ref<ImageTexture>();

    img->generate_mipmaps();
    return ImageTexture::create_from_image(img);
}

/* Generate a simple tangent-space normal map from albedo luminance.
 * This is a fallback for textures that have no authored normal map. */
static Ref<ImageTexture> generate_normal_from_albedo(const Ref<ImageTexture> &albedo_tex) {
    if (!albedo_tex.is_valid()) return Ref<ImageTexture>();

    Ref<Image> src = albedo_tex->get_image();
    if (!src.is_valid() || src->is_empty()) return Ref<ImageTexture>();

    int w = src->get_width();
    int h = src->get_height();
    if (w < 2 || h < 2) return Ref<ImageTexture>();

    src->decompress();
    Ref<Image> gray = src->duplicate();
    gray->convert(Image::FORMAT_RGBA8);

    Ref<Image> out;
    out.instantiate();
    out->create(w, h, false, Image::FORMAT_RGBA8);

    auto lum = [&](int x, int y) -> float {
        x = (x < 0) ? 0 : (x >= w ? w - 1 : x);
        y = (y < 0) ? 0 : (y >= h ? h - 1 : y);
        Color c = gray->get_pixel(x, y);
        return c.r * 0.2126f + c.g * 0.7152f + c.b * 0.0722f;
    };

    const float strength = 3.0f;
    for (int y = 0; y < h; y++) {
        for (int x = 0; x < w; x++) {
            float dx = (lum(x + 1, y) - lum(x - 1, y)) * strength;
            float dy = (lum(x, y + 1) - lum(x, y - 1)) * strength;
            Vector3 n(-dx, -dy, 1.0f);
            n = n.normalized();
            Color nc(n.x * 0.5f + 0.5f, n.y * 0.5f + 0.5f, n.z * 0.5f + 0.5f, 1.0f);
            out->set_pixel(x, y, nc);
        }
    }

    out->generate_mipmaps();
    return ImageTexture::create_from_image(out);
}

/* Recursively scan a directory for PBR texture sets */
static void scan_directory(const String &dir_path, const std::string &rel_prefix) {
    Ref<DirAccess> dir = DirAccess::open(dir_path);
    if (!dir.is_valid()) return;

    dir->list_dir_begin();
    String entry = dir->get_next();
    while (!entry.is_empty()) {
        if (dir->current_is_dir()) {
            if (entry != "." && entry != "..") {
                String sub = dir_path + String("/") + entry;
                std::string sub_rel = rel_prefix.empty()
                    ? std::string(entry.utf8().get_data())
                    : rel_prefix + "/" + std::string(entry.utf8().get_data());
                scan_directory(sub, sub_rel);
            }
        } else {
            /* Check for _albedo.png files — these define a PBR set */
            std::string fname(entry.utf8().get_data());
            const char *suffix = "_albedo.png";
            size_t slen = strlen(suffix);
            if (fname.size() > slen &&
                fname.compare(fname.size() - slen, slen, suffix) == 0) {

                /* Extract base name (without _albedo.png) */
                std::string base = fname.substr(0, fname.size() - slen);
                std::string full_rel = rel_prefix.empty()
                    ? base : rel_prefix + "/" + base;

                /* Normalise key to match engine texture paths */
                std::string key = normalise_key(full_rel.c_str());

                std::string dir_str(dir_path.utf8().get_data());

                PBRFilePaths paths;
                paths.albedo_path = dir_str + "/" + base + "_albedo.png";
                paths.normal_path = dir_str + "/" + base + "_normal-0.png";
                paths.roughness_path = dir_str + "/" + base + "_roughness.png";
                paths.emission_path = dir_str + "/" + base + "_emission.png";

                s_pbr_paths[key] = paths;
                s_pbr_count++;
            }
        }
        entry = dir->get_next();
    }
    dir->list_dir_end();
}

/* ── Public API ── */

void Godot_PBR_Init() {
    s_pbr_paths.clear();
    s_pbr_cache.clear();
    s_pbr_count = 0;
    s_pbr_applied = 0;
    s_pbr_missed = 0;
    s_pbr_summary_printed = false;

    /* Determine PBR asset root directory.
     * Search multiple engine paths in priority order (same as cgame loading):
     *   1. fs_homedatapath/{gamedir}/zgodot_pbr_project/mohaa-hd-assets/
     *   2. fs_basepath/{gamedir}/zgodot_pbr_project/mohaa-hd-assets/
     *   3. fs_homepath/{gamedir}/zgodot_pbr_project/mohaa-hd-assets/
     * The homedatapath is typically ~/.local/share/openmohaa
     * The gamedir is typically "main" */
    const char *gdir = Godot_VFS_GetGamedir();
    if (!gdir || !gdir[0]) {
        UtilityFunctions::print("[PBR] Cannot determine game directory — PBR disabled.");
        s_pbr_enabled = false;
        return;
    }

    const char *search_paths[] = {
        Godot_VFS_GetHomedatapath(),
        Godot_VFS_GetBasepath(),
        Godot_VFS_GetHomepath(),
    };
    const char *search_names[] = {
        "fs_homedatapath",
        "fs_basepath",
        "fs_homepath",
    };

    String root_str;
    bool found = false;
    for (int i = 0; i < 3; i++) {
        if (!search_paths[i] || !search_paths[i][0]) continue;
        std::string candidate = std::string(search_paths[i]) + "/" +
                                std::string(gdir) +
                                "/zgodot_pbr_project/mohaa-hd-assets";
        String candidate_str = String(candidate.c_str());
        Ref<DirAccess> test_dir = DirAccess::open(candidate_str);
        if (test_dir.is_valid()) {
            s_pbr_root = candidate;
            root_str = candidate_str;
            found = true;
            UtilityFunctions::print(String("[PBR] Found PBR assets via ") +
                                   String(search_names[i]) + String(": ") +
                                   candidate_str);
            break;
        }
    }

    if (!found) {
        /* Show the first valid path as the suggested location */
        std::string suggested;
        for (int i = 0; i < 3; i++) {
            if (search_paths[i] && search_paths[i][0]) {
                suggested = std::string(search_paths[i]) + "/" +
                            std::string(gdir) +
                            "/zgodot_pbr_project/mohaa-hd-assets";
                break;
            }
        }
        UtilityFunctions::print(String("[PBR] PBR asset directory not found."));
        UtilityFunctions::print(String("[PBR] Place HD assets in: ") +
                               String(suggested.c_str()));
        s_pbr_enabled = false;
        return;
    }

    /* Scan for PBR texture sets.
     * The directory structure mirrors the engine's VFS layout:
     *   textures/ → world textures
     *   models/   → model textures
     *   gfx/      → UI textures
     *   env/      → environment/skybox */
    scan_directory(root_str, "");

    UtilityFunctions::print(String("[PBR] Discovered ") +
                            String::num_int64(s_pbr_count) +
                            String(" PBR texture sets in ") + root_str);

    if (s_pbr_count > 0) {
        s_pbr_enabled = true;
    } else {
        UtilityFunctions::print("[PBR] No PBR textures found — PBR rendering disabled.");
        s_pbr_enabled = false;
    }
}

void Godot_PBR_Shutdown() {
    s_pbr_cache.clear();
    s_pbr_paths.clear();
    s_pbr_count = 0;
}

bool Godot_PBR_IsEnabled() {
    return s_pbr_enabled && s_pbr_count > 0;
}

void Godot_PBR_SetEnabled(bool enabled) {
    s_pbr_enabled = enabled;
}

void Godot_PBR_SetProceduralNormalsEnabled(bool enabled) {
    s_pbr_procedural_normals_enabled = enabled;
}

void Godot_PBR_SetWetHeuristicsEnabled(bool enabled) {
    s_pbr_wet_heuristics_enabled = enabled;
}

void Godot_PBR_SetMaterialDepthEnabled(bool enabled) {
    s_pbr_material_depth_enabled = enabled;
}

void Godot_PBR_SetMaterialDepthOverdriveEnabled(bool enabled) {
    s_pbr_material_depth_overdrive_enabled = enabled;
}

void Godot_PBR_SetDepthNormalScale(float scale) {
    s_pbr_depth_normal_scale = clampf(scale, 0.1f, 4.0f);
}

void Godot_PBR_SetDepthRoughnessMul(float mul) {
    s_pbr_depth_roughness_mul = clampf(mul, 0.2f, 3.0f);
}

void Godot_PBR_SetDepthSpecularMul(float mul) {
    s_pbr_depth_specular_mul = clampf(mul, 0.2f, 3.0f);
}

void Godot_PBR_SetDepthMetallicMul(float mul) {
    s_pbr_depth_metallic_mul = clampf(mul, 0.2f, 3.0f);
}

const PBRTextureSet *Godot_PBR_Find(const char *engine_texture_path) {
    if (!s_pbr_enabled || !engine_texture_path || !engine_texture_path[0]) {
        return nullptr;
    }

    std::string key = normalise_key(engine_texture_path);
    if (key.empty()) return nullptr;

    /* Check loaded cache first */
    auto cache_it = s_pbr_cache.find(key);
    if (cache_it != s_pbr_cache.end()) {
        return cache_it->second.loaded ? &cache_it->second : nullptr;
    }

    /* Check if we have paths for this texture */
    auto path_it = s_pbr_paths.find(key);
    if (path_it == s_pbr_paths.end()) {
        /* Cache negative result */
        PBRTextureSet empty;
        empty.loaded = false;
        s_pbr_cache[key] = empty;
        return nullptr;
    }

    /* Load the PBR textures from disk */
    const PBRFilePaths &paths = path_it->second;
    PBRTextureSet set;
    set.loaded = false;

    set.is_metallic = false;
    set.is_emissive = false;
    set.is_wet = false;

    set.albedo = load_png_from_disk(String(paths.albedo_path.c_str()));
    if (set.albedo.is_valid()) {
        set.loaded = true;
    }

    set.normal = load_png_from_disk(String(paths.normal_path.c_str()));
    set.roughness = load_png_from_disk(String(paths.roughness_path.c_str()));
    set.emission = load_png_from_disk(String(paths.emission_path.c_str()));

    if (s_pbr_procedural_normals_enabled && !set.normal.is_valid() && set.albedo.is_valid()) {
        set.normal = generate_normal_from_albedo(set.albedo);
    }

    /* ── Material heuristics from texture path keywords ── */

    /* Metal detection: textures whose names suggest metallic surfaces. */
    static const char *metal_keywords[] = {
        "metal", "steel", "iron", "brass", "copper", "chrome",
        "alumin", "grill", "pipe", "vent", "railing", "hatch",
        "rivet", "girder", "tank", "hull", "barrel", "gun",
        nullptr
    };
    for (const char **kw = metal_keywords; *kw; kw++) {
        if (key.find(*kw) != std::string::npos) {
            set.is_metallic = true;
            break;
        }
    }

    /* Emission detection: textures that represent light sources. */
    static const char *emissive_keywords[] = {
        "light", "lamp", "bulb", "glow", "neon", "fire",
        "flame", "lava", "screen", "monitor", "electric",
        "spark", "corona", "flare", "lantern", "candle",
        nullptr
    };
    for (const char **kw = emissive_keywords; *kw; kw++) {
        if (key.find(*kw) != std::string::npos) {
            set.is_emissive = true;
            break;
        }
    }

    /* Wetness detection: rain/damp/water-like surfaces benefit from
     * lower roughness and stronger specular highlights. */
    static const char *wet_keywords[] = {
        "wet", "water", "puddle", "mud", "damp", "rain",
        "leak", "drip", "slime", "slick", "stream", "flood",
        nullptr
    };
    for (const char **kw = wet_keywords; *kw; kw++) {
        if (key.find(*kw) != std::string::npos) {
            set.is_wet = true;
            break;
        }
    }

    s_pbr_cache[key] = set;

    if (set.loaded) {
        return &s_pbr_cache[key];
    }

    return nullptr;
}

bool Godot_PBR_ApplyToMaterial(Ref<StandardMaterial3D> &mat,
                               const char *engine_texture_path)
{
    if (!mat.is_valid() || !Godot_PBR_IsEnabled()) return false;

    const PBRTextureSet *pbr = Godot_PBR_Find(engine_texture_path);
    if (!pbr || !pbr->loaded) {
        s_pbr_missed++;
        return false;
    }

    s_pbr_applied++;

    /* Print a summary after the first batch of applications */
    if (!s_pbr_summary_printed && (s_pbr_applied + s_pbr_missed) >= 10) {
        UtilityFunctions::print(String("[PBR] Application summary: ") +
                               String::num_int64(s_pbr_applied) + String(" applied, ") +
                               String::num_int64(s_pbr_missed) + String(" missed, of ") +
                               String::num_int64(s_pbr_count) + String(" available sets."));
        s_pbr_summary_printed = true;
    }

    /* Apply HD albedo (replaces the original low-res diffuse) */
    if (pbr->albedo.is_valid()) {
        mat->set_texture(BaseMaterial3D::TEXTURE_ALBEDO, pbr->albedo);
    }

    /* Apply normal map */
    const float depth_overdrive_normal_mul = s_pbr_material_depth_overdrive_enabled ? 1.8f : 1.0f;
    const float depth_overdrive_spec_mul = s_pbr_material_depth_overdrive_enabled ? 1.30f : 1.0f;
    const float depth_overdrive_rough_mul = s_pbr_material_depth_overdrive_enabled ? 0.72f : 1.0f;
    const float depth_overdrive_metal_mul = s_pbr_material_depth_overdrive_enabled ? 1.20f : 1.0f;

    if (pbr->normal.is_valid() && s_pbr_material_depth_enabled) {
        mat->set_feature(BaseMaterial3D::FEATURE_NORMAL_MAPPING, true);
        mat->set_texture(BaseMaterial3D::TEXTURE_NORMAL, pbr->normal);
        float normal_scale = s_pbr_depth_normal_scale * depth_overdrive_normal_mul;
        mat->set_normal_scale(clampf(normal_scale, 0.1f, 6.0f));
    }

    /* Apply roughness map */
    if (pbr->roughness.is_valid()) {
        mat->set_texture(BaseMaterial3D::TEXTURE_ROUGHNESS, pbr->roughness);
        /* The roughness texture channel — greyscale stored in R */
        mat->set_roughness_texture_channel(BaseMaterial3D::TEXTURE_CHANNEL_GRAYSCALE);
    } else {
        /* No roughness texture — use a reasonable default */
        float rough = 0.8f;
        if (s_pbr_material_depth_enabled) {
            rough *= s_pbr_depth_roughness_mul * depth_overdrive_rough_mul;
        }
        mat->set_roughness(clampf(rough, 0.03f, 1.0f));
    }

    /* ── Metallic / specular heuristics ── */
    if (pbr->is_metallic) {
        float metallic = 0.7f;
        float specular = 0.8f;
        if (s_pbr_material_depth_enabled) {
            metallic *= s_pbr_depth_metallic_mul * depth_overdrive_metal_mul;
            specular *= s_pbr_depth_specular_mul * depth_overdrive_spec_mul;
        }
        mat->set_metallic(clampf(metallic, 0.0f, 1.0f));
        mat->set_specular(clampf(specular, 0.0f, 1.0f));
        if (!pbr->roughness.is_valid()) {
            float rough = 0.35f;
            if (s_pbr_material_depth_enabled) {
                rough *= s_pbr_depth_roughness_mul * depth_overdrive_rough_mul;
            }
            mat->set_roughness(clampf(rough, 0.03f, 1.0f));
        }
    } else {
        mat->set_metallic(0.0f);
        float specular = 0.5f;
        if (s_pbr_material_depth_enabled) {
            specular *= s_pbr_depth_specular_mul * depth_overdrive_spec_mul;
        }
        mat->set_specular(clampf(specular, 0.0f, 1.0f));
    }

    /* Wet materials: strong highlights, smoother micro-surface.
     * Keeps metallic at 0 while boosting reflective response. */
    if (s_pbr_wet_heuristics_enabled && pbr->is_wet) {
        mat->set_metallic(0.0f);
        float wet_spec = 0.9f;
        if (s_pbr_material_depth_enabled) {
            wet_spec *= s_pbr_depth_specular_mul * depth_overdrive_spec_mul;
        }
        mat->set_specular(clampf(wet_spec, 0.0f, 1.0f));
        if (pbr->roughness.is_valid()) {
            float rough = 0.22f;
            if (s_pbr_material_depth_enabled) {
                rough *= s_pbr_depth_roughness_mul * depth_overdrive_rough_mul;
            }
            mat->set_roughness(clampf(rough, 0.02f, 1.0f));
        } else {
            float rough = 0.28f;
            if (s_pbr_material_depth_enabled) {
                rough *= s_pbr_depth_roughness_mul * depth_overdrive_rough_mul;
            }
            mat->set_roughness(clampf(rough, 0.02f, 1.0f));
        }
    }

    /* ── Emission (self-illumination for lights, screens, fire) ── */
    if (pbr->is_emissive) {
        mat->set_feature(BaseMaterial3D::FEATURE_EMISSION, true);
        if (pbr->emission.is_valid()) {
            mat->set_texture(BaseMaterial3D::TEXTURE_EMISSION, pbr->emission);
        } else {
            /* Use albedo as emission source — the whole texture glows */
            mat->set_texture(BaseMaterial3D::TEXTURE_EMISSION, pbr->albedo);
        }
        mat->set_emission(Color(1.0, 0.95, 0.85));  /* Warm white */
        mat->set_emission_energy_multiplier(2.0);
    }

    /* Shading mode is already PER_PIXEL from the BSP/entity material
     * creation — no need to change it here.  PBR enhancements (normal
     * maps, roughness, metallic) work on top of the lit material. */

    return true;
}

int Godot_PBR_GetCount() {
    return s_pbr_count;
}
