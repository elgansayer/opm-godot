#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd -- "$SCRIPT_DIR/.." && pwd)"
PROJECT_BIN_DIR="$REPO_ROOT/project/bin"
PROJECT_DIR="$REPO_ROOT/project"
EXPORT_DIR="$REPO_ROOT/web"
EXPORT_HTML="$EXPORT_DIR/mohaa.html"
EXPORT_JS="$EXPORT_DIR/mohaa.js"
PROJECT_GDEXT="$PROJECT_DIR/openmohaa.gdextension"

if [[ -f "$REPO_ROOT/openmohaa/SConstruct" ]]; then
    OPENMOHAA_DIR="$REPO_ROOT/openmohaa"
elif [[ -f "$REPO_ROOT/openmohaa/openmohaa/SConstruct" ]]; then
    OPENMOHAA_DIR="$REPO_ROOT/openmohaa/openmohaa"
else
    echo "ERROR: Could not find OpenMoHAA SConstruct under $REPO_ROOT/openmohaa" >&2
    exit 1
fi

EMSDK_DIR="${EMSDK_DIR:-$HOME/emsdk}"
BUILD_TARGET="template_debug"
CHECK_ONLY=0
EXPORT_AFTER_BUILD=1
PATCH_ONLY=0
SERVE_ONLY=0
ASSET_PATH="${ASSET_PATH:-}"
EXTRA_SCONS_ARGS=()

