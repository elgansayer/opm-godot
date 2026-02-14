# Agent Task 54: SConstruct Cleanup + Build Hardening

## Objective
Clean up the SConstruct build file: remove dead code, add missing source files from recent agents, ensure all godot_*.c/.cpp files are auto-discovered, and add build hardening (warnings-as-errors for new code, sanitiser toggles).

## Files to MODIFY
- `SConstruct` — the main SCons build file

## DO NOT MODIFY
- Any source files in `code/` — this task is build-system only
- `godot-cpp/SConstruct` (upstream submodule)

## Implementation

### 1. Auto-discover godot source files
Replace manual file lists with glob:
```python
import glob

# Auto-discover all godot glue files
godot_c_sources = glob.glob('code/godot/*.c')
godot_cpp_sources = glob.glob('code/godot/*.cpp')
```
This ensures newly-added agent files are automatically included without SConstruct edits.

### 2. Add sanitiser toggles
```python
# Address Sanitizer (for debug builds)
if env.get('sanitize', '') == 'address':
    env.Append(CCFLAGS=['-fsanitize=address', '-fno-omit-frame-pointer'])
    env.Append(LINKFLAGS=['-fsanitize=address'])

# Undefined Behaviour Sanitizer
if env.get('sanitize', '') == 'undefined':
    env.Append(CCFLAGS=['-fsanitize=undefined'])
    env.Append(LINKFLAGS=['-fsanitize=undefined'])
```
Usage: `scons sanitize=address ...`

### 3. Add -Werror for godot/ directory only
```python
# Stricter warnings for new Godot glue code
godot_env = env.Clone()
godot_env.Append(CCFLAGS=['-Werror', '-Wno-unused-function'])
godot_objs = []
for src in godot_c_sources + godot_cpp_sources:
    godot_objs.append(godot_env.SharedObject(src))
```

### 4. Remove duplicate/dead source entries
Audit the existing source lists for:
- Files that no longer exist
- Files listed twice
- Old stubs that have been replaced by real implementations

### 5. Add `scons -h` help text
```python
Help("""
Build options:
  platform=linux|windows|macos   Target platform
  target=template_debug|template_release  Build type
  dev_build=yes|no               Developer build (extra debug info)
  sanitize=address|undefined     Enable sanitizers (debug only)
  
Targets:
  (default)   Build both libopenmohaa.so and libcgame.so
""")
```

### 6. Verify cgame exclusion filter
Ensure the cgame.so build correctly excludes all `code/godot/` files (cgame must not link any Godot glue).

## Build Verification
```bash
cd openmohaa && scons platform=linux target=template_debug -j$(nproc) dev_build=yes
# Verify both .so files build clean
ls -la bin/libopenmohaa.so bin/libcgame.so
```

## Documentation
Append `## Phase 265: SConstruct Cleanup + Build Hardening ✅` to `TASKS.md`.
