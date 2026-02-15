#ifndef GODOT_PACKED_BYTE_ARRAY_HPP
#define GODOT_PACKED_BYTE_ARRAY_HPP

#include <vector>
#include <cstdint>

namespace godot {

class PackedByteArray {
public:
    std::vector<uint8_t> _data;
    void resize(int size) { _data.resize(size); }
    uint8_t* ptrw() { return _data.data(); }
    const uint8_t* ptr() const { return _data.data(); }
};

} // namespace godot

#endif
