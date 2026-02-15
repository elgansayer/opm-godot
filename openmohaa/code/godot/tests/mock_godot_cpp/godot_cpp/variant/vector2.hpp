#ifndef GODOT_VECTOR2_HPP
#define GODOT_VECTOR2_HPP

namespace godot {

struct Vector2 {
    float x, y;
    Vector2(float x = 0, float y = 0) : x(x), y(y) {}
    Vector2 operator*(float s) const { return Vector2(x*s, y*s); }
    Vector2 operator+(const Vector2& v) const { return Vector2(x+v.x, y+v.y); }
    Vector2& operator+=(const Vector2& v) { x+=v.x; y+=v.y; return *this; }
};

} // namespace godot

#endif
