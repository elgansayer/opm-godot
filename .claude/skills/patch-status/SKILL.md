# /patch-status — Check which web runtime patches are applied

Verify that the web build's JS/HTML patches were applied correctly by `build-web.sh`.

## Steps

1. Check that `web/mohaa.html` and `web/mohaa.js` exist
2. Check each patch by looking for its marker or injected code:

   | Patch | File | What to look for |
   |-------|------|-----------------|
   | Memory growth | mohaa.js | `patch_web_runtime_memory` or `ALLOW_MEMORY_GROWTH` |
   | Service worker disable | mohaa.html | Service worker registration removed/commented |
   | File picker | mohaa.html | File picker HTML/JS injected |
   | WebSocket relay | mohaa.js | Relay URL configuration |
   | SharedArrayBuffer | mohaa.html | COOP/COEP meta tags or headers |
   | Asset preload | mohaa.html | IndexedDB preload script |
   | dlopen patch | mohaa.js | cgame.so dynamic loading |
   | Audio unlock | mohaa.js | User gesture audio context resume |

3. Report status of each patch (applied/missing)
4. If any patches are missing, suggest re-running:
   ```bash
   ./build.sh web --release
   ```

## Notes

- Patches are applied by Python functions in `scripts/build-web.sh`
- A missing patch can cause silent failures (e.g., no audio, no asset loading)
- The `--patch-only` flag in build-web.sh can re-apply patches without full rebuild
