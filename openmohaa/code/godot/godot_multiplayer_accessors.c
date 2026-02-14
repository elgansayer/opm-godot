/*
 * godot_multiplayer_accessors.c — Multiplayer server browser + hosting accessors.
 *
 * Provides thin C wrappers around engine commands for server browsing
 * (global/LAN queries) and server hosting.  MoHAARunner.cpp calls
 * these via extern "C" to avoid including client.h directly.
 */

#include "godot_multiplayer_accessors.h"

#ifdef GODOT_GDEXTENSION

#include "../qcommon/qcommon.h"
#include "../client/client.h"

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
    return cls.numlocalservers;
}

#endif
