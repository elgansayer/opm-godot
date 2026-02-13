/*
 * godot_weapon_viewport.h — SubViewport weapon rendering manager.
 *
 * Phase 62: First-person weapons (RF_FIRST_PERSON + RF_DEPTHHACK) are
 * rendered into a separate SubViewport and composited over the main view.
 * This gives correct self-occlusion for complex weapon models without
 * the depth-test disable hack.
 *
 * Scene tree layout (created by MoHAARunner during setup_3d_scene):
 *
 *   MoHAARunner (Node)
 *     game_world (Node3D)
 *       camera (Camera3D)           <- main camera
 *       entity_root (Node3D)        <- world entities
 *     weapon_viewport (SubViewport) <- NEW: weapon rendering
 *       weapon_camera (Camera3D)    <- copies main camera transform
 *       weapon_root (Node3D)        <- RF_FIRST_PERSON entities go here
 *     weapon_overlay (CanvasLayer)  <- NEW: composites weapon_viewport
 *       weapon_rect (TextureRect)   <- ViewportTexture from weapon_viewport
 *
 * MoHAARunner Integration Required:
 *   1. In setup_3d_scene(): call Godot_WeaponViewport_Create() to build
 *      the SubViewport + overlay nodes. Pass the main camera and runner node.
 *   2. In update_entities(): for entities with RF_FIRST_PERSON (0x04) or
 *      RF_DEPTHHACK (0x08), reparent their MeshInstance3D to the weapon_root
 *      returned by Godot_WeaponViewport_GetRoot() instead of entity_root.
 *   3. In _process(): call Godot_WeaponViewport_SyncCamera() to copy the
 *      main camera's transform/FOV to the weapon camera each frame.
 *   4. On shutdown: call Godot_WeaponViewport_Destroy() for cleanup.
 */

#ifndef GODOT_WEAPON_VIEWPORT_H
#define GODOT_WEAPON_VIEWPORT_H

#include <godot_cpp/classes/node.hpp>
#include <godot_cpp/classes/node3d.hpp>
#include <godot_cpp/classes/camera3d.hpp>
#include <godot_cpp/classes/sub_viewport.hpp>
#include <godot_cpp/classes/canvas_layer.hpp>
#include <godot_cpp/classes/texture_rect.hpp>

using namespace godot;

/*
 * Godot_WeaponViewport — manages the SubViewport pipeline for weapons.
 *
 * Singleton; created once during scene setup, destroyed on shutdown.
 */
class Godot_WeaponViewport {
public:
    static Godot_WeaponViewport &get();

    /*
     * Create the SubViewport, weapon Camera3D, weapon root Node3D,
     * CanvasLayer, and TextureRect overlay.
     *
     * @param runner      The MoHAARunner node (parent for viewport + overlay)
     * @param main_camera The main scene camera (transform is copied each frame)
     * @param width       Viewport width in pixels
     * @param height      Viewport height in pixels
     */
    void create(Node *runner, Camera3D *main_camera,
                int width, int height);

    /*
     * Destroy all created nodes and reset state.
     */
    void destroy();

    /*
     * Sync weapon camera transform and FOV from the main camera.
     * Call once per frame in _process().
     */
    void sync_camera();

    /*
     * Get the Node3D root where weapon entities should be parented.
     * Returns nullptr if the viewport hasn't been created.
     */
    Node3D *get_weapon_root() const { return weapon_root_; }

    /*
     * Get the SubViewport node (for resize handling etc.).
     */
    SubViewport *get_viewport() const { return viewport_; }

    /*
     * Check if the viewport system has been created.
     */
    bool is_created() const { return created_; }

    /*
     * Resize the weapon viewport (e.g. when window size changes).
     */
    void resize(int width, int height);

private:
    Godot_WeaponViewport() : created_(false), viewport_(nullptr),
                              weapon_camera_(nullptr), weapon_root_(nullptr),
                              overlay_(nullptr), overlay_rect_(nullptr),
                              main_camera_(nullptr) {}

    bool         created_;
    SubViewport *viewport_;
    Camera3D    *weapon_camera_;
    Node3D      *weapon_root_;
    CanvasLayer *overlay_;
    TextureRect *overlay_rect_;
    Camera3D    *main_camera_;
};

#endif /* GODOT_WEAPON_VIEWPORT_H */
