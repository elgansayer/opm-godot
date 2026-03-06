# /docker-logs — Tail and analyze Docker container logs

View and troubleshoot logs from the web and relay Docker containers.

## Steps

1. Check which containers are running:
   ```bash
   docker compose ps
   ```
2. If no containers are running, offer to start them (requires ASSET_PATH)
3. Show recent logs from all services:
   ```bash
   docker compose logs --tail=50
   ```
4. Analyze logs for common issues:
   - **nginx**: 403/404 errors (wrong asset path), missing COOP/COEP headers
   - **relay**: WebSocket connection failures, UDP forwarding errors, port conflicts
5. If errors found, suggest fixes:
   - Asset path issues → suggest running `/asset-validate`
   - Port conflicts → suggest running `/port-check`
   - Container crash loops → show `docker compose logs <service> --tail=100`
6. Offer to follow logs in real-time:
   ```bash
   docker compose logs -f
   ```

## Notes

- Relay uses `network_mode: host` — it shares the host's network stack
- nginx serves on port 8086
- Default relay port is 12300