while [[ $# -gt 0 ]]; do
    case "$1" in
        --release)
            BUILD_TARGET="template_release"
            shift
            ;;
        --debug)
            BUILD_TARGET="template_debug"
            shift
            ;;
        --check)
            CHECK_ONLY=1
            shift
            ;;
        --no-export)
            EXPORT_AFTER_BUILD=0
            shift
            ;;
        --patch-only)
            PATCH_ONLY=1
            EXPORT_AFTER_BUILD=0
            shift
            ;;
        --serve)
            # Full build then (re-)deploy docker compose stack.
            SERVE_ONLY=1
            shift
            ;;
        --serve-only)
            # (Re-)deploy docker compose stack and exit; no build.
            SERVE_ONLY=2
            shift
            ;;
        --asset-path)
            if [[ $# -lt 2 ]]; then
                echo "ERROR: --asset-path requires a path" >&2
                exit 1
            fi
            ASSET_PATH="$2"
            shift 2
            ;;
        --emsdk)
            if [[ $# -lt 2 ]]; then
                echo "ERROR: --emsdk requires a path" >&2
                exit 1
            fi
            EMSDK_DIR="$2"
            shift 2
            ;;
        *)
            EXTRA_SCONS_ARGS+=("$1")
            shift
            ;;
    esac
done

serve_docker() {
    local asset_path="${ASSET_PATH:-}"
    if [[ -z "$asset_path" ]]; then
        echo "ERROR: ASSET_PATH is not set. Pass --asset-path /path/to/game/files or export ASSET_PATH." >&2
        exit 1
    fi

    if [[ ! -d "$asset_path/main" ]]; then
        echo "ERROR: asset path '$asset_path' does not contain a main/ directory." >&2
        exit 1
    fi

    # Fail fast on missing base game data to avoid a silent web boot that never loads a map.
    local missing_paks=()
    local pak
    for pak in 0 1 2 3 4 5 6; do
        if ! find "$asset_path/main" -maxdepth 1 -type f -iname "pak${pak}.pk3" | grep -q .; then
            missing_paks+=("pak${pak}.pk3")
        fi
    done
    if [[ ${#missing_paks[@]} -gt 0 ]]; then
        echo "ERROR: Missing required AA pak files under '$asset_path/main': ${missing_paks[*]}" >&2
        echo "       Web map loading requires a complete base set (pak0..pak6)." >&2
        exit 1
    fi

    echo "Deploying docker compose stack (asset path: $asset_path)..."
    cd "$REPO_ROOT"
    # Force-remove any lingering containers by name to avoid the 'already in use' conflict,
    # then bring the stack up with --force-recreate so existing containers are replaced atomically.
    docker rm -f mohaa-godot-web mohaa-godot-relay 2>/dev/null || true
    ASSET_PATH="$asset_path" \
    WEB_DIST="$EXPORT_DIR" \
    CDN_URL="${CDN_URL:-/assets}" \
    docker compose -f "$REPO_ROOT/docker/docker-compose.yml" up -d --build --force-recreate

    # Wait for the relay health check to confirm the container is fully up.
    echo "Waiting for relay health check..."
    local max_wait=60
    local waited=0
    while [[ $waited -lt $max_wait ]]; do
        if curl -sf http://127.0.0.1:8086/health >/dev/null 2>&1; then
            local health
            health=$(curl -sf http://127.0.0.1:8086/health)
            echo "Relay healthy: $health"
            echo "Stack is up. Web: http://localhost:8086"
            return 0
        fi
        sleep 2
        waited=$((waited + 2))
        echo "  ...waiting ($waited/${max_wait}s)"
    done
    echo "WARNING: Relay health check failed after ${max_wait}s. Container may still be starting."
    echo "  Check: docker logs mohaa-godot-web"
    echo "Stack may be up. Web: http://localhost:8086"
}

EMSDK_ENV_SH="$EMSDK_DIR/emsdk_env.sh"
if [[ ! -f "$EMSDK_ENV_SH" && "$SERVE_ONLY" -eq 0 && "$PATCH_ONLY" -eq 0 ]]; then
    echo "ERROR: Emscripten SDK env script not found at: $EMSDK_ENV_SH" >&2
    exit 1
fi

if [[ "$SERVE_ONLY" -eq 2 && "$PATCH_ONLY" -eq 0 ]]; then
    serve_docker
    exit 0
fi

# --patch-only only needs the repo tree; skip toolchain setup entirely.
if [[ "$PATCH_ONLY" -eq 0 ]]; then
    set +u
    # shellcheck disable=SC1090
    source "$EMSDK_ENV_SH" >/dev/null
    set -u

    # emsdk_env.sh sets EMSDK but may clear EMSDK_DIR; re-derive it.
    EMSDK_DIR="${EMSDK_DIR:-${EMSDK:-$HOME/emsdk}}"

    # emsdk_env.sh sets PATH and EMSDK but may not set EM_CONFIG.
    # If emcc is still not working (requires binaryen), point it at the bundled config
    # that lives alongside the upstream binaries so BINARYEN_ROOT is resolved correctly.
    if ! command -v emcc >/dev/null 2>&1; then
        echo "ERROR: emcc not found in PATH after sourcing $EMSDK_ENV_SH" >&2
        exit 1
    fi
    _EMSDK_BUNDLED_CONFIG="$EMSDK_DIR/upstream/emscripten_config"
    if [[ -f "$_EMSDK_BUNDLED_CONFIG" ]]; then
        export EM_CONFIG="$_EMSDK_BUNDLED_CONFIG"
    fi

    if ! command -v scons >/dev/null 2>&1; then
        echo "ERROR: scons not found in PATH" >&2
        exit 1
    fi

    if ! command -v godot >/dev/null 2>&1; then
        echo "ERROR: godot not found in PATH" >&2
        exit 1
    fi
fi

if [[ "$CHECK_ONLY" -eq 1 ]]; then
    echo "Toolchain check OK"
    echo "  EMSDK_DIR: $EMSDK_DIR"
    echo "  emcc: $(command -v emcc)"
    echo "  em++: $(command -v em++ || true)"
    echo "  scons: $(command -v scons)"
    echo "  godot: $(command -v godot)"
    exit 0
fi

sync_gdextension_web_entries() {
    local debug_threads=""
    local debug_nothreads=""
    local release_threads=""
    local release_nothreads=""
    local generic_wasm=""
    local artifact
    local name

    for artifact in "$@"; do
        name="$(basename "$artifact")"
        if [[ "$name" == *"template_debug"*"nothreads"* ]]; then
            debug_nothreads="$name"
        elif [[ "$name" == *"template_debug"* ]]; then
            debug_threads="$name"
        elif [[ "$name" == *"template_release"*"nothreads"* ]]; then
            release_nothreads="$name"
        elif [[ "$name" == *"template_release"* ]]; then
            release_threads="$name"
        elif [[ "$name" == *.wasm ]]; then
            generic_wasm="$name"
        fi
    done

    if [[ -n "$generic_wasm" ]]; then
        [[ -z "$debug_threads" ]] && debug_threads="$generic_wasm"
        [[ -z "$debug_nothreads" ]] && debug_nothreads="$generic_wasm"
        [[ -z "$release_threads" ]] && release_threads="$generic_wasm"
        [[ -z "$release_nothreads" ]] && release_nothreads="$generic_wasm"
    fi

    if [[ -z "$debug_threads" && -n "$debug_nothreads" ]]; then
        debug_threads="$debug_nothreads"
    fi
    if [[ -z "$debug_nothreads" && -n "$debug_threads" ]]; then
        debug_nothreads="$debug_threads"
    fi
    if [[ -z "$release_threads" && -n "$release_nothreads" ]]; then
        release_threads="$release_nothreads"
    fi
    if [[ -z "$release_nothreads" && -n "$release_threads" ]]; then
        release_nothreads="$release_threads"
    fi

    if [[ ! -f "$PROJECT_GDEXT" ]]; then
        echo "ERROR: Missing $PROJECT_GDEXT" >&2
        exit 1
    fi

    awk '!/^web\.(debug|release|template_debug|template_release)(\.threads)?\.wasm32\s*=/' "$PROJECT_GDEXT" > "$PROJECT_GDEXT.tmp"

    {
        if [[ -n "$debug_threads" ]]; then
            echo "web.debug.threads.wasm32 = \"res://bin/$debug_threads\""
            echo "web.template_debug.threads.wasm32 = \"res://bin/$debug_threads\""
        fi
        if [[ -n "$debug_nothreads" ]]; then
            echo "web.debug.wasm32 = \"res://bin/$debug_nothreads\""
            echo "web.template_debug.wasm32 = \"res://bin/$debug_nothreads\""
        fi
        if [[ -n "$release_threads" ]]; then
            echo "web.release.threads.wasm32 = \"res://bin/$release_threads\""
            echo "web.template_release.threads.wasm32 = \"res://bin/$release_threads\""
        fi
        if [[ -n "$release_nothreads" ]]; then
            echo "web.release.wasm32 = \"res://bin/$release_nothreads\""
            echo "web.template_release.wasm32 = \"res://bin/$release_nothreads\""
        fi
    } >> "$PROJECT_GDEXT.tmp"

    mv "$PROJECT_GDEXT.tmp" "$PROJECT_GDEXT"
}

patch_web_js() {
    # Apply all JavaScript patches to the Emscripten-generated mohaa.js.
    # Patches: memory pre-grow, VFS preloader, C++ exception ABI,
    # longjmp/invoke_* polyfills, cgame.so registration, WS relay bridge.
    # See scripts/web_assets/patch_web_js.py for details.
    if [[ ! -f "$EXPORT_JS" ]]; then
        echo "WARNING: Export JS not found: $EXPORT_JS"
        return
    fi
    python3 "$REPO_ROOT/scripts/web_assets/patch_web_js.py" "$EXPORT_JS" "$REPO_ROOT/scripts/web_assets/js"
}

patch_web_html() {
    # Apply all HTML patches from static templates and remove the service worker.
    if [[ ! -f "$EXPORT_HTML" ]]; then
        echo "WARNING: Export HTML not found: $EXPORT_HTML"
        return
    fi
    # Delete the generated service worker file — we don't use it.
    local sw_file
    sw_file="$(dirname "$EXPORT_HTML")/mohaa.service.worker.js"
    [[ -f "$sw_file" ]] && rm -f "$sw_file" && echo "Removed: $sw_file"
    # Patch HTML using static template files.
    python3 "$REPO_ROOT/scripts/web_assets/render_html_template.py" "$EXPORT_HTML" "$REPO_ROOT/scripts/web_assets/templates"
}

cd "$OPENMOHAA_DIR"

if [[ "$PATCH_ONLY" -eq 1 ]]; then
    echo "Patch-only mode: re-applying JS/HTML patches to existing export..."
    patch_web_js
    patch_web_html
    echo "Patch-only complete."
    if [[ "$SERVE_ONLY" -eq 1 ]]; then
        serve_docker
    fi
    exit 0
fi

PARSER_DIR="code/parser/generated"
if [[ ! -f "$PARSER_DIR/yyParser.hpp" ]]; then
    mkdir -p "$PARSER_DIR"
    bison --defines="$PARSER_DIR/yyParser.hpp" -o "$PARSER_DIR/yyParser.cpp" code/parser/bison_source.txt
    flex -Cem --nounistd -o "$PARSER_DIR/yyLexer.cpp" --header-file="$PARSER_DIR/yyLexer.h" code/parser/lex_source.txt
fi

# Cross-platform CPU count: nproc (Linux), sysctl (macOS/BSD), fallback to 4.
NPROC=$(nproc 2>/dev/null || sysctl -n hw.ncpu 2>/dev/null || echo 4)
scons platform=web target="$BUILD_TARGET" -j"$NPROC" "${EXTRA_SCONS_ARGS[@]}"

# Collect wasm artifacts (POSIX-compatible; avoids bash 4+ mapfile).
WASM_ARTIFACTS=()
while IFS= read -r f; do WASM_ARTIFACTS+=("$f"); done < <(find bin -maxdepth 1 -type f -name "*openmohaa*.wasm" | sort)
if [[ ${#WASM_ARTIFACTS[@]} -eq 0 ]]; then
    echo "ERROR: Build completed but no wasm artifacts were found in $(pwd)/bin" >&2
    exit 1
fi

mkdir -p "$PROJECT_BIN_DIR"
for artifact in "${WASM_ARTIFACTS[@]}"; do
    cp -f "$artifact" "$PROJECT_BIN_DIR/$(basename "$artifact")"
    echo "Deployed: $(basename "$artifact") -> $PROJECT_BIN_DIR"
done

sync_gdextension_web_entries "${WASM_ARTIFACTS[@]}"

# Ensure web export always uses the freshly built cgame module from this build.
# For web builds SCons+emcc may produce libcgame.wasm (WASM SIDE_MODULE) or
# libcgame.so (same WASM content with .so extension).  Check both.
CGAME_ARTIFACT=""
if [[ -f "$OPENMOHAA_DIR/bin/libcgame.wasm" ]]; then
    CGAME_ARTIFACT="$OPENMOHAA_DIR/bin/libcgame.wasm"
elif [[ -f "$OPENMOHAA_DIR/bin/libcgame.so" ]]; then
    CGAME_ARTIFACT="$OPENMOHAA_DIR/bin/libcgame.so"
fi
if [[ -n "$CGAME_ARTIFACT" ]]; then
    mkdir -p "$EXPORT_DIR/main"
    cp -f "$CGAME_ARTIFACT" "$EXPORT_DIR/main/cgame.so"
    echo "Deployed: $(basename "$CGAME_ARTIFACT") -> $EXPORT_DIR/main/cgame.so"
    # Sanity check: WASM files start with \0asm magic; warn if the file is
    # still an ELF (native) binary which Emscripten dlopen cannot load.
    if file "$EXPORT_DIR/main/cgame.so" 2>/dev/null | grep -q "ELF"; then
        echo "WARNING: cgame.so is a native ELF binary — Emscripten dlopen will reject it."
        echo "         Re-run build-web.sh to get a WASM SIDE_MODULE cgame."
    else
        echo "OK: cgame.so is a WASM module (Emscripten dlopen compatible)."
    fi
else
    echo "WARNING: cgame artifact not found in $OPENMOHAA_DIR/bin/"
fi

if [[ "$EXPORT_AFTER_BUILD" -eq 1 ]]; then
    mkdir -p "$EXPORT_DIR"

    # Temporarily strip non-web library entries from .gdextension so Godot
    # doesn't try to load a missing host-platform .so/.dll/.dylib during export.
    cp "$PROJECT_GDEXT" "$PROJECT_GDEXT.bak"
    awk '!/^(linux|windows|macos)\./' "$PROJECT_GDEXT.bak" > "$PROJECT_GDEXT"

    godot_export_status=0
    if [[ "$BUILD_TARGET" == "template_release" ]]; then
        godot --headless --path "$PROJECT_DIR" --export-release Web "$EXPORT_HTML" || godot_export_status=$?
    else
        godot --headless --path "$PROJECT_DIR" --export-debug Web "$EXPORT_HTML" || godot_export_status=$?
    fi

    # Always restore the original .gdextension regardless of export outcome.
    mv "$PROJECT_GDEXT.bak" "$PROJECT_GDEXT"

    if [[ "$godot_export_status" -ne 0 ]]; then
        echo "ERROR: Godot export failed with status $godot_export_status" >&2
        exit 1
    fi

    patch_web_js
    patch_web_html
fi

echo "Web build complete (target=$BUILD_TARGET)."
echo "Export output: $EXPORT_HTML"

if [[ "$SERVE_ONLY" -eq 1 ]]; then
    serve_docker
fi

