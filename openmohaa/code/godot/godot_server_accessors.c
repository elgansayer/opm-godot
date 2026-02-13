/*
 * godot_server_accessors.c — Thin accessor functions for server state.
 *
 * MoHAARunner.cpp (C++) cannot easily include server.h because of
 * the deep header dependency chain (q_shared.h → qcommon.h → server.h
 * collides with godot-cpp headers).  Instead, these C accessor
 * functions are compiled as part of the openmohaa source tree where
 * server.h is available, and MoHAARunner.cpp calls them via extern "C".
 */

#include "../server/server.h"

int Godot_GetServerState(void) {
    return (int)sv.state;
}

const char *Godot_GetMapName(void) {
    return svs.mapName;
}

int Godot_GetPlayerCount(void) {
    return svs.iNumClients;
}
