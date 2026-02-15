#ifndef GODOT_SHADER_MATERIAL_HPP
#define GODOT_SHADER_MATERIAL_HPP

#include "material.hpp"
#include "../variant/variant.hpp"

namespace godot {

class ShaderMaterial : public Material {
public:
    void set_shader_parameter(const String &param, const Variant &value) {}
};

}

#endif
