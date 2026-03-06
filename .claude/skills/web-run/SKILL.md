# /web-run — Build and run the web version in Docker

Build the web export and launch it locally in Docker with correct asset paths.

## Steps

1. Ask for the game asset path if not provided. This is the directory containing `main/`, `mainta/`, `maintt/` with pk3 files. Store the path for future use in this session.
2. Ask if a fresh build is needed or if the existing `web/` output should be reused
3. If building fresh:
   - Run `./build.sh web --release` and monitor for errors
   - Verify `web/mohaa.html` exists after build
4. Start the Docker stack:
   ```bash
   ASSET_PATH=<path> docker compose up -d
   ```
5. Verify containers are running:
   ```bash
   docker compose ps
   ```
6. Ask if any engine args should be passed (e.g., `+set com_target_game 2`, `+map dm/mohdm1`)
7. Open the browser:
   ```bash
   ./launch.sh web [engine args...]
   ```
8. Report:
   - URL: http://localhost:8086/mohaa.html (with any query params)
   - Container status
   - How to stop: `docker compose down`

## Troubleshooting

- If nginx container fails, check `ASSET_PATH` points to valid game assets
- If relay container fails, check if port is already in use (`network_mode: host`)
- Asset path must contain pk3 files in `main/`, `mainta/`, or `maintt/` subdirectories
