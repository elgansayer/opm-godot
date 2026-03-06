# /port-check — Check if required ports are available

Verify that ports needed by the Docker stack are not already in use.

## Steps

1. Check all required ports:
   ```bash
   ss -tlnp | grep -E ':(8086|12300) '
   ```
   - **8086** — nginx web server
   - **12300** — WebSocket relay
2. If ports are in use, identify the process:
   ```bash
   ss -tlnp | grep :<port>
   ```
3. Check if it's our own Docker containers:
   ```bash
   docker compose ps
   ```
4. Report:
   - Port 8086: free / in use by (process)
   - Port 12300: free / in use by (process)
5. If ports are occupied by old containers, offer to restart:
   ```bash
   docker compose down && docker compose up -d
   ```

## Notes

- Run this before `/web-run` or `/deploy` to avoid cryptic Docker bind errors
- The relay uses `network_mode: host`, so port 12300 is on the host directly
