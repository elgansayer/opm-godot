# /web-launch — Build and launch the web version

Build the web export and launch it in Docker with the correct asset path, all in one command.

**Asset path:** `/home/elgan/mohaa-web-base/`

## Steps

1. Check if ports are free:
   ```bash
   ss -tlnp | grep -E ':(8086|12300) '
   ```
   If occupied by our containers, that's fine. If occupied by something else, warn and offer to stop it.

2. Ask if a fresh web build is needed or reuse existing `web/` output:
   - **Fresh build**: `./build.sh web --release`
   - **Reuse existing**: skip to step 3
   - If `web/mohaa.html` doesn't exist, force a fresh build

3. Start the Docker stack with the asset path:
   ```bash
   ASSET_PATH=/home/elgan/mohaa-web-base docker compose -f docker/docker-compose.yml up -d
   ```

4. Verify containers are running:
   ```bash
   docker compose -f docker/docker-compose.yml ps
   ```

5. Ask if any engine args are needed:
   - Game variant: AA (default), Spearhead (`+set com_target_game 1`), Breakthrough (`+set com_target_game 2`)
   - Map override (e.g., `+map dm/mohdm1`)
   - Cheats (`+set cheats 1`)
   - Or just launch with defaults

6. Open the browser:
   ```bash
   ./launch.sh web [any engine args from step 5]
   ```

7. Report:
   - URL opened (http://localhost:8086/mohaa.html with any query params)
   - Container status
   - How to stop: `docker compose -f docker/docker-compose.yml down`
   - How to view logs: `docker compose -f docker/docker-compose.yml logs -f`

## Troubleshooting

- If nginx fails to start, verify `/home/elgan/mohaa-web-base/main/` contains pk3 files
- If relay fails, check if port 12300 is already in use: `ss -tlnp | grep 12300`
- If the page loads but game doesn't start, run `/patch-status` to check web patches
- To force-rebuild containers: `ASSET_PATH=/home/elgan/mohaa-web-base docker compose -f docker/docker-compose.yml up -d --force-recreate`
