/* godot_pbr.h — PBR texture discovery and material enhancement
 *
 * Scans the zgodot_pbr_project/mohaa-hd-assets/ directory (or any
 * configured PBR asset directory) for HD PBR texture variants:
 *   {basename}_albedo.png   — HD diffuse/albedo (replaces original)
 *   {basename}_normal-0.png — Normal map (OpenGL convention)
 *   {basename}_roughness.png — Roughness map
 *
 * The mapping is based on the engine's texture path convention:
 *   textures/french/dyer.tga → textures/french/dyer_albedo.png, etc.
 *
 * PBR mode is toggled via the r_pbr cvar (default: 1 = enabled).
 * When enabled, materials are switched from UNSHADED to lit mode
 * with normal/roughness maps applied.
 */

#ifndef GODOT_PBR_H
#define GODOT_PBR_H

#include <godot_cpp/classes/image_texture.hpp>
#include <godot_cpp/classes/standard_material3d.hpp>

using namespace godot;

/* PBR texture set for a single engine texture */
struct PBRTextureSet {
    Ref<ImageTexture> albedo;       /* HD albedo (replaces original diffuse) */
    Ref<ImageTexture> normal;       /* Normal map */
    Ref<ImageTexture> roughness;    /* Roughness map (greyscale) */
    Ref<ImageTexture> emission;     /* Emission map (self-illumination) */
    bool loaded;                    /* True if at least the albedo was loaded */
    bool is_metallic;               /* Heuristic: texture name implies metal */
    bool is_emissive;               /* Heuristic: texture name implies light source */
    bool is_wet;                    /* Heuristic: wet/water/puddle-like surface */
};

/* Initialise the PBR system: scan the PBR asset directory and build
 * the mapping from engine texture base names to PBR file paths.
 * Called once during map load (after Com_Init). */
void Godot_PBR_Init();

/* Shut down and free all cached PBR textures.
 * Called on map change / shutdown. */
void Godot_PBR_Shutdown();

/* Returns true if PBR mode is enabled (r_pbr cvar). */
bool Godot_PBR_IsEnabled();
void Godot_PBR_SetEnabled(bool enabled);
void Godot_PBR_SetProceduralNormalsEnabled(bool enabled);
void Godot_PBR_SetWetHeuristicsEnabled(bool enabled);

/* Look up PBR textures for an engine texture path.
 * |engine_texture_path| is the qpath used by the engine, e.g.
 * "textures/french/dyer" or "textures/french/dyer.tga".
 * Returns a pointer to the PBR texture set, or nullptr if no PBR
 * textures exist for this path.  The returned pointer is valid
 * until Godot_PBR_Shutdown() is called. */
const PBRTextureSet *Godot_PBR_Find(const char *engine_texture_path);

/* Apply PBR textures to a StandardMaterial3D.
 * If PBR textures exist for |engine_texture_path|:
 *   - Replaces albedo with HD albedo (if available)
 *   - Sets normal map
 *   - Sets roughness texture
 *   - Switches shading mode from UNSHADED to per-pixel lit
 *   - Sets metallic to 0 (non-metallic — most game surfaces)
 * Returns true if PBR was applied, false if no PBR textures found. */
bool Godot_PBR_ApplyToMaterial(Ref<StandardMaterial3D> &mat,
                               const char *engine_texture_path);

/* Get the number of PBR texture sets discovered. */
int Godot_PBR_GetCount();

#endif /* GODOT_PBR_H */
