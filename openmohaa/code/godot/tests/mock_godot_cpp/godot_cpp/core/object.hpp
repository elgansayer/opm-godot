#ifndef GODOT_OBJECT_HPP
#define GODOT_OBJECT_HPP

#include "../variant/string.hpp"

#define memnew(Class) new Class
#define memdelete(Ptr) delete Ptr

namespace godot {

class Object {
public:
    virtual ~Object() {}
    void set_meta(const String& name, const String& value) {}
};

}

#endif
