# /launch-config — Generate and run a launch command

Help configure and launch the game with the right arguments.

## Steps

1. Ask for the platform: `linux` or `web`
2. Ask for the launch mode:
   - **Play** — standard client
   - **Listen server** — host + play (with map selection)
   - **Dedicated server** — headless server
   - **Connect** — join an existing server
3. Ask for optional settings:
   - Game variant: AA (0), Spearhead (1), Breakthrough (2)
   - Map name (e.g., `dm/mohdm1`, `dm/mohdm2`)
   - Cheats enabled (yes/no)
   - Custom config to exec
4. Build the command:

   **Linux examples:**
   ```bash
   ./launch.sh linux                                          # Basic play
   ./launch.sh linux "+set com_target_game 2" --map=dm/mohdm1 # Breakthrough on mohdm1
   ./launch.sh linux --dedicated --map=dm/mohdm1              # Dedicated server
   ./launch.sh linux "+set cheats 1"                          # With cheats
   ./launch.sh linux "+connect 192.168.1.5"                   # Join server
   ```

   **Web examples:**
   ```bash
   ./launch.sh web                              # Basic web
   ./launch.sh web "+set com_target_game 1"     # Spearhead
   ./launch.sh web --server                     # Web server mode
   ```

5. Show the generated command and run it after user confirmation

## Notes

- Linux mode runs natively via Godot editor
- Web mode starts Docker stack (nginx + relay) and opens browser at http://localhost:8086/mohaa.html
- Web mode requires Docker to be running and ASSET_PATH configured
- Game variants: 0 = Allied Assault, 1 = Spearhead, 2 = Breakthrough
