#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd -- "$SCRIPT_DIR/.." && pwd)"
PROJECT_BIN_DIR="$REPO_ROOT/project/bin"
PROJECT_DIR="$REPO_ROOT/project"
# Output dir is variant-aware: dist/web/debug or dist/web/release.
# Set by --debug/--release flags (default: debug).
_WEB_VARIANT="debug"
EXPORT_DIR=""  # computed after arg parsing
EXPORT_HTML="" # computed after arg parsing
EXPORT_JS=""   # computed after arg parsing
WEB_TEMPLATE_DIR="$REPO_ROOT/scripts/web_assets/templates"
WEB_HTML_RENDERER="$REPO_ROOT/scripts/web_assets/render_html_template.py"
PROJECT_GDEXT="$PROJECT_DIR/openmohaa.gdextension"
GAME_FILES_DIR="${GAME_FILES_DIR:-$HOME/.local/share/openmohaa}"

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
COPY_GAME_FILES=1
PATCH_ONLY=0
SERVE_ONLY=0
ASSET_PATH="${ASSET_PATH:-}"
BUILD_ONLY=0
MINIMAL_MODE=0
EXTRA_SCONS_ARGS=()

while [[ $# -gt 0 ]]; do
    case "$1" in
        --release)
            BUILD_TARGET="template_release"
            _WEB_VARIANT="release"
            shift
            ;;
        --debug)
            BUILD_TARGET="template_debug"
            _WEB_VARIANT="debug"
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
            COPY_GAME_FILES=0
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
        --build-only)
            # Compile only: no export, no runtime patching, no asset staging.
            BUILD_ONLY=1
            EXPORT_AFTER_BUILD=0
            COPY_GAME_FILES=0
            shift
            ;;
        --minimal)
            # Minimal/proper export: keep build + Godot export only, skip custom JS/HTML patching.
            MINIMAL_MODE=1
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
        --no-game-files)
            COPY_GAME_FILES=0
            shift
            ;;
        --emsdk)
            if [[ $# -lt 2 ]]; then
                echo "ERROR: --emsdk requires a path" >&2
                exit 1
            fi
            EMSDK_DIR="$2"
            shift 2
            ;;
        --game-files)
            if [[ $# -lt 2 ]]; then
                echo "ERROR: --game-files requires a path" >&2
                exit 1
            fi
            GAME_FILES_DIR="$2"
            COPY_GAME_FILES=1
            shift 2
            ;;
        *)
            EXTRA_SCONS_ARGS+=("$1")
            shift
            ;;
    esac
done

# ── Compute output paths now that variant is known ────────────────────────
EXPORT_DIR="$REPO_ROOT/dist/web/$_WEB_VARIANT"
EXPORT_HTML="$EXPORT_DIR/mohaa.html"
EXPORT_JS="$EXPORT_DIR/mohaa.js"

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
    docker rm -f opm-godot-web opm-godot-relay 2>/dev/null || true
    WEB_DIST="$EXPORT_DIR" ASSET_PATH="$asset_path" CDN_URL="${CDN_URL:-/assets}" docker compose up -d --build --force-recreate
    echo "Stack is up. Web: http://localhost:8086"
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

set +u
# shellcheck disable=SC1090
source "$EMSDK_ENV_SH" >/dev/null
set -u

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

generate_web_main_manifest() {
    local manifest_path="$EXPORT_DIR/.openmohaa-main-files.txt"

    : > "$manifest_path"

    # Scan all three game directories: main, mainta, maintt
    for game_dir_name in main mainta maintt; do
        local game_dir="$EXPORT_DIR/$game_dir_name"
        if [[ -d "$game_dir" ]]; then
            while IFS= read -r -d '' f; do
                local rel="${f#"$game_dir/"}"
                # Skip hidden/dot files and directories (dev artifacts: .vscode, .genkit, etc.)
                case "$rel" in
                    .*|*/.*) continue ;;
                esac
                case "${rel,,}" in
                    pak0.pk3|pak1.pk3|pak2.pk3|pak3.pk3|pak4.pk3|pak5.pk3|pak6.pk3|openmohaa.pk3|cgame.so)
                        continue
                        ;;
                    *.log|crashlog.txt|qconsole.log)
                        continue
                        ;;
                    *.so|*.cfg)
                        printf '%s/%s\n' "$game_dir_name" "$rel" >> "$manifest_path"
                        ;;
                    *)
                        continue
                        ;;
                esac
            done < <(find "$game_dir" \( -name ".*" -prune \) -o -type f -print0 | sort -z)
        fi
    done

    echo "$manifest_path"
}

