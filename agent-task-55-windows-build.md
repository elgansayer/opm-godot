# Agent Task 55: Windows Cross-Compile Support

## Objective
Add Windows build support to SConstruct so `scons platform=windows` produces `openmohaa.dll` and `cgame.dll`. Target MinGW-w64 cross-compilation from Linux (the primary dev platform).

## Files to MODIFY
- `SConstruct` — add Windows platform handling

## Files to CREATE
- `code/godot/godot_sys_win.c` — Windows-specific system stubs (Sys_Milliseconds, Sys_Sleep, etc.)

## DO NOT MODIFY
- Any existing platform-agnostic source files
- `code/sys/sys_main.c` (has existing `#ifdef _WIN32` blocks  — don't touch)
- `godot-cpp/SConstruct` (submodule)

## Implementation

### 1. SConstruct Windows platform block
```python
if env['platform'] == 'windows':
    env.Append(CPPDEFINES=['_WIN32', 'WIN32', '_WINDOWS'])
    env['SHLIBSUFFIX'] = '.dll'
    env['SHLIBPREFIX'] = ''
    
    # MinGW cross-compile
    if env.get('use_mingw', True):
        env['CC'] = 'x86_64-w64-mingw32-gcc'
        env['CXX'] = 'x86_64-w64-mingw32-g++'
        env['LINK'] = 'x86_64-w64-mingw32-g++'
        env['AR'] = 'x86_64-w64-mingw32-ar'
        env['RANLIB'] = 'x86_64-w64-mingw32-ranlib'
    
    # Windows libraries
    env.Append(LIBS=['ws2_32', 'winmm', 'kernel32', 'user32'])
    
    # Remove Linux-only flags
    env['LINKFLAGS'] = [f for f in env.get('LINKFLAGS', [])
                        if f not in ['-z', 'muldefs', '-Bsymbolic-functions']]
    env.Append(LINKFLAGS=['-Wl,--allow-multiple-definition'])
```

### 2. Windows system stubs (`godot_sys_win.c`)
```c
#ifdef GODOT_GDEXTENSION
#ifdef _WIN32
#include <windows.h>

int Sys_Milliseconds(void) {
    return (int)GetTickCount();
}

void Sys_Sleep(int msec) {
    Sleep(msec);
}

void Sys_Mkdir(const char *path) {
    CreateDirectoryA(path, NULL);
}

char *Sys_Cwd(void) {
    static char cwd[MAX_PATH];
    GetCurrentDirectoryA(MAX_PATH, cwd);
    return cwd;
}
#endif
#endif
```

### 3. Conditional source inclusion
```python
if env['platform'] == 'windows':
    main_sources.append('code/godot/godot_sys_win.c')
    # Exclude Linux-specific sys files
    exclude_patterns.append('code/sys/sys_unix.c')
elif env['platform'] == 'linux':
    exclude_patterns.append('code/godot/godot_sys_win.c')
```

### 4. GDExtension manifest update
Update `bin/openmohaa.gdextension`:
```ini
[libraries]
linux.debug.x86_64 = "res://bin/libopenmohaa.so"
windows.debug.x86_64 = "res://bin/openmohaa.dll"
```

## Build Verification
```bash
# Check MinGW is available
which x86_64-w64-mingw32-gcc

# Build for Windows
cd openmohaa && scons platform=windows target=template_debug -j$(nproc) dev_build=yes

# Verify output
file bin/openmohaa.dll   # should say PE32+ executable
```

## Documentation
Append `## Phase 266: Windows Cross-Compile Support ✅` to `TASKS.md`.
