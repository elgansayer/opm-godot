/*
 * godot_skel_model.cpp — Skeletal model cache for the Godot GDExtension.
 *
 * Reads engine TIKI/SKD skeletal model data via C accessors
 * (godot_skel_model_accessors.cpp) and builds Godot ArrayMesh instances
 * with correct geometry, normals, and UV coordinates.
 *
 * Coordinate conversion:
 *   Godot.x = -id.Y    Godot.y = id.Z    Godot.z = -id.X
 *   Scale: id inches → Godot metres (÷ 39.37)
 *
 * Phase 9 — Skeletal model rendering.
 */

#include "godot_skel_model.h"

#include <godot_cpp/classes/array_mesh.hpp>
#include <godot_cpp/classes/surface_tool.hpp>
#include <godot_cpp/variant/packed_vector3_array.hpp>
#include <godot_cpp/variant/packed_vector2_array.hpp>
#include <godot_cpp/variant/packed_int32_array.hpp>
#include <godot_cpp/variant/utility_functions.hpp>

#include <cstring>
#include <cstdlib>

/* ── C accessor declarations (godot_skel_model_accessors.cpp + godot_renderer.c) ── */
extern "C" {
    /* From godot_renderer.c */
    void *Godot_Model_GetTikiPtr(int hModel);
    int   Godot_Model_GetType(int hModel);

    /* From godot_skel_model_accessors.cpp */
    int         Godot_Skel_GetMeshCount(void *tikiPtr);
    float       Godot_Skel_GetScale(void *tikiPtr);
    void        Godot_Skel_GetOrigin(void *tikiPtr, float *out);
    int         Godot_Skel_GetSurfaceCount(void *tikiPtr, int meshIndex);
    int         Godot_Skel_GetSurfaceInfo(void *tikiPtr, int meshIndex, int surfIndex,
                                           int *numVerts, int *numTriangles,
                                           char *surfName, int surfNameLen,
                                           char *shaderName, int shaderNameLen);
    int         Godot_Skel_GetSurfaceVertices(void *tikiPtr, int meshIndex, int surfIndex,
                                               float *positions, float *normals, float *texcoords);
    int         Godot_Skel_GetSurfaceIndices(void *tikiPtr, int meshIndex, int surfIndex,
                                              int *indices);
    int         Godot_Skel_GetBoneCount(void *tikiPtr, int meshIndex);
    int         Godot_Skel_GetBoneParent(void *tikiPtr, int meshIndex, int boneIndex);
    const char *Godot_Skel_GetName(void *tikiPtr);
}

/* ── Coordinate conversion (id → Godot) ── */
static const float MOHAA_UNIT_SCALE = 1.0f / 39.37f;  /* inches to metres */

static inline Vector3 id_to_godot_point(float ix, float iy, float iz)
{
    return Vector3(-iy, iz, -ix);
}

static inline Vector3 id_to_godot_normal(float nx, float ny, float nz)
{
    /* Normals use the same axis re-mapping but no scale */
    return Vector3(-ny, nz, -nx);
}

/* ── Singleton ── */
GodotSkelModelCache &GodotSkelModelCache::get()
{
    static GodotSkelModelCache instance;
    return instance;
}

void GodotSkelModelCache::clear()
{
    cache_.clear();
}

const GodotSkelModelCache::CachedModel *GodotSkelModelCache::get_model(int hModel)
{
    /* Check cache first */
    auto it = cache_.find(hModel);
    if (it != cache_.end()) {
        return &it->second;
    }

    /* Build and cache */
    CachedModel *built = build_model(hModel);
    if (!built) return nullptr;

    return &cache_[hModel];
}

