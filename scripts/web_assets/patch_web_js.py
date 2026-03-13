#!/usr/bin/env python3
"""Patch the Emscripten-generated mohaa.js with runtime fixes.

Emscripten's generated code assumes a simple C runtime.  OpenMoHAA is a full
ioquake3-derived C++ game engine that needs: C++ exceptions, setjmp/longjmp,
dynamic module loading (cgame.so), VFS preloading, and WebSocket networking.
This script applies the necessary patches to make it all work.

All non-trivial replacement JS lives in static .js files under <js_dir>,
keeping this script short and the JS readable/editable.

Patches applied (in order):
  1. WASM memory pre-grow before loadDylibs
  2. Module preRun injection (module_prerun.js)
  3. Unresolved symbol diagnostics
  4. Runtime import stub resolver (stubs_resolver.js)
  5. resolveGlobalSymbol fallback chain (resolve_global_symbol.js)
  6. cgame.so pre-registration in dynamicLibraries
  7. loadDylibs try/catch wrapper
  8. locateFile gdextension lookup fix
  9. C++ exception ABI stubs (inline — simple find/replace pairs)
 10. WebSocket relay bridge (ws_relay_bridge.js)

Usage:
    python3 patch_web_js.py <mohaa.js> <js_dir>

Where <js_dir> contains the static .js files listed above.
"""
import re
import sys
from pathlib import Path


def read(path: Path) -> str:
    return path.read_text(encoding="utf-8", errors="ignore")


def minify_js(src: str) -> str:
    """Strip JS block/line comments and collapse whitespace for injection."""
    # Remove block comments (non-greedy)
    src = re.sub(r"/\*.*?\*/", "", src, flags=re.DOTALL)
    # Remove line comments (not inside strings — basic heuristic)
    src = re.sub(r"(?<!['\"`])//[^\n]*", "", src)
    # Collapse whitespace runs to single space
    src = re.sub(r"\s+", " ", src).strip()
    return src


# ── 1. Memory pre-grow ─────────────────────────────────────────────────────
def patch_memory_pregrow(src: str) -> str:
    """Grow WASM memory before loadDylibs so the side module can instantiate."""
    old = "LDSO.init();loadDylibs();"
    new = (
        "LDSO.init();"
        "var __wm_pages=(wasmMemory.buffer.byteLength>>>16);"
        "if(__wm_pages<2048){"
        "try{wasmMemory.grow(2048-__wm_pages);updateMemoryViews()}"
        "catch(e){console.warn('OpenMoHAA: memory pre-grow failed',e)}}"
        "loadDylibs();"
    )
    if old in src:
        src = src.replace(old, new, 1)
        print("  [1/10] memory pre-grow before loadDylibs")
    elif "__wm_pages" in src:
        print("  [1/10] skip: memory pre-grow already applied")
    else:
        print("  [1/10] WARNING: memory pre-grow marker not found")
    return src


# ── 2. Module preRun injection ─────────────────────────────────────────────
def patch_module_prerun(src: str, prerun_path: Path) -> str:
    """Inject VFS preloader, __hash_memory polyfill, and stdout capture."""
    prerun_js = read(prerun_path)

    preload_re = re.compile(r"var Module=moduleArg;[\s\S]*?var ENVIRONMENT_IS_WEB=")
    m = preload_re.search(src)
    if m:
        replacement = "var Module=moduleArg;\n" + prerun_js + "\nvar ENVIRONMENT_IS_WEB="
        src = src[:m.start()] + replacement + src[m.end():]
        print("  [2/10] module preRun injection")
        return src

    if "openmohaa-pk3-preload" in src or "openmohaa-vfs-preload" in src:
        pat = re.compile(
            r"Module\['preRun'\]=Module\['preRun'\]\|\|\[\];.*?"
            r"var ENVIRONMENT_IS_WEB=",
            re.DOTALL,
        )
        m2 = pat.search(src)
        if m2:
            replacement = prerun_js + "\nvar ENVIRONMENT_IS_WEB="
            src = src[:m2.start()] + replacement + src[m2.end():]
            print("  [2/10] module preRun injection (replaced old)")
            return src
        print("  [2/10] WARNING: preloader present but boundary not found")
    else:
        print("  [2/10] WARNING: module preRun marker not found")
    return src


