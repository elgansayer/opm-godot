# Agent Task 56: macOS Cross-Compile Support

## Objective
Add macOS build support to SConstruct so `scons platform=macos` produces `libopenmohaa.dylib` and `libcgame.dylib`. Target the osxcross toolchain for cross-compilation from Linux.

## Files to MODIFY
- `SConstruct` — add macOS platform handling

## Files to CREATE
- `code/godot/godot_sys_macos.c` — macOS-specific system stubs

## DO NOT MODIFY
- Any existing platform-agnostic source files
- `godot-cpp/SConstruct` (submodule)

## Implementation

### 1. SConstruct macOS platform block
```python
if env['platform'] == 'macos':
    env.Append(CPPDEFINES=['__APPLE__', 'MACOS_X'])
    env['SHLIBSUFFIX'] = '.dylib'
    env['SHLIBPREFIX'] = 'lib'
    
    # osxcross toolchain (adjust path as needed)
    osxcross = os.environ.get('OSXCROSS_ROOT', '/opt/osxcross')
    if os.path.exists(osxcross):
        env['CC'] = os.path.join(osxcross, 'bin/o64-clang')
        env['CXX'] = os.path.join(osxcross, 'bin/o64-clang++')
        env['LINK'] = os.path.join(osxcross, 'bin/o64-clang++')
    
    # macOS frameworks
    env.Append(LINKFLAGS=['-framework', 'CoreFoundation', '-framework', 'CoreServices'])
    
    # Remove Linux-only linker flags
    env['LINKFLAGS'] = [f for f in env.get('LINKFLAGS', [])
                        if f not in ['-z', 'muldefs', '-Bsymbolic-functions', '-ldl']]
    
    # Universal binary support (optional)
    if env.get('arch', '') == 'universal':
        env.Append(CCFLAGS=['-arch', 'x86_64', '-arch', 'arm64'])
        env.Append(LINKFLAGS=['-arch', 'x86_64', '-arch', 'arm64'])
    elif env.get('arch', '') == 'arm64':
        env.Append(CCFLAGS=['-arch', 'arm64'])
        env.Append(LINKFLAGS=['-arch', 'arm64'])
```

### 2. macOS system stubs (`godot_sys_macos.c`)
```c
#ifdef GODOT_GDEXTENSION
#ifdef __APPLE__
#include <mach/mach_time.h>
#include <sys/stat.h>
#include <unistd.h>

// macOS uses the same POSIX APIs as Linux for most things,
// but Sys_Milliseconds uses mach_absolute_time for precision.

static uint64_t sys_timebase_info_numer = 0;
static uint64_t sys_timebase_info_denom = 0;

int Sys_Milliseconds_macOS(void) {
    if (sys_timebase_info_numer == 0) {
        mach_timebase_info_data_t info;
        mach_timebase_info(&info);
        sys_timebase_info_numer = info.numer;
        sys_timebase_info_denom = info.denom;
    }
    uint64_t t = mach_absolute_time();
    return (int)((t * sys_timebase_info_numer / sys_timebase_info_denom) / 1000000);
}
#endif
#endif
```

### 3. Conditional source inclusion
```python
if env['platform'] == 'macos':
    main_sources.append('code/godot/godot_sys_macos.c')
    exclude_patterns.append('code/sys/sys_unix.c')  # if macOS needs different sys
```

### 4. GDExtension manifest update
Update `bin/openmohaa.gdextension`:
```ini
[libraries]
linux.debug.x86_64 = "res://bin/libopenmohaa.so"
windows.debug.x86_64 = "res://bin/openmohaa.dll"
macos.debug = "res://bin/libopenmohaa.dylib"
```

## Build Verification
```bash
# If osxcross is available:
cd openmohaa && scons platform=macos target=template_debug -j$(nproc) dev_build=yes
file bin/libopenmohaa.dylib

# If osxcross is NOT available, at minimum verify SConstruct doesn't error:
cd openmohaa && scons platform=macos target=template_debug --dry-run 2>&1 | head -20
```

## Documentation
Append `## Phase 267: macOS Cross-Compile Support ✅` to `TASKS.md`.
