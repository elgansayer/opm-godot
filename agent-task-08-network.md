# Agent Task 08: Network & Multiplayer Foundation

## Objective
Verify and fix the engine's networking stack under the Godot GDExtension integration: UDP socket management, server hosting, client connection flow, snapshot system, client prediction, lag compensation, reliable commands, master server registration, and connection robustness. Ensure full protocol compatibility with existing OpenMoHAA clients and servers.

## Starting Point
Read `.github/copilot-instructions.md`, `openmohaa/AGENTS.md`, and `openmohaa/TASKS.md`. Engine networking code compiles and is linked into the GDExtension binary. `NET_Init()` is called during `Com_Init()`. However, networking has not been tested with real remote clients/servers under the Godot integration. The engine uses standard UDP sockets (`code/qcommon/net_ip.c`) and the Quake 3 snapshot/delta protocol.

## Scope — Phases 121–155

### Phase 121: Network Initialisation
- Verify `NET_Init()` creates UDP sockets correctly under Godot runtime
- Check that socket creation doesn't fail due to Godot's process model
- Verify `Sys_IsLANAddress()`, `NET_SendPacket()`, `NET_GetPacket()` work correctly
- Test `net_port` cvar (default 12203 for MOHAA)
- Check IPv4 binding on all interfaces

### Phase 122: Server Hosting
- Verify `SV_Init()` → server starts and listens for connections
- Test `sv_maxclients` (player limit), `sv_hostname`, `g_gametype`
- Listen server mode: client + server in one process (already the default with `dedicated 0`)
- Dedicated server mode: test with `dedicated 1` (headless)
- Verify `sv_mapRotation` and `SV_MapRestart()` work

### Phase 123: Client Connection Flow
- `connect <ip:port>` command initiates connection
- Challenge/response handshake: `getchallenge` → `challengeResponse` → `connect`
- Connection accepted → `clientConnect` → gamestate download → first snapshot
- Verify the full pipeline: `CL_Connect_f()` → `CL_ConnectionlessPacket()` → `CL_ParseGamestate()`
- Check timeout handling if server doesn't respond

### Phase 124: Snapshot System
- Delta-compressed entity snapshots from server to client
- `SV_BuildClientSnapshot()` — gathers visible entities for each client
- `SV_SendClientSnapshot()` — delta-compresses against last acknowledged snapshot
- `CL_ParseSnapshot()` — client decodes and applies
- Verify entity baseline creation and delta encoding produce correct results
- Check snapshot size limits (`sv_maxSnapshotSize`)

### Phase 125: Client Prediction
- `CL_PredictPlayerState()` — runs `Pmove()` locally with pending usercmds
- Prediction error correction: smooth snap-back when server state diverges
- Verify prediction runs the same `Pmove()` as server (shared `bg_pmove.cpp`)
- Check `cl_predict` cvar
- Test with simulated latency: does prediction hide lag correctly?

### Phase 126: Lag Compensation
- `sv_antilag` cvar enables server-side lag compensation
- Server rewinds entity positions to client's timestamp for hit detection
- Verify `G_AntilagRewind()` / `G_AntilagForward()` work correctly
- Test with `CL_TimeNudge` and varying network latency

### Phase 127: Reliable Commands
- `clc_clientCommand` / `svc_serverCommand` — guaranteed delivery over UDP
- Command sequence numbers ensure ordering
- Handle overflow: `MAX_RELIABLE_COMMANDS` (64 or 128)
- Verify config string updates (`CS_PLAYERS`, `CS_SERVERINFO`) arrive correctly
- Test rapid command submission (e.g. rapid chat messages)

### Phase 128: Configstrings & Userinfo
- Server sends configstrings during gamestate
- Client sends userinfo (`name`, `rate`, `model`, etc.)
- Verify `SV_UpdateConfigString()` propagates to all connected clients
- Check `CL_SystemInfoChanged()` handles all fields

