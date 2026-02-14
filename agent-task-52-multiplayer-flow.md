# Agent Task 52: Multiplayer Server Browser + Create Server Flow

## Objective
Wire the engine's existing GameSpy master server query and server hosting into Godot-accessible functions. The engine already has `CL_GlobalServers`, `CL_LocalServers`, `SV_SpawnServer` — this agent exposes them via C accessors and adds GDScript-callable methods.

## Files to CREATE
- `code/godot/godot_multiplayer_accessors.c` — C accessor for server browser + hosting
- `code/godot/godot_multiplayer_accessors.h` — Header

## Files to MODIFY
- `code/godot/MoHAARunner.cpp` — `connect_to_server()`, `host_server()`, `refresh_server_list()` methods

## DO NOT MODIFY
- `code/gamespy/` (GameSpy protocol implementation)
- `code/client/cl_main.cpp` (client connect logic)
- `code/server/sv_init.c` (server spawn logic)
- `code/godot/godot_network_accessors.c` (owned by other agent)

## Implementation

### 1. Multiplayer accessors (`godot_multiplayer_accessors.c`)
```c
#include "godot_multiplayer_accessors.h"

#ifdef GODOT_GDEXTENSION
#include "../qcommon/qcommon.h"

void Godot_MP_ConnectToServer(const char *address) {
    char cmd[256];
    snprintf(cmd, sizeof(cmd), "connect %s\n", address);
    Cbuf_ExecuteText(EXEC_APPEND, cmd);
}

void Godot_MP_Disconnect(void) {
    Cbuf_ExecuteText(EXEC_APPEND, "disconnect\n");
}

void Godot_MP_HostServer(const char *mapname, int maxclients, int gametype) {
    char cmd[512];
    // Set cvars then launch
    snprintf(cmd, sizeof(cmd),
        "sv_maxclients %d\n"
        "g_gametype %d\n"
        "map %s\n",
        maxclients, gametype, mapname);
    Cbuf_ExecuteText(EXEC_APPEND, cmd);
}

void Godot_MP_RefreshServerList(void) {
    Cbuf_ExecuteText(EXEC_APPEND, "globalservers 0 12203 empty full\n");
}

void Godot_MP_RefreshLAN(void) {
    Cbuf_ExecuteText(EXEC_APPEND, "localservers\n");
}

int Godot_MP_GetServerCount(void) {
    extern int cls_numlocalservers;
    return cls_numlocalservers;
}
#endif
```

### 2. Header (`godot_multiplayer_accessors.h`)
```c
#pragma once
#ifdef __cplusplus
extern "C" {
#endif

void Godot_MP_ConnectToServer(const char *address);
void Godot_MP_Disconnect(void);
void Godot_MP_HostServer(const char *mapname, int maxclients, int gametype);
void Godot_MP_RefreshServerList(void);
void Godot_MP_RefreshLAN(void);
int  Godot_MP_GetServerCount(void);

#ifdef __cplusplus
}
#endif
```

### 3. MoHAARunner GDScript-callable methods
```cpp
#if __has_include("godot_multiplayer_accessors.h")
#define HAS_MP_MODULE
#include "godot_multiplayer_accessors.h"
#endif

void MoHAARunner::connect_to_server(String address) {
#ifdef HAS_MP_MODULE
    Godot_MP_ConnectToServer(address.utf8().get_data());
#endif
}

void MoHAARunner::host_server(String map, int maxplayers, int gametype) {
#ifdef HAS_MP_MODULE
    Godot_MP_HostServer(map.utf8().get_data(), maxplayers, gametype);
#endif
}

// Bind in _bind_methods:
ClassDB::bind_method(D_METHOD("connect_to_server", "address"), &MoHAARunner::connect_to_server);
ClassDB::bind_method(D_METHOD("host_server", "map", "maxplayers", "gametype"), &MoHAARunner::host_server);
```

### 4. Add to SConstruct
Ensure `godot_multiplayer_accessors.c` is in the main source list.

## Build Verification
```bash
cd openmohaa && scons platform=linux target=template_debug -j$(nproc) dev_build=yes
```

## Documentation
Append `## Phase 263: Multiplayer Server Browser + Hosting ✅` to `TASKS.md`.
