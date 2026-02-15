#include <godot_cpp/classes/standard_material3d.hpp>
#include <godot_cpp/variant/string.hpp>
#include <godot_cpp/core/object.hpp>
#include <godot_cpp/classes/ref.hpp>
#include <unordered_map>
#include <string>
#include <vector>
#include <chrono>
#include <iostream>
#include <algorithm>

using namespace godot;

// Minimal mock of GodotShaderProps
struct GodotShaderProps {
    bool has_tcmod;
    // ... other fields irrelevant for lookup benchmark
};

// Mock lookup table
std::unordered_map<std::string, GodotShaderProps> s_shader_props;

const GodotShaderProps *Godot_ShaderProps_Find(const char *shader_name) {
    if (!shader_name || !shader_name[0]) return nullptr;

    std::string key(shader_name);
    for (auto &c : key) c = tolower((unsigned char)c);

    auto it = s_shader_props.find(key);
    if (it != s_shader_props.end())
        return &it->second;

    return nullptr;
}

int main() {
    // 1. Populate shader props with dummy data
    const int NUM_SHADERS = 1000;
    std::vector<String> shader_names;
    for (int i = 0; i < NUM_SHADERS; ++i) {
        std::string name = "textures/test/shader_" + std::to_string(i);
        s_shader_props[name] = GodotShaderProps{true};
        shader_names.push_back(String(name.c_str()));
    }

    // 2. Create materials
    const int NUM_MATERIALS = 5000;
    std::vector<Ref<StandardMaterial3D>> materials;
    for (int i = 0; i < NUM_MATERIALS; ++i) {
        Ref<StandardMaterial3D> mat;
        mat.instantiate();
        // Assign random shader name
        mat->set_meta("shader_name", shader_names[i % NUM_SHADERS]);
        materials.push_back(mat);
    }

    // 3. Benchmark Baseline
    auto start = std::chrono::high_resolution_clock::now();
    const int ITERATIONS = 200;

    long long ops = 0;

    for (int iter = 0; iter < ITERATIONS; ++iter) {
        for (const auto& mat_ref : materials) {
            StandardMaterial3D* smat = mat_ref.ptr;

            // Baseline logic
            String shader_name = smat->get_meta("shader_name", "");
            if (shader_name.is_empty()) continue;

            CharString cs = shader_name.ascii();
            const GodotShaderProps *sp = Godot_ShaderProps_Find(cs.get_data());
            if (!sp) continue;

            if (sp->has_tcmod) {
                ops++; // Dummy op
            }
        }
    }

    auto end = std::chrono::high_resolution_clock::now();
    auto duration_baseline = std::chrono::duration_cast<std::chrono::milliseconds>(end - start).count();
    std::cout << "Baseline duration: " << duration_baseline << " ms" << std::endl;


    // 4. Benchmark Optimized
    // Reset materials metadata for optimized run (not strictly needed as we use a different key)

    start = std::chrono::high_resolution_clock::now();

    for (int iter = 0; iter < ITERATIONS; ++iter) {
        for (const auto& mat_ref : materials) {
            StandardMaterial3D* smat = mat_ref.ptr;

            // Optimized logic
            uint64_t props_ptr = (uint64_t)smat->get_meta("shader_props_ptr", (uint64_t)0);
            const GodotShaderProps *sp = nullptr;

            if (props_ptr > 1) {
                 sp = (const GodotShaderProps*)(props_ptr - 1);
            } else if (props_ptr == 0) { // Not computed yet
                 String shader_name = smat->get_meta("shader_name", "");
                 if (!shader_name.is_empty()) {
                     CharString cs = shader_name.ascii();
                     sp = Godot_ShaderProps_Find(cs.get_data());
                     // Cache it (add 1 to distinguish null from not-computed)
                     smat->set_meta("shader_props_ptr", (uint64_t)sp + 1);
                 } else {
                     // No shader name, mark as null (1)
                     smat->set_meta("shader_props_ptr", (uint64_t)1);
                 }
            }

            if (!sp) continue;

            if (sp->has_tcmod) {
                ops++;
            }
        }
    }

    end = std::chrono::high_resolution_clock::now();
    auto duration_optimized = std::chrono::duration_cast<std::chrono::milliseconds>(end - start).count();
    std::cout << "Optimized duration: " << duration_optimized << " ms" << std::endl;

    std::cout << "Speedup: " << (double)duration_baseline / duration_optimized << "x" << std::endl;

    return 0;
}
