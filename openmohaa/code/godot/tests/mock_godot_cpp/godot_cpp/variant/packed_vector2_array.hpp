#ifndef GODOT_PACKED_VECTOR2_ARRAY_HPP
#define GODOT_PACKED_VECTOR2_ARRAY_HPP

#include "vector2.hpp"
#include <vector>

namespace godot {

class PackedVector2Array {
public:
    std::vector<Vector2> _data;
    void resize(int size) { _data.resize(size); }
    Vector2* ptrw() { return _data.data(); }
    const Vector2* ptr() const { return _data.data(); }
};

} // namespace godot

#endif
