#ifndef GODOT_VECTOR3_HPP
#define GODOT_VECTOR3_HPP

#include <cmath>

namespace godot {

struct Vector3 {
    float x, y, z;
    Vector3(float x = 0, float y = 0, float z = 0) : x(x), y(y), z(z) {}
    Vector3 operator*(float s) const { return Vector3(x*s, y*s, z*s); }
    Vector3 operator+(const Vector3& v) const { return Vector3(x+v.x, y+v.y, z+v.z); }
    Vector3& operator+=(const Vector3& v) { x+=v.x; y+=v.y; z+=v.z; return *this; }
    Vector3& operator/=(float s) { x/=s; y/=s; z/=s; return *this; }
    float length() const { return std::sqrt(x*x + y*y + z*z); }
};

} // namespace godot

#endif