# ── 3. Unresolved symbol diagnostics ──────────────────────────────────────
def patch_symbol_diagnostics(src: str) -> str:
    old = (
        "var reportUndefinedSymbols=()=>{for(var[symName,entry]of Object.entries(GOT)){"
        "if(entry.value==-1){var value=resolveGlobalSymbol(symName,true).sym;"
    )
    new = (
        "var reportUndefinedSymbols=()=>{for(var[symName,entry]of Object.entries(GOT)){"
        "if(entry.value==-1){var value=resolveGlobalSymbol(symName,true).sym;"
        "if(!value&&entry.required){console.error('OpenMoHAA unresolved symbol',symName,'required',!!entry.required)}"
    )
    if old in src:
        src = src.replace(old, new, 1)
        print("  [3/10] unresolved symbol diagnostics")
    else:
        print("  [3/10] WARNING: symbol diagnostics marker not found")

    call_old = "if(!flags.allowUndefined){reportUndefinedSymbols()}"
    call_new = (
        "if(!flags.allowUndefined){"
        "try{reportUndefinedSymbols()}"
        "catch(e){console.error('OpenMoHAA reportUndefinedSymbols exception',e,e&&e.message,e&&e.stack);throw e}"
        "}"
    )
    if call_old in src:
        src = src.replace(call_old, call_new, 1)
    return src


# ── 4. Runtime import stub resolver (from stubs_resolver.js) ─────────────
def patch_runtime_stubs(src: str, stubs_path: Path) -> str:
    """Replace Emscripten's one-liner stub resolver with stubs_resolver.js."""
    old = "stubs[prop]=(...args)=>{resolved||=resolveSymbol(prop);return resolved(...args)}"
    if old in src:
        src = src.replace(old, minify_js(read(stubs_path)), 1)
        print("  [4/10] runtime import stub resolver")
    else:
        print("  [4/10] WARNING: stub resolver marker not found")
    return src


# ── 5. resolveGlobalSymbol (from resolve_global_symbol.js) ───────────────
def patch_resolve_global_symbol(src: str, rgs_path: Path) -> str:
    """Replace Emscripten's resolveGlobalSymbol with resolve_global_symbol.js."""
    old = (
        "var resolveGlobalSymbol=(symName,direct=false)=>"
        "{var sym;if(isSymbolDefined(symName)){sym=wasmImports[symName]}"
        "return{sym,name:symName}};"
    )
    if old in src:
        src = src.replace(old, minify_js(read(rgs_path)), 1)
        print("  [5/10] resolveGlobalSymbol fallback chain")
    else:
        print("  [5/10] WARNING: resolveGlobalSymbol marker not found")
    return src


# ── 6. cgame.so pre-registration ─────────────────────────────────────────
def patch_cgame_registration(src: str) -> str:
    """Pre-register cgame.so in dynamicLibraries for synchronous dlopen."""
    variants = [
        (
            "'dynamicLibraries': [`${loadPath}.side.wasm`].concat(this.gdextensionLibs),",
            "'dynamicLibraries': [`${loadPath}.side.wasm`].concat(this.gdextensionLibs).concat(['main/cgame.so']),",
        ),
        (
            "'dynamicLibraries': [`${loadPath}.side.wasm`].concat(this.extensionLibs),",
            "'dynamicLibraries': [`${loadPath}.side.wasm`].concat(this.extensionLibs).concat(['main/cgame.so']),",
        ),
    ]
    for _, new in variants:
        if new in src:
            print("  [6/10] skip: cgame.so already registered")
            return src
    for old, new in variants:
        if old in src:
            src = src.replace(old, new, 1)
            print("  [6/10] cgame.so in dynamicLibraries")
            return src
    print("  [6/10] WARNING: dynamicLibraries marker not found")
    return src


# ── 7. loadDylibs try/catch wrapper ──────────────────────────────────────
def patch_loaddylibs(src: str) -> str:
    """Wrap loadDylibs with per-library try/catch and verbose logging."""
    old = (
        "var loadDylibs=async()=>"
        "{if(!dynamicLibraries.length){reportUndefinedSymbols();return}"
        'addRunDependency("loadDylibs");'
        "for(var lib of dynamicLibraries)"
        "{await loadDynamicLibrary(lib,{loadAsync:true,global:true,nodelete:true,allowUndefined:true})}"
        'reportUndefinedSymbols();removeRunDependency("loadDylibs")}'
    )
    new = (
        "var __openmohaaLoadDylibsPromise=null;"
        "var loadDylibs=async()=>{"
        "if(__openmohaaLoadDylibsPromise){return __openmohaaLoadDylibsPromise}"
        "__openmohaaLoadDylibsPromise=(async()=>{"
        "if(!dynamicLibraries.length){reportUndefinedSymbols();return}"
        'addRunDependency("loadDylibs");'
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
        'reportUndefinedSymbols();removeRunDependency("loadDylibs")'
        "})();"
        "return __openmohaaLoadDylibsPromise}"
    )
    if old in src:
        src = src.replace(old, new, 1)
        print("  [7/10] loadDylibs per-lib try/catch")
    else:
        print("  [7/10] WARNING: loadDylibs marker not found")
    return src


# ── 8. locateFile gdextension lookup fix ──────────────────────────────────
def patch_locatefile(src: str) -> str:
    """Fix 'in' operator (checks indices) to 'includes' (checks values)."""
    old = "} else if (path in gdext) {"
    new = "} else if (gdext.includes(path)) {"
    if old in src:
        src = src.replace(old, new, 1)
        print("  [8/10] locateFile gdextension lookup")
    else:
        print("  [8/10] WARNING: locateFile marker not found")
    return src


