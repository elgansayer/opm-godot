/*
 * godot_bsp_mesh.h — MOHAA BSP world loader for the Godot GDExtension.
 *
 * Reads a MOHAA BSP file (ident "2015", versions 17–21) via the engine's
 * VFS and creates Godot MeshInstance3D/ArrayMesh nodes for the world
 * geometry.  Handles MST_PLANAR, MST_TRIANGLE_SOUP, MST_PATCH, and
 * MOHAA terrain patches (LUMP_TERRAIN).
 *
 * Also parses:
 *   - LUMP_STATICMODELDEF (25) — static TIKI model placements
 *   - LUMP_MODELS (13) — inline brush sub-models for doors/movers
 *   - LUMP_FOGS (13 in BSP ≤18) — per-surface fog volumes
 *   - Fullbright/nolightmap surfaces (SURF_NOLIGHTMAP flag)
 *   - Portal surfaces (surfaceparm portal)
 *   - Flare surfaces (MST_FLARE type)
 *
 * Coordinate conversion from id Tech 3 (X=Forward, Y=Left, Z=Up) to
 * Godot (X=Right, Y=Up, -Z=Forward) and unit scaling from inches to
 * metres (1/39.37) is applied to all vertex data.
 */

#ifndef GODOT_BSP_MESH_H
#define GODOT_BSP_MESH_H

#include <godot_cpp/classes/node3d.hpp>
#include <godot_cpp/classes/array_mesh.hpp>

/* ── Static model definition from BSP LUMP_STATICMODELDEF ── */
struct BSPStaticModelDef {
    char  model[128];     /* TIKI path, e.g. "static/bush_full.tik" */
    float origin[3];      /* world-space position (id coordinates) */
    float angles[3];      /* [pitch, yaw, roll] in degrees */
    float scale;          /* additional instance scale factor */
};

/// Load a MOHAA BSP file from the engine VFS and return a Node3D tree
/// containing MeshInstance3D children with the world geometry.
/// Also parses static model definitions and brush sub-models.
/// @param bsp_path  Engine-relative path, e.g. "maps/DM/mohdm1.bsp"
/// @return  Owning pointer to a Node3D, or nullptr on failure.
///          Caller is responsible for adding it to the scene tree
///          (or calling memdelete).
godot::Node3D *Godot_BSP_LoadWorld(const char *bsp_path);

/// Free any internally cached data from a previous load.
void Godot_BSP_Unload();

/// Get the number of static model definitions from the last BSP load.
int Godot_BSP_GetStaticModelCount();

/// Get a static model definition by index (0-based).
/// Returns nullptr if index is out of range.
const BSPStaticModelDef *Godot_BSP_GetStaticModelDef(int index);

/// Get the number of brush sub-models (excluding model 0, the world).
int Godot_BSP_GetBrushModelCount();

/// Get the pre-built ArrayMesh for a brush sub-model (1-based index).
/// Returns an empty Ref if the index is out of range or the mesh is empty.
godot::Ref<godot::ArrayMesh> Godot_BSP_GetBrushModelMesh(int submodelIndex);

/* ── Phase 78: BSP fog volume definition ── */
struct BSPFogVolume {
    char  shader[64];       /* Fog shader name */
    int   brushNum;         /* BSP brush defining the fog region */
    int   visibleSide;      /* Brush side for ray tests (-1 = none) */
    float color[3];         /* Fog colour (RGB, 0–1) — from shader props */
    float depthForOpaque;   /* Distance for full opacity — from shader props */
};

/// Get the number of fog volumes parsed from the BSP.
int Godot_BSP_GetFogVolumeCount();

/// Get a fog volume definition by index (0-based).
/// Returns nullptr if index is out of range.
const BSPFogVolume *Godot_BSP_GetFogVolume(int index);

/* ── Phase 74: Flare surface definition ── */
struct BSPFlare {
    float origin[3];        /* Flare position in Godot coordinates */
    float color[3];         /* Flare colour (RGB, 0–1) */
    char  shader[64];       /* Shader name for flare texture */
};

/// Get the number of flare surfaces parsed from the BSP.
int Godot_BSP_GetFlareCount();

/// Get a flare definition by index (0-based).
/// Returns nullptr if index is out of range.
const BSPFlare *Godot_BSP_GetFlare(int index);

#ifdef __cplusplus
extern "C" {
#endif

/* Phase 65: Check if a BSP surface has a lightmap (nolightmap flag check) */
int Godot_BSP_SurfaceHasLightmap(int surface_index);

/* Phase 18: Entity token parser */
int Godot_BSP_GetEntityToken(char *buffer, int bufferSize);
void Godot_BSP_ResetEntityTokenParse(void);

/* Phase 47: Raw entity string accessor (for speaker entity parsing) */
const char *Godot_BSP_GetEntityString(void);

/* Phase 19: Inline model bounds */
void Godot_BSP_GetInlineModelBounds(int index, float *mins, float *maxs);

/* Phase 20: Map version */
int Godot_BSP_GetMapVersion(void);

/* Phase 28: Lightgrid sampling */
int Godot_BSP_LightForPoint(const float point[3], float ambientLight[3],
                            float directedLight[3], float lightDir[3]);

/* Phase 31: PVS visibility */
int Godot_BSP_InPVS(const float p1[3], const float p2[3]);

/* PVS cluster queries */
int Godot_BSP_PointLeaf(const float pt[3]);
int Godot_BSP_PointCluster(const float pt[3]);
int Godot_BSP_ClusterVisible(int source, int target);
int Godot_BSP_GetNumClusters(void);

/// Mark-fragment query: clip a decal polygon against the world BSP.
/// Output arrays (fragFirstPoint, fragNumPoints, fragIIndex) must
/// each be at least maxFragments entries.
/// Returns the number of fragments produced.
int Godot_BSP_MarkFragments(
    int numPoints, const float points[][3], const float projection[3],
    int maxPoints, float *pointBuffer,
    int maxFragments,
    int *fragFirstPoint, int *fragNumPoints, int *fragIIndex,
    float fRadiusSquared);

/// Mark-fragment query for an inline brush model (door/mover).
/// vAngles/vOrigin describe the model's current pose.
int Godot_BSP_MarkFragmentsForInlineModel(
    int bmodelIndex,
    const float vAngles[3], const float vOrigin[3],
    int numPoints, const float points[][3], const float projection[3],
    int maxPoints, float *pointBuffer,
    int maxFragments,
    int *fragFirstPoint, int *fragNumPoints, int *fragIIndex,
    float fRadiusSquared);

#ifdef __cplusplus
}
#endif

/* PVS cluster mesh accessors (C++ only — return Godot types) */
#ifdef __cplusplus
int Godot_BSP_GetPVSNumClusters();
godot::MeshInstance3D *Godot_BSP_GetClusterMesh(int cluster);
#endif

#endif // GODOT_BSP_MESH_H
