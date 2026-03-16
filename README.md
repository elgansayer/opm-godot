# ShinMOHAA

ShinMOHAA ports OpenMoHAA into Godot 4 as a monolithic GDExtension. The original engine code still provides the game, networking, script, and asset-loading behaviour; Godot provides the host runtime, scene integration, and export pipeline.

This repository currently has two supported build front doors:

- `./build.sh` for the normal day-to-day workflow.
- Root `CMakeLists.txt` and `CMakePresets.json` as an orchestration layer over the same shell scripts.

Important: the root CMake project does not replace the underlying engine build. It drives the repository's shell scripts, which in turn invoke SCons for the engine and `godot --export-*` for packaged exports.

## Contents

1. [What This Repo Builds](#what-this-repo-builds)
2. [Repository Layout](#repository-layout)
3. [Build System Overview](#build-system-overview)
4. [Platform Support Matrix](#platform-support-matrix)
5. [Build Cheat Sheet](#build-cheat-sheet)
6. [Requirements](#requirements)
7. [Game Assets](#game-assets)
8. [Quick Start](#quick-start)
9. [CMake Usage](#cmake-usage)
10. [Platform Guides](#platform-guides)
11. [Running And Testing](#running-and-testing)
12. [Custom Cvars](#custom-cvars)
13. [Troubleshooting](#troubleshooting)
14. [Current Gaps](#current-gaps)
15. [Disclaimer And Licence](#disclaimer-and-licence)

## What This Repo Builds

The main outputs are:

- Engine libraries staged into `project/bin/` for development.
- Godot exports staged into `dist/<platform>/<variant>/` for packaged builds.
- Optional archives under `dist/packages/`.

Typical staged engine outputs are:

| Target platform | Main library in `project/bin/` | Runtime companion |
| --- | --- | --- |
| Linux | `libopenmohaa.so` | `cgame.so` |
| Windows | `openmohaa.dll` or `libopenmohaa.dll` | `cgame.dll` plus MinGW runtime DLLs |
| macOS | `libopenmohaa.dylib` | `cgame.dylib` |
| Web | `libopenmohaa.wasm` | web export assets |

Typical packaged export outputs are:

| Target platform | Export output |
| --- | --- |
| Linux | `dist/linux/<variant>/openmohaa.x86_64` |
| Windows | `dist/windows/<variant>/openmohaa.exe` |
| macOS | `dist/macos/<variant>/openmohaa.app` |
| Web | Current full pipeline writes the patched export to `web/mohaa.html` |

## Repository Layout

```text
mohaa-godot/
|- build.sh                 Top-level build entry point
|- CMakeLists.txt           CMake orchestration layer
|- CMakePresets.json        Configure/build presets
|- launch.sh                Simple Linux/web launcher helper
|- openmohaa/               Engine source and SCons build
|- project/                 Godot project and export presets
|- scripts/                 Build/export/package/test helpers
|  |- build-desktop.sh      Desktop engine build + staging
|  |- build-web.sh          Web engine build, export, patching, and serving
|  |- export-godot.sh       Godot CLI export step
|  |- package-build.sh      Package dist archives
|  `- web_assets/           Static assets and scripts for web patching
|     |- patch_web_js.py    Applies 10 named patches to Emscripten-generated mohaa.js
|     |- render_html_template.py  Patches the exported HTML with templates
|     |- js/                Static JavaScript injected into mohaa.js
|     |  |- module_prerun.js        Memory polyfill, stdout capture, VFS preloader
|     |  |- stubs_resolver.js       C++ exception ABI, longjmp, invoke_* wrappers
|     |  |- resolve_global_symbol.js  Extended symbol resolution with fallbacks
|     |  `- ws_relay_bridge.js      WebSocket relay bridge for multiplayer
|     `- templates/         HTML/CSS/JS templates injected into mohaa.html
|        |- boot_block.js           Boot UI, file picker logic, cvar display
|        |- file_picker.html        Pak file upload form
|        |- file_picker.css         File picker and boot UI styles
|        `- service_worker_cleanup_head.html  Service worker unregistration
|- dist/                    Packaged exports
|- build-cmake/             CMake configure trees
|- docker/                  Web hosting stack
|- relay/                   WebSocket-to-UDP relay
`- godot-cpp/               Godot C++ bindings submodule
```

## Build System Overview

There are four layers in the current build pipeline:

1. `openmohaa/SConstruct`
   Builds the engine and companion modules with SCons.

2. `scripts/build-desktop.sh` and `scripts/build-web.sh`
   Repository-owned wrappers that build the engine and stage outputs into `project/bin/`.

3. `scripts/export-godot.sh`
   Runs the Godot CLI export step into `dist/<platform>/<variant>/`.

4. `build.sh` and root CMake
   High-level orchestration over the scripts above.

### Web patching pipeline

The web build has an extra post-export step. Godot's Emscripten export produces vanilla HTML and JS files that need game-specific patches to work with the OpenMoHAA engine. Two Python scripts handle this:

- `scripts/web_assets/patch_web_js.py` applies 10 named patches to `mohaa.js`: memory pre-grow, Module preRun injection, Emscripten symbol diagnostics, C++ stubs resolver, resolveGlobalSymbol extension, cgame.so pre-registration, loadDynamicLibraries override, locateFile override, CXA exception stubs, and WebSocket relay bridge.
- `scripts/web_assets/render_html_template.py` patches `mohaa.html` with service worker cleanup, file picker UI, boot block JS, and CSS from template files.

All injected JavaScript lives in `scripts/web_assets/js/` as standalone `.js` files. All injected HTML, CSS, and boot JS lives in `scripts/web_assets/templates/`. The Python scripts read these static files and insert them at the correct locations in the exported output — no inline heredocs or string construction.

For Web specifically, the current full pipeline is special: `scripts/build-web.sh` exports and patches the web build in `web/`, while some adjacent scripts still expect a later `dist/web/<variant>/` layout. Treat `build.sh web-full` as the source of truth for the current web flow.

The recommended mental model is:

- `build.sh build --platform ...` means "compile and stage engine libraries for development".
- `build.sh package --platform ...` means "compile, export, stage companions, and archive".
- `cmake --preset ...` configures the same flows, but still ends up calling the shell scripts.

## Platform Support Matrix

This table reflects what is actually wired by the scripts in this repository today.

| Host OS | Linux target | Windows target | macOS target | Web target | Notes |
| --- | --- | --- | --- | --- | --- |
| Linux | Yes, native | Yes, via MinGW-w64 cross toolchain | Yes, via osxcross | Yes | Best-supported all-round build host |
| Windows | Not scripted | Yes, native via MSYS2/MinGW and a Bash shell | Not scripted | Not documented | Use MSYS2 MINGW64 or WSL rather than plain `cmd.exe` |
| macOS | Not scripted | Not scripted | Yes, native | Not documented | Native macOS target is supported; cross-target desktop builds are not wired here |

Practical guidance:

- If you want one host that can build Linux, Windows, and macOS targets, use Linux.
- If you want to build on Windows itself, the supported path is a native Windows target build from an MSYS2 MINGW64 shell.
- If you want to build on macOS itself, the supported path is a native macOS target build.

## Build Cheat Sheet

Use this section if you just want the right command quickly.

### Most common development builds

| Goal | Recommended command |
| --- | --- |
| Linux host -> Linux debug engine | `./build.sh build --platform linux` |
| Linux host -> Linux release engine | `./build.sh build --platform linux --release` |
| Linux host -> Windows debug engine | `./build.sh build --platform windows` |
| Linux host -> Windows release engine | `./build.sh build --platform windows --release` |
| Linux host -> macOS debug engine | `./build.sh build --platform macos --arch x86_64` or `--arch arm64` |
| Linux host -> macOS release engine | `./build.sh build --platform macos --release --arch x86_64` or `--arch arm64` |
| Windows host -> Windows debug engine | `./build.sh build --platform windows` |
| Windows host -> Windows release engine | `./build.sh build --platform windows --release` |
| macOS host -> macOS debug engine | `./build.sh build --platform macos` |
| macOS host -> macOS release engine | `./build.sh build --platform macos --release` |
| Any supported host -> full web pipeline | `./build.sh web-full --asset-path /path/to/openmohaa-data` |

### Most common packaged exports

| Goal | Recommended command |
| --- | --- |
| Linux package | `./build.sh package --platform linux` |
| Linux release package | `./build.sh package --platform linux --release` |
| Windows package | `./build.sh package --platform windows` |
| Windows release package | `./build.sh package --platform windows --release` |
| macOS package | `./build.sh package --platform macos` |
| macOS release package | `./build.sh package --platform macos --release` |

### Same flows via CMake

If you prefer CMake, the equivalent pattern is:

```bash
cmake --preset <platform>-<variant>
cmake --build build-cmake/<platform>-<variant> --target mohaa-engine
cmake --build build-cmake/<platform>-<variant> --target mohaa-export
```

Examples:

```bash
cmake --preset linux-debug
cmake --build build-cmake/linux-debug --target mohaa-engine

cmake --preset windows-release
cmake --build build-cmake/windows-release --target mohaa-engine
cmake --build --preset windows-release-export
```

## Requirements

### Common tools

These are the baseline tools used by the repository:

| Tool | Why it is needed |
| --- | --- |
| `git` | Clone repo and submodules |
| `python3` | SCons and helper scripts |
| `scons` | Engine build |
| `cmake` | Optional orchestration layer |
| `ninja` | Required by the CMake presets |
| `godot` | Run and export the Godot project |
| `bison` | Parser generation when generated files are absent |
| `flex` | Lexer generation when generated files are absent |

### Linux host

Recommended packages on Debian or Ubuntu:

```bash
sudo apt-get update
sudo apt-get install -y \
  build-essential \
  bison \
  flex \
  cmake \
  ninja-build \
  pkg-config \
  zlib1g-dev \
  mingw-w64
python3 -m pip install --user scons
```

Additional tools by target:

- Linux target: nothing extra beyond the base toolchain.
- Windows target: `x86_64-w64-mingw32-g++` and `x86_64-w64-mingw32-objdump` in `PATH`.
- macOS target: a working `osxcross` installation and `OSXCROSS_ROOT` set.
- Web target: an installed Emscripten SDK, usually at `~/emsdk` or passed with `--emsdk`.

### Windows host

Use an MSYS2 `MINGW64` shell, not plain PowerShell or `cmd.exe`, because the repo scripts are Bash scripts.

Install packages from MSYS2:

```bash
pacman -S --needed \
  base-devel \
  git \
  mingw-w64-x86_64-toolchain \
  mingw-w64-x86_64-cmake \
  mingw-w64-x86_64-ninja \
  mingw-w64-x86_64-python \
  mingw-w64-x86_64-bison \
  mingw-w64-x86_64-flex
python -m pip install --user scons
```

You also need:

- `godot` available in `PATH`.
- A Bash shell capable of running `./build.sh` and the scripts under `scripts/`.

### macOS host

Install Xcode Command Line Tools first:

```bash
xcode-select --install
```

Then install userland tools, for example with Homebrew:

```bash
brew install python scons cmake ninja bison flex
```

If Homebrew installs `bison` and `flex` outside the default shell `PATH`, export them before building:

```bash
export PATH="$(brew --prefix bison)/bin:$(brew --prefix flex)/bin:$PATH"
```

## Game Assets

Game assets are not included in this repository. They are only required at runtime, not for compilation, and the binaries must be able to see your existing MOHAA install through the engine's normal filesystem search paths.

The game searches for data under three root path variables:

- `fs_homedatapath`: user data root used for readable game content and writable runtime data.
- `fs_basepath`: install/data root.
- `fs_homepath`: user override root; if set manually it overrides the default home locations.

Within those roots, the engine searches the game directories it is configured to use:

- `main/` for Allied Assault.
- `mainta/` for Spearhead.
- `maintt/` for Breakthrough.
- `fs_game/` first if you are running a mod.
- `fs_basegame/` as an additional base game layer when set.

In practice, that means your MOHAA data only needs to exist in a location the engine can reach through those roots. On Linux, this port commonly resolves data under `~/.local/share/openmohaa`, while config/state files use the home-path settings separately. You can also point the game at another install by passing startup cvars such as:

```bash
godot --path project -- +set fs_basepath "/path/to/openmohaa-data"
godot --path project -- +set fs_homedatapath "/path/to/openmohaa-data"
```

For the base game, the web pipeline still needs the full `pak0.pk3` through `pak6.pk3` set available under the chosen asset path's `main/` directory.

## Quick Start

### Clone the repository

```bash
git clone --recursive https://github.com/elgansayer/mohaa-godot.git
cd mohaa-godot
```

### Quick start with `build.sh`

Linux native debug build:

```bash
./build.sh build --platform linux
```

That will:

- build the engine via `scripts/build-desktop.sh`
- stage libraries into `project/bin/`
- leave the Godot project ready to run locally

Then run a smoke test:

```bash
./scripts/test.sh
```

Or launch the project manually:

```bash
godot --path project
```

### Quick start with CMake

Linux native debug build:

```bash
cmake --preset linux-debug
cmake --build --preset linux-debug-engine
```

Linux packaged export:

```bash
cmake --build --preset linux-debug-export
```

The CMake build presets are not symmetrical for every target, so read the [CMake Usage](#cmake-usage) section below before assuming that every platform has a `*-engine` shortcut preset.

## CMake Usage

The root CMake project is an orchestrator. It does not compile the engine directly; it defines custom targets that call the repository scripts.

Key cache variables:

| Variable | Values | Purpose |
| --- | --- | --- |
| `MOHAA_TARGET_PLATFORM` | `linux`, `windows`, `macos`, `web`, `android`, `ios` | Selects target platform |
| `MOHAA_BUILD_VARIANT` | `debug`, `release` | Selects debug or release flow |
| `MOHAA_ARCH` | target-specific | Architecture hint, mainly for macOS |
| `MOHAA_EMSDK_DIR` | path | Emscripten SDK root for web builds |
| `MOHAA_GODOT_EXPORT_PRESET` | preset name | Override Godot export preset |
| `MOHAA_GODOT_EXPORT_OUTPUT` | path | Override export output path |

Key CMake targets:

| Target | What it does |
| --- | --- |
| `mohaa-engine` | Build and stage engine artefacts into `project/bin/` |
| `mohaa-export` | Run the normal Godot export flow using artefacts already staged in `project/bin/`; for desktop targets this writes to `dist/<platform>/<variant>/` |
| `mohaa-web-export` | Run the current full web pipeline via `scripts/build-web.sh`; today that produces the patched export in `web/` |
| `mohaa-package` | Create archive from `dist/<platform>/<variant>/` |
| `mohaa-sign-android` | Signing helper |
| `mohaa-sign-ios` | Signing helper |

### Configure presets

Available configure presets live in `CMakePresets.json` and include:

- `linux-debug`, `linux-release`
- `windows-debug`, `windows-release`
- `macos-debug`, `macos-release`
- `web-debug`, `web-release`
- `android-debug`, `android-release`
- `ios-debug`, `ios-release`

Important: Android and iOS presets exist in CMake, but they are not fully wired end-to-end in the same way as Linux, Windows, macOS, and Web. This README focuses on the desktop and web flows that are actually implemented.

### Build presets

Convenience build presets currently exist for:

- Linux engine and export
- Web engine and export
- Windows export
- macOS export
- Android release export
- iOS release export

That means:

- `cmake --build --preset linux-debug-engine` works.
- `cmake --build --preset windows-debug-export` works.
- There is no `windows-debug-engine` build preset today, so for that case you build the target explicitly from the configure tree.

### Recommended CMake command patterns

Linux target:

```bash
cmake --preset linux-debug
cmake --build --preset linux-debug-engine
cmake --build --preset linux-debug-export
```

If you want a one-shot package rather than a separate engine build and export, run:

```bash
cmake --build build-cmake/linux-debug --target mohaa-package
```

Windows target:

```bash
cmake --preset windows-debug
cmake --build build-cmake/windows-debug --target mohaa-engine
cmake --build --preset windows-debug-export
```

macOS target:

```bash
cmake --preset macos-debug
cmake --build build-cmake/macos-debug --target mohaa-engine
cmake --build --preset macos-debug-export
```

Web target:

```bash
cmake --preset web-debug
cmake --build --preset web-debug-engine
cmake --build --preset web-debug-export
```

If you want release builds, swap `debug` for `release`.

## Platform Guides

### Linux host -> Linux target

This is the simplest native desktop build.

Debug engine build with `build.sh`:

```bash
./build.sh build --platform linux
```

Release engine build with `build.sh`:

```bash
./build.sh build --platform linux --release
```

Debug engine build with CMake:

```bash
cmake --preset linux-debug
cmake --build --preset linux-debug-engine
```

Release engine build with CMake:

```bash
cmake --preset linux-release
cmake --build --preset linux-release-engine
```

Debug packaged export:

```bash
./build.sh package --platform linux
```

Release packaged export:

```bash
./build.sh package --platform linux --release
```

Debug packaged export with CMake:

```bash
cmake --build --preset linux-debug-engine
cmake --build --preset linux-debug-export
```

Release packaged export with CMake:

```bash
cmake --preset linux-release
cmake --build --preset linux-release-engine
cmake --build --preset linux-release-export
```

### Linux host -> Windows target

This path is explicitly supported by the repo scripts using MinGW-w64.

Requirements:

- `x86_64-w64-mingw32-g++` in `PATH`
- `x86_64-w64-mingw32-objdump` in `PATH`
- `godot` export templates installed if you want `.exe` exports

Debug engine build with `build.sh`:

```bash
./build.sh build --platform windows
```

Release engine build with `build.sh`:

```bash
./build.sh build --platform windows --release
```

Debug engine build with CMake:

```bash
cmake --preset windows-debug
cmake --build build-cmake/windows-debug --target mohaa-engine
```

Release engine build with CMake:

```bash
cmake --preset windows-release
cmake --build build-cmake/windows-release --target mohaa-engine
```

Debug packaged export:

```bash
./build.sh package --platform windows
```

Release packaged export:

```bash
./build.sh package --platform windows --release
```

Debug packaged export with CMake:

```bash
cmake --build build-cmake/windows-debug --target mohaa-engine
cmake --build --preset windows-debug-export
```

Release packaged export with CMake:

```bash
cmake --preset windows-release
cmake --build build-cmake/windows-release --target mohaa-engine
cmake --build --preset windows-release-export
```

What the scripts do for you:

- build the Windows DLLs
- stage `cgame.dll`
- stage MinGW runtime DLLs such as `libstdc++-6.dll`, `libgcc_s_seh-1.dll`, and `libwinpthread-1.dll` when found

### Linux host -> macOS target

This path is supported via `osxcross`.

First, verify the toolchain:

```bash
./scripts/setup-macos-build.sh
```

If needed, generate a reusable shell snippet:

```bash
./scripts/configure-macos-cross-env.sh
source scripts/env.macos-cross.sh
```

Then build a debug engine for Intel macOS:

```bash
./build.sh build --platform macos --arch x86_64
```

Or a debug engine for Apple Silicon:

```bash
./build.sh build --platform macos --arch arm64
```

Release engine examples:

```bash
./build.sh build --platform macos --release --arch x86_64
./build.sh build --platform macos --release --arch arm64
```

Debug engine build with CMake:

```bash
cmake --preset macos-debug -DMOHAA_ARCH=x86_64
cmake --build build-cmake/macos-debug --target mohaa-engine
cmake --build --preset macos-debug-export
```

Release engine or export with CMake:

```bash
cmake --preset macos-release -DMOHAA_ARCH=x86_64
cmake --build build-cmake/macos-release --target mohaa-engine
cmake --build --preset macos-release-export
```

If you want a one-shot packaged build with CMake instead of separate steps:

```bash
cmake --build build-cmake/macos-debug --target mohaa-package
```

Or the release equivalent:

```bash
cmake --build build-cmake/macos-release --target mohaa-package
```

Notes:

- `scripts/build-desktop.sh` auto-detects the `osxcross_sdk` tag if you do not pass one.
- macOS signing and notarisation are separate concerns from building the unsigned app bundle.
- A native macOS host is still the better place to do final signed macOS releases.

### Windows host -> Windows target

Use an MSYS2 `MINGW64` shell.

Debug engine build with `build.sh`:

```bash
./build.sh build --platform windows
```

Release engine build with `build.sh`:

```bash
./build.sh build --platform windows --release
```

Debug engine build with CMake:

```bash
cmake --preset windows-debug
cmake --build build-cmake/windows-debug --target mohaa-engine
cmake --build --preset windows-debug-export
```

Release engine or export with CMake:

```bash
cmake --preset windows-release
cmake --build build-cmake/windows-release --target mohaa-engine
cmake --build --preset windows-release-export
```

Important details:

- Run from a Bash-capable shell such as MSYS2 `MINGW64`.
- The repository scripts are not written for MSVC-first workflows.
- The current documented native Windows path is MinGW-based.

### macOS host -> macOS target

Debug engine build with `build.sh`:

```bash
./build.sh build --platform macos
```

Release engine build with `build.sh`:

```bash
./build.sh build --platform macos --release
```

Debug engine build with CMake:

```bash
cmake --preset macos-debug
cmake --build build-cmake/macos-debug --target mohaa-engine
cmake --build --preset macos-debug-export
```

Release engine or export with CMake:

```bash
cmake --preset macos-release
cmake --build build-cmake/macos-release --target mohaa-engine
cmake --build --preset macos-release-export
```

If you want a specific architecture, pass it through:

```bash
./build.sh build --platform macos --arch arm64
./build.sh build --platform macos --arch x86_64
```

The Godot export preset is currently set up for a universal macOS export path in `project/export_presets.cfg`, while the engine build itself can be steered with `--arch`.

### Web target

Debug full web pipeline with `build.sh`:

```bash
./build.sh web-full --asset-path /path/to/openmohaa-data
```

Release full web pipeline with `build.sh`:

```bash
./build.sh web-full --release --asset-path /path/to/openmohaa-data
```

Debug web build with CMake:

```bash
cmake --preset web-debug
cmake --build --preset web-debug-engine
cmake --build --preset web-debug-export
```

Release web build with CMake:

```bash
cmake --preset web-release
cmake --build --preset web-release-engine
cmake --build --preset web-release-export
```

Notes:

- `scripts/build-web.sh` expects an Emscripten SDK, defaulting to `~/emsdk`.
- The full web flow is more than just a Godot export; it also applies web-specific JS and HTML patching via `scripts/web_assets/patch_web_js.py` and `scripts/web_assets/render_html_template.py` (see [Web patching pipeline](#web-patching-pipeline)).
- Use `--patch-only` to re-run just the patching step without rebuilding or re-exporting.
- Use `--serve` to start a local HTTPS dev server on port 8443 after building.
- The current full pipeline writes the patched browser build to `web/mohaa.html` and stages related files under `web/`.
- Some surrounding scripts still expect `dist/web/<variant>/`, including `build.sh serve`, `scripts/build-web-docker.sh`, and `scripts/deploy.sh`, so that part of the web toolchain is not fully reconciled yet.

## Running And Testing

### Run the project locally

Cross-platform manual run:

```bash
godot --path project
```

Linux helper launcher:

```bash
./launch.sh linux
```

Headless smoke test:

```bash
./scripts/test.sh
```

Full test suite:

```bash
./scripts/test-all.sh
```

Optional build-matrix sanity check:

```bash
./scripts/test-build-matrix.sh
```

## Custom Cvars

This port adds several console variables on top of the standard OpenMoHAA/MOHAA set. All of these are set from the in-game console (`~`) using `seta <cvar> <value>`. Archived cvars are saved to the config file automatically.

### Rendering

| Cvar | Default | Flags | Description |
| --- | --- | --- | --- |
| `r_shadows` | `0` | archive | Shadow mode. `0` = classic MOHAA shadow blobs. `1` = Godot GPU shadows from the map's sun direction, cast by all `RF_SHADOW` entities onto BSP surfaces. |
| `r_dlight_shadows` | `0` | archive | Dynamic light shadows. `0` = point lights illuminate but do not cast shadows. `1` = point lights cast shadows (expensive: 6 depth passes per light). Requires `r_shadows 1`. |
| `r_godot_rain` | `1` | archive | Rain mode. `0` = original MOHAA line-streak rain from cgame. `1` = Godot physics rain with collision. |
| `r_gamma` | `1` | archive | Display gamma correction value. |

### UI Text Scaling

These cvars scale the font size for individual UI text widgets. A value of `1.0` is the original size. Values above `1.0` make text larger; values below `1.0` make it smaller. Line height, word wrap, and character spacing all scale proportionally.

| Cvar | Default | Flags | Description |
| --- | --- | --- | --- |
| `ui_dmbox_scale` | `1.0` | archive | Scale factor for the death/chat message box (kill feed and player chat). |
| `ui_gmbox_scale` | `1.0` | archive | Scale factor for the game message box (objectives, side messages). |
| `ui_console_scale` | `1.0` | archive | Scale factor for the developer console (`~` key). |
| `ui_minicon_scale` | `1.0` | archive | Scale factor for the mini console overlay. |

Example — make the kill feed 50% larger and the console text smaller:

```
seta ui_dmbox_scale 1.5
seta ui_console_scale 0.8
```

### Debug

| Cvar | Default | Flags | Description |
| --- | --- | --- | --- |
| `r_showtris` | `0` | cheat | Wireframe overlay. `0` = off, `1` = wireframe, `2` = wireframe + solid. |
| `r_shownormals` | `0` | cheat | Draw surface normals. |
| `r_speeds` | `0` | cheat | Show per-frame rendering stats overlay. |
| `r_lockpvs` | `0` | cheat | Freeze PVS culling at the current position. |
| `r_showbbox` | `0` | cheat | Draw entity bounding boxes. |

## Troubleshooting

### `cmake --preset ...` works, but the build step fails immediately

The configure step only writes a build tree. The actual build targets still call repository scripts, so you still need the underlying tools installed:

- `bash`
- `scons`
- `godot`
- `bison`
- `flex`
- target-specific toolchains such as MinGW-w64 or osxcross

### Windows build from Windows fails in PowerShell or `cmd.exe`

Use MSYS2 `MINGW64` or another Bash-capable shell. The scripts are `bash` scripts.

### Windows export runs, but the exported `.exe` cannot start

Make sure the companion DLLs were staged next to the export. The repo's export flow copies runtime companions such as:

- `cgame.dll`
- `libgcc_s_seh-1.dll`
- `libstdc++-6.dll`
- `libwinpthread-1.dll`

### macOS build from Linux says `OSXCROSS_ROOT` is missing

That is expected until osxcross is installed and exported. Use:

```bash
export OSXCROSS_ROOT=/path/to/osxcross
./scripts/setup-macos-build.sh
```

### Godot export fails even though the engine built successfully

Check:

- `godot` is in `PATH`
- the matching export preset exists in `project/export_presets.cfg`
- the required engine artefacts are present in `project/bin/`

### The game starts but cannot find data files

Verify the binaries can reach your MOHAA assets through the configured search roots in [Game Assets](#game-assets): `fs_homedatapath`, `fs_basepath`, and `fs_homepath`, with the expected game dirs such as `main/`, `mainta/`, or `maintt/`.

## Current Gaps

These are the important current limitations of the build/docs surface:

- Android and iOS appear in the root CMake presets, but they are not documented here as first-class end-to-end targets.
- Native Windows is currently a MinGW/MSYS2-oriented path, not an MSVC-oriented path.
- Native macOS cross-target desktop exports are not scripted for Windows or Linux targets from a macOS host.
- `launch.sh` only supports `linux` and `web`; for Windows and macOS, run `godot --path project` directly.
- The web pipeline output path is currently inconsistent: `scripts/build-web.sh` writes the patched export to `web/`, while `build.sh serve`, `scripts/build-web-docker.sh`, and `scripts/deploy.sh` still expect `dist/web/<variant>/`.

## Disclaimer And Licence

This project is licensed under the GNU General Public License v2.0. See `LICENSE`.

This repository does not include retail MOHAA assets. You must provide your own legal copy of the game data.

This is a non-commercial fan project and is not affiliated with or endorsed by Electronic Arts, the original MOHAA developers, or the OpenMoHAA project.