# ── 9. C++ exception ABI stubs ────────────────────────────────────────────
def patch_cxa_stubs(src: str) -> str:
    """Replace Emscripten's abort()-based C++ exception stubs with working ones."""
    patches = [
        (
            'function ___cxa_throw(){abort()}___cxa_throw.sig="vppp";',
            'var _cxaLast=0;'
            'function ___cxa_throw(ptr,type,dtor){'
            '_cxaLast=ptr;'
            'var e=new Error("CxxException");e.name="CxxException";e.__cxa_ptr=ptr;'
            'throw e'
            '}___cxa_throw.sig="vppp";',
        ),
        (
            'function ___cxa_rethrow(){abort()}___cxa_rethrow.sig="v";',
            'function ___cxa_rethrow(){'
            'if(_cxaLast){'
            'var e=new Error("CxxException");e.name="CxxException";e.__cxa_ptr=_cxaLast;throw e}'
            '}___cxa_rethrow.sig="v";',
        ),
        (
            'function _llvm_eh_typeid_for(){abort()}_llvm_eh_typeid_for.sig="vp";',
            'function _llvm_eh_typeid_for(type){return type}_llvm_eh_typeid_for.sig="vp";',
        ),
        (
            'function ___cxa_begin_catch(){abort()}___cxa_begin_catch.sig="pp";',
            'function ___cxa_begin_catch(ptr){return ptr}___cxa_begin_catch.sig="pp";',
        ),
        (
            'function ___cxa_end_catch(){abort()}___cxa_end_catch.sig="v";',
            'function ___cxa_end_catch(){_cxaLast=0}___cxa_end_catch.sig="v";',
        ),
        (
            'function ___cxa_call_unexpected(){abort()}___cxa_call_unexpected.sig="vp";',
            'function ___cxa_call_unexpected(ptr){'
            'console.warn("cxa_call_unexpected",ptr)}___cxa_call_unexpected.sig="vp";',
        ),
        (
            'function ___cxa_find_matching_catch(){abort()}',
            'function ___cxa_find_matching_catch(){'
            'if(typeof setTempRet0!=="undefined")setTempRet0(0);'
            'return _cxaLast}',
        ),
        (
            'function ___resumeException(){abort()}___resumeException.sig="vp";',
            'function ___resumeException(ptr){'
            'if(ptr)_cxaLast=ptr;'
            'var e=new Error("CxxException");e.name="CxxException";e.__cxa_ptr=_cxaLast;'
            'throw e'
            '}___resumeException.sig="vp";',
        ),
    ]
    count = sum(1 for old, _ in patches if old in src)
    for old, new in patches:
        if old in src:
            src = src.replace(old, new, 1)
    print(f"  [9/10] C++ exception ABI stubs ({count}/{len(patches)})")
    return src


# ── 10. WebSocket relay bridge ────────────────────────────────────────────
def patch_ws_relay(src: str, bridge_path: Path) -> str:
    """Inject the WebSocket relay bridge early in mohaa.js."""
    bridge_js = read(bridge_path)
    marker = "var ENVIRONMENT_IS_WEB="
    if "OpenMoHAA WebSocket Relay Bridge" in src:
        print("  [10/10] skip: WS relay bridge already present")
    elif marker in src:
        src = src.replace(marker, bridge_js + "\n" + marker, 1)
        print("  [10/10] WebSocket relay bridge")
    else:
        print("  [10/10] WARNING: WS relay marker not found")
    return src


# ── Entry point ───────────────────────────────────────────────────────────
def main() -> int:
    if len(sys.argv) < 3:
        print("Usage: patch_web_js.py <mohaa.js> <js_dir>", file=sys.stderr)
        return 2

    js_path = Path(sys.argv[1])
    js_dir = Path(sys.argv[2])

    if not js_path.is_file():
        print(f"WARNING: mohaa.js not found: {js_path}")
        return 0

    print(f"Patching {js_path.name}...")
    src = read(js_path)

    src = patch_memory_pregrow(src)
    src = patch_module_prerun(src, js_dir / "module_prerun.js")
    src = patch_symbol_diagnostics(src)
    src = patch_runtime_stubs(src, js_dir / "stubs_resolver.js")
    src = patch_resolve_global_symbol(src, js_dir / "resolve_global_symbol.js")
    src = patch_cgame_registration(src)
    src = patch_loaddylibs(src)
    src = patch_locatefile(src)
    src = patch_cxa_stubs(src)
    src = patch_ws_relay(src, js_dir / "ws_relay_bridge.js")

    js_path.write_text(src, encoding="utf-8")
    print(f"All JS patches applied to {js_path}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
