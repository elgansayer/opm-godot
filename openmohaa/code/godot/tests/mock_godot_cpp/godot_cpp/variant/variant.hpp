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

    operator String() const { return str_val; }
    operator uint64_t() const { return int_val; }
    operator int() const { return (int)int_val; }
    operator bool() const {
        if (type == NIL) return false;
        if (type == INT) return int_val != 0;
        return true;
    }

    bool operator==(const Variant& other) const {
        if (type != other.type) return false;
        if (type == STRING) return str_val == other.str_val;
        if (type == INT) return int_val == other.int_val;
        return true; // NIL == NIL
    }

    // Generic constructor for other types (fallback to NIL or dummy)
    template<typename T>
    Variant(const T& val) : type(NIL), int_val(0) {}
};

}

#endif
