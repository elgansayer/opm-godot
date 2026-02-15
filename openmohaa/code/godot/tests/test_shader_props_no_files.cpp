/*
===========================================================================
Test: Godot_ShaderProps_Load (No Files Found)

Verifies that Godot_ShaderProps_Load correctly handles the case where
Godot_VFS_ListFiles returns no files or nullptr, logging a warning instead
of crashing or proceeding with invalid data.

This test uses the mock godot-cpp environment to simulate engine behavior
without linking against the full engine.
===========================================================================
*/

#include <iostream>
#include <string>
#include <vector>
#include <cstring>
#include <unordered_map>
#include <strings.h> // for strcasecmp

// Include mocks (resolved via mock_godot_cpp include path in SConstruct)
#include <godot_cpp/variant/utility_functions.hpp>
#include <godot_cpp/variant/string.hpp>

// Define global variable for capturing output
std::string g_mock_print_last;

namespace godot {
    void UtilityFunctions::print(const String &msg) {
        // Capture output for verification
        g_mock_print_last = msg.utf8();
        // Also print to stdout for debugging
        std::cout << "[MOCK PRINT] " << g_mock_print_last << std::endl;
    }

    void UtilityFunctions::printerr(const String &msg) {
        std::cerr << "[MOCK PRINTERR] " << msg.utf8() << std::endl;
    }
}

// Mocks for C functions required by godot_shader_props.cpp
extern "C" {
    // VFS List Files - The core logic under test
    char **Godot_VFS_ListFiles(const char *directory, const char *extension, int *out_count) {
        std::cout << "[MOCK VFS] ListFiles: " << directory << " (" << extension << ")" << std::endl;
        // Simulate no files found
        if (out_count) *out_count = 0;
        return nullptr;
    }

    void Godot_VFS_FreeFileList(char **list) {
        // No-op for null list
    }

    // VFS Read/Free - Not expected to be called in this test case
    long Godot_VFS_ReadFile(const char *qpath, void **out_buffer) {
        return 0;
    }
    void Godot_VFS_FreeFile(void *buffer) {}

    // Engine tokeniser mocks - Not expected to be called
    char *COM_ParseExt(char **data_p, int allowLineBreaks) { return (char*)""; }
    void  SkipRestOfLine(char **data) {}
    int   COM_Compress(char *data_p) { return 0; }

    // String helpers - wrappers around standard C functions
    int   Q_stricmp(const char *s1, const char *s2) { return strcasecmp(s1, s2); }
    int   Q_stricmpn(const char *s1, const char *s2, unsigned long n) { return strncasecmp(s1, s2, n); }
    void  Q_strncpyz(char *dest, const char *src, unsigned long destsize) {
        strncpy(dest, src, destsize);
        if (destsize > 0) dest[destsize - 1] = '\0';
    }
}

// Include the source file under test directly
// We suppress warnings because we are including a cpp file
#pragma GCC diagnostic push
#pragma GCC diagnostic ignored "-Wunused-variable"
#pragma GCC diagnostic ignored "-Wunused-function"
#include "../godot_shader_props.cpp"
#pragma GCC diagnostic pop

int main() {
    std::cout << "Running test_shader_props_no_files..." << std::endl;

    // Reset capture
    g_mock_print_last = "";

    // Call the function under test
    Godot_ShaderProps_Load();

    // Verify results
    bool passed = true;
    std::string expected = "[ShaderProps] WARNING: no shader files found";

    if (g_mock_print_last != expected) {
        std::cerr << "FAILED: Expected warning '" << expected << "', got '" << g_mock_print_last << "'" << std::endl;
        passed = false;
    } else {
        std::cout << "SUCCESS: Warning message verified." << std::endl;
    }

    if (passed) {
        std::cout << "ALL TESTS PASSED" << std::endl;
        return 0;
    } else {
        return 1;
    }
}
