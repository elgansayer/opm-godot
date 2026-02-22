#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_BIN_DIR="$SCRIPT_DIR/project/bin"
PROJECT_DIR="$SCRIPT_DIR/project"
EXPORT_DIR="$SCRIPT_DIR/exports/web"
EXPORT_HTML="$EXPORT_DIR/mohaa.html"
EXPORT_JS="$EXPORT_DIR/mohaa.js"
PROJECT_GDEXT="$PROJECT_DIR/openmohaa.gdextension"
GAME_FILES_DIR="${GAME_FILES_DIR:-$HOME/.local/share/openmohaa/main}"

if [[ -f "$SCRIPT_DIR/openmohaa/SConstruct" ]]; then
    OPENMOHAA_DIR="$SCRIPT_DIR/openmohaa"
elif [[ -f "$SCRIPT_DIR/openmohaa/openmohaa/SConstruct" ]]; then
    OPENMOHAA_DIR="$SCRIPT_DIR/openmohaa/openmohaa"
else
    echo "ERROR: Could not find OpenMoHAA SConstruct under $SCRIPT_DIR/openmohaa" >&2
    exit 1
fi

EMSDK_DIR="${EMSDK_DIR:-/home/elgan/emsdk}"
BUILD_TARGET="template_debug"
CHECK_ONLY=0
EXPORT_AFTER_BUILD=1
COPY_GAME_FILES=1
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

EMSDK_ENV_SH="$EMSDK_DIR/emsdk_env.sh"
if [[ ! -f "$EMSDK_ENV_SH" ]]; then
    echo "ERROR: Emscripten SDK env script not found at: $EMSDK_ENV_SH" >&2
    exit 1
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

    awk '!/^web\.(debug|release)(\.threads)?\.wasm32\s*=/' "$PROJECT_GDEXT" > "$PROJECT_GDEXT.tmp"

    {
        if [[ -n "$debug_threads" ]]; then
            echo "web.debug.threads.wasm32 = \"res://bin/$debug_threads\""
        fi
        if [[ -n "$debug_nothreads" ]]; then
            echo "web.debug.wasm32 = \"res://bin/$debug_nothreads\""
        fi
        if [[ -n "$release_threads" ]]; then
            echo "web.release.threads.wasm32 = \"res://bin/$release_threads\""
        fi
        if [[ -n "$release_nothreads" ]]; then
            echo "web.release.wasm32 = \"res://bin/$release_nothreads\""
        fi
    } >> "$PROJECT_GDEXT.tmp"

    mv "$PROJECT_GDEXT.tmp" "$PROJECT_GDEXT"
}

generate_web_main_manifest() {
    local manifest_path="$EXPORT_DIR/.openmohaa-main-files.txt"
    local main_dir="$EXPORT_DIR/main"

    : > "$manifest_path"

    if [[ -d "$main_dir" ]]; then
        while IFS= read -r -d '' f; do
            local rel="${f#"$main_dir/"}"
            case "${rel,,}" in
                pak0.pk3|pak1.pk3|pak2.pk3|pak3.pk3|pak4.pk3|pak5.pk3|pak6.pk3|openmohaa.pk3|cgame.so)
                    continue
                    ;;
            esac
            printf '%s\n' "$rel" >> "$manifest_path"
        done < <(find "$main_dir" -type f -print0 | sort -z)
    fi

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
    f"['main/{_js_quote(rel)}','/main/{_js_quote(rel)}']" for rel in extra_preload_entries
)

old = "loadDylibs();updateMemoryViews();return wasmExports"
new = (
    "if(wasmMemory&&wasmMemory.buffer&&wasmMemory.buffer.byteLength<4096*65536){"
    "try{var __godot_required_pages=(4096*65536-wasmMemory.buffer.byteLength+65535)>>16;"
    "if(__godot_required_pages>0){wasmMemory.grow(__godot_required_pages);updateMemoryViews()}}"
    "catch(e){console.warn('OpenMoHAA: wasm memory grow before dylib load failed',e)}}"
    "loadDylibs();updateMemoryViews();return wasmExports"
)

old_threads = (
    "if(metadata.neededDynlibs){dynamicLibraries=metadata.neededDynlibs.concat(dynamicLibraries)}"
    "registerTLSInit"
)
new_threads = (
    "if(metadata.neededDynlibs){dynamicLibraries=metadata.neededDynlibs.concat(dynamicLibraries)}"
    "if(wasmMemory&&wasmMemory.buffer&&wasmMemory.buffer.byteLength<4096*65536){"
    "try{var __godot_required_pages=(4096*65536-wasmMemory.buffer.byteLength+65535)>>16;"
    "if(__godot_required_pages>0){wasmMemory.grow(__godot_required_pages);updateMemoryViews()}}"
    "catch(e){console.warn('OpenMoHAA: wasm memory grow before dylib load failed',e)}}"
    "registerTLSInit"
)

patched = False
if old in src:
    src = src.replace(old, new, 1)
    patched = True
elif old_threads in src:
    src = src.replace(old_threads, new_threads, 1)
    patched = True

if not patched:
    print("WARNING: Could not find wasm dylib load marker in mohaa.js; memory patch skipped")
else:
    print("Patched mohaa.js runtime memory growth for GDExtension load")

