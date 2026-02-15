#ifndef GODOT_ARRAY_HPP
#define GODOT_ARRAY_HPP

#include "packed_vector3_array.hpp"
#include "packed_vector2_array.hpp"
#include "packed_color_array.hpp"
#include "packed_int32_array.hpp"
#include "packed_byte_array.hpp"

namespace godot {

class Array {
public:
    void resize(int size) {}

    struct ElementProxy {
        template<typename T>
        void operator=(const T& val) {}
    };

    ElementProxy operator[](int index) { return ElementProxy(); }
};

} // namespace godot

#endif
