# OPM-Godot

An experimental port of [OpenMoHAA](https://github.com/openmoh/openmohaa) (an open-source Medal of Honor: Allied Assault engine) into **Godot 4** as a GDExtension shared library.

The engine boots, loads maps, renders BSP world geometry with textures/lightmaps/shaders/terrain/patches/skybox, renders animated skeletal models (TIKI), plays positional 3D audio, handles keyboard/mouse input, draws HUD overlay with fonts, supports decals/marks/polys/sprites/beams/swipes, and exits cleanly.

> **Disclaimer:** This project is **not affiliated with, endorsed by, or connected to** the [OpenMoHAA project](https://github.com/openmoh/openmohaa), Electronic Arts, or any rights holders of Medal of Honor: Allied Assault. It is an independent, experimental project that uses OpenMoHAA's open-source engine code under the terms of the GNU General Public License v2.

## Requirements

- **Godot 4.2+** (must be in PATH as `godot`)
- **SCons** (`pip install scons`)
- **Linux build tools:** `gcc`, `g++`, `make`, `pkg-config`
- **Libraries:** `zlib`, `libdl`
- **Game assets (runtime only):** `Pak0.pk3`–`Pak6.pk3` from a MOHAA installation

## Quick Start

```bash
# Clone with submodules
git clone --recursive https://github.com/elgansayer/opm-godot.git
cd opm-godot

# Build
./build.sh

# Run (requires game assets in ~/.local/share/openmohaa/main/)
cd project && godot
```

## Repository Structure

```
opm-godot/
├── godot-cpp/          # Godot C++ bindings (submodule, branch 4.2)
├── openmohaa/          # Engine source with Godot glue code
│   ├── code/godot/     # All Godot-specific code
│   ├── SConstruct      # Build configuration
│   └── TASKS.md        # Implementation log
├── project/            # Godot editor project
├── docker/web/         # Docker config (nginx + Dockerfile)
├── relay/              # WebSocket-to-UDP relay server
├── scripts/            # Build, test, and release scripts
└── web/                # Web export output (gitignored)
```

## Building

### Native (Linux)

```bash
./build.sh
# Or manually:
cd openmohaa && scons platform=linux target=template_debug -j$(nproc) dev_build=yes
```

### Web (WASM)

Requires [Emscripten SDK](https://emscripten.org/docs/getting_started/downloads.html).

```bash
./build-web.sh
```

### Docker (local dev server)

```bash
ASSET_PATH=/path/to/mohaa-assets docker compose up
# Serves at http://localhost:8086
```

## Build Outputs

| File | Description |
|------|-------------|
| `openmohaa/bin/libopenmohaa.so` | Main GDExtension library |
| `openmohaa/bin/libcgame.so` | Client game module |
| `openmohaa/bin/libopenmohaa.wasm` | Web build (WASM) |

## Scripts

| Script | Purpose |
|--------|---------|
| `build.sh` | Native Linux build |
| `build-web.sh` | Full web build (SCons + Godot export + JS patches) |
| `release.sh` | Build → deploy → push pipeline |
| `test.sh` | Headless smoke test |

## Supported Games

- **Medal of Honor: Allied Assault** (`main/`)
- **Spearhead** expansion (`mainta/`)
- **Breakthrough** expansion (`maintt/`)

You must own the game to obtain the required `.pk3` asset files.

## License

This project is licensed under the **GNU General Public License v2** — see [LICENSE](LICENSE) for details.

The engine source is derived from [OpenMoHAA](https://github.com/openmoh/openmohaa), which is itself derived from [ioquake3](https://github.com/ioquake/ioq3) and the [F.A.K.K SDK](https://code.idtech.space/ritual/fakk2-sdk).
