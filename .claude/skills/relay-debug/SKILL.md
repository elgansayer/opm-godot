# /relay-debug — Debug the WebSocket-to-UDP relay server

Start or troubleshoot the Node.js WebSocket relay that bridges web clients to game servers.

## Steps

1. Check if relay is already running:
   ```bash
   docker compose ps relay 2>/dev/null
   # or check for standalone process
   pgrep -f mohaa_relay
   ```
2. Check relay dependencies:
   ```bash
   cd relay && npm ls
   ```
   Install if missing: `cd relay && npm install`
3. Check if the relay port (12300) is available:
   ```bash
   ss -tlnp | grep 12300
   ```
4. Options:
   - **Via Docker**: `docker compose up relay` (uses network_mode: host)
   - **Standalone**: `cd relay && node mohaa_relay.js`
5. Show relay logs:
   ```bash
   docker compose logs -f relay
   ```
6. Troubleshoot common issues:
   - Port 12300 already in use → identify and kill conflicting process
   - `ws` module not found → run `npm install` in relay/
   - Network mode host not working → check Docker permissions

## Notes

- The relay bridges WebSocket connections (from web clients) to UDP (game server protocol)
- It runs with `network_mode: host` in Docker to access the host network for UDP broadcast
- Source: `relay/mohaa_relay.js`