preload_old = "var moduleRtn;var Module=moduleArg;var ENVIRONMENT_IS_WEB="
preload_new = (
    "var moduleRtn;var Module=moduleArg;"
    "Module['preRun']=Module['preRun']||[];"
    "Module['preRun'].push(()=>{"
    "if(typeof FS==='undefined'||typeof fetch==='undefined'||typeof addRunDependency!=='function'||typeof removeRunDependency!=='function'){return;}"
    "try{FS.mkdir('/main')}catch(e){}"
    "var __requiredFiles=["
    "['Pak0.pk3','pak0.pk3'],"
    "['Pak1.pk3','pak1.pk3'],"
    "['Pak2.pk3','pak2.pk3'],"
    "['Pak3.pk3','pak3.pk3'],"
    "['Pak4.pk3','pak4.pk3'],"
    "['Pak5.pk3','pak5.pk3'],"
    "['Pak6.pk3','pak6.pk3'],"
    "['openmohaa.pk3'],"
    "['cgame.so']"
    "];"
    f"var __extraFiles=[{extra_files_js}];"
    "var __dep='openmohaa-pk3-preload';"
    "var __extraLoaded=0;"
    "addRunDependency(__dep);"
    "var __remaining=__requiredFiles.length+__extraFiles.length;"
    "var __finishOne=()=>{__remaining--;if(__remaining<=0){removeRunDependency(__dep)}};"
    "var __ensureDir=(path)=>{"
    "if(!path||path==='/'||path===''){return}"
    "if(typeof FS.mkdirTree==='function'){try{FS.mkdirTree(path)}catch(e){}return}"
    "var parts=path.split('/').filter(Boolean);"
    "var cur='';"
    "for(var i=0;i<parts.length;i++){cur+='/'+parts[i];try{FS.mkdir(cur)}catch(e){}}"
    "};"
    "var __tryNames=(names,done)=>{"
    "if(!names.length){done(false);return;}"
    "var name=names[0];"
    "fetch('main/'+name).then((res)=>{if(!res.ok){throw new Error('HTTP '+res.status)}return res.arrayBuffer()})"
    ".then((buf)=>{FS.writeFile('/main/'+name,new Uint8Array(buf),{canRead:true,canWrite:false});done(true,name)})"
    ".catch(()=>{__tryNames(names.slice(1),done)});"
    "};"
    "__requiredFiles.forEach((candidates)=>{"
    "__tryNames(candidates,(ok,name)=>{"
    "if(!ok){console.warn('OpenMoHAA preload missing',candidates[0])}"
    "else{console.log('OpenMoHAA preloaded',name)}"
    "__finishOne();"
    "});"
    "});"
    "var __extraQueue=__extraFiles.slice();"
    "var __extraWorkers=8;"
    "for(var __worker=0;__worker<__extraWorkers;__worker++){"
    "(function __pumpExtra(){"
    "var entry=__extraQueue.shift();"
    "if(!entry){return}"
    "var srcPath=entry[0];"
    "var dstPath=entry[1];"
    "fetch(srcPath).then((res)=>{if(!res.ok){throw new Error('HTTP '+res.status)}return res.arrayBuffer()})"
    ".then((buf)=>{"
    "var cut=dstPath.lastIndexOf('/');"
    "if(cut>0){__ensureDir(dstPath.slice(0,cut))}"
    "FS.writeFile(dstPath,new Uint8Array(buf),{canRead:true,canWrite:false});"
    "__extraLoaded++;"
    "if(__extraLoaded<=5){console.log('OpenMoHAA preloaded loose',srcPath)}"
    "})"
    ".catch(()=>{})"
    ".finally(()=>{__finishOne();__pumpExtra()});"
    "})();"
    "}"
    "});"
    "var ENVIRONMENT_IS_WEB="
)

if preload_old in src:
    src = src.replace(preload_old, preload_new, 1)
    print("Patched mohaa.js async preRun pk3 preload")
else:
    print("WARNING: Could not find Module preRun injection marker in mohaa.js; pk3 preload patch skipped")

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
    "resolved||=resolveSymbol(prop);"
    "if(!resolved&&prop==='__cxa_find_matching_catch_2'){resolved=()=>0}"
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
dynlib_old = "'dynamicLibraries': [`${loadPath}.side.wasm`].concat(this.gdextensionLibs),"
dynlib_new = "'dynamicLibraries': [`${loadPath}.side.wasm`, 'main/cgame.so'].concat(this.gdextensionLibs),"
if dynlib_old in src:
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
cleanup_snippet = """<head>\n<script>(function(){\n  if (!('serviceWorker' in navigator)) return;\n  window.addEventListener('load', function(){\n    navigator.serviceWorker.getRegistrations()\n      .then(function(regs){ return Promise.all(regs.map(function(reg){ return reg.unregister(); })); })\n      .then(function(){\n        if (!('caches' in window)) return;\n        return caches.keys().then(function(keys){ return Promise.all(keys.map(function(key){ return caches.delete(key); })); });\n      })\n      .then(function(){ console.log('OpenMoHAA: cleared stale service workers/caches'); })\n      .catch(function(err){ console.warn('OpenMoHAA: SW cleanup warning', err); });\n  });\n})();</script>"""
if cleanup_marker in src and "OpenMoHAA: cleared stale service workers/caches" not in src:
    src = src.replace(cleanup_marker, cleanup_snippet, 1)
    print("Injected stale service-worker cleanup snippet")
elif "OpenMoHAA: cleared stale service workers/caches" in src:
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

cd "$OPENMOHAA_DIR"

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
    if [[ -d "$GAME_FILES_DIR" ]]; then
        mkdir -p "$EXPORT_DIR/main"
        rsync -a --delete "$GAME_FILES_DIR/" "$EXPORT_DIR/main/"
        echo "Copied game files: $GAME_FILES_DIR -> $EXPORT_DIR/main"
    else
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
fi

echo "Web build complete (target=$BUILD_TARGET)."
echo "Export output: $EXPORT_HTML"

