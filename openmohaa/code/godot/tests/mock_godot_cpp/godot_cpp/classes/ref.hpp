#ifndef GODOT_REF_HPP
#define GODOT_REF_HPP

namespace godot {

template <typename T>
class Ref {
public:
    T* ptr;
    Ref() : ptr(nullptr) {}
    Ref(T* p) : ptr(p) {}
    Ref(const Ref& other) : ptr(other.ptr) {}
    ~Ref() {} // Leak intentionally for simplicity in tests

    T* operator->() { return ptr; }
    const T* operator->() const { return ptr; }
    bool is_valid() const { return ptr != nullptr; }
    bool is_null() const { return ptr == nullptr; }

    void instantiate() { ptr = new T(); }

    // Mock casting
    template <typename U>
    operator Ref<U>() const { return Ref<U>((U*)ptr); }
};

}

#endif
