/*
 * godot_skel_model.h — Skeletal model cache for the Godot GDExtension.
 *
 * Builds Godot ArrayMesh instances from engine TIKI/SKD skeletal model
 * data.  Meshes are cached per hModel so geometry is only extracted once.
 *
 * Phase 9 — Skeletal model rendering.
 */

#ifndef GODOT_SKEL_MODEL_H
#define GODOT_SKEL_MODEL_H

#include <godot_cpp/classes/array_mesh.hpp>
#include <godot_cpp/classes/image_texture.hpp>
#include <godot_cpp/variant/string.hpp>

#include <unordered_map>
#include <vector>

using namespace godot;

class GodotSkelModelCache {
public:
    /* Per-surface shader name + material state */
    struct SurfaceInfo {
        String shader_name;   /* e.g. "models/weapons/m1_garand/gun" */
    };

    /* Cached model = mesh + per-surface shader names + scale */
    struct CachedModel {
        Ref<ArrayMesh>            mesh;
        std::vector<SurfaceInfo>  surfaces;
        float                     tiki_scale;    /* dtiki_t::load_scale */
    };

    /* Singleton access */
    static GodotSkelModelCache &get();

    /* Build (or return cached) mesh for a TIKI model handle.
     * Returns nullptr if hModel is invalid or not a TIKI model. */
    const CachedModel *get_model(int hModel);

    /* Clear the cache (call on map change / shutdown). */
    void clear();

private:
    std::unordered_map<int, CachedModel> cache_;

    /* Build a new CachedModel from engine data.  Returns nullptr on failure. */
    CachedModel *build_model(int hModel);
};

#endif /* GODOT_SKEL_MODEL_H */
