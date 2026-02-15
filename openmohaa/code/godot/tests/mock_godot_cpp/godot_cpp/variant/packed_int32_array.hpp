#ifndef GODOT_PACKED_INT32_ARRAY_HPP
#define GODOT_PACKED_INT32_ARRAY_HPP

#include <vector>
#include <cstdint>

namespace godot {

class PackedInt32Array {
public:
    std::vector<int32_t> _data;
    void resize(int size) { _data.resize(size); }
    int32_t* ptrw() { return _data.data(); }
    const int32_t* ptr() const { return _data.data(); }
};

} // namespace godot

#endif
