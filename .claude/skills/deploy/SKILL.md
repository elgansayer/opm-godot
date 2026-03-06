# /deploy — Full build, deploy, and push pipeline

Run the complete release pipeline: build web export, deploy locally via Docker, and push to GitHub.

## Steps

1. Ask for the asset path if not provided (e.g., `/path/to/mohaa-assets` containing `main/`, `mainta/`, `maintt/` with pk3 files)
2. Ask which steps to include:
   - Build web export (or `--skip-build` to reuse existing)
   - Local Docker deploy (or `--skip-serve`)
   - Git commit + push (or `--no-push`)
3. Run `./scripts/deploy.sh` with the chosen flags:
   ```
   ./scripts/deploy.sh --asset-path <path> [--skip-build] [--skip-serve] [--no-push] [--message "MSG"]
   ```
4. Monitor the pipeline output for errors at each stage
5. Report the result:
   - Build status
   - Local URL: http://localhost:8086
   - GitHub Actions link: https://github.com/elgansayer/opm-godot/actions
   - Portainer deployment status

## Important

- `--asset-path` is required unless using `--skip-serve`
- The deploy script will `git add -A && git commit && git push` — confirm with the user before pushing
- GHCR image: `ghcr.io/elgansayer/opm-godot:latest`
