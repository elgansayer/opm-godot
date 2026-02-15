#ifndef GODOT_BASE_MATERIAL3D_HPP
#define GODOT_BASE_MATERIAL3D_HPP

#include "material.hpp"
#include "image_texture.hpp"

namespace godot {

class BaseMaterial3D : public Material {
public:
    enum CullMode {
        CULL_BACK = 0,
        CULL_FRONT = 1,
        CULL_DISABLED = 2
    };
    enum Transparency {
        TRANSPARENCY_DISABLED = 0,
        TRANSPARENCY_ALPHA = 1,
        TRANSPARENCY_ALPHA_SCISSOR = 2,
        TRANSPARENCY_ALPHA_HASH = 3,
        TRANSPARENCY_ALPHA_DEPTH_PRE_PASS = 4
    };
    enum BlendMode {
        BLEND_MODE_MIX = 0,
        BLEND_MODE_ADD = 1,
        BLEND_MODE_SUB = 2,
        BLEND_MODE_MUL = 3
    };
    enum TextureParam {
        TEXTURE_ALBEDO = 0,
        TEXTURE_DETAIL_ALBEDO = 1
    };
    enum DetailUV {
        DETAIL_UV_1 = 0,
        DETAIL_UV_2 = 1
    };
    enum Feature {
        FEATURE_DETAIL = 0
    };
    enum Flags {
        FLAG_ALBEDO_FROM_VERTEX_COLOR = 0,
        FLAG_UV2_USE_TRIPLANAR = 1
    };

    void set_cull_mode(CullMode mode) {}
    void set_texture(TextureParam param, const Ref<class Texture2D> &texture) {}
    void set_transparency(Transparency transparency) {}
    void set_alpha_scissor_threshold(float threshold) {}
    void set_blend_mode(BlendMode mode) {}
    void set_flag(Flags flag, bool enable) {}
    void set_detail_blend_mode(BlendMode mode) {}
    void set_detail_uv(DetailUV detail_uv) {}
    void set_feature(Feature feature, bool enable) {}
};

}

#endif
