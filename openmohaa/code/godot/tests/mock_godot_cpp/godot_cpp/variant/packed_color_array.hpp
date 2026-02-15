#ifndef GODOT_PACKED_COLOR_ARRAY_HPP
#define GODOT_PACKED_COLOR_ARRAY_HPP

#include "color.hpp"
#include <vector>

namespace godot {

class PackedColorArray {
public:
    std::vector<Color> _data;
    void resize(int size) { _data.resize(size); }
    Color* ptrw() { return _data.data(); }
    const Color* ptr() const { return _data.data(); }
};

} // namespace godot

#endif
