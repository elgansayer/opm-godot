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
