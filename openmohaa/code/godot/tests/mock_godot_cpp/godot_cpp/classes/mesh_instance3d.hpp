#ifndef GODOT_MESH_INSTANCE3D_HPP
#define GODOT_MESH_INSTANCE3D_HPP

#include "node3d.hpp"
#include "mesh.hpp"

namespace godot {

class MeshInstance3D : public Node3D {
public:
    void set_mesh(const Ref<Mesh> &mesh) {}
    void surface_set_material(int surface, const Ref<Material> &material) {}
};

}

#endif
