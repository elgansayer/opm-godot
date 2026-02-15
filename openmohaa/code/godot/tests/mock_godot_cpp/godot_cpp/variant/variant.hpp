#ifndef GODOT_VARIANT_HPP
#define GODOT_VARIANT_HPP

#include "string.hpp"
#include <cstdint>

namespace godot {

class Variant {
    enum Type { NIL, STRING, INT };
    Type type;
    String str_val;
    uint64_t int_val;

public:
    Variant() : type(NIL), int_val(0) {}
    Variant(const String& val) : type(STRING), str_val(val), int_val(0) {}
    Variant(const char* val) : type(STRING), str_val(val), int_val(0) {}
    Variant(uint64_t val) : type(INT), int_val(val) {}
    Variant(int val) : type(INT), int_val((uint64_t)val) {}

    // Generic constructor for other types (fallback to NIL or error if needed, but for mocks keeping simple)
    template<typename T>
    Variant(const T& val) : type(NIL), int_val(0) {}

    operator String() const { return str_val; }
    operator uint64_t() const { return int_val; }
    operator int() const { return (int)int_val; }

    // For comparing with default value
    bool operator==(const Variant& other) const {
        if (type != other.type) return false;
        if (type == STRING) return str_val == other.str_val;
        if (type == INT) return int_val == other.int_val;
        return true; // NIL == NIL
    }
    bool operator!=(const Variant& other) const { return !(*this == other); }

    bool is_null() const { return type == NIL; }
};

}

#endif
