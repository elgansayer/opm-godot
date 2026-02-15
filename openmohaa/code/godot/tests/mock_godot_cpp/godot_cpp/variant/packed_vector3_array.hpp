#ifndef GODOT_PACKED_VECTOR3_ARRAY_HPP
#define GODOT_PACKED_VECTOR3_ARRAY_HPP

#include "vector3.hpp"
#include <vector>

namespace godot {

class PackedVector3Array {
public:
    std::vector<Vector3> _data;
    void resize(int size) { _data.resize(size); }
    Vector3* ptrw() { return _data.data(); }
    const Vector3* ptr() const { return _data.data(); }
};

} // namespace godot

#endif
