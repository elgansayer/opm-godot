#ifndef GODOT_NODE_HPP
#define GODOT_NODE_HPP

#include "../core/object.hpp"

namespace godot {

class Node : public Object {
public:
    void set_name(const String& name) {}
    void add_child(Node* node) {}
};

}

#endif
