#ifndef GODOT_UTILITY_FUNCTIONS_HPP
#define GODOT_UTILITY_FUNCTIONS_HPP

#include "string.hpp"

namespace godot {

class UtilityFunctions {
public:
    static void print(const String &msg);
    static void printerr(const String &msg);
};

} // namespace godot

#endif
