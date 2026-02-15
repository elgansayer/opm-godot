#ifndef GODOT_ARRAY_MESH_HPP
#define GODOT_ARRAY_MESH_HPP

#include "mesh.hpp"
#include "../variant/dictionary.hpp"

namespace godot {

class ArrayMesh : public Mesh {
public:
    void add_surface_from_arrays(PrimitiveType primitive, const Array &arrays, const Array &blend_shapes = Array(), const Dictionary &lods = Dictionary(), int32_t flags = 0) {}
};

}

#endif
