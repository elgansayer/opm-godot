/*
 * godot_vfx.cpp — VFX Manager: billboard sprite pool and lifecycle.
 *
 * Reads RT_SPRITE entities from the renderer entity buffer (via the
 * C accessor in godot_vfx_accessors.c) and renders them as camera-facing
 * billboard quads in the Godot 3D scene.
 *
 * Pool of up to VFX_SPRITE_POOL_SIZE MeshInstance3D nodes.  Each frame the
 * active sprites are assigned to pool slots; unused slots are hidden.
 *
 * Phase 221: VFX Manager Foundation
 */

#include "godot_vfx.h"

#include <godot_cpp/classes/array_mesh.hpp>
#include <godot_cpp/classes/image.hpp>
#include <godot_cpp/classes/image_texture.hpp>
#include <godot_cpp/classes/mesh_instance3d.hpp>
#include <godot_cpp/classes/standard_material3d.hpp>
#include <godot_cpp/variant/packed_byte_array.hpp>
#include <godot_cpp/variant/packed_int32_array.hpp>
#include <godot_cpp/variant/packed_vector2_array.hpp>
#include <godot_cpp/variant/packed_vector3_array.hpp>

#include <unordered_map>
#include <cstring>
#include <cmath>

using namespace godot;

/* ── C-linkage accessors (godot_vfx_accessors.c, godot_renderer.c, godot_vfs_accessors.c) ── */
extern "C" {
    int  Godot_VFX_GetSpriteCount(void);
    void Godot_VFX_GetSprite(int idx, float *origin, float *radius,
                             int *shaderHandle, float *rotation,
                             unsigned char *rgba);

    const char *Godot_Renderer_GetShaderName(int handle);
    const char *Godot_Renderer_GetShaderRemap(const char *name);

    long Godot_VFS_ReadFile(const char *qpath, void **out_buffer);
    void Godot_VFS_FreeFile(void *buffer);
}

/* ── Constants ── */
static constexpr int   VFX_SPRITE_POOL_SIZE = 512;
static constexpr float MOHAA_UNIT_SCALE     = 1.0f / 39.37f;

/* ── id Tech 3 → Godot coordinate conversion ── */
static inline Vector3 id_to_godot(float ix, float iy, float iz) {
    return Vector3(-iy * MOHAA_UNIT_SCALE,
                    iz * MOHAA_UNIT_SCALE,
                   -ix * MOHAA_UNIT_SCALE);
}

/* ── Module state ── */
static Node3D                              *vfx_parent     = nullptr;
static MeshInstance3D                      *vfx_pool[VFX_SPRITE_POOL_SIZE] = {};
static bool                                 vfx_initialised = false;
static std::unordered_map<int, Ref<ImageTexture>> vfx_tex_cache;

/* ── Texture loading (mirrors MoHAARunner::get_shader_texture pattern) ── */
static Ref<ImageTexture> vfx_load_texture(int shader_handle)
{
    /* Check cache */
    auto it = vfx_tex_cache.find(shader_handle);
    if (it != vfx_tex_cache.end()) {
        return it->second;
    }

    /* Look up shader name, apply remap */
    const char *raw_name = Godot_Renderer_GetShaderName(shader_handle);
    const char *remapped = Godot_Renderer_GetShaderRemap(raw_name);
    const char *name     = (remapped && remapped[0]) ? remapped : raw_name;
    if (!name || !name[0]) {
        vfx_tex_cache[shader_handle] = Ref<ImageTexture>();
        return Ref<ImageTexture>();
    }

    /* Try loading with different extensions */
    const char *extensions[] = { "", ".tga", ".jpg", ".png", nullptr };
    Ref<ImageTexture> tex;

    for (int ext_i = 0; extensions[ext_i]; ext_i++) {
        char path[128];
        snprintf(path, sizeof(path), "%s%s", name, extensions[ext_i]);

        void *buf = nullptr;
        long len = Godot_VFS_ReadFile(path, &buf);
        if (len <= 0 || !buf) continue;

        PackedByteArray pba;
        pba.resize(len);
        memcpy(pba.ptrw(), buf, len);
        Godot_VFS_FreeFile(buf);

        Ref<Image> img;
        img.instantiate();
        Error err;

        /* Detect format by magic bytes */
        const uint8_t *data = pba.ptr();
        if (len > 2 && data[0] == 0xFF && data[1] == 0xD8) {
            err = img->load_jpg_from_buffer(pba);
        } else if (len > 3 && data[0] == 0x89 && data[1] == 'P') {
            err = img->load_png_from_buffer(pba);
        } else {
            err = img->load_tga_from_buffer(pba);
            if (err != OK) {
                err = img->load_jpg_from_buffer(pba);
            }
        }

        if (err == OK && !img->is_empty()) {
            tex = ImageTexture::create_from_image(img);
            break;
        }
    }

    vfx_tex_cache[shader_handle] = tex;
    return tex;
}

/* ── Pre-built unit quad mesh (shared by all pool slots) ── */
static Ref<ArrayMesh> vfx_unit_quad;

