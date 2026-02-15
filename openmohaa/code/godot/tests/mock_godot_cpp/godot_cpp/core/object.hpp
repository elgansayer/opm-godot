#ifndef GODOT_OBJECT_HPP
#define GODOT_OBJECT_HPP

#include "../variant/string.hpp"
#include "../variant/variant.hpp"
#include <map>

#define memnew(Class) new Class
#define memdelete(Ptr) delete Ptr

namespace godot {

class Object {
    std::map<String, Variant> metadata;
public:
    virtual ~Object() {}

    void set_meta(const String& name, const Variant& value) {
        metadata[name] = value;
    }

    Variant get_meta(const String& name, const Variant& default_val = Variant()) const {
        auto it = metadata.find(name);
        if (it != metadata.end()) {
            return it->second;
        }
        return default_val;
    }

    bool has_meta(const String& name) const {
        return metadata.find(name) != metadata.end();
    }

    template<typename T>
    static T* cast_to(Object* obj) {
        return static_cast<T*>(obj);
    }
};

}

#endif
