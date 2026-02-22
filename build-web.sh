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
            esac
            printf '%s\n' "$rel" >> "$manifest_path"
        done < <(find "$main_dir" \( -name ".*" -prune \) -o -type f -print0 | sort -z)
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
    ('godotengine.org',              'openmohaa.net'),
]

def apply_renames(txt):
    for old, new in renames:
        txt = txt.replace(old, new)
    # Only rename user-visible "Godot" text, NOT snake_case function names
    # which are WASM import symbols that must match the compiled binary.
    txt = re.sub(r'\bGodot Engine\b', 'OpenMoHAA Engine', txt)
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

# ── 3. Silence console output in mohaa.js ──
def silence_console(txt):
    if txt is None:
        return None
    # Redirect console.log/warn/info to no-ops at the very start.
    # Keep console.error for real errors.
    silencer = (
        '(function(){var _n=function(){}; '
        'console.log=_n; console.info=_n; console.warn=_n; '
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
    txt = txt.replace('OpenMoHAA Test', 'OpenMoHAA')
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
    m = m.replace('OpenMoHAA Test', 'OpenMoHAA')
    write(manifest_file, m)
    counts['manifest'] = True

print(f"Obfuscated Godot fingerprints in {len(counts)} files: {', '.join(counts.keys())}")
PYOBF
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
        rsync -a --delete --exclude='.*' "$GAME_FILES_DIR/" "$EXPORT_DIR/main/"
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
    patch_web_ws_relay
    obfuscate_godot_fingerprints
fi

echo "Web build complete (target=$BUILD_TARGET)."
echo "Export output: $EXPORT_HTML"

