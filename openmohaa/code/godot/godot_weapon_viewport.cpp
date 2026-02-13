/*
 * godot_weapon_viewport.cpp — SubViewport weapon rendering manager.
 *
 * Phase 62: First-person weapon rendering via SubViewport compositing.
 */

#include "godot_weapon_viewport.h"

#include <godot_cpp/classes/viewport_texture.hpp>
#include <godot_cpp/classes/environment.hpp>
#include <godot_cpp/classes/world3d.hpp>
#include <godot_cpp/variant/utility_functions.hpp>

Godot_WeaponViewport &Godot_WeaponViewport::get()
{
    static Godot_WeaponViewport instance;
    return instance;
}

void Godot_WeaponViewport::create(Node *runner, Camera3D *main_camera,
                                   int width, int height)
{
    if (created_ || !runner || !main_camera) return;

    main_camera_ = main_camera;

    /* 1. Create SubViewport */
    viewport_ = memnew(SubViewport);
    viewport_->set_name("weapon_viewport");
    viewport_->set_size(Vector2i(width, height));
    viewport_->set_transparent_background(true);
    viewport_->set_clear_mode(SubViewport::CLEAR_MODE_ALWAYS);
    viewport_->set_update_mode(SubViewport::UPDATE_ALWAYS);

    /*
     * Share the main camera's World3D so that world lighting and
     * environment affect the weapon viewport.  The weapon entities
     * render in the same 3D world but are composited on top.
     *
     * NOTE: For full isolation, use a separate World3D instead.
     * Sharing avoids duplicating all light/environment setup.
     */
    Ref<World3D> main_world = main_camera->get_world_3d();
    if (main_world.is_valid()) {
        viewport_->set_world_3d(main_world);
    }

    runner->add_child(viewport_);

    /* 2. Create weapon Camera3D inside the SubViewport */
    weapon_camera_ = memnew(Camera3D);
    weapon_camera_->set_name("weapon_camera");
    weapon_camera_->set_current(true);
    viewport_->add_child(weapon_camera_);

    /* 3. Create weapon root Node3D */
    weapon_root_ = memnew(Node3D);
    weapon_root_->set_name("weapon_root");
    viewport_->add_child(weapon_root_);

    /* 4. Create CanvasLayer for overlay compositing */
    overlay_ = memnew(CanvasLayer);
    overlay_->set_name("weapon_overlay");
    overlay_->set_layer(10);  /* render on top */
    runner->add_child(overlay_);

    /* 5. Create TextureRect to display the weapon viewport */
    overlay_rect_ = memnew(TextureRect);
    overlay_rect_->set_name("weapon_rect");
    overlay_rect_->set_anchors_preset(Control::PRESET_FULL_RECT);
    overlay_rect_->set_stretch_mode(TextureRect::STRETCH_SCALE);
    overlay_rect_->set_texture(viewport_->get_texture());
    overlay_->add_child(overlay_rect_);

    created_ = true;

    UtilityFunctions::print(
        String("[MoHAA] Weapon SubViewport created: ") +
        String::num_int64(width) + String("x") +
        String::num_int64(height)
    );
}

void Godot_WeaponViewport::destroy()
{
    if (!created_) return;

    /* Nodes are freed by their parent when removed from the tree,
     * but we explicitly queue_free to be safe. */
    if (overlay_rect_) {
        overlay_rect_->queue_free();
        overlay_rect_ = nullptr;
    }
    if (overlay_) {
        overlay_->queue_free();
        overlay_ = nullptr;
    }
    if (weapon_root_) {
        weapon_root_->queue_free();
        weapon_root_ = nullptr;
    }
    if (weapon_camera_) {
        weapon_camera_->queue_free();
        weapon_camera_ = nullptr;
    }
    if (viewport_) {
        viewport_->queue_free();
        viewport_ = nullptr;
    }

    main_camera_ = nullptr;
    created_ = false;
}

void Godot_WeaponViewport::sync_camera()
{
    if (!created_ || !main_camera_ || !weapon_camera_) return;

    /* Copy transform and projection from the main camera */
    weapon_camera_->set_global_transform(main_camera_->get_global_transform());
    weapon_camera_->set_fov(main_camera_->get_fov());
    weapon_camera_->set_near(main_camera_->get_near());
    weapon_camera_->set_far(main_camera_->get_far());
}

void Godot_WeaponViewport::resize(int width, int height)
{
    if (!created_ || !viewport_) return;
    viewport_->set_size(Vector2i(width, height));
}
