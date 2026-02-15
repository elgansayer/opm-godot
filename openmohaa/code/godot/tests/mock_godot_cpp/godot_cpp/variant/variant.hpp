#ifndef GODOT_VARIANT_HPP
#define GODOT_VARIANT_HPP

namespace godot {
class Variant {
public:
    template<typename T>
    Variant(const T& val) {}
    Variant() {}
};
}

#endif
