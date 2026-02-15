#ifndef GODOT_IMAGE_TEXTURE_HPP
#define GODOT_IMAGE_TEXTURE_HPP

#include "texture2d.hpp"
#include "image.hpp"

namespace godot {

class ImageTexture : public Texture2D {
public:
    static Ref<ImageTexture> create_from_image(const Ref<Image> &image) { return Ref<ImageTexture>(); }
};

}

#endif
