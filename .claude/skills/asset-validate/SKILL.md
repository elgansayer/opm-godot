# /asset-validate — Validate game asset directory

Check that a game asset directory is correctly structured for use with Docker builds and web deployment.

## Steps

1. Ask for the asset path if not provided as an argument
2. Validate the directory structure exists:
   ```bash
   ls -d "$ASSET_PATH"/main "$ASSET_PATH"/mainta "$ASSET_PATH"/maintt 2>/dev/null
   ```
3. Check each subdirectory for .pk3 files:
   ```bash
   find "$ASSET_PATH"/main -name "*.pk3" | wc -l
   find "$ASSET_PATH"/mainta -name "*.pk3" | wc -l
   find "$ASSET_PATH"/maintt -name "*.pk3" | wc -l
   ```
4. Show total asset size:
   ```bash
   du -sh "$ASSET_PATH"
   ```
5. Check for common issues:
   - Symlinks that could cause Docker mount problems
   - Missing directories (warn which game expansions are absent)
   - Empty directories with no pk3 files
6. Report: valid/invalid, with details on what's missing

## Expected structure

```
$ASSET_PATH/
  main/      — Medal of Honor: Allied Assault base assets (*.pk3)
  mainta/    — Spearhead expansion (*.pk3)
  maintt/    — Breakthrough expansion (*.pk3)
```

## Notes

- `main/` is required; `mainta/` and `maintt/` are optional expansion packs
- This path is used by `ASSET_PATH` env var in docker-compose.yml
- Common mistake: pointing to `main/` itself instead of its parent directory