GodotSkelModelCache::CachedModel *GodotSkelModelCache::build_model(int hModel)
{
    /* Validate model type */
    int modType = Godot_Model_GetType(hModel);
    if (modType != 2 /* GR_MOD_TIKI */) return nullptr;

    void *tikiPtr = Godot_Model_GetTikiPtr(hModel);
    if (!tikiPtr) return nullptr;

    int meshCount = Godot_Skel_GetMeshCount(tikiPtr);
    if (meshCount <= 0) return nullptr;

    float tikiScale = Godot_Skel_GetScale(tikiPtr);
    float loadOrigin[3] = {0, 0, 0};
    Godot_Skel_GetOrigin(tikiPtr, loadOrigin);

    /* Pre-compute the load origin in Godot space */
    Vector3 originOffset = id_to_godot_point(loadOrigin[0], loadOrigin[1], loadOrigin[2])
                           * tikiScale * MOHAA_UNIT_SCALE;

    CachedModel &model = cache_[hModel];
    model.tiki_scale = tikiScale;

    Ref<ArrayMesh> arrayMesh;
    arrayMesh.instantiate();

    int totalVerts = 0;
    int totalTris  = 0;
    static bool logged_first = false;

    /* Iterate all meshes and all surfaces */
    for (int mesh = 0; mesh < meshCount; mesh++) {
        int surfCount = Godot_Skel_GetSurfaceCount(tikiPtr, mesh);

        for (int surf = 0; surf < surfCount; surf++) {
            int numVerts = 0, numTris = 0;
            char surfName[64]   = {0};
            char shaderName[64] = {0};

            if (!Godot_Skel_GetSurfaceInfo(tikiPtr, mesh, surf,
                                            &numVerts, &numTris,
                                            surfName, sizeof(surfName),
                                            shaderName, sizeof(shaderName))) {
                continue;
            }

            if (numVerts <= 0 || numTris <= 0) continue;

            /* Allocate temp buffers for vertex data */
            float *positions = (float *)malloc(numVerts * 3 * sizeof(float));
            float *normals   = (float *)malloc(numVerts * 3 * sizeof(float));
            float *texcoords = (float *)malloc(numVerts * 2 * sizeof(float));
            int   *indices   = (int *)malloc(numTris * 3 * sizeof(int));

            if (!positions || !normals || !texcoords || !indices) {
                free(positions); free(normals); free(texcoords); free(indices);
                continue;
            }

            if (!Godot_Skel_GetSurfaceVertices(tikiPtr, mesh, surf,
                                                positions, normals, texcoords)) {
                free(positions); free(normals); free(texcoords); free(indices);
                continue;
            }

            if (!Godot_Skel_GetSurfaceIndices(tikiPtr, mesh, surf, indices)) {
                free(positions); free(normals); free(texcoords); free(indices);
                continue;
            }

            /* Build Godot PackedArrays with coordinate conversion */
            PackedVector3Array godotPositions;
            PackedVector3Array godotNormals;
            PackedVector2Array godotUVs;
            PackedInt32Array   godotIndices;

            godotPositions.resize(numVerts);
            godotNormals.resize(numVerts);
            godotUVs.resize(numVerts);
            godotIndices.resize(numTris * 3);

            for (int v = 0; v < numVerts; v++) {
                float px = positions[v * 3 + 0];
                float py = positions[v * 3 + 1];
                float pz = positions[v * 3 + 2];

                /* Apply tiki load_scale then convert id→Godot.
                 * load_origin is handled at the entity level via transform,
                 * since the mesh is in model-local space. */
                Vector3 pos = id_to_godot_point(px, py, pz) * tikiScale * MOHAA_UNIT_SCALE;

                float nx = normals[v * 3 + 0];
                float ny = normals[v * 3 + 1];
                float nz = normals[v * 3 + 2];
                Vector3 nrm = id_to_godot_normal(nx, ny, nz);
                /* Normalise to handle any engine quirks */
                if (nrm.length_squared() > 0.001f) {
                    nrm = nrm.normalized();
                }

                float u = texcoords[v * 2 + 0];
                float vt = texcoords[v * 2 + 1];

                godotPositions.set(v, pos);
                godotNormals.set(v, nrm);
                godotUVs.set(v, Vector2(u, vt));
            }

            /* Copy indices — winding order may need reversing due to
             * coordinate system change (right-hand → left-hand swap).
             * Id Tech 3 uses CW front face; Godot uses CCW.
             * The axis remapping flips handedness, so we reverse winding. */
            for (int t = 0; t < numTris; t++) {
                godotIndices.set(t * 3 + 0, indices[t * 3 + 0]);
                godotIndices.set(t * 3 + 1, indices[t * 3 + 2]);
                godotIndices.set(t * 3 + 2, indices[t * 3 + 1]);
            }

            /* Build ArrayMesh surface */
            Array arrays;
            arrays.resize(Mesh::ARRAY_MAX);
            arrays[Mesh::ARRAY_VERTEX] = godotPositions;
            arrays[Mesh::ARRAY_NORMAL] = godotNormals;
            arrays[Mesh::ARRAY_TEX_UV] = godotUVs;
            arrays[Mesh::ARRAY_INDEX]  = godotIndices;

            arrayMesh->add_surface_from_arrays(Mesh::PRIMITIVE_TRIANGLES, arrays);

            /* Track surface shader info */
            SurfaceInfo sinfo;
            sinfo.shader_name = String(shaderName);
            model.surfaces.push_back(sinfo);

            totalVerts += numVerts;
            totalTris  += numTris;

            free(positions);
            free(normals);
            free(texcoords);
            free(indices);
        }
    }

    if (arrayMesh->get_surface_count() == 0) {
        cache_.erase(hModel);
        return nullptr;
    }

    model.mesh = arrayMesh;

    /* Log first successful model build */
    if (!logged_first) {
        const char *name = Godot_Skel_GetName(tikiPtr);
        UtilityFunctions::print(
            String("[MoHAA] First skeletal model built: ") + String(name) +
            String(" — ") + String::num_int64(totalVerts) + String(" verts, ") +
            String::num_int64(totalTris) + String(" tris, ") +
            String::num_int64(arrayMesh->get_surface_count()) + String(" surfaces")
        );
        logged_first = true;
    }

    return &model;
}
