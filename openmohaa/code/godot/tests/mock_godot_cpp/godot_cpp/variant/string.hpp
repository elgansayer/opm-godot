#ifndef GODOT_STRING_HPP
#define GODOT_STRING_HPP

#include <string>
#include <cstring>

namespace godot {

class CharString {
public:
    std::string _data;
    CharString(const char* s) : _data(s) {}
    const char* get_data() const { return _data.c_str(); }
};

class String {
public:
    std::string _data;

    String() {}
    String(const char* s) : _data(s ? s : "") {}
    String(const std::string& s) : _data(s) {}

    const char* utf8() const { return _data.c_str(); }
    CharString ascii() const { return CharString(_data.c_str()); }

    // Concatenation
    String operator+(const String& other) const {
        return String(_data + other._data);
    }
    String operator+(const char* other) const {
        return String(_data + (other ? other : ""));
    }

    static String num_int64(int64_t num) {
        return String(std::to_string(num));
    }
};

} // namespace godot

#endif
