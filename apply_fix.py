import sys

filepath = "openmohaa/code/godot/MoHAARunner.cpp"
with open(filepath, "r") as f:
    content = f.read()

search_block = """            // Check resource metadata for shader name (stored during BSP build)
            String shader_name = smat->get_meta("shader_name", "");
            if (shader_name.is_empty()) continue;

            CharString cs = shader_name.ascii();
            const GodotShaderProps *sp = Godot_ShaderProps_Find(cs.get_data());
            if (!sp) continue;"""

replace_block = """            // Check resource metadata for shader name (stored during BSP build)
            const GodotShaderProps *sp = nullptr;
            String shader_name; // Default empty, retrieved lazily if needed for animMap

            // Phase 36 performance optimization: Cache shader property pointer in metadata
            // to avoid string lookup and conversion every frame.
            // Stored as uint64_t + 1 (0 = not computed, 1 = null, >1 = valid pointer)
            uint64_t sp_ptr_val = (uint64_t)smat->get_meta("shader_props_ptr", 0);

            if (sp_ptr_val != 0) {
                if (sp_ptr_val > 1) {
                    sp = (const GodotShaderProps *)(sp_ptr_val - 1);
                } else {
                    sp = nullptr;
                }
            } else {
                shader_name = smat->get_meta("shader_name", "");
                if (shader_name.is_empty()) {
                    smat->set_meta("shader_props_ptr", 1); // Cache null
                    continue;
                }

                CharString cs = shader_name.ascii();
                sp = Godot_ShaderProps_Find(cs.get_data());

                if (sp) {
                    smat->set_meta("shader_props_ptr", (uint64_t)sp + 1);
                } else {
                    smat->set_meta("shader_props_ptr", 1);
                }
            }

            if (!sp) continue;"""

if search_block in content:
    new_content = content.replace(search_block, replace_block)

    # Second replacement
    search_block_2 = """            // Phase 55: animMap frame swap
            if (sp->has_animmap && sp->animmap_num_frames > 0 && sp->animmap_freq > 0.0f) {"""

    replace_block_2 = """            // Phase 55: animMap frame swap
            if (sp->has_animmap && sp->animmap_num_frames > 0 && sp->animmap_freq > 0.0f) {
                // We need the shader name for animMap handling.
                // If it wasn't fetched above (cache hit), fetch it now.
                if (shader_name.is_empty()) {
                    shader_name = smat->get_meta("shader_name", "");
                }"""

    if search_block_2 in new_content:
        new_content = new_content.replace(search_block_2, replace_block_2)
        with open(filepath, "w") as f:
            f.write(new_content)
        print("Success")
    else:
        print("Second block not found")
else:
    print("First block not found")
