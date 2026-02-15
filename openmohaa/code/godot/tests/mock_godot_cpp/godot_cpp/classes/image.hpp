#ifndef GODOT_IMAGE_HPP
#define GODOT_IMAGE_HPP

#include "resource.hpp"
#include "../variant/packed_byte_array.hpp"

namespace godot {

enum Error {
    OK = 0,
    FAILED = 1
};

class Image : public Resource {
public:
    enum Format {
        FORMAT_RGBA8 = 0,
        FORMAT_RGB8 = 1
    };

    static Ref<Image> create_from_data(int width, int height, bool use_mipmaps, Format format, const PackedByteArray &data) { return Ref<Image>(); }

    Error load_jpg_from_buffer(const PackedByteArray &buffer) { return OK; }
    Error load_tga_from_buffer(const PackedByteArray &buffer) { return OK; }

    int get_width() const { return 1; }
    int get_height() const { return 1; }
    void generate_mipmaps() {}
};

}

#endif
