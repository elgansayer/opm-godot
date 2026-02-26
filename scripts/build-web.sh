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

serve_docker() {
    local asset_path="${ASSET_PATH:-}"
    if [[ -z "$asset_path" ]]; then
        echo "ERROR: ASSET_PATH is not set. Pass --asset-path /path/to/game/files or export ASSET_PATH." >&2
        exit 1
    fi
    echo "Deploying docker compose stack (asset path: $asset_path)..."
    cd "$REPO_ROOT"
    # Force-remove any lingering containers by name to avoid the 'already in use' conflict,
    # then bring the stack up with --force-recreate so existing containers are replaced atomically.
    docker rm -f opm-godot-web opm-godot-relay 2>/dev/null || true
    ASSET_PATH="$asset_path" docker compose up -d --build --force-recreate
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
mem_old = "LDSO.init();loadDylibs();"
mem_new = (
    "LDSO.init();"
    "var __wm_pages=(wasmMemory.buffer.byteLength>>>16);"
    "if(__wm_pages<2048){"
    "try{wasmMemory.grow(2048-__wm_pages);updateMemoryViews()}"
    "catch(e){console.warn('OpenMoHAA: memory pre-grow failed',e)}}"
    "loadDylibs();"
)
if mem_old in src:
    src = src.replace(mem_old, mem_new, 1)
    print("Patched mohaa.js: memory pre-grow before loadDylibs (2048 pages)")
elif "__wm_pages" in src:
    print("Memory pre-grow already patched (idempotent)")
else:
    print("WARNING: Could not find LDSO.init();loadDylibs(); marker; memory pre-grow skipped")

preload_old = "var moduleRtn;var Module=moduleArg;var ENVIRONMENT_IS_WEB="
preload_new = (
    "var moduleRtn;var Module=moduleArg;"
    "Module['preRun']=Module['preRun']||[];"
    "Module['preRun'].push(()=>{"
    "if(typeof FS==='undefined'||typeof fetch==='undefined'||typeof addRunDependency!=='function'||typeof removeRunDependency!=='function'){return;}"
    "var __dep='openmohaa-vfs-preload'; addRunDependency(__dep);"
    "(async()=>{"
    "  var cfg=(typeof OPM_CONFIG!=='undefined'?OPM_CONFIG:{}),cdn=cfg['CDN_URL']||'';"
    "  if(cdn&&!cdn.endsWith('/'))cdn+='/';"
    "  var cache=null; try{cache=await caches.open('mohaajs-assets-v1')}catch(e){console.warn('[MOHAAjs] Cache API unavailable',e)}"
    # --- helper: ensure MEMFS directory exists ---
    "  var __mkdirs=(path)=>{"
    "    var p='',ps=path.split('/').filter(Boolean);"
    "    for(var i=0;i<ps.length;i++){p+='/'+ps[i];try{FS.mkdir(p)}catch(e){}}"
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
    # --- recursive walk: discover + download simultaneously ---
    "  var total=0,loaded=0,failed=0;"
    "  var __walk=async(relDir)=>{"
    "    var entries=await __listDir(relDir);"
    "    var promises=[];"
    "    for(var i=0;i<entries.length;i++){"
    "      var e=entries[i],name=e.name;"
    "      if(name.startsWith('.'))continue;"
    # skip native binaries (Linux .so, Windows .dll, macOS .dylib) — useless on web
    "      var ln=name.toLowerCase();"
    "      if(ln.endsWith('.so')||ln.endsWith('.dll')||ln.endsWith('.dylib'))continue;"
    "      var rel=relDir+name;"
    "      if(e.type==='directory'){"
    "        __mkdirs('/'+rel);"
    "        promises.push(__walk(rel+'/'));"
    "      }else{"
    "        total++;"
    "        promises.push((async(r)=>{"
    "          await __acquire();"
    "          try{"
    "            if(FS.analyzePath('/'+r).exists){loaded++;return}"
    "            var result=await __fetchOne(r);"
    "            if(result){"
    "              var cut=result.dst.lastIndexOf('/');"
    "              if(cut>0)__mkdirs(result.dst.slice(0,cut));"
    "              FS.writeFile(result.dst,result.data,{canRead:true,canWrite:false});"
    "              loaded++;"
    "            }else{failed++}"
    "          }catch(e){failed++}"
    "          finally{__release()}"
    "          if((loaded+failed)%200===0||loaded+failed===total)"
    "            console.log('[MOHAAjs] Progress: '+(loaded+failed)+'/'+total+' ('+failed+' failed)');"
    "        })(rel));"
    "      }"
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
    "      try{FS.writeFile(__ldst,__lf[__lrel],{canRead:true,canWrite:false})}catch(e){}"
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
    print("dynamicLibraries already patched (idempotent)")
elif dynlib_old in src:
    src = src.replace(dynlib_old, dynlib_new, 1)
    print("Patched mohaa.js dynamicLibraries to pre-register cgame.so")
else:
    print("WARNING: Could not find dynamicLibraries marker in mohaa.js; cgame pre-registration skipped")

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

patch_web_html_disable_service_worker() {
    local export_html="$EXPORT_HTML"
    if [[ ! -f "$export_html" ]]; then
        echo "WARNING: Export HTML not found for service worker patch: $export_html"
        return
    fi

    python3 - "$export_html" <<'PY'
import sys
from pathlib import Path

html_path = Path(sys.argv[1])
src = html_path.read_text(encoding='utf-8', errors='ignore')

old = "if (GODOT_CONFIG['serviceWorker'] && GODOT_CONFIG['ensureCrossOriginIsolationHeaders'] && 'serviceWorker' in navigator) {"
new = "if (false) {"

if old in src:
    src = src.replace(old, new, 1)
else:
    print("WARNING: Could not find service-worker registration marker in mohaa.html; patch skipped")

sw_cfg_old = '"serviceWorker":"mohaa.service.worker.js"'
sw_cfg_new = '"serviceWorker":""'
if sw_cfg_old in src:
    src = src.replace(sw_cfg_old, sw_cfg_new, 1)
    print("Patched mohaa.html serviceWorker config to empty")
else:
    print("WARNING: Could not find serviceWorker config marker in mohaa.html")

cleanup_marker = "<head>"
cleanup_snippet = """<head>\n<script>(function(){\n  if (!('serviceWorker' in navigator)) return;\n  window.addEventListener('load', function(){\n    navigator.serviceWorker.getRegistrations()\n      .then(function(regs){ return Promise.all(regs.map(function(reg){ return reg.unregister(); })); })\n      .then(function(){\n        if (!('caches' in window)) return;\n        return caches.keys().then(function(keys){ return Promise.all(keys.map(function(key){ return caches.delete(key); })); });\n      })\n      .then(function(){ console.log('MOHAAjs: cleared stale service workers/caches'); })\n      .catch(function(err){ console.warn('MOHAAjs: SW cleanup warning', err); });\n  });\n})();</script>"""
if cleanup_marker in src and "cleared stale service workers/caches" not in src:
    src = src.replace(cleanup_marker, cleanup_snippet, 1)
    print("Injected stale service-worker cleanup snippet")
elif "cleared stale service workers/caches" in src:
    print("Service-worker cleanup snippet already present")
else:
    print("WARNING: Could not inject service-worker cleanup snippet")

html_path.write_text(src, encoding='utf-8')
print("Patched mohaa.html to disable service-worker registration")
PY

    local sw_file
    sw_file="$(dirname "$export_html")/mohaa.service.worker.js"
    if [[ -f "$sw_file" ]]; then
        rm -f "$sw_file"
        echo "Removed generated service worker: $sw_file"
    fi
}

patch_web_html_file_picker() {
    # Inject a local-file-picker UI + IndexedDB cache into mohaa.html so
    # users can load their own MOHAA game files from disk.  Missing files
    # are then gap-filled from the server by the JS preRun walker.
    local export_html="$EXPORT_HTML"
    if [[ ! -f "$export_html" ]]; then
        echo "WARNING: Export HTML not found for file picker patch: $export_html"
        return
    fi

    python3 - "$export_html" <<'PYPICK'
import sys
from pathlib import Path

html_path = Path(sys.argv[1])
src = html_path.read_text(encoding='utf-8', errors='ignore')

# Idempotency: strip old picker content so we can re-inject with latest code
if 'opm-loader' in src:
    import re
    print("Stripping old file picker for re-injection...")
    # Remove old CSS block (from marker comment to just before </style>)
    src = re.sub(r'/\* ── MOHAAjs Local File Loader ── \*/.*?(?=</style>)', '', src, flags=re.DOTALL)
    # Remove old HTML loader div (from <div id="opm-loader"> to its closing </div></div>)
    src = re.sub(r'\s*<div id="opm-loader">.*?</div>\s*</div>\s*(?=\s*<script)', '\n', src, flags=re.DOTALL)

# ── 1. Inject CSS before </style> ─────────────────────────────────────────
picker_css = """
/* ── MOHAAjs Local File Loader ── */
#opm-loader {
  position:fixed;inset:0;background:#1a1a1a;z-index:1000;
  display:none;flex-direction:column;align-items:center;justify-content:center;
  font-family:'Noto Sans',Arial,sans-serif;color:#e0e0e0;
}
.opm-inner{text-align:center;max-width:580px;padding:2rem}
.opm-inner h2{color:#c0a060;font-size:1.8rem;margin:0 0 .4rem}
.opm-inner p{margin:.4rem 0;line-height:1.5}
.opm-hint{font-size:.85rem;color:#888}
.opm-hint code{background:#333;padding:.1rem .4rem;border-radius:3px}
.opm-game-select{margin:.6rem 0}
.opm-game-select label{font-size:.9rem;color:#aaa;margin-right:.4rem}
.opm-game-select select{
  padding:.3rem .6rem;background:#333;color:#e0e0e0;border:1px solid #555;
  border-radius:4px;font-size:.9rem;
}
.opm-cache-status{font-size:.85rem;color:#7a7;margin:.3rem 0}
#opm-pick-section{display:none}
.opm-btn{
  display:inline-block;margin:1rem .5rem;padding:.7rem 2rem;
  background:#c0a060;color:#1a1a1a;border:none;border-radius:6px;
  font-size:1rem;font-weight:bold;cursor:pointer;transition:background .2s;
}
.opm-btn:hover{background:#d4b87a}
.opm-btn:disabled{background:#555;cursor:not-allowed}
.opm-link{
  display:block;margin:.6rem auto;padding:.3rem;background:none;border:none;
  color:#888;font-size:.85rem;cursor:pointer;text-decoration:underline;
}
.opm-link:hover{color:#aaa}
#opm-prog-area{margin:1rem 0;display:none}
#opm-file-prog{width:100%;height:6px}
#opm-prog-text{font-size:.85rem;color:#aaa;margin-top:.3rem}
.opm-disclaimer{font-size:.75rem;color:#666;margin-top:1.5rem;line-height:1.4;max-width:520px}
.opm-disclaimer a{color:#888}
"""

style_close = '</style>'
if style_close in src:
    src = src.replace(style_close, picker_css + style_close, 1)
    print("Injected file picker CSS")
else:
    print("WARNING: Could not find </style> for CSS injection")

# ── 2. Inject HTML before <script src="mohaa.js"> ─────────────────────────
picker_html = """
\t\t<div id="opm-loader">
\t\t\t<div class="opm-inner">
\t\t\t\t<h2>MOHAAjs</h2>
\t\t\t\t<p>Medal of Honor: Allied Assault</p>
\t\t\t\t<div class="opm-game-select" id="opm-game-select">
\t\t\t\t\t<label for="opm-target-game">Select game:</label>
\t\t\t\t\t<select id="opm-target-game">
\t\t\t\t\t\t<option value="0">Allied Assault (main)</option>
\t\t\t\t\t\t<option value="1">Spearhead (mainta)</option>
\t\t\t\t\t\t<option value="2">Breakthrough (maintt)</option>
\t\t\t\t\t</select>
\t\t\t\t</div>
\t\t\t\t<p id="opm-cache-status" class="opm-cache-status"></p>
\t\t\t\t<button id="opm-play-btn" class="opm-btn">Play</button>
\t\t\t\t<div id="opm-pick-section">
\t\t\t\t\t<p class="opm-hint"><strong>\u26a0\ufe0f Select the MOHAA <em>installation</em> folder</strong> \u2014 the folder that <em>contains</em> <code>main</code>, <code>mainta</code>, and/or <code>maintt</code>.<br>Do <strong>NOT</strong> select the <code>main</code> folder itself!</p>
\t\t\t\t\t<button id="opm-pick-btn" class="opm-btn">Select MOHAA Installation Folder</button>
\t\t\t\t\t<input type="file" id="opm-input-fb" webkitdirectory multiple style="display:none">
\t\t\t\t\t<div id="opm-prog-area">
\t\t\t\t\t\t<progress id="opm-file-prog" style="width:100%"></progress>
\t\t\t\t\t\t<p id="opm-prog-text">Reading files\u2026</p>
\t\t\t\t\t</div>
\t\t\t\t</div>
\t\t\t\t<button id="opm-skip-btn" class="opm-link">Skip \u2014 use server files only</button>
\t\t\t\t<p class="opm-disclaimer">MOHAAjs is an independent fan project and is not affiliated with, endorsed by, or connected to Electronic Arts, the OpenMoHAA project, or any original rights holders of Medal of Honor: Allied Assault. All trademarks belong to their respective owners. You must own a legitimate copy of the game to use this application.</p>
\t\t\t</div>
\t\t</div>

"""

script_tag = '<script src="mohaa.js"></script>'
if script_tag in src:
    src = src.replace(script_tag, picker_html + '\t\t' + script_tag, 1)
    print("Injected file picker HTML")
else:
    print("WARNING: Could not find <script src=mohaa.js> for HTML injection")

# ── 3. Replace the engine.startGame() boot block ──────────────────────────
# On first patch: locate by original engine markers (setStatusMode/displayFailureNotice).
# On re-patch: locate by our custom OPM_BOOT_START/OPM_BOOT_END markers.
OPM_BOOT_MARKER_START = "/* OPM_BOOT_START */"
OPM_BOOT_MARKER_END   = "/* OPM_BOOT_END */"
BOOT_START = "setStatusMode('progress');"
BOOT_END   = "}, displayFailureNotice);"

opm_si = src.find(OPM_BOOT_MARKER_START)
opm_ei = src.find(OPM_BOOT_MARKER_END, opm_si) if opm_si >= 0 else -1
if opm_si >= 0 and opm_ei >= 0:
    si = opm_si
    ei = opm_ei + len(OPM_BOOT_MARKER_END)
    print("Found OPM boot markers for re-patch")
else:
    si = src.find(BOOT_START)
    ei = src.find(BOOT_END, si) if si >= 0 else -1
    if si >= 0 and ei >= 0:
        ei += len(BOOT_END)
        print("Found original engine boot markers for first-time patch")

if si < 0 or ei < 0:
    print("WARNING: Could not locate engine.startGame() boot block")
    html_path.write_text(src, encoding='utf-8')
    sys.exit(0)

T2 = '\t\t'
T3 = '\t\t\t'
T4 = '\t\t\t\t'
T5 = '\t\t\t\t\t'

new_boot = f"""/* OPM_BOOT_START */
{T2}/* MOHAAjs: Game Selector + Per-Game Cache + Local File Loader */
{T2}(async function opmBoot() {{
{T3}var DB_VER=1,ST='f';
{T3}var GAME_DIRS={{0:'main',1:'mainta',2:'maintt'}};
{T3}var GAME_NAMES={{0:'Allied Assault',1:'Spearhead',2:'Breakthrough'}};
{T3}/* Which caches to load for each game (base + expansion) */
{T3}var GAME_DEPS={{0:['main'],1:['main','mainta'],2:['main','maintt']}};
{T3}var targetGame=0;
{T3}window.__opmTargetGame=0;

{T3}/* ── Pre-select from URL param ── */
{T3}var urlParams=new URLSearchParams(window.location.search);
{T3}var urlTG=urlParams.get('com_target_game');
{T3}if(urlTG!==null){{var p=parseInt(urlTG,10);if(p>=0&&p<=2)targetGame=p}}

{T3}var gameSel=document.getElementById('opm-target-game');
{T3}var loader=document.getElementById('opm-loader');
{T3}var pickSection=document.getElementById('opm-pick-section');
{T3}var playBtn=document.getElementById('opm-play-btn');
{T3}var cacheStatus=document.getElementById('opm-cache-status');
{T3}if(gameSel)gameSel.value=String(targetGame);

{T3}/* ── Per-game IndexedDB helpers ── */
{T3}function dbName(gd){{return 'opm-'+gd}}
{T3}function openGameDB(gd){{
{T4}return new Promise(function(ok){{
{T5}try{{var r=indexedDB.open(dbName(gd),DB_VER);
{T5}r.onupgradeneeded=function(e){{var db=e.target.result;if(!db.objectStoreNames.contains(ST))db.createObjectStore(ST)}};
{T5}r.onsuccess=function(e){{ok(e.target.result)}};
{T5}r.onerror=function(){{ok(null)}}}}catch(e){{ok(null)}}
{T4}}})
{T3}}}

{T3}async function loadFromDB(gd){{
{T4}var db=await openGameDB(gd);if(!db)return null;
{T4}return new Promise(function(ok){{
{T5}try{{var tx=db.transaction(ST,'readonly'),s=tx.objectStore(ST),out={{}},n=0;
{T5}var cur=s.openCursor();
{T5}cur.onsuccess=function(e){{var c=e.target.result;if(c){{out[c.key]=c.value;n++;c.continue()}}else{{db.close();ok(n?out:null)}}}};
{T5}cur.onerror=function(){{db.close();ok(null)}}}}catch(e){{db.close();ok(null)}}
{T4}}})
{T3}}}

{T3}async function saveToDB(gd,files){{
{T4}var db=await openGameDB(gd);if(!db)return;
{T4}var keys=Object.keys(files),bs=20;
{T4}for(var i=0;i<keys.length;i+=bs){{
{T5}var chunk=keys.slice(i,i+bs);
{T5}await new Promise(function(done){{
{T5}{T2}try{{var tx=db.transaction(ST,'readwrite'),s=tx.objectStore(ST);
{T5}{T2}chunk.forEach(function(k){{s.put(files[k],k)}});
{T5}{T2}tx.oncomplete=done;tx.onerror=function(){{done()}}}}catch(e){{done()}}
{T5}}})
{T4}}}
{T4}db.close()
{T3}}}

{T3}async function hasCache(gd){{
{T4}var db=await openGameDB(gd);if(!db)return false;
{T4}return new Promise(function(ok){{
{T5}try{{var tx=db.transaction(ST,'readonly');var req=tx.objectStore(ST).count();
{T5}req.onsuccess=function(){{db.close();ok(req.result>0)}};
{T5}req.onerror=function(){{db.close();ok(false)}}}}catch(e){{db.close();ok(false)}}
{T4}}})
{T3}}}

{T3}async function loadGameCaches(game){{
{T4}var deps=GAME_DEPS[game]||['main'];
{T4}/* ALL deps must be cached — partial hits are a cache miss */
{T4}for(var i=0;i<deps.length;i++){{
{T5}if(!(await hasCache(deps[i]))){{
{T5}{T2}console.log('[MOHAAjs] Cache miss: '+deps[i]+' not cached');
{T5}{T2}return null
{T5}}}
{T4}}}
{T4}var allFiles={{}};
{T4}for(var i=0;i<deps.length;i++){{
{T5}var files=await loadFromDB(deps[i]);
{T5}if(files){{var ks=Object.keys(files);for(var j=0;j<ks.length;j++)allFiles[ks[j]]=files[ks[j]];
{T5}console.log('[MOHAAjs] Loaded '+ks.length+' files from '+deps[i]+' cache')}}
{T4}}}
{T4}return Object.keys(allFiles).length?allFiles:null
{T3}}}

{T3}async function cacheByGameDir(rawFiles){{
{T4}var buckets={{}};var keys=Object.keys(rawFiles);
{T4}for(var i=0;i<keys.length;i++){{
{T5}var rel=keys[i].replace(/\\\\/g,'/');
{T5}var slash=rel.indexOf('/');
{T5}if(slash>0){{
{T5}{T2}var td=rel.substring(0,slash).toLowerCase();
{T5}{T2}if(td==='main'||td==='mainta'||td==='maintt'){{
{T5}{T3}if(!buckets[td])buckets[td]={{}};buckets[td][rel]=rawFiles[keys[i]];continue
{T5}{T2}}}
{T5}}}
{T5}if(!buckets['main'])buckets['main']={{}};buckets['main'][rel]=rawFiles[keys[i]]
{T4}}}
{T4}var dirs=Object.keys(buckets);
{T4}console.log('[MOHAAjs] Caching files for: '+dirs.join(', '));
{T4}for(var d=0;d<dirs.length;d++){{
{T5}var n=Object.keys(buckets[dirs[d]]).length;
{T5}await saveToDB(dirs[d],buckets[dirs[d]]);
{T5}console.log('[MOHAAjs] Cached '+n+' files to '+dirs[d])
{T4}}}
{T3}}}

{T3}async function updateCacheStatus(){{
{T4}var parts=[];
{T4}for(var k=0;k<3;k++){{
{T5}var gd=GAME_DIRS[k];
{T5}if(await hasCache(gd))parts.push(GAME_NAMES[k]+' \\u2714')
{T4}}}
{T4}if(cacheStatus)cacheStatus.textContent=parts.length?'Cached: '+parts.join(', '):'No cached game files'
{T3}}}

{T3}/* ── File reading helpers ── */
{T3}async function opmReadDirHandle(h,prefix){{
{T4}var files={{}};
{T4}for await(var entry of h.values()){{
{T5}if(entry.name.startsWith('.'))continue;
{T5}var p=prefix?prefix+'/'+entry.name:entry.name;
{T5}if(entry.kind==='directory'){{Object.assign(files,await opmReadDirHandle(entry,p))}}
{T5}else{{try{{var f=await entry.getFile();files[p]=new Uint8Array(await f.arrayBuffer())}}catch(e){{}}}}
{T4}}}
{T4}return files
{T3}}}

{T3}async function opmReadViaInput(){{
{T4}return new Promise(function(ok){{
{T5}var inp=document.getElementById('opm-input-fb');
{T5}inp.onchange=async function(){{
{T5}{T2}var list=Array.from(inp.files),files={{}};
{T5}{T2}var area=document.getElementById('opm-prog-area');
{T5}{T2}var bar=document.getElementById('opm-file-prog');
{T5}{T2}var txt=document.getElementById('opm-prog-text');
{T5}{T2}area.style.display='block';bar.max=list.length;bar.value=0;
{T5}{T2}for(var i=0;i<list.length;i++){{
{T5}{T3}var f=list[i],rp=f.webkitRelativePath||f.name;
{T5}{T3}var slash=rp.indexOf('/');if(slash>=0)rp=rp.substring(slash+1);
{T5}{T3}if(!rp||rp.startsWith('.'))continue;
{T5}{T3}try{{files[rp]=new Uint8Array(await f.arrayBuffer())}}catch(e){{}}
{T5}{T3}bar.value=i+1;txt.textContent='Reading: '+(i+1)+'/'+list.length
{T5}{T2}}}
{T5}{T2}area.style.display='none';
{T5}{T2}ok(Object.keys(files).length?files:null)
{T5}}};
{T5}inp.click()
{T4}}})
{T3}}}

{T3}async function opmPickFiles(){{
{T4}var area=document.getElementById('opm-prog-area');
{T4}var txt=document.getElementById('opm-prog-text');
{T4}if(window.showDirectoryPicker){{
{T5}try{{
{T5}{T2}area.style.display='block';txt.textContent='Reading files from folder\\u2026';
{T5}{T2}var dh=await window.showDirectoryPicker({{mode:'read'}});
{T5}{T2}var files=await opmReadDirHandle(dh,'');
{T5}{T2}area.style.display='none';
{T5}{T2}if(Object.keys(files).length)return files
{T5}}}catch(e){{
{T5}{T2}area.style.display='none';
{T5}{T2}if(e.name==='AbortError')return null;
{T5}{T2}console.warn('[MOHAAjs] Directory picker error, trying fallback:',e)
{T5}}}
{T4}}}
{T4}return opmReadViaInput()
{T3}}}

{T3}function opmMapFilesToMemfs(rawFiles){{
{T4}var mapped={{}};var keys=Object.keys(rawFiles);var foundDirs={{}};
{T4}for(var i=0;i<keys.length;i++){{
{T5}var rel=keys[i].replace(/\\\\/g,'/');
{T5}var firstSlash=rel.indexOf('/');
{T5}if(firstSlash>0){{
{T5}{T2}var topDir=rel.substring(0,firstSlash).toLowerCase();
{T5}{T2}if(topDir==='main'||topDir==='mainta'||topDir==='maintt')foundDirs[topDir]=true
{T5}}}
{T5}mapped[rel]=rawFiles[keys[i]]
{T4}}}
{T4}var dirList=Object.keys(foundDirs);
{T4}if(dirList.length>0)console.log('[MOHAAjs] Detected game directories: '+dirList.join(', '));
{T4}else console.warn('[MOHAAjs] No main/mainta/maintt subdirs found in selection');
{T4}return mapped
{T3}}}

{T3}/* ── Engine starter ── */
{T3}function startEngine(){{
{T4}var currentUrl=new URL(window.location.href);
{T4}currentUrl.searchParams.set('com_target_game',String(targetGame));
{T4}window.history.replaceState(null,'',currentUrl.toString());
{T4}window.__opmTargetGame=targetGame;
{T4}window.__opmGameDir=GAME_DIRS[targetGame]||'main';
{T4}setStatusMode('progress');
{T4}var engineArgs=['+set','com_target_game',String(targetGame)];
{T4}engine.startGame({{
{T5}'args':engineArgs,
{T5}'onProgress':function(current,total){{
{T5}{T2}if(current>0&&total>0){{statusProgress.value=current;statusProgress.max=total}}
{T5}{T2}else{{statusProgress.removeAttribute('value');statusProgress.removeAttribute('max')}}
{T5}}}
{T4}}}).then(function(){{setStatusMode('hidden')}},displayFailureNotice)
{T3}}}

{T3}/* ── Always show game picker ── */
{T3}statusOverlay.style.visibility='hidden';
{T3}loader.style.display='flex';
{T3}if(pickSection)pickSection.style.display='none';
{T3}await updateCacheStatus();

{T3}await new Promise(function(resolve){{
{T4}playBtn.onclick=async function(){{
{T5}targetGame=parseInt(gameSel.value,10)||0;
{T5}window.__opmTargetGame=targetGame;
{T5}playBtn.disabled=true;playBtn.textContent='Loading\\u2026';
{T5}/* Check per-game caches */
{T5}var cached=await loadGameCaches(targetGame);
{T5}if(cached){{
{T5}{T2}console.log('[MOHAAjs] Cache hit for '+GAME_NAMES[targetGame]);
{T5}{T2}window.__opmLocalFiles=cached;
{T5}{T2}loader.style.display='none';
{T5}{T2}resolve();return
{T5}}}
{T5}/* No cache \u2014 show file picker */
{T5}playBtn.style.display='none';
{T5}if(pickSection)pickSection.style.display='block';
{T5}document.getElementById('opm-pick-btn').onclick=async function(){{
{T5}{T2}this.disabled=true;
{T5}{T2}var rawFiles=await opmPickFiles();
{T5}{T2}if(rawFiles){{
{T5}{T3}targetGame=parseInt(gameSel.value,10)||0;
{T5}{T3}window.__opmTargetGame=targetGame;
{T5}{T3}window.__opmGameDir=GAME_DIRS[targetGame]||'main';
{T5}{T3}var files=opmMapFilesToMemfs(rawFiles);
{T5}{T3}var n=Object.keys(files).length;
{T5}{T3}console.log('[MOHAAjs] Read '+n+' local files (target: '+GAME_NAMES[targetGame]+')');
{T5}{T3}window.__opmLocalFiles=files;
{T5}{T3}loader.style.display='none';
{T5}{T3}cacheByGameDir(files).catch(function(e){{console.warn('[MOHAAjs] Cache save failed',e)}});
{T5}{T3}resolve()
{T5}{T2}}}else{{this.disabled=false}}
{T5}}}
{T4}}};
{T4}document.getElementById('opm-skip-btn').onclick=function(){{
{T5}targetGame=parseInt(gameSel.value,10)||0;
{T5}window.__opmTargetGame=targetGame;
{T5}loader.style.display='none';
{T5}resolve()
{T4}}}
{T3}}});

{T3}startEngine()
{T2}}})().catch(displayFailureNotice);
/* OPM_BOOT_END */"""

src = src[:si] + new_boot + src[ei:]
print("Patched boot sequence with local file picker gate")

html_path.write_text(src, encoding='utf-8')
print("File picker HTML patch complete")
PYPICK
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

obfuscate_godot_fingerprints() {
    # Post-build pass: remove/rename ALL Godot-identifiable strings from the
    # exported JS, HTML, and audio worklet files so the engine lineage is not
    # visible in browser DevTools, page source, or network requests.
    #
    # This is purely cosmetic — WASM binaries are already opaque bytecode.
    # We rename identifiers consistently across all files so cross-references
    # (e.g. worklet processor names) remain valid.

    local export_dir="$EXPORT_DIR"
    [[ -d "$export_dir" ]] || return 0

    python3 - "$export_dir" << 'PYOBF'
import sys, os, re, pathlib

export_dir = pathlib.Path(sys.argv[1])

# ── Files to process ──
js_file = export_dir / 'mohaa.js'
html_file = export_dir / 'mohaa.html'
worklet_file = export_dir / 'mohaa.audio.worklet.js'
pos_worklet_file = export_dir / 'mohaa.audio.position.worklet.js'
manifest_file = export_dir / 'mohaa.manifest.json'

def read(p):
    return p.read_text(encoding='utf-8') if p.exists() else None

def write(p, txt):
    if txt is not None:
        p.write_text(txt, encoding='utf-8')

# ── 1. Identifier renaming (order matters: longer matches first) ──
# These replacements are applied to ALL text files.
renames = [
    # PascalCase class names
    ('GodotAudioScript',             'OpmAudioScript'),
    ('GodotAudioWorklet',            'OpmAudioWorklet'),
    ('GodotAudio',                   'OpmAudio'),
    ('GodotChannel',                 'OpmChannel'),
    ('GodotConfig',                  'OpmConfig'),
    ('GodotDisplayCursor',           'OpmDisplayCursor'),
    ('GodotDisplayScreen',           'OpmDisplayScreen'),
    ('GodotDisplayVK',               'OpmDisplayVK'),
    ('GodotDisplay',                 'OpmDisplay'),
    ('GodotEmscripten',              'OpmEmscripten'),
    ('GodotEventListeners',          'OpmEventListeners'),
    ('GodotFetch',                   'OpmFetch'),
    ('GodotFS',                      'OpmFS'),
    ('GodotIME',                     'OpmIME'),
    ('GodotInputDragDrop',           'OpmInputDragDrop'),
    ('GodotInputGamepads',           'OpmInputGamepads'),
    ('GodotInput',                   'OpmInput'),
    ('GodotJSWrapper',               'OpmJSWrapper'),
    ('GodotOS',                      'OpmOS'),
    ('GodotPWA',                     'OpmPWA'),
    ('GodotRTCDataChannel',          'OpmRTCDataChannel'),
    ('GodotRTCPeerConnection',       'OpmRTCPeerConnection'),
    ('GodotRuntime',                 'OpmRuntime'),
    ('GodotWebGL',                   'OpmWebGL'),
    ('GodotWebMidi',                 'OpmWebMidi'),
    ('GodotWebSocket',               'OpmWebSocket'),
    ('GodotWebXR',                   'OpmWebXR'),
    ('GodotProcessor',               'OpmProcessor'),
    ('GodotPositionReportingProcessor', 'OpmPositionReportingProcessor'),

    # Worklet processor registration names (cross-referenced between JS and worklet files)
    ('godot-position-reporting-processor', 'opm-position-reporting-processor'),
    ('godot-processor',              'opm-processor'),

    # Config property names (HTML + JS)
    ('gdextensionLibs',              'extensionLibs'),
    ('godotPoolSize',                'workerPoolSize'),

    # UPPER_CASE config names (HTML inline script)
    ('GODOT_THREADS_ENABLED',        'OPM_THREADS_ENABLED'),
    ('GODOT_CONFIG',                 'OPM_CONFIG'),

    # NOTE: Do NOT rename godot_* / _godot_* snake_case function names!
    # These are WASM import/export symbols (C-exported via Emscripten) and
    # C++ mangled names (e.g. _Z14godot_web_mainiPPc). The .wasm binary
    # still references the original names — renaming them in JS breaks linking.

    # Safe string-only renames
    ('OpenMoHAA',                    'MOHAAjs'),
    ('godotengine.org',              'openmohaa.net'),
]

def apply_renames(txt):
    for old, new in renames:
        txt = txt.replace(old, new)
    # Only rename user-visible "Godot" text, NOT snake_case function names
    # which are WASM import symbols that must match the compiled binary.
    txt = re.sub(r'\bGodot Engine\b', 'MOHAAjs Engine', txt)
    txt = re.sub(r'\bGodot projects\b', 'projects', txt)
    # Rename PascalCase "Godot" only when NOT preceded by _ or lowercase
    # (to avoid mangled C++ names like _Z14godot_web_mainiPPc)
    # The PascalCase class renames above already handle GodotXxx classes.
    # This catches any remaining standalone "Godot" in string literals.
    txt = re.sub(r'(?<![_a-z0-9])Godot(?![_a-z])', 'Opm', txt)
    return txt

# ── 2. Strip copyright headers mentioning Godot from worklet files ──
def strip_godot_headers(txt):
    if txt is None:
        return None
    # Remove multi-line /* ... GODOT ENGINE ... */ comment blocks
    txt = re.sub(
        r'/\*[^*]*\*+(?:[^/*][^*]*\*+)*/\s*',
        '',
        txt,
        count=0,
        flags=re.DOTALL
    )
    # Remove any remaining single-line // comments mentioning godot
    txt = re.sub(r'//.*godot.*\n', '\n', txt, flags=re.IGNORECASE)
    return txt

# ── 3. Silence noisy console output in mohaa.js ──
def silence_console(txt):
    if txt is None:
        return None
    marker = '/*opm-console-silence*/'
    # Strip any previously-prepended silencers (idempotent)
    txt = re.sub(r'(?:/\*opm-console-silence\*/\s*)?\(function\(\)\{var _n=function\(\)\{\};\s*console\.log=_n;\s*console\.info=_n;\s*console\.warn=_n;\s*console\.debug=_n;\}\)\(\);\n?', '', txt)
    # Redirect console.log/info/debug to no-ops.  Keep warn and error for debugging.
    silencer = (
        marker + '(function(){var _n=function(){}; '
        'console.log=_n; console.info=_n; '
        'console.debug=_n;})();\n'
    )
    txt = silencer + txt
    return txt

# ── 4. Clean HTML ──
def clean_html(txt):
    if txt is None:
        return None
    txt = apply_renames(txt)
    # After apply_renames, "Godot" is now "Opm" — match the transformed text
    txt = txt.replace(
        'required to run Opm projects on the Web are missing',
        'required to run this application on the Web are missing'
    )
    txt = txt.replace(
        'required to run projects on the Web are missing',
        'required to run this application on the Web are missing'
    )
    # Clean page title if still default
    txt = txt.replace('OpenMoHAA Test', 'MOHAAjs')
    txt = txt.replace('OpenMoHAA', 'MOHAAjs')
    return txt

# ── Process all files ──
counts = {}

# mohaa.js — main runtime
js = read(js_file)
if js:
    js = silence_console(js)
    js = apply_renames(js)
    # Strip the "Godot Engine v4.x.x" startup banner from print output
    js = re.sub(r'Opm Engine v[\d.]+[^\n]*', '', js)
    write(js_file, js)
    counts['mohaa.js'] = True

# mohaa.html
html = read(html_file)
if html:
    html = clean_html(html)
    write(html_file, html)
    counts['mohaa.html'] = True

# Audio worklet files
for wf in [worklet_file, pos_worklet_file]:
    w = read(wf)
    if w:
        w = strip_godot_headers(w)
        w = apply_renames(w)
        write(wf, w)
        counts[wf.name] = True

# Manifest
m = read(manifest_file)
if m:
    m = m.replace('OpenMoHAA Test', 'MOHAAjs')
    m = m.replace('OpenMoHAA', 'MOHAAjs')
    write(manifest_file, m)
    counts['manifest'] = True

print(f"Obfuscated Godot fingerprints in {len(counts)} files: {', '.join(counts.keys())}")
PYOBF
}

cd "$OPENMOHAA_DIR"

if [[ "$PATCH_ONLY" -eq 1 ]]; then
    echo "Patch-only mode: re-applying JS/HTML patches to existing export..."
    MAIN_FILES_MANIFEST="$(generate_web_main_manifest)"
    patch_web_runtime_memory "$MAIN_FILES_MANIFEST"
    patch_web_html_disable_service_worker
    patch_web_html_file_picker
    patch_web_ws_relay
    obfuscate_godot_fingerprints
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

sync_gdextension_web_entries "${WASM_ARTIFACTS[@]}"

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

    MAIN_FILES_MANIFEST="$(generate_web_main_manifest)"
    patch_web_runtime_memory "$MAIN_FILES_MANIFEST"
    patch_web_html_disable_service_worker
    patch_web_html_file_picker
    patch_web_ws_relay
    obfuscate_godot_fingerprints
fi

echo "Web build complete (target=$BUILD_TARGET)."
echo "Export output: $EXPORT_HTML"

if [[ "$SERVE_ONLY" -eq 1 ]]; then
    serve_docker
fi

