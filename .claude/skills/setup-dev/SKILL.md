# /setup-dev — Check and initialize development environment

Verify all required tools are installed and the project is ready to build.

## Steps

1. Check required tools and report status:
   ```bash
   godot --version          # Godot 4.2+
   scons --version          # SCons build system
   bison --version          # Parser generator (for Morfuse)
   flex --version           # Lexer generator
   gcc --version || clang --version  # C/C++ compiler
   python3 --version        # Python 3 (for SCons)
   ```
2. Check optional tools:
   ```bash
   docker compose version   # Docker (for web deployment)
   emcc --version           # Emscripten (for web builds)
   node --version           # Node.js (for relay server)
   clang-format --version   # Code formatting
   ```
3. Check submodule status:
   ```bash
   git submodule status
   ```
   - If submodules are uninitialized, run: `git submodule update --init --recursive`
4. Check Godot export templates (for web builds):
   ```bash
   ls ~/.local/share/godot/export_templates/
   ```
5. Report:
   - List of installed/missing tools
   - Submodule status
   - Platform-specific install commands for missing tools (apt, brew, etc.)
   - Ready-to-build status per platform (linux, web)