patch_web_runtime_memory() {
    local preload_manifest="${1:-}"
    if [[ ! -f "$EXPORT_JS" ]]; then
        echo "WARNING: Export JS not found for memory patch: $EXPORT_JS"
        return
    fi

    python3 - "$EXPORT_JS" "$preload_manifest" <<'PY'
import sys
from pathlib import Path

js_path = Path(sys.argv[1])
manifest_path = Path(sys.argv[2]) if len(sys.argv) > 2 and sys.argv[2] else None
src = js_path.read_text(encoding='utf-8', errors='ignore')

def _js_quote(text: str) -> str:
    return text.replace('\\', '\\\\').replace("'", "\\'")

extra_preload_entries = []
if manifest_path and manifest_path.is_file():
    for raw in manifest_path.read_text(encoding='utf-8', errors='ignore').splitlines():
        rel = raw.strip().replace('\\', '/').lstrip('/')
        if not rel:
            continue
        extra_preload_entries.append(rel)

extra_files_js = ','.join(
    f"['{_js_quote(rel)}','/{_js_quote(rel)}']" for rel in extra_preload_entries
)

# Grow wasm memory before loadDylibs so the GDExtension side module (which
# declares initial=1628 pages) can be instantiated.  Use >>> (unsigned right
# shift) to avoid signed-int overflow at 2GB.  Target 2048 pages (128 MB).
# Also inject a polyfill for std::__2::__hash_memory before loadDylibs so the
# Emscripten dynamic linker can resolve the symbol when instantiating
# libopenmohaa.wasm.  The symbol is used by std::hash<std::string> (called
# from std::unordered_map<std::string,…>) in libopenmohaa.wasm which was
# compiled with a newer libc++ (std::__2) while Godot 4.2's web template was
# compiled with libc++ std::__1 — causing the symbol to be unresolved at
# run-time and triggering an infinite stub-call hang during BSP world load.
_HASH_POLY = (
    "if(typeof globalThis['_ZNSt3__213__hash_memoryEPKvm']==='undefined'){"
    "globalThis['_ZNSt3__213__hash_memoryEPKvm']=function(ptr,size){"
    # FNV-1a hash — matches std::hash<std::string> semantics well enough for
    # std::unordered_map correctness; exact libc++ algorithm not required.
    "var h=2166136261,m=16777619,mem=HEAPU8||new Uint8Array(wasmMemory.buffer);"
    "for(var i=0;i<(size>>>0);++i){h=(h^mem[(ptr+i)>>>0])>>>0;h=Math.imul(h,m)>>>0;}"
    "return h;};"
    "console.log('OpenMoHAA: injected std::__2::__hash_memory polyfill');}"
)
# Belt-and-suspenders: push cgame.so into dynamicLibraries right before loadDylibs().
# This runs AFTER Module["dynamicLibraries"] is already copied into dynamicLibraries,
# so it guarantees cgame.so is loaded regardless of whether the GodotExtension class
# constructor patch (further below) succeeded or not.
_CGAME_PUSH = (
    "if(!dynamicLibraries.includes('main/cgame.so')){"
    "dynamicLibraries.push('main/cgame.so');"
    "console.log('OpenMoHAA: pre-registered main/cgame.so in dynamicLibraries');}"
)
mem_old = "LDSO.init();loadDylibs();"
mem_new = (
    "LDSO.init();"
    "var __wm_pages=(wasmMemory.buffer.byteLength>>>16);"
    "if(__wm_pages<2048){"
    "try{wasmMemory.grow(2048-__wm_pages);updateMemoryViews()}"
    "catch(e){console.warn('OpenMoHAA: memory pre-grow failed',e)}}"
    + _HASH_POLY +
    _CGAME_PUSH +
    "loadDylibs();"
)
_HAS_HASH = "_ZNSt3__213__hash_memoryEPKvm" in src
_HAS_CGAME = "dynamicLibraries.includes('main/cgame.so')" in src
if _HAS_HASH and _HAS_CGAME:
    print("__hash_memory polyfill + cgame.so push already injected (idempotent)")
elif mem_old in src:
    src = src.replace(mem_old, mem_new, 1)
    print("Patched mohaa.js: memory pre-grow + __hash_memory polyfill + cgame.so push before loadDylibs")
elif "__wm_pages" in src:
    # Memory pre-grow already applied in a previous build; inject missing pieces.
    for _warn in ("'OpenMoHAA: memory pre-grow failed',e)}}", "'MOHAAjs: memory pre-grow failed',e)}}"):
        _old_frag = _warn + "loadDylibs();"
        _new_parts = _warn
        if not _HAS_HASH:
            _new_parts += _HASH_POLY
        if not _HAS_CGAME:
            _new_parts += _CGAME_PUSH
        _new_frag = _new_parts + "loadDylibs();"
        if _old_frag in src and _new_frag != _old_frag:
            src = src.replace(_old_frag, _new_frag, 1)
            _parts = []
            if not _HAS_HASH: _parts.append("__hash_memory polyfill")
            if not _HAS_CGAME: _parts.append("cgame.so push")
            print(f"Patched mohaa.js: injected {' + '.join(_parts)} (memory pre-grow was already applied)")
            break
    else:
        if _HAS_HASH and not _HAS_CGAME:
            # Hash polyfill present; try to anchor cgame push directly before loadDylibs.
            # Try both non-obfuscated (OpenMoHAA) and obfuscated (MOHAAjs) variants of
            # the log string, since --patch-only re-runs on an already-obfuscated file.
            for _prefix in ("OpenMoHAA", "MOHAAjs"):
                _cgame_anchor = f"console.log('{_prefix}: injected std::__2::__hash_memory polyfill');}}loadDylibs();"
                _cgame_anchor_new = f"console.log('{_prefix}: injected std::__2::__hash_memory polyfill');}}" + _CGAME_PUSH + "loadDylibs();"
                if _cgame_anchor in src:
                    src = src.replace(_cgame_anchor, _cgame_anchor_new, 1)
                    print("Patched mohaa.js: injected cgame.so push (anchored to hash polyfill tail)")
                    break
            else:
                print("WARNING: Memory pre-grow already applied but could not anchor missing patches")
        else:
            print("WARNING: Memory pre-grow already applied but could not anchor __hash_memory polyfill + cgame.so push")
else:
    print("WARNING: Could not find LDSO.init();loadDylibs(); marker; memory pre-grow + polyfill skipped")

preload_old = "var moduleRtn;var Module=moduleArg;var ENVIRONMENT_IS_WEB="
preload_new = (
    "var moduleRtn;var Module=moduleArg;"
    "if(typeof window!=='undefined'){window.__opmStdout=window.__opmStdout||[];window.__opmMapLoadedLog='';}"
    "(function(){"
    "  var __wrap=function(name){"
    "    var prev=Module[name];"
    "    Module[name]=function(){"
    "      var msg=Array.prototype.slice.call(arguments).join(' ');"
    "      if(typeof window!=='undefined'){"
    "        window.__opmStdout.push(msg);"
    "        if(msg.indexOf('Main: SIGNAL map_loaded ->')!==-1)window.__opmMapLoadedLog=msg;"
    "      }"
    "      if(typeof prev==='function')return prev.apply(this,arguments);"
    "      if(name==='printErr'){console.error(msg)}else{console.log(msg)}"
    "    };"
    "  };"
    "  __wrap('print');"
    "  __wrap('printErr');"
    "})();"
    "Module['preRun']=Module['preRun']||[];"
    "Module['preRun'].push(()=>{"
    "if(typeof FS==='undefined'||typeof fetch==='undefined'||typeof addRunDependency!=='function'||typeof removeRunDependency!=='function'){return;}"
    "var __dep='openmohaa-vfs-preload'; addRunDependency(__dep);"
    "(async()=>{"
    "  var cfg=(typeof OPM_CONFIG!=='undefined'?OPM_CONFIG:{}),cdn=cfg['CDN_URL']||'/assets';"
    "  if(cdn&&!cdn.endsWith('/'))cdn+='/';"
    "  var cache=null; try{cache=await caches.open('mohaajs-assets-v1')}catch(e){console.warn('[MOHAAjs] Cache API unavailable',e)}"
    # --- helper: ensure MEMFS directory exists ---
    "  var __mkdirs=(path)=>{"
    "    var p='',ps=path.split('/').filter(Boolean);"
    "    for(var i=0;i<ps.length;i++){p+='/'+ps[i];try{FS.mkdir(p)}catch(e){}}"
    "  };"
    # --- helper: write file + lowercase pak alias when needed ---
    "  var __writeFileWithPakAlias=(dst,data)=>{"
    "    FS.writeFile(dst,data,{canRead:true,canWrite:false});"
    "    var m=dst.match(/^(.*\/)([^\/]+)$/);"
    "    if(!m)return;"
    "    var dir=m[1],base=m[2];"
    "    if(!/^pak\d+\.pk3$/i.test(base))return;"
    "    var lowerBase=base.toLowerCase();"
    "    if(lowerBase===base)return;"
    "    var alias=dir+lowerBase;"
    "    try{if(!FS.analyzePath(alias).exists){FS.writeFile(alias,data,{canRead:true,canWrite:false})}}catch(e){}"
    "  };"
    # --- helper: fetch directory listing as JSON array ---
    "  var __listDir=async(relDir)=>{"
    "    try{"
    "      var r=await fetch(cdn+relDir,{cache:'no-cache',headers:{'Accept':'application/json'}});"
    "      if(!r.ok)return[];"
    "      var j=await r.json();"
    "      if(Array.isArray(j)&&j.length&&typeof j[0]==='object')return j;"
    "      return[];"
    "    }catch(e){return[]}"
    "  };"
    # --- helper: fetch a single file, return {dst, data} or null ---
    "  var __fetchOne=async(rel)=>{"
    "    var src=cdn+rel,dst='/'+rel;"
    "    try{"
    "      var res=null; if(cache)res=await cache.match(src);"
    "      if(!res){"
    "        res=await fetch(src); if(!res.ok)return null;"
    "        if(cache)try{cache.put(src,res.clone())}catch(e){}"
    "      }"
    "      return{dst:dst,data:new Uint8Array(await res.arrayBuffer())};"
    "    }catch(e){return null}"
    "  };"
    # --- bounded concurrency pool ---
    "  var __sem=0,__maxSem=30,__semQ=[];"
    "  var __acquire=()=>__sem<__maxSem?(++__sem,Promise.resolve()):new Promise(r=>{__semQ.push(r)});"
    "  var __release=()=>{__sem--;if(__semQ.length){__sem++;(__semQ.shift())()}};"
    # --- bounded root scan: fetch only required archives/configs ---
    "  var total=0,loaded=0,failed=0;"
    "  var __walk=async(relDir)=>{"
    "    var entries=await __listDir(relDir);"
    "    var promises=[];"
    "    for(var i=0;i<entries.length;i++){"
    "      var e=entries[i],name=e.name;"
    "      if(name.startsWith('.'))continue;"
    # root-only fetch: skip subdirectories and focus on pack/config files.
    "      if(e.type==='directory')continue;"
    "      var ln=name.toLowerCase();"
    "      if(!(ln.endsWith('.pk3')||ln.endsWith('.cfg')))continue;"
    "      var rel=relDir+name;"
    "      total++;"
    "      promises.push((async(r)=>{"
    "        await __acquire();"
    "        try{"
    "          if(FS.analyzePath('/'+r).exists){loaded++;return}"
    "          var result=await __fetchOne(r);"
    "          if(result){"
    "            var cut=result.dst.lastIndexOf('/');"
    "            if(cut>0)__mkdirs(result.dst.slice(0,cut));"
    "            __writeFileWithPakAlias(result.dst,result.data);"
    "            loaded++;"
    "          }else{failed++}"
    "        }catch(e){failed++}"
    "        finally{__release()}"
    "        if((loaded+failed)%200===0||loaded+failed===total)"
    "          console.log('[MOHAAjs] Progress: '+(loaded+failed)+'/'+total+' ('+failed+' failed)');"
    "      })(rel));"
    "    }"
    "    await Promise.all(promises);"
    "  };"
    # --- write local files from picker/cache into MEMFS ---
    # Files now arrive with full relative paths including game subdirs:
    #   main/Pak0.pk3, mainta/Pak0.pk3, maintt/Pak0.pk3, etc.
    # Write them at their original path so all game dirs are available.
    "  var __lf=(typeof window!=='undefined'&&window.__opmLocalFiles)||{};"
    "  var __lfKeys=Object.keys(__lf);"
    "  if(__lfKeys.length>0){"
    "    console.log('[MOHAAjs] Writing '+__lfKeys.length+' local files to MEMFS...');"
    "    for(var __li=0;__li<__lfKeys.length;__li++){"
    "      var __lrel=__lfKeys[__li];"
    "      var __ldst='/'+__lrel;"
    "      var __lcut=__ldst.lastIndexOf('/');"
    "      if(__lcut>0)__mkdirs(__ldst.slice(0,__lcut));"
    "      try{__writeFileWithPakAlias(__ldst,__lf[__lrel])}catch(e){}"
    "    }"
    "    console.log('[MOHAAjs] Wrote '+__lfKeys.length+' local files to MEMFS');"
    "    if(typeof window!=='undefined')window.__opmLocalFiles=null;"
    "  }"
    # --- walk server for base game directory only (gap-fill) ---
    # Only walk 'main/' on the server — expansion dirs (mainta/, maintt/)
    # are provided entirely by local files / IndexedDB cache and do NOT
    # exist on the web server, so walking them would produce 404 errors.
    "  var __tg=(typeof window!=='undefined'&&window.__opmTargetGame)||0;"
    "  var __gdMap={1:'mainta',2:'maintt'};"
    "  var __expDir=__gdMap[__tg];"
    "  if(__expDir)__mkdirs('/'+__expDir);"
    "  __mkdirs('/main');"
    "  console.log('[MOHAAjs] Server gap-fill: scanning /main/ ...');"
    "  await __walk('main/');"
    "  if(__expDir){"
    "    console.log('[MOHAAjs] Server gap-fill: scanning /'+__expDir+'/ ...');"
    "    await __walk(__expDir+'/');"
    "  }"
    "  console.log('[MOHAAjs] VFS preload complete: '+loaded+' files ready, '+failed+' failed');"
    "})().catch(e=>console.error('[MOHAAjs] PreRun error',e)).finally(()=>removeRunDependency(__dep));"
    "});"
    "var ENVIRONMENT_IS_WEB="
)

if preload_old in src:
    src = src.replace(preload_old, preload_new, 1)
    print("Patched mohaa.js async preRun VFS preload (fresh)")
elif "openmohaa-pk3-preload" in src or "openmohaa-vfs-preload" in src:
    # Already patched with old or current preloader — strip and re-inject
    import re
    # The preloader block starts with Module['preRun'] and ends just before var ENVIRONMENT_IS_WEB=
    pat = re.compile(
        r"Module\['preRun'\]=Module\['preRun'\]\|\|\[\];.*?"
        r"var ENVIRONMENT_IS_WEB=",
        re.DOTALL
    )
    m = pat.search(src)
    if m:
        # Replace old preloader text with just the marker (the new preload_new ends with it)
        src = src[:m.start()] + preload_new.split("var moduleRtn;var Module=moduleArg;", 1)[-1] + src[m.end():]
        print("Patched mohaa.js async preRun VFS preload (replaced old preloader)")
    else:
        print("WARNING: Found preloader dep ID but could not locate preloader block boundary")
else:
    print("WARNING: Could not find Module preRun injection marker in mohaa.js; preload patch skipped")

if extra_preload_entries:
    print(f"Prepared full main preload entries: {len(extra_preload_entries)}")
else:
    print("Prepared full main preload entries: 0")

symbol_old = (
    "var reportUndefinedSymbols=()=>{for(var[symName,entry]of Object.entries(GOT)){"
    "if(entry.value==-1){var value=resolveGlobalSymbol(symName,true).sym;"
)
symbol_new = (
    "var reportUndefinedSymbols=()=>{for(var[symName,entry]of Object.entries(GOT)){"
    "if(entry.value==-1){var value=resolveGlobalSymbol(symName,true).sym;"
    "if(!value&&entry.required){console.error('OpenMoHAA unresolved symbol',symName,'required',!!entry.required)}"
)

if symbol_old in src:
    src = src.replace(symbol_old, symbol_new, 1)
    print("Patched mohaa.js unresolved-symbol diagnostics")
else:
    print("WARNING: Could not find unresolved-symbol marker in mohaa.js; symbol diagnostics skipped")

call_old = "if(!flags.allowUndefined){reportUndefinedSymbols()}"
call_new = (
    "if(!flags.allowUndefined){"
    "try{reportUndefinedSymbols()}"
    "catch(e){console.error('OpenMoHAA reportUndefinedSymbols exception',e,e&&e.message,e&&e.stack);throw e}"
    "}"
)

if call_old in src:
    src = src.replace(call_old, call_new, 1)
    print("Patched mohaa.js reportUndefinedSymbols exception diagnostics")
else:
    print("WARNING: Could not find reportUndefinedSymbols call marker; exception diagnostics skipped")

stub_old = "stubs[prop]=(...args)=>{resolved||=resolveSymbol(prop);return resolved(...args)}"
stub_new = (
    "stubs[prop]=(...args)=>{"
    # C++ exception runtime - must run BEFORE resolveSymbol so our versions
    # take precedence over Godot's abort() stubs for these symbols.
    "if(prop==='___cxa_throw'){resolved=(ptr,type,destructor)=>{var e=new Error('CxxException');e.name='CxxException';e.__cxa_ptr=ptr;stubs.__cxaLast=ptr;stubs.__cxaType=type;throw e};}"
    "if(prop==='___resumeException'){resolved=(ptr)=>{stubs.__cxaLast=ptr||stubs.__cxaLast||0;var e=new Error('CxxException');e.name='CxxException';e.__cxa_ptr=stubs.__cxaLast;throw e};}"
    "if(prop==='__cxa_begin_catch'){resolved=(ptr)=>{stubs.__cxaLast=0;return ptr};}"
    "if(prop==='__cxa_end_catch'||prop==='__cxa_free_exception'){resolved=()=>{stubs.__cxaLast=0};}"
    "if(prop==='__cxa_rethrow'){resolved=()=>{var e=new Error('CxxException');e.name='CxxException';e.__cxa_ptr=stubs.__cxaLast||0;throw e};}"
    # __cxa_find_matching_catch_N: read _cxaLast (set by ___cxa_throw via wasmImports)
    # stubs.__cxaLast is a fallback for completeness; _cxaLast is the primary source
    "if(/^__cxa_find_matching_catch_\\d+$/.test(prop)){resolved=()=>{"
    "var ptr=(typeof _cxaLast!=='undefined'?_cxaLast:0)||stubs.__cxaLast||0;"
    "if(typeof setTempRet0!=='undefined'){setTempRet0(0)}else if(typeof _setTempRet0!=='undefined'){_setTempRet0(0)}"
    "return ptr};}"
    "resolved||=resolveSymbol(prop);"
    "if(!resolved&&/^__cxa_find_matching_catch_\\d+$/.test(prop)){resolved=()=>0}"
    "if(!resolved){"
    "var __baseProp=String(prop||'');"
    "var __trimmed=__baseProp.replace(/^_+/, '');"
    "var __candidates=[__baseProp,'_'+__baseProp,__trimmed,'_'+__trimmed];"
    "for(var __i=0;__i<__candidates.length&&!resolved;__i++){"
    "var __name=__candidates[__i];"
    "if(!__name){continue}"
    "if(typeof __name==='string'&&typeof resolveSymbol==='function'){resolved=resolveSymbol(__name)||resolved}"
    "if(!resolved&&typeof Module!=='undefined'&&Module){resolved=Module[__name]||resolved}"
    "if(!resolved&&typeof globalThis!=='undefined'&&globalThis){resolved=globalThis[__name]||resolved}"
    "}"
    "}"
    "if(!resolved&&prop==='emscripten_longjmp'){"
    "var __throwLongjmp=resolveSymbol('emscripten_throw_longjmp');"
    "var __cLongjmp=(typeof ___c_longjmp!=='undefined'&&___c_longjmp)||(typeof __c_longjmp!=='undefined'&&__c_longjmp)||resolveSymbol('__c_longjmp')||resolveSymbol('___c_longjmp')||(typeof globalThis!=='undefined'&&(globalThis.___c_longjmp||globalThis.__c_longjmp));"
    "var __wasmLongjmp=(typeof ___wasm_longjmp!=='undefined'&&___wasm_longjmp)||(typeof __wasm_longjmp!=='undefined'&&__wasm_longjmp)||resolveSymbol('__wasm_longjmp')||resolveSymbol('___wasm_longjmp');"
    "if(typeof __cLongjmp==='number'&&typeof wasmTable!=='undefined'){var __cLongjmpFn=wasmTable.get(__cLongjmp|0);if(__cLongjmpFn){__cLongjmp=__cLongjmpFn}}"
    "if(typeof __wasmLongjmp==='number'&&typeof wasmTable!=='undefined'){var __wasmLongjmpFn=wasmTable.get(__wasmLongjmp|0);if(__wasmLongjmpFn){__wasmLongjmp=__wasmLongjmpFn}}"
    "if(typeof __throwLongjmp==='function'){"
    "resolved=(env,val)=>__throwLongjmp(env|0,val|0)"
    "}else if(typeof __cLongjmp==='function'){"
    "resolved=(env,val)=>__cLongjmp(env|0,val|0)"
    "}else if(typeof __wasmLongjmp==='function'){"
    "resolved=(env,val)=>__wasmLongjmp(env|0,val|0)"
    "}else{"
    "resolved=(env,val)=>{throw new Error('OpenMoHAA missing usable emscripten longjmp helper')}"
    "}"
    "}"
    "if(!resolved&&prop.startsWith('invoke_')){"
    "resolved=(...invokeArgs)=>{"
    "var fnIndex=invokeArgs[0]|0;"
    "var fn=wasmTable.get(fnIndex);"
    "try{return fn(...invokeArgs.slice(1))}"
    "catch(e){"
    "if(e&&e.name==='ExitStatus'){throw e}"
    "if(e&&e.name==='CxxException'&&e.__cxa_ptr){stubs.__cxaLast=e.__cxa_ptr}"
    "else if(e&&e.name==='RuntimeError'&&typeof ABORT!=='undefined'&&ABORT){ABORT=false}"
    "if(typeof _setThrew==='function'){_setThrew(1,0)}else if(typeof setThrew==='function'){setThrew(1,0)}"
    "return 0"
    "}"
    "}"
    "}"
    "if(typeof resolved==='number'){"
    "var __fn=wasmTable.get(resolved|0);"
    "if(__fn){resolved=__fn}"
    "}"
    "if(resolved&&typeof resolved==='object'&&typeof resolved.value==='number'){"
    "var __fn2=wasmTable.get(resolved.value|0);"
    "if(__fn2){resolved=__fn2}"
    "}"
    "if(!resolved){console.error('OpenMoHAA unresolved runtime import',prop,args);"
    "throw new Error('OpenMoHAA unresolved runtime import: '+prop)}"
    "if(typeof resolved!=='function'){console.error('OpenMoHAA non-callable runtime import',prop,typeof resolved,resolved,args);"
    "throw new Error('OpenMoHAA non-callable runtime import: '+prop)}"
    "try{return resolved(...args)}catch(e){"
    "if(prop==='emscripten_longjmp'){throw e}"
    "console.error('OpenMoHAA runtime import threw',prop,e,e&&e.message,e&&e.stack,args);"
    "throw e}}"
)

if stub_old in src:
    src = src.replace(stub_old, stub_new, 1)
    print("Patched mohaa.js runtime import diagnostics")
else:
    print("WARNING: Could not find runtime import stub marker; import diagnostics skipped")

# Pre-register cgame.so in dynamicLibraries so it loads on the main Emscripten thread
# (before pthreads start) via loadDylibs(). This allows synchronous dlopen() from a
# Godot worker thread to succeed by finding the library already in LDSO.loadedLibsByName.
# loadDylibs() processes dynamicLibraries in order; mohaa.side.wasm (the GDExtension) is
# listed first (from Module.dynamicLibraries), so all engine symbols are available when
# PATH.normalize("./main/cgame.so") == "main/cgame.so" (strips ./ prefix, no leading slash).
# loadDynamicLibrary stores the key verbatim, so we must register with "main/cgame.so" (no
# leading slash) to match the normalized path that dlopenInternal looks up.
dynlib_old = "'dynamicLibraries': [`${loadPath}.side.wasm`].concat(this.extensionLibs),"
dynlib_new = "'dynamicLibraries': [`${loadPath}.side.wasm`].concat(this.extensionLibs).concat(['main/cgame.so']),"
if dynlib_new in src:
    print("dynamicLibraries class constructor already patched (idempotent)")
elif dynlib_old in src:
    src = src.replace(dynlib_old, dynlib_new, 1)
    print("Patched mohaa.js dynamicLibraries class constructor to pre-register cgame.so")
else:
    # Not a fatal error: cgame.so is also pushed via _CGAME_PUSH in the mem block above.
    print("NOTE: GodotExtension class constructor dynamicLibraries marker not found; relying on direct push above")

# Wrap loadDylibs() iterations with try/catch so a failed lib (e.g. compile error) does
# not escape as an unhandled rejection and prevents removeRunDependency("loadDylibs") from
# running (which would deadlock the entire Emscripten runtime). Also adds verbose logging
# so build-time diagnostics can identify which library fails and why.
dylibs_old = (
    "var loadDylibs=async()=>{if(!dynamicLibraries.length){reportUndefinedSymbols();return}"
    "addRunDependency(\"loadDylibs\");"
    "for(var lib of dynamicLibraries){await loadDynamicLibrary(lib,{loadAsync:true,global:true,nodelete:true,allowUndefined:true})}"
    "reportUndefinedSymbols();removeRunDependency(\"loadDylibs\")}"
)
dylibs_new = (
    "var __openmohaaLoadDylibsPromise=null;"
    "var loadDylibs=async()=>{"
    "if(__openmohaaLoadDylibsPromise){return __openmohaaLoadDylibsPromise}"
    "__openmohaaLoadDylibsPromise=(async()=>{"
    "if(!dynamicLibraries.length){reportUndefinedSymbols();return}"
    "addRunDependency(\"loadDylibs\");"
    "console.log('OpenMoHAA loadDylibs: processing',dynamicLibraries.length,'libs:',JSON.stringify(dynamicLibraries));"
    "for(var lib of dynamicLibraries){"
    "  try{"
    "    console.log('OpenMoHAA loadDylibs: loading',lib,'...');"
    "    await loadDynamicLibrary(lib,{loadAsync:true,global:true,nodelete:true,allowUndefined:true});"
    "    console.log('OpenMoHAA loadDylibs: loaded',lib,'OK. LDSO keys:',Object.keys(LDSO.loadedLibsByName).join('|'));"
    "  }catch(e){"
    "    console.error('OpenMoHAA loadDylibs: FAILED to load',lib,String(e),e&&e.message,e&&e.stack);"
    "  }"
    "}"
    "reportUndefinedSymbols();removeRunDependency(\"loadDylibs\")"
    "})();"
    "return __openmohaaLoadDylibsPromise"
    "}"
)
if dylibs_old in src:
    src = src.replace(dylibs_old, dylibs_new, 1)
    print("Patched loadDylibs with per-lib try/catch and verbose logging")
else:
    print("WARNING: Could not find loadDylibs loop marker; try/catch patch skipped")

# Godot's generated locateFile uses `path in gdext` where gdext is an array.
# In JavaScript this checks indices, not values, so entries like "libopenmohaa.wasm"
# are not matched and can be incorrectly rewritten to `${loadPath}.wasm`.
gdext_locate_old = "} else if (path in gdext) {"
gdext_locate_new = "} else if (gdext.includes(path)) {"
if gdext_locate_old in src:
    src = src.replace(gdext_locate_old, gdext_locate_new, 1)
    print("Patched mohaa.js locateFile gdextension lookup (includes)")
else:
    print("WARNING: Could not find locateFile gdextension marker; lookup patch skipped")

# Patch C++ exception ABI stubs: replace abort()-based stubs with proper JS
# implementations so the WASM's try/catch blocks work correctly.
# wasmImports maps  __cxa_throw -> ___cxa_throw  (2 vs 3 leading underscores).
# The stubs proxy short-circuits via `if(prop in wasmImports)` before our
# CxxException intercept could fire, so we must patch the hardcoded functions.
cxa_patches = [
    # 1. ___cxa_throw: add _cxaLast state + throw CxxException object
    (
        'function ___cxa_throw(){abort()}___cxa_throw.sig="vppp";',
        'var _cxaLast=0;'
        'function ___cxa_throw(ptr,type,dtor){'
          '_cxaLast=ptr;'
          'var e=new Error("CxxException");e.name="CxxException";e.__cxa_ptr=ptr;'
          'throw e'
        '}___cxa_throw.sig="vppp";'
    ),
    # 2. ___cxa_rethrow
    (
        'function ___cxa_rethrow(){abort()}___cxa_rethrow.sig="v";',
        'function ___cxa_rethrow(){'
          'if(_cxaLast){var e=new Error("CxxException");e.name="CxxException";e.__cxa_ptr=_cxaLast;throw e}'
        '}___cxa_rethrow.sig="v";'
    ),
    # 3. _llvm_eh_typeid_for
    (
        'function _llvm_eh_typeid_for(){abort()}_llvm_eh_typeid_for.sig="vp";',
        'function _llvm_eh_typeid_for(type){return type}_llvm_eh_typeid_for.sig="vp";'
    ),
    # 4. ___cxa_begin_catch
    (
        'function ___cxa_begin_catch(){abort()}___cxa_begin_catch.sig="pp";',
        'function ___cxa_begin_catch(ptr){return ptr}___cxa_begin_catch.sig="pp";'
    ),
    # 5. ___cxa_end_catch
    (
        'function ___cxa_end_catch(){abort()}___cxa_end_catch.sig="v";',
        'function ___cxa_end_catch(){_cxaLast=0}___cxa_end_catch.sig="v";'
    ),
    # 6. ___cxa_call_unexpected
    (
        'function ___cxa_call_unexpected(){abort()}___cxa_call_unexpected.sig="vp";',
        'function ___cxa_call_unexpected(ptr){console.warn("cxa_call_unexpected",ptr)}___cxa_call_unexpected.sig="vp";'
    ),
    # 7. ___cxa_find_matching_catch (no .sig; immediately followed by ___resumeException)
    (
        'function ___cxa_find_matching_catch(){abort()}',
        'function ___cxa_find_matching_catch(){'
          'if(typeof setTempRet0!=="undefined")setTempRet0(0);'
          'return _cxaLast'
        '}'
    ),
    # 8. ___resumeException
    (
        'function ___resumeException(){abort()}___resumeException.sig="vp";',
        'function ___resumeException(ptr){'
          'if(ptr)_cxaLast=ptr;'
          'var e=new Error("CxxException");e.name="CxxException";e.__cxa_ptr=_cxaLast;'
          'throw e'
        '}___resumeException.sig="vp";'
    ),
]
cxa_patched = 0
for cxa_old, cxa_new in cxa_patches:
    if cxa_old in src:
        src = src.replace(cxa_old, cxa_new, 1)
        cxa_patched += 1
if cxa_patched == len(cxa_patches):
    print(f"Patched mohaa.js C++ exception ABI stubs ({cxa_patched}/{len(cxa_patches)})")
else:
    print(f"WARNING: Only {cxa_patched}/{len(cxa_patches)} C++ exception ABI stubs found/patched")

js_path.write_text(src, encoding='utf-8')
PY
}

