#ifndef GODOT_COLOR_HPP
#define GODOT_COLOR_HPP

namespace godot {

struct Color {
    float r, g, b, a;
    Color(float r, float g, float b, float a = 1.0f) : r(r), g(g), b(b), a(a) {}
    Color() : r(0), g(0), b(0), a(1) {}

    Color operator*(float scalar) const {
        return Color(r * scalar, g * scalar, b * scalar, a * scalar);
    }

    Color& operator+=(const Color& other) {
        r += other.r; g += other.g; b += other.b; a += other.a;
        return *this;
    }
};

} // namespace godot

#endif
