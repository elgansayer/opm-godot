#include "../godot_shader_props.h"
#include "godot_cpp/classes/standard_material3d.hpp"
#include <iostream>
#include <chrono>
#include <vector>
#include <unordered_map>
#include <string>
#include <algorithm> // for tolower

using namespace godot;

// Mock GodotShaderProps table
std::unordered_map<std::string, GodotShaderProps> s_props;

void setup_props() {
    GodotShaderProps p = {};
    p.has_tcmod = true;
    p.tcmod_scroll_s = 0.1f;
    s_props["textures/common/caulk"] = p;
    s_props["textures/common/nodraw"] = p;
    // Add more entries to make lookup slightly realistic
    for (int i=0; i<100; ++i) {
        s_props["textures/common/dummy" + std::to_string(i)] = p;
    }
}

// Implement Godot_ShaderProps_Find
const GodotShaderProps *Godot_ShaderProps_Find(const char *shader_name) {
    if (!shader_name || !shader_name[0]) return nullptr;
    std::string key(shader_name);
    // Lowercase (simplified)
    for (auto &c : key) c = tolower((unsigned char)c);
    auto it = s_props.find(key);
    if (it != s_props.end()) return &it->second;
    return nullptr;
}

// Dummy functions to satisfy linker if needed (though we compile standalone)
void Godot_ShaderProps_Load() {}
void Godot_ShaderProps_Unload() {}
int Godot_ShaderProps_Count() { return 0; }
const char *Godot_ShaderProps_GetSkyEnv() { return nullptr; }

int main() {
    setup_props();

    StandardMaterial3D *mat = memnew(StandardMaterial3D);
    mat->set_meta("shader_name", "textures/common/caulk");

    const int ITERATIONS = 1000000;

    // Baseline: String lookup
    auto start = std::chrono::high_resolution_clock::now();
    volatile int hit_count = 0; // Prevent optimization

    for (int i = 0; i < ITERATIONS; ++i) {
        String shader_name = mat->get_meta("shader_name", "");
        if (shader_name.is_empty()) continue;

        CharString cs = shader_name.ascii();
        const GodotShaderProps *sp = Godot_ShaderProps_Find(cs.get_data());
        if (!sp) continue;

        if (sp->has_tcmod) {
            hit_count++;
        }
    }
    auto end = std::chrono::high_resolution_clock::now();
    std::chrono::duration<double, std::milli> baseline_ms = end - start;

    std::cout << "Baseline (String lookup): " << baseline_ms.count() << " ms" << std::endl;

    // Optimization: Cached pointer
    start = std::chrono::high_resolution_clock::now();
    hit_count = 0;

    for (int i = 0; i < ITERATIONS; ++i) {
        // Optimized logic
        const GodotShaderProps *sp = nullptr;
        uint64_t ptr_val = mat->get_meta("shader_props_ptr", 0);

        if (ptr_val == 0) {
            // Not computed
            String shader_name = mat->get_meta("shader_name", "");
            if (!shader_name.is_empty()) {
                CharString cs = shader_name.ascii();
                sp = Godot_ShaderProps_Find(cs.get_data());
            }
            // Cache it (+1 encoding)
            mat->set_meta("shader_props_ptr", (uint64_t)sp + 1);
        } else if (ptr_val > 1) {
            // Valid pointer
            sp = (const GodotShaderProps*)(ptr_val - 1);
        } else {
            // computed but null (val == 1)
            sp = nullptr;
        }

        if (!sp) continue;

        if (sp->has_tcmod) {
            hit_count++;
        }
    }
    end = std::chrono::high_resolution_clock::now();
    std::chrono::duration<double, std::milli> optimized_ms = end - start;

    std::cout << "Optimized (Cached pointer): " << optimized_ms.count() << " ms" << std::endl;
    std::cout << "Speedup: " << baseline_ms.count() / optimized_ms.count() << "x" << std::endl;

    memdelete(mat);
    return 0;
}