render_web_html_from_templates() {
    if [[ ! -f "$WEB_HTML_RENDERER" ]]; then
        echo "ERROR: Missing HTML renderer script: $WEB_HTML_RENDERER" >&2
        exit 1
    fi
    if [[ ! -d "$WEB_TEMPLATE_DIR" ]]; then
        echo "ERROR: Missing web template directory: $WEB_TEMPLATE_DIR" >&2
        exit 1
    fi
    python3 "$WEB_HTML_RENDERER" "$EXPORT_HTML" "$WEB_TEMPLATE_DIR"
}

patch_web_ws_relay() {
    # Inject WebSocket relay bridge functions into mohaa.js.
    # These are called from the GDExtension SIDE_MODULE (net_ws.c)
    # via the Emscripten runtime stub resolver's globalThis fallback.
    #
    # IMPORTANT: The bridge IIFE runs early in mohaa.js before Module is
    # defined. We register functions on globalThis with the underscore-
    # prefixed names that the WASM import table uses (C function
    # opm_ws_open -> import _opm_ws_open). The patched stub resolver
    # checks globalThis[__name] as a fallback, so it finds them.
    # Module.HEAPU8 / UTF8ToString are accessed at *call* time (not
    # registration time) — they are available then because the SIDE_MODULE
    # is loaded after the main WASM module initialises.
    local export_js="$EXPORT_JS"
    if [[ ! -f "$export_js" ]]; then
        echo "WARNING: Export JS not found for WS relay patch: $export_js"
        return
    fi

    python3 - "$export_js" <<'PYWS'
import sys
from pathlib import Path

js_path = Path(sys.argv[1])
src = js_path.read_text(encoding='utf-8', errors='ignore')

# Register on globalThis so the stub resolver's globalThis[__name] fallback
# finds them. Use underscore-prefixed names (_opm_ws_open) matching the WASM
# import names. Module is NOT available at injection time, so we look it up
# at call time via globalThis.Module (set by Emscripten during init).
ws_bridge_js = r"""
/* ═══════ OpenMoHAA WebSocket Relay Bridge (injected by build-web.sh) ═══════ */
(function() {
    var _opmWsRelay = null;
    var _opmWsRecvQueue = [];
    var _opmWsConnected = false;

    /** Helper: get the Emscripten Module at call time (not capture time). */
    function _getModule() {
        return (typeof Module !== 'undefined' && Module) || globalThis.Module || null;
    }

    /**
     * _opm_ws_open(url_ptr) — Connect to a WebSocket relay server.
     * @param url_ptr  WASM pointer to a NUL-terminated C string (the relay URL)
     * @returns 1 on success, 0 on failure
     */
    globalThis._opm_ws_open = function(url_ptr) {
        var url;
        try {
            url = UTF8ToString(url_ptr);
        } catch (e) {
            console.error('opm_ws_open: UTF8ToString failed', e);
            return 0;
        }
        if (!url) { console.warn('opm_ws_open: empty URL'); return 0; }

        /* Close any existing connection */
        if (_opmWsRelay) {
            try { _opmWsRelay.close(); } catch (e) {}
            _opmWsRelay = null;
        }
        _opmWsConnected = false;
        _opmWsRecvQueue = [];

        try {
            _opmWsRelay = new WebSocket(url);
            _opmWsRelay.binaryType = 'arraybuffer';

            _opmWsRelay.onopen = function() {
                _opmWsConnected = true;
                console.log('[mohaa-ws] Connected to relay:', url);
            };

            _opmWsRelay.onclose = function(ev) {
                _opmWsConnected = false;
                console.log('[mohaa-ws] Disconnected from relay, code=' + ev.code);
            };

            _opmWsRelay.onerror = function(ev) {
                console.error('[mohaa-ws] WebSocket error:', ev);
            };

            _opmWsRelay.onmessage = function(ev) {
                if (ev.data instanceof ArrayBuffer && ev.data.byteLength >= 6) {
                    _opmWsRecvQueue.push(new Uint8Array(ev.data));
                }
            };

            return 1;
        } catch (e) {
            console.error('[mohaa-ws] Failed to create WebSocket:', e);
            return 0;
        }
    };

    /**
     * _opm_ws_close() — Close the relay WebSocket connection.
     */
    globalThis._opm_ws_close = function() {
        if (_opmWsRelay) {
            try { _opmWsRelay.close(1000, 'shutdown'); } catch (e) {}
            _opmWsRelay = null;
        }
        _opmWsConnected = false;
        _opmWsRecvQueue = [];
    };

    /**
     * _opm_ws_send(data_ptr, length) — Send a binary message via the relay.
     * @param data_ptr  WASM pointer to the data buffer
     * @param length    Number of bytes to send
     * @returns 1 on success, 0 on failure
     */
    globalThis._opm_ws_send = function(data_ptr, length) {
        if (!_opmWsRelay || !_opmWsConnected) return 0;
        if (length <= 0 || length > 65536) return 0;
        try {
            var M = _getModule();
            var heap = M ? M.HEAPU8 : (typeof HEAPU8 !== 'undefined' ? HEAPU8 : null);
            if (!heap) { console.error('[mohaa-ws] Send: no HEAPU8'); return 0; }
            var data = heap.slice(data_ptr, data_ptr + length);
            _opmWsRelay.send(data.buffer);
            return 1;
        } catch (e) {
            console.error('[mohaa-ws] Send failed:', e);
            return 0;
        }
    };

    /**
     * _opm_ws_recv(data_ptr, maxlen) — Receive the next queued binary message.
     * @param data_ptr  WASM pointer to a receive buffer
     * @param maxlen    Maximum bytes to copy
     * @returns Number of bytes written, or 0 if queue is empty
     */
    globalThis._opm_ws_recv = function(data_ptr, maxlen) {
        if (_opmWsRecvQueue.length === 0) return 0;
        var pkt = _opmWsRecvQueue.shift();
        var len = Math.min(pkt.length, maxlen);
        var M = _getModule();
        var heap = M ? M.HEAPU8 : (typeof HEAPU8 !== 'undefined' ? HEAPU8 : null);
        if (!heap) { console.error('[mohaa-ws] Recv: no HEAPU8'); return 0; }
        heap.set(pkt.subarray(0, len), data_ptr);
        return len;
    };

    /**
     * _opm_ws_status() — Check if the relay connection is active.
     * @returns 1 if connected, 0 otherwise
     */
    globalThis._opm_ws_status = function() {
        return (_opmWsConnected && _opmWsRelay &&
                _opmWsRelay.readyState === WebSocket.OPEN) ? 1 : 0;
    };

    /* Also register without the underscore prefix — the stub resolver tries
       both _opm_ws_open and opm_ws_open as candidates. */
    globalThis.opm_ws_open   = globalThis._opm_ws_open;
    globalThis.opm_ws_close  = globalThis._opm_ws_close;
    globalThis.opm_ws_send   = globalThis._opm_ws_send;
    globalThis.opm_ws_recv   = globalThis._opm_ws_recv;
    globalThis.opm_ws_status = globalThis._opm_ws_status;

    console.log('[mohaa-ws] WebSocket relay bridge registered on globalThis');
})();
/* ═══════ End OpenMoHAA WebSocket Relay Bridge ═══════ */
"""

# Inject the bridge early in the JS file. The exact position doesn't matter
# since we use globalThis (always available), not Module.
marker = "var ENVIRONMENT_IS_WEB="
if marker in src:
    src = src.replace(marker, ws_bridge_js + marker, 1)
    print("Patched mohaa.js with WebSocket relay bridge functions (globalThis)")
else:
    print("WARNING: Could not find injection marker for WS relay bridge")

js_path.write_text(src, encoding='utf-8')
PYWS
}