### Phase 129: Master Server Registration
- GameSpy heartbeat protocol (`code/gamespy/`)
- `sv_master1` / `sv_master2` cvars point to master server(s)
- Heartbeat packets: server sends periodic heartbeats with server info
- Status query responses: external tools query server info
- Verify `SV_MasterHeartbeat()`, `SV_MasterGameSpy()`
- Test with public OpenMoHAA master server if available

### Phase 130: Connection Robustness
- Timeout handling: `cl_timeout` (client), `sv_timeout` (server)
- Graceful disconnect: `disconnect` command sends reliable disconnect
- Ungraceful disconnect: timeout detection and client slot cleanup
- Network error recovery: ignore malformed packets, handle partial reads
- Reconnect logic: `reconnect` command re-establishes connection

### Phases 131–140: Protocol Compatibility Testing
- **131:** Test: our client → OpenMoHAA dedicated server (compile opm server separately or use existing)
- **132:** Test: OpenMoHAA client → our server
- **133:** Protocol version negotiation (`PROTOCOL_VERSION` in `qcommon.h`)
- **134:** Game version matching — AA (target_game=0), SH (1), BT (2) protocols
- **135:** Cross-version edge cases (e.g. SH client → AA server)
- **136:** Player count testing — verify up to `sv_maxclients` connections (start with 2, test 4, 8, 16)
- **137:** Map rotation — `sv_mapRotation` cycling, mid-match map changes
- **138:** Vote system — `callvote`, `vote yes/no` commands
- **139:** RCON — `rcon <password> <command>` remote administration
- **140:** Spectator mode — spectator join, free-fly, follow modes

### Phases 141–150: Network Edge Cases
- **141:** Port forwarding verification — ensure `net_port` is correctly bound
- **142:** IPv4 support verification (IPv6 if engine supports it)
- **143:** Rate limiting: `rate`, `snaps`, `cl_maxpackets` cvars honoured
- **144:** Packet fragmentation for large snapshots (maps with many entities)
- **145:** Server-authoritative state — clients can't inject invalid state
- **146:** Client disconnect cleanup — entity removal, score preservation
- **147:** Server shutdown: `killserver` → all clients gracefully disconnected
- **148:** Multiple servers on different ports (`+set net_port XXXXX`)
- **149:** RCON password authentication (`rconpassword` cvar)
- **150:** Server status query protocol (for external server browsers)

### Phases 151–155: Network Performance
- **151:** Bandwidth profiling: measure bytes/sec for various scenarios
- **152:** Snapshot size optimisation: verify delta compression works efficiently
- **153:** PVS-based snapshot building: only send entities visible to client
- **154:** Server tick rate stability: verify `sv_fps` (default 20) is consistent
- **155:** Client interpolation: verify smooth entity movement between snapshots

## Files You OWN (create or primarily modify)

### New files to create
| File | Purpose |
|------|---------|
| `code/godot/godot_network_accessors.c` | C accessors for network state: connection status, ping, packet stats |
| `code/godot/godot_network_accessors.h` | Network accessor header |

### Engine files you may modify (with `#ifdef GODOT_GDEXTENSION` guards)
| File | What to change |
|------|----------------|
| `code/qcommon/net_ip.c` | Socket initialisation fixes if Godot's process model causes issues |
| `code/qcommon/net_chan.c` | Channel reliability fixes if needed |
| `code/qcommon/msg.c` | Message read/write fixes if snapshot encoding differs |
| `code/server/sv_client.c` | Client connection handling fixes |
| `code/server/sv_snapshot.c` | Snapshot building fixes |
| `code/server/sv_init.c` | Server init fixes |
| `code/server/sv_main.c` | Server frame/heartbeat fixes |
| `code/client/cl_main.cpp` | Client connection flow fixes |
| `code/client/cl_net_chan.cpp` | Client network channel |
| `code/client/cl_parse.cpp` | Snapshot parsing fixes |
| `code/client/cl_cgame.cpp` | Client-game communication |
| `code/gamespy/*.c` | Master server registration fixes |