static Ref<ArrayMesh> vfx_get_unit_quad()
{
    if (vfx_unit_quad.is_valid()) return vfx_unit_quad;

    PackedVector3Array pos;
    PackedVector2Array uv;
    PackedInt32Array   idx;
    pos.resize(4);
    uv.resize(4);
    idx.resize(6);

    /* 1×1 quad centred at origin — scaled per-sprite via node scale */
    pos.set(0, Vector3(-0.5f, -0.5f, 0.0f));
    pos.set(1, Vector3( 0.5f, -0.5f, 0.0f));
    pos.set(2, Vector3( 0.5f,  0.5f, 0.0f));
    pos.set(3, Vector3(-0.5f,  0.5f, 0.0f));
    uv.set(0, Vector2(0, 1));
    uv.set(1, Vector2(1, 1));
    uv.set(2, Vector2(1, 0));
    uv.set(3, Vector2(0, 0));
    idx.set(0, 0); idx.set(1, 1); idx.set(2, 2);
    idx.set(3, 0); idx.set(4, 2); idx.set(5, 3);

    Array arrays;
    arrays.resize(Mesh::ARRAY_MAX);
    arrays[Mesh::ARRAY_VERTEX] = pos;
    arrays[Mesh::ARRAY_TEX_UV] = uv;
    arrays[Mesh::ARRAY_INDEX]  = idx;

    vfx_unit_quad.instantiate();
    vfx_unit_quad->add_surface_from_arrays(Mesh::PRIMITIVE_TRIANGLES, arrays);
    return vfx_unit_quad;
}

/* ──────────────────────────────────────────── */
/*  Public API                                  */
/* ──────────────────────────────────────────── */

void Godot_VFX_Init(Node3D *parent)
{
    if (vfx_initialised || !parent) return;

    vfx_parent = parent;

    for (int i = 0; i < VFX_SPRITE_POOL_SIZE; i++) {
        MeshInstance3D *mi = memnew(MeshInstance3D);
        mi->set_mesh(vfx_get_unit_quad());
        mi->set_visible(false);
        /* Cast no shadows — sprites are VFX, not geometry */
        mi->set_cast_shadows_setting(GeometryInstance3D::SHADOW_CASTING_SETTING_OFF);
        parent->add_child(mi);
        vfx_pool[i] = mi;
    }

    vfx_initialised = true;
}

void Godot_VFX_Update(float delta)
{
    (void)delta;
    if (!vfx_initialised) return;

    /* Scan entity buffer for sprites (rebuilds the cached index list) */
    int count = Godot_VFX_GetSpriteCount();

    for (int i = 0; i < VFX_SPRITE_POOL_SIZE; i++) {
        MeshInstance3D *mi = vfx_pool[i];
        if (!mi) continue;

        if (i >= count) {
            mi->set_visible(false);
            continue;
        }

        /* Read sprite data */
        float origin[3]      = {0};
        float radius          = 0.0f;
        float rotation        = 0.0f;
        int   shaderHandle    = 0;
        unsigned char rgba[4] = {255, 255, 255, 255};

        Godot_VFX_GetSprite(i, origin, &radius, &shaderHandle,
                            &rotation, rgba);

        if (radius < 0.001f) {
            mi->set_visible(false);
            continue;
        }

        /* Coordinate conversion + positioning */
        Vector3 pos = id_to_godot(origin[0], origin[1], origin[2]);
        float scaledRadius = radius * MOHAA_UNIT_SCALE;

        /* Apply billboard material */
        Ref<StandardMaterial3D> mat;
        mat.instantiate();
        mat->set_billboard_mode(BaseMaterial3D::BILLBOARD_ENABLED);
        mat->set_cull_mode(BaseMaterial3D::CULL_DISABLED);
        mat->set_transparency(BaseMaterial3D::TRANSPARENCY_ALPHA);
        mat->set_shading_mode(BaseMaterial3D::SHADING_MODE_UNSHADED);
        mat->set_depth_draw_mode(BaseMaterial3D::DEPTH_DRAW_DISABLED);
        mat->set_albedo(Color(rgba[0] / 255.0f, rgba[1] / 255.0f,
                              rgba[2] / 255.0f, rgba[3] / 255.0f));

        /* Load and apply texture */
        if (shaderHandle > 0) {
            Ref<ImageTexture> tex = vfx_load_texture(shaderHandle);
            if (tex.is_valid()) {
                mat->set_texture(BaseMaterial3D::TEXTURE_ALBEDO, tex);
            }
        }

        mi->set_surface_override_material(0, mat);

        /* Scale the unit quad by diameter (radius × 2) */
        float diameter = scaledRadius * 2.0f;

        /* Build transform: position + uniform scale */
        Basis basis;
        basis.scale(Vector3(diameter, diameter, diameter));
        mi->set_global_transform(Transform3D(basis, pos));

        mi->set_visible(true);
    }
}

void Godot_VFX_Shutdown(void)
{
    if (!vfx_initialised) return;

    for (int i = 0; i < VFX_SPRITE_POOL_SIZE; i++) {
        if (vfx_pool[i]) {
            vfx_pool[i]->queue_free();
            vfx_pool[i] = nullptr;
        }
    }

    vfx_tex_cache.clear();
    vfx_unit_quad.unref();
    vfx_parent      = nullptr;
    vfx_initialised = false;
}

void Godot_VFX_Clear(void)
{
    if (!vfx_initialised) return;

    for (int i = 0; i < VFX_SPRITE_POOL_SIZE; i++) {
        if (vfx_pool[i]) {
            vfx_pool[i]->set_visible(false);
        }
    }
}