cd "$OPENMOHAA_DIR"

if [[ "$PATCH_ONLY" -eq 1 ]]; then
    if [[ "$MINIMAL_MODE" -eq 1 ]]; then
        echo "Patch-only + minimal mode requested: nothing to patch."
        exit 0
    fi
    echo "Patch-only mode: re-applying JS/HTML patches to existing export..."
    MAIN_FILES_MANIFEST="$(generate_web_main_manifest)"
    patch_web_runtime_memory "$MAIN_FILES_MANIFEST"
    render_web_html_from_templates
    patch_web_ws_relay
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

scons platform=web target="$BUILD_TARGET" -j"$(nproc)" "${EXTRA_SCONS_ARGS[@]}"

mapfile -t WASM_ARTIFACTS < <(find bin -maxdepth 1 -type f -name "*openmohaa*.wasm" | sort)
if [[ ${#WASM_ARTIFACTS[@]} -eq 0 ]]; then
    echo "ERROR: Build completed but no wasm artifacts were found in $(pwd)/bin" >&2
    exit 1
fi

mkdir -p "$PROJECT_BIN_DIR"
for artifact in "${WASM_ARTIFACTS[@]}"; do
    cp -f "$artifact" "$PROJECT_BIN_DIR/$(basename "$artifact")"
    echo "Deployed: $(basename "$artifact") -> $PROJECT_BIN_DIR"
done

# Keep a canonical filename that existing Godot export presets/paths expect.
CANONICAL_WASM="$PROJECT_BIN_DIR/libopenmohaa.wasm"
if [[ ! -f "$CANONICAL_WASM" ]]; then
    cp -f "${WASM_ARTIFACTS[0]}" "$CANONICAL_WASM"
    echo "Deployed canonical wasm: $(basename "${WASM_ARTIFACTS[0]}") -> $CANONICAL_WASM"
fi

sync_gdextension_web_entries "${WASM_ARTIFACTS[@]}"

if [[ "$BUILD_ONLY" -eq 1 ]]; then
    echo "Build-only mode: produced wasm artefacts in $OPENMOHAA_DIR/bin"
    printf '  - %s\n' "${WASM_ARTIFACTS[@]}"
    echo "Build-only mode: deployed wasm artefacts to $PROJECT_BIN_DIR and updated $PROJECT_GDEXT"
    echo "Web build complete (target=$BUILD_TARGET)."
    exit 0
fi

if [[ "$COPY_GAME_FILES" -eq 1 ]]; then
    # GAME_FILES_DIR should point to the MOHAA install root (parent of main/, mainta/, maintt/).
    # If it points directly to main/, use its parent instead.
    GAME_BASE_DIR="$GAME_FILES_DIR"
    if [[ "$(basename "$GAME_BASE_DIR")" == "main" ]]; then
        GAME_BASE_DIR="$(dirname "$GAME_BASE_DIR")"
    fi
    # Copy each game directory that exists
    for gdir in main mainta maintt; do
        if [[ -d "$GAME_BASE_DIR/$gdir" ]]; then
            mkdir -p "$EXPORT_DIR/$gdir"
            rsync -a --delete --exclude='.*' "$GAME_BASE_DIR/$gdir/" "$EXPORT_DIR/$gdir/"
            echo "Copied game files: $GAME_BASE_DIR/$gdir -> $EXPORT_DIR/$gdir"
        fi
    done
    if [[ ! -d "$GAME_BASE_DIR/main" && ! -d "$GAME_FILES_DIR" ]]; then
        echo "WARNING: Game files directory not found: $GAME_FILES_DIR"
    fi
fi

# Ensure web export always uses the freshly built cgame module from this build,
# not a potentially stale copy from GAME_FILES_DIR.
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
    if [[ "$BUILD_TARGET" == "template_release" ]]; then
        godot --headless --path "$PROJECT_DIR" --export-release Web "$EXPORT_HTML"
    else
        godot --headless --path "$PROJECT_DIR" --export-debug Web "$EXPORT_HTML"
    fi

    if [[ "$MINIMAL_MODE" -eq 0 ]]; then
        MAIN_FILES_MANIFEST="$(generate_web_main_manifest)"
        patch_web_runtime_memory "$MAIN_FILES_MANIFEST"
        render_web_html_from_templates
        patch_web_ws_relay
    fi
fi

echo "Web build complete (target=$BUILD_TARGET)."
echo "Export output: $EXPORT_HTML"

if [[ "$SERVE_ONLY" -eq 1 ]]; then
    serve_docker
fi

