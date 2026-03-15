/* ═══════ OpenMoHAA resolveGlobalSymbol Replacement ═══════
 * Replaces Emscripten's default:
 *   var resolveGlobalSymbol=(symName,direct=false)=>{
 *       var sym;if(isSymbolDefined(symName)){sym=wasmImports[symName]}
 *       return{sym,name:symName}};
 *
 * Extended with: underscore-variant search, Module/globalThis fallbacks,
 * emscripten_longjmp polyfill, and invoke_* wrapper synthesis.
 *
 * Injected by patch_web_js.py — runs inside Emscripten's module scope
 * with access to isSymbolDefined, wasmImports, wasmTable, Module, etc.
 * ═══════════════════════════════════════════════════════════════════ */
var resolveGlobalSymbol = (symName, direct = false) => {
    var sym;
    if (isSymbolDefined(symName)) { sym = wasmImports[symName]; }

    /* ── Underscore variants + Module/globalThis search ── */
    if (!sym && typeof symName === 'string') {
        var base = String(symName || '');
        var trimmed = base.replace(/^_+/, '');
        var candidates = [base, '_' + base, trimmed, '_' + trimmed];
        for (var i = 0; i < candidates.length && !sym; i++) {
            var name = candidates[i];
            if (!name) continue;
            if (isSymbolDefined(name)) sym = wasmImports[name];
            if (!sym && typeof Module !== 'undefined' && Module) sym = Module[name] || sym;
            if (!sym && typeof globalThis !== 'undefined') sym = globalThis[name] || sym;
        }
    }

    /* ── LDSO loaded-library GOT.data search ──
     * Belt-and-suspenders: if the GOT repair sweep in loadDylibs didn't fire
     * (e.g. this function is called during module loading before all libs are
     * ready), search every already-loaded LDSO library for a 'got.<sym>'
     * export.  This handles data globals imported by cgame.wasm (SIDE_MODULE=2)
     * that are defined in openmohaa.wasm (SIDE_MODULE=1), e.g. numDebugLines.
     * Each 'got.<sym>' export is a WebAssembly.Global (mutable i32) whose
     * .value is the in-memory address of the variable. */
    if (!sym && typeof LDSO !== 'undefined' && LDSO) {
        var _ldsoLibs = Object.values(LDSO.loadedLibsByName || {});
        for (var _ldi = 0; _ldi < _ldsoLibs.length && !sym; _ldi++) {
            var _ldlib = _ldsoLibs[_ldi];
            if (!_ldlib || !_ldlib.exports || typeof _ldlib.exports !== 'object') continue;
            /* Primary: 'got.<symName>' — Emscripten's PIC data-global export */
            var _gotKey = 'got.' + symName;
            if (_gotKey in _ldlib.exports) {
                var _gotGlobal = _ldlib.exports[_gotKey];
                var _gotAddr = (typeof _gotGlobal === 'object' && _gotGlobal !== null && 'value' in _gotGlobal)
                    ? _gotGlobal.value : _gotGlobal;
                if (typeof _gotAddr === 'number' && _gotAddr !== -1) {
                    sym = _gotAddr;
                    /* Repair the GOT entry if still -1 so cgame gets the correct address */
                    if (typeof GOT !== 'undefined' && GOT && (symName in GOT) && GOT[symName].value === -1) {
                        GOT[symName].value = _gotAddr;
                    }
                }
            }
            /* Fallback: 'got.mem.<symName>' (some linker versions use this prefix) */
            if (!sym) {
                var _gotMemKey = 'got.mem.' + symName;
                if (_gotMemKey in _ldlib.exports) {
                    var _gotMemGlobal = _ldlib.exports[_gotMemKey];
                    var _gotMemAddr = (typeof _gotMemGlobal === 'object' && _gotMemGlobal !== null && 'value' in _gotMemGlobal)
                        ? _gotMemGlobal.value : _gotMemGlobal;
                    if (typeof _gotMemAddr === 'number' && _gotMemAddr !== -1) {
                        sym = _gotMemAddr;
                        if (typeof GOT !== 'undefined' && GOT && (symName in GOT) && GOT[symName].value === -1) {
                            GOT[symName].value = _gotMemAddr;
                        }
                    }
                }
            }
        }
    }

    /* ── emscripten_longjmp polyfill ── */
    if (!sym && symName === 'emscripten_longjmp') {
        var throwLJ = (typeof emscripten_throw_longjmp === 'function' && emscripten_throw_longjmp)
            || (typeof _emscripten_throw_longjmp === 'function' && _emscripten_throw_longjmp)
            || (typeof Module !== 'undefined' && Module && (Module.emscripten_throw_longjmp || Module._emscripten_throw_longjmp))
            || (typeof globalThis !== 'undefined' && (globalThis.emscripten_throw_longjmp || globalThis._emscripten_throw_longjmp));
        var cLJ = (typeof ___c_longjmp !== 'undefined' && ___c_longjmp)
            || (typeof __c_longjmp !== 'undefined' && __c_longjmp)
            || (typeof Module !== 'undefined' && Module && (Module.___c_longjmp || Module.__c_longjmp))
            || (typeof globalThis !== 'undefined' && (globalThis.___c_longjmp || globalThis.__c_longjmp));
        var wasmLJ = (typeof ___wasm_longjmp !== 'undefined' && ___wasm_longjmp)
            || (typeof __wasm_longjmp !== 'undefined' && __wasm_longjmp)
            || (typeof Module !== 'undefined' && Module && (Module.___wasm_longjmp || Module.__wasm_longjmp))
            || (typeof globalThis !== 'undefined' && (globalThis.___wasm_longjmp || globalThis.__wasm_longjmp));
        if (typeof cLJ === 'number' && typeof wasmTable !== 'undefined') {
            var fn = wasmTable.get(cLJ | 0); if (fn) cLJ = fn;
        }
        if (typeof wasmLJ === 'number' && typeof wasmTable !== 'undefined') {
            var fn2 = wasmTable.get(wasmLJ | 0); if (fn2) wasmLJ = fn2;
        }
        if (typeof throwLJ === 'function') sym = (env, val) => throwLJ(env | 0, val | 0);
        else if (typeof cLJ === 'function') sym = (env, val) => cLJ(env | 0, val | 0);
        else if (typeof wasmLJ === 'function') sym = (env, val) => wasmLJ(env | 0, val | 0);
        if (sym) wasmImports[symName] = sym;
    }

    /* ── invoke_* wrapper synthesis ── */
    if (!sym && typeof symName === 'string' && symName.startsWith('invoke_')) {
        sym = (...invokeArgs) => {
            var fnIndex = invokeArgs[0] | 0;
            var fn = wasmTable.get(fnIndex);
            try { return fn(...invokeArgs.slice(1)); }
            catch (e) {
                if (e && e.name === 'ExitStatus') throw e;
                if (typeof _setThrew === 'function') _setThrew(1, 0);
                else if (typeof setThrew === 'function') setThrew(1, 0);
                return 0;
            }
        };
        sym.sig = symName.slice('invoke_'.length);
        wasmImports[symName] = sym;
    }

    return { sym, name: symName };
};
