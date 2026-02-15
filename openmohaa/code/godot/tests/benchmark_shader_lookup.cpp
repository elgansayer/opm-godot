#include "godot_shader_props.h"
#include <godot_cpp/classes/standard_material3d.hpp>
#include <godot_cpp/variant/string.hpp>
#include <vector>
#include <chrono>
#include <cstdio>
#include <string>
#include <unordered_map>

// Mock implementation of Godot_ShaderProps_Find
std::unordered_map<std::string, GodotShaderProps> shader_props_db;

const GodotShaderProps *Godot_ShaderProps_Find(const char *shader_name) {
    if (!shader_name) return nullptr;
    auto it = shader_props_db.find(shader_name);
    if (it != shader_props_db.end()) {
        return &it->second;
    }
    return nullptr;
}

// Mock Load function to populate DB
void Mock_Load_Shaders() {
    for (int i = 0; i < 1000; i++) {
        std::string name = "textures/test/shader_" + std::to_string(i);
        GodotShaderProps props;
        // Initialize basic props
        props.has_tcmod = (i % 2 == 0);
        shader_props_db[name] = props;
    }
}

using namespace godot;

int main() {
    Mock_Load_Shaders();

    // Setup materials
    const int NUM_MATERIALS = 10000;
    std::vector<Ref<StandardMaterial3D>> materials;
    materials.reserve(NUM_MATERIALS);

    for (int i = 0; i < NUM_MATERIALS; i++) {
        Ref<StandardMaterial3D> mat;
        mat.instantiate();
        // Assign a shader name that exists
        std::string name = "textures/test/shader_" + std::to_string(i % 1000);
        mat->set_meta("shader_name", String(name.c_str()));
        materials.push_back(mat);
    }

    printf("Benchmarking shader lookup optimization...\n");
    printf("Materials: %d\n", NUM_MATERIALS);

    // 1. Baseline: String lookup every time
    auto start = std::chrono::high_resolution_clock::now();
    int hits_baseline = 0;
    // Run enough frames to measure time significantly
    const int FRAMES = 500;

    for (int frame = 0; frame < FRAMES; frame++) {
        for (auto mat : materials) {
            String shader_name = mat->get_meta("shader_name", "");
            if (shader_name.is_empty()) continue;

            CharString cs = shader_name.ascii();
            const GodotShaderProps *sp = Godot_ShaderProps_Find(cs.get_data());
            if (sp && sp->has_tcmod) {
                hits_baseline++;
            }
        }
    }
    auto end = std::chrono::high_resolution_clock::now();
    auto duration_baseline = std::chrono::duration_cast<std::chrono::milliseconds>(end - start).count();
    printf("Baseline: %lld ms (Hits: %d)\n", (long long)duration_baseline, hits_baseline);

    // 2. Optimized: Cache pointer in metadata
    start = std::chrono::high_resolution_clock::now();
    int hits_optimized = 0;
    for (int frame = 0; frame < FRAMES; frame++) {
        for (auto mat : materials) {
            const GodotShaderProps *sp = nullptr;

            // Try cache
            // Note: In real Godot 'get_meta' with default value is fast if we know key exists?
            // Or we check 'has_meta'.
            // The logic:
            Variant ptr_var = mat->get_meta("shader_props_ptr", 0);
            uint64_t ptr_val = (uint64_t)ptr_var;

            if (ptr_val != 0) {
                 if (ptr_val > 1) {
                    sp = (const GodotShaderProps *)(ptr_val - 1);
                 } else {
                    sp = nullptr;
                 }
            } else {
                // Not cached (0 means not computed yet)
                String shader_name = mat->get_meta("shader_name", "");
                if (shader_name.is_empty()) {
                    mat->set_meta("shader_props_ptr", 1); // Cache null
                    continue;
                }

                CharString cs = shader_name.ascii();
                sp = Godot_ShaderProps_Find(cs.get_data());

                if (sp) {
                    mat->set_meta("shader_props_ptr", (uint64_t)sp + 1);
                } else {
                    mat->set_meta("shader_props_ptr", 1);
                }
            }

            if (sp && sp->has_tcmod) {
                hits_optimized++;
            }
        }
    }
    end = std::chrono::high_resolution_clock::now();
    auto duration_optimized = std::chrono::duration_cast<std::chrono::milliseconds>(end - start).count();
    printf("Optimized: %lld ms (Hits: %d)\n", (long long)duration_optimized, hits_optimized);

    double speedup = (duration_optimized > 0) ? (double)duration_baseline / (double)duration_optimized : 0.0;
    printf("Speedup: %.2fx\n", speedup);

    if (hits_baseline != hits_optimized) {
        printf("FAIL: Logic mismatch! Baseline hits: %d, Optimized hits: %d\n", hits_baseline, hits_optimized);
        return 1;
    }

    return 0;
}
