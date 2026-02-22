#!/usr/bin/env python3
"""
Patch the deployed exports/web/mohaa.js with runtime fixes for openmohaa.
Safe to run multiple times (idempotent checks before each patch).
"""
from pathlib import Path

JS = Path('/run/media/elgan/bdb8dbed-86d7-41d2-90f3-09a45ed5ad9c1/dev/opm-godot/exports/web/mohaa.js')
src = JS.read_text(encoding='utf-8')
orig_len = len(src)

def patch(description, old, new):
    global src
    if old in src:
        src = src.replace(old, new, 1)
        print(f'[ OK ] {description}')
        return True
    elif new in src:
        print(f'[SKIP] {description} (already applied)')
        return False
    else:
        print(f'[WARN] {description} - marker not found')
        return False

# ---------------------------------------------------------------------------
# 1.  Full C++ exception runtime injection
#
#     Godot's web template is built without C++ exceptions, so it exports
#     abort() stubs for ___cxa_throw / ___resumeException.  Our openmohaa
#     WASM is built with -fexceptions -sDISABLE_EXCEPTION_CATCHING=0 and
#     imports these symbols.  resolveSymbol() finds Godot's abort versions
#     first.  We must set our overrides BEFORE resolveSymbol runs.
# ---------------------------------------------------------------------------

CXA_RUNTIME = (
    "if(prop==='___cxa_throw'){"
    "resolved=(ptr,type,destructor)=>{"
    "var e=new Error('CxxException');e.name='CxxException';e.__cxa_ptr=ptr;"
    "stubs.__cxaLast=ptr;stubs.__cxaType=type;"
    "throw e};"
    "}"
    "if(prop==='___resumeException'){"
    "resolved=(ptr)=>{"
    "stubs.__cxaLast=ptr||stubs.__cxaLast||0;"
    "var e=new Error('CxxException');e.name='CxxException';e.__cxa_ptr=stubs.__cxaLast;"
    "throw e};"
    "}"
    "if(prop==='__cxa_begin_catch'){"
    "resolved=(ptr)=>{stubs.__cxaLast=0;return ptr};"
    "}"
    "if(prop==='__cxa_end_catch'||prop==='__cxa_free_exception'){"
    "resolved=()=>{stubs.__cxaLast=0};"
    "}"
    "if(prop==='__cxa_rethrow'){"
    "resolved=()=>{"
    "var e=new Error('CxxException');e.name='CxxException';e.__cxa_ptr=stubs.__cxaLast||0;"
    "throw e};"
    "}"
    "if(/^__cxa_find_matching_catch_\\d+$/.test(prop)){"
    "resolved=()=>{"
    "var ptr=stubs.__cxaLast||0;"
    "if(typeof setTempRet0!=='undefined'){setTempRet0(0)}"
    "else if(typeof _setTempRet0!=='undefined'){_setTempRet0(0)}"
    "return ptr};"
    "}"
)

OLD_LAZY = "resolved||=resolveSymbol(prop);if(!resolved&&/^__cxa_find_matching_catch_\\d+$/.test(prop)){resolved=()=>0}"
NEW_LAZY  = CXA_RUNTIME + "resolved||=resolveSymbol(prop);"

patch("C++ exception runtime (cxa_throw/resumeException/find_matching_catch)", OLD_LAZY, NEW_LAZY)

# ---------------------------------------------------------------------------
# 2.  invoke_* handler: reset abort flag on CxxException so the frame
#     continues without aborting the whole Emscripten runtime.
# ---------------------------------------------------------------------------
OLD_INVOKE = (
    "if(e&&e.name==='ExitStatus'){throw e}"
    "if(typeof _setThrew==='function'){_setThrew(1,0)}else if(typeof setThrew==='function'){setThrew(1,0)}"
    "return 0"
)
NEW_INVOKE = (
    "if(e&&e.name==='ExitStatus'){throw e}"
    "if(e&&e.name==='RuntimeError'&&typeof ABORT!=='undefined'&&ABORT){ABORT=false}"
    "if(typeof _setThrew==='function'){_setThrew(1,0)}else if(typeof setThrew==='function'){setThrew(1,0)}"
    "return 0"
)
patch("invoke_* RuntimeError abort suppression", OLD_INVOKE, NEW_INVOKE)

# ---------------------------------------------------------------------------
# 3.  Legacy __cxa_find_matching_catch_2 guard (belt-and-suspenders if the
#     regex patch in step 1 was already applied but the old form was not)
# ---------------------------------------------------------------------------
patch(
    "__cxa_find_matching_catch_N stub legacy guard",
    "if(!resolved&&prop==='__cxa_find_matching_catch_2'){resolved=()=>0}",
    "if(!resolved&&/^__cxa_find_matching_catch_\\d+$/.test(prop)){resolved=()=>0}"
)

# ---------------------------------------------------------------------------
# Save
# ---------------------------------------------------------------------------
if len(src) != orig_len:
    JS.write_text(src, encoding='utf-8')
    print(f'Saved: {JS} ({orig_len} -> {len(src)} bytes)')
else:
    print('No net changes - file unchanged.')
