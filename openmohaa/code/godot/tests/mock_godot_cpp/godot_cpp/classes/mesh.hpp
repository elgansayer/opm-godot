#ifndef GODOT_MESH_HPP
#define GODOT_MESH_HPP

#include "resource.hpp"
#include "../variant/array.hpp"

namespace godot {

class Material; // Forward decl

class Mesh : public Resource {
public:
    enum ArrayType {
        ARRAY_VERTEX = 0,
        ARRAY_NORMAL = 1,
        ARRAY_TANGENT = 2,
        ARRAY_COLOR = 3,
        ARRAY_TEX_UV = 4,
        ARRAY_TEX_UV2 = 5,
        ARRAY_CUSTOM0 = 6,
        ARRAY_CUSTOM1 = 7,
        ARRAY_CUSTOM2 = 8,
        ARRAY_CUSTOM3 = 9,
        ARRAY_BONES = 10,
        ARRAY_WEIGHTS = 11,
        ARRAY_INDEX = 12,
        ARRAY_MAX = 13
    };
    enum PrimitiveType {
        PRIMITIVE_POINTS = 0,
        PRIMITIVE_LINES = 1,
        PRIMITIVE_LINE_STRIP = 2,
        PRIMITIVE_LINE_LOOP = 3,
        PRIMITIVE_TRIANGLES = 4,
        PRIMITIVE_TRIANGLE_STRIP = 5,
        PRIMITIVE_TRIANGLE_FAN = 6
    };

    virtual int get_surface_count() const { return 0; }
    virtual void surface_set_material(int surf_idx, const Ref<Material> &material) {}
};

}

#endif