**ALL changes MUST be wrapped in `#ifdef GODOT_GDEXTENSION` / `#endif`.**

## Files You Must NOT Touch
- `MoHAARunner.cpp` / `MoHAARunner.h` — do NOT modify.
- `godot_renderer.c` — not your domain.
- `godot_sound.c` — owned by Agent 1.
- `godot_shader_props.cpp/.h` — owned by Agent 2.
- `godot_bsp_mesh.cpp/.h` — owned by Agent 3.
- `godot_skel_model*.cpp` — owned by Agent 4.
- `code/fgame/*.cpp` — owned by Agent 7 (Game Logic). If you find a game-logic bug during network testing, document it for Agent 7.
- Files in `code/godot/` created by other agents.

## Architecture Notes

### Network State Machine
```
Client states (cls.state):
  CA_UNINITIALIZED → CA_DISCONNECTED → CA_CONNECTING → CA_CHALLENGING
  → CA_CONNECTED → CA_LOADING → CA_PRIMED → CA_ACTIVE

Server client states (client->state):
  CS_FREE → CS_ZOMBIE → CS_CONNECTED → CS_PRIMED → CS_ACTIVE
```

### Key cvars
```
sv_maxclients        — max player count
sv_fps               — server tick rate (default 20)
sv_timeout           — client timeout (seconds)
cl_timeout           — server timeout (seconds)
rate                 — client bandwidth (bytes/sec)
snaps                — client snapshot request rate
cl_maxpackets        — max client packets per second
sv_antilag           — lag compensation enable
rconpassword         — remote console password
net_port             — UDP port (default 12203)
```

### Testing Without Remote Clients
Most verification can be done by:
1. Inspecting code paths with `#ifdef GODOT_GDEXTENSION` guards
2. Adding debug logging to network functions
3. Testing loopback: `connect localhost` (client connects to its own server)
4. Verifying server starts and responds to heartbeats

For actual multi-client testing (Phases 131+), you'd need a second MOHAA client instance.
At minimum, verify loopback connection works.

### Network Accessor Design
```c
// godot_network_accessors.h
int Godot_Net_GetClientState(void);           // cls.state
int Godot_Net_GetServerClientCount(void);     // count of active clients
int Godot_Net_GetPing(void);                  // cls.ping (if connected)
int Godot_Net_GetSnapshotRate(void);          // current snapshot rate
const char *Godot_Net_GetServerAddress(void); // server we're connected to
int Godot_Net_IsLANGame(void);               // whether current game is LAN
```

## Integration Points
Document in TASKS.md:
1. Network accessor functions available for Agent 5 (UI — server browser), Agent 10 (Integration)
2. Any engine fixes that affect server/client startup in `Com_Init` flow
3. Any new cvars or commands added
4. Protocol compatibility status for each game version (AA/SH/BT)

## Build & Test
```bash
cd openmohaa && rm -f .sconsign.dblite && scons platform=linux target=template_debug -j$(nproc) dev_build=yes
```

## Documentation
Add Phase entries (121–155) to `openmohaa/TASKS.md`.

## Merge Awareness
- You primarily work in `code/qcommon/`, `code/server/`, `code/client/` networking files, and `code/gamespy/`.
- Agent 7 (Game Logic) works in `code/fgame/` — no overlap.
- Agent 5 (UI) works on UI rendering — no overlap, but may call your network accessors.
- Your `godot_network_accessors.c/.h` files are new — zero conflict risk.
- **Shared file risk:** `code/server/sv_main.c` — both you and Agent 7 might touch this. You own the network/heartbeat sections; Agent 7 owns game logic sections. Use `#ifdef` comments to delineate.
- **Shared file risk:** `code/client/cl_main.cpp` — you own connection flow; Agent 5 might need input routing in `cl_keys.cpp`. These are different files so should be fine.
