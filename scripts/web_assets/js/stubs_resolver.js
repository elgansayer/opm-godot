/* ═══════ OpenMoHAA Runtime Import Stub Resolver ═══════
 * Replaces Emscripten's default one-liner:
 *   stubs[prop]=(...args)=>{resolved||=resolveSymbol(prop);return resolved(...args)}
 *
 * This extended version handles: C++ exception ABI, emscripten_longjmp,
 * invoke_* wrappers, and multi-source symbol resolution fallbacks.
 *
 * Injected by patch_web_js.py — runs inside Emscripten's module scope
 * with access to resolveSymbol, wasmTable, Module, etc.
 * ═══════════════════════════════════════════════════════ */
stubs[prop] = (...args) => {
    /* ── C++ exception ABI intercepts ── */
    if (prop === '___cxa_throw') {
        resolved = (ptr, type, destructor) => {
            var e = new Error('CxxException');
            e.name = 'CxxException';
            e.__cxa_ptr = ptr;
            stubs.__cxaLast = ptr;
            stubs.__cxaType = type;
            throw e;
        };
    }
    if (prop === '___resumeException') {
        resolved = (ptr) => {
            stubs.__cxaLast = ptr || stubs.__cxaLast || 0;
            var e = new Error('CxxException');
            e.name = 'CxxException';
            e.__cxa_ptr = stubs.__cxaLast;
            throw e;
        };
    }
    if (prop === '__cxa_begin_catch') {
        resolved = (ptr) => { stubs.__cxaLast = 0; return ptr; };
    }
    if (prop === '__cxa_end_catch' || prop === '__cxa_free_exception') {
        resolved = () => { stubs.__cxaLast = 0; };
    }
    if (prop === '__cxa_rethrow') {
        resolved = () => {
            var e = new Error('CxxException');
            e.name = 'CxxException';
            e.__cxa_ptr = stubs.__cxaLast || 0;
            throw e;
        };
    }
    if (/^__cxa_find_matching_catch_\d+$/.test(prop)) {
        resolved = () => {
            var ptr = (typeof _cxaLast !== 'undefined' ? _cxaLast : 0) || stubs.__cxaLast || 0;
            if (typeof setTempRet0 !== 'undefined') { setTempRet0(0); }
            else if (typeof _setTempRet0 !== 'undefined') { _setTempRet0(0); }
            return ptr;
        };
    }

    /* ── Standard resolution with fallbacks ── */
    resolved ||= resolveSymbol(prop);
    if (!resolved && /^__cxa_find_matching_catch_\d+$/.test(prop)) {
        resolved = () => 0;
    }
    if (!resolved) {
        var base = String(prop || '');
        var trimmed = base.replace(/^_+/, '');
        var candidates = [base, '_' + base, trimmed, '_' + trimmed];
        for (var i = 0; i < candidates.length && !resolved; i++) {
            var name = candidates[i];
            if (!name) continue;
            if (typeof resolveSymbol === 'function') resolved = resolveSymbol(name) || resolved;
            if (!resolved && typeof Module !== 'undefined' && Module) resolved = Module[name] || resolved;
            if (!resolved && typeof globalThis !== 'undefined') resolved = globalThis[name] || resolved;
        }
    }

    /* ── emscripten_longjmp resolution chain ── */
    if (!resolved && prop === 'emscripten_longjmp') {
        var throwLJ = resolveSymbol('emscripten_throw_longjmp');
        var cLJ = (typeof ___c_longjmp !== 'undefined' && ___c_longjmp)
            || (typeof __c_longjmp !== 'undefined' && __c_longjmp)
            || resolveSymbol('__c_longjmp') || resolveSymbol('___c_longjmp')
            || (typeof globalThis !== 'undefined' && (globalThis.___c_longjmp || globalThis.__c_longjmp));
        var wasmLJ = (typeof ___wasm_longjmp !== 'undefined' && ___wasm_longjmp)
            || (typeof __wasm_longjmp !== 'undefined' && __wasm_longjmp)
            || resolveSymbol('__wasm_longjmp') || resolveSymbol('___wasm_longjmp');
        if (typeof cLJ === 'number' && typeof wasmTable !== 'undefined') {
            var fn = wasmTable.get(cLJ | 0); if (fn) cLJ = fn;
        }
        if (typeof wasmLJ === 'number' && typeof wasmTable !== 'undefined') {
            var fn2 = wasmTable.get(wasmLJ | 0); if (fn2) wasmLJ = fn2;
        }
        if (typeof throwLJ === 'function') resolved = (env, val) => throwLJ(env | 0, val | 0);
        else if (typeof cLJ === 'function') resolved = (env, val) => cLJ(env | 0, val | 0);
        else if (typeof wasmLJ === 'function') resolved = (env, val) => wasmLJ(env | 0, val | 0);
        else resolved = () => { throw new Error('OpenMoHAA: no usable longjmp helper'); };
    }

    /* ── invoke_* wrappers ── */
    if (!resolved && prop.startsWith('invoke_')) {
        resolved = (...invokeArgs) => {
            var fnIndex = invokeArgs[0] | 0;
            var fn = wasmTable.get(fnIndex);
            try { return fn(...invokeArgs.slice(1)); }
            catch (e) {
                if (e && e.name === 'ExitStatus') throw e;
                if (e && e.name === 'CxxException' && e.__cxa_ptr) stubs.__cxaLast = e.__cxa_ptr;
                else if (e && e.name === 'RuntimeError' && typeof ABORT !== 'undefined' && ABORT) ABORT = false;
                if (typeof _setThrew === 'function') _setThrew(1, 0);
                else if (typeof setThrew === 'function') setThrew(1, 0);
                return 0;
            }
        };
    }

    /* ── Table index → function resolution ── */
    if (typeof resolved === 'number') {
        var fn3 = wasmTable.get(resolved | 0); if (fn3) resolved = fn3;
    }
    if (resolved && typeof resolved === 'object' && typeof resolved.value === 'number') {
        var fn4 = wasmTable.get(resolved.value | 0); if (fn4) resolved = fn4;
    }

    /* ── Final dispatch with error handling ── */
    if (!resolved) {
        console.error('OpenMoHAA unresolved runtime import', prop, args);
        throw new Error('OpenMoHAA unresolved runtime import: ' + prop);
    }
    if (typeof resolved !== 'function') {
        console.error('OpenMoHAA non-callable runtime import', prop, typeof resolved, resolved, args);
        throw new Error('OpenMoHAA non-callable runtime import: ' + prop);
    }
    try { return resolved(...args); }
    catch (e) {
        if (prop === 'emscripten_longjmp') throw e;
        console.error('OpenMoHAA runtime import threw', prop, e, e && e.message, e && e.stack, args);
        throw e;
    }
}
