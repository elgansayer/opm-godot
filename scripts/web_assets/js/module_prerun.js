/* ═══════ OpenMoHAA Module preRun Injection ═══════ */
/* Injected into mohaa.js by patch_web_js.py between:
 *   Module=moduleArg  ...  ENVIRONMENT_IS_WEB
 *
 * Runs inside Emscripten's module scope with access to Module, FS,
 * addRunDependency, removeRunDependency, wasmMemory, etc.
 *
 * Provides:
 *  1. libc++ __hash_memory polyfill (murmur2, cross-emsdk compat)
 *  2. Stdout/stderr capture for test diagnostics
 *  3. VFS preloader: IndexedDB cache → local file picker → server gap-fill
 */

/* ── 1. libc++ __hash_memory polyfill (murmur2 32-bit) ──
 * Godot 4.6 export templates use emsdk 4.0.20; our SIDE_MODULEs may be
 * built with a newer emsdk whose libc++ externalises __hash_memory.
 * The main module doesn't export it, so the stubs resolver would throw.
 * wasmMemory is captured by reference — initialised by call time. */
globalThis._ZNSt3__213__hash_memoryEPKvm = function(ptr, len) {
    var h = len >>> 0, m = 0x5bd1e995, r = 24;
    var u8 = new Uint8Array(wasmMemory.buffer);
    var i = 0;
    while (i + 4 <= len) {
        var k = (u8[ptr+i] | (u8[ptr+i+1]<<8) | (u8[ptr+i+2]<<16) | (u8[ptr+i+3]<<24)) >>> 0;
        k = Math.imul(k, m) >>> 0;
        k = (k ^ (k >>> r)) >>> 0;
        k = Math.imul(k, m) >>> 0;
        h = Math.imul(h, m) >>> 0;
        h = (h ^ k) >>> 0;
        i += 4;
    }
    var rem = len - i;
    if (rem >= 3) h = (h ^ (u8[ptr+i+2] << 16)) >>> 0;
    if (rem >= 2) h = (h ^ (u8[ptr+i+1] << 8)) >>> 0;
    if (rem >= 1) { h = (h ^ u8[ptr+i]) >>> 0; h = Math.imul(h, m) >>> 0; }
    h = (h ^ (h >>> 13)) >>> 0;
    h = Math.imul(h, m) >>> 0;
    h = (h ^ (h >>> 15)) >>> 0;
    return h;
};

/* ── 2. Stdout/stderr capture for test diagnostics ── */
if (typeof window !== 'undefined') {
    window.__mohaaStdout = window.__mohaaStdout || [];
    window.__mohaaMapLoadedLog = '';
}
(function() {
    var __wrap = function(name) {
        var prev = Module[name];
        Module[name] = function() {
            var msg = Array.prototype.slice.call(arguments).join(' ');
            if (typeof window !== 'undefined') {
                window.__mohaaStdout.push(msg);
                if (msg.indexOf('Main: SIGNAL map_loaded ->') !== -1)
                    window.__mohaaMapLoadedLog = msg;
            }
            if (typeof prev === 'function') return prev.apply(this, arguments);
            if (name === 'printErr') { console.error(msg); } else { console.log(msg); }
        };
    };
    __wrap('print');
    __wrap('printErr');
})();

/* ── 3. VFS preloader ──
 * Loads game files from IndexedDB cache and local file picker into MEMFS,
 * then gap-fills from the server (fetches only .pk3/.cfg from /main/). */
Module['preRun'] = Module['preRun'] || [];
Module['preRun'].push(() => {
    if (typeof FS === 'undefined' || typeof fetch === 'undefined' ||
        typeof addRunDependency !== 'function' || typeof removeRunDependency !== 'function') {
        return;
    }

    var __dep = 'openmohaa-vfs-preload';
    addRunDependency(__dep);

    (async () => {
        var cfg = (typeof MOHAA_CONFIG !== 'undefined' ? MOHAA_CONFIG : {}),
            cdn = cfg['CDN_URL'] || '/assets';
        if (cdn && !cdn.endsWith('/')) cdn += '/';

        var cache = null;
        try { cache = await caches.open('mohaajs-assets-v1'); }
        catch (e) { console.warn('MOHAAjs: Cache API unavailable', e); }

        /* Helper: ensure MEMFS directory tree exists */
        var __mkdirs = (path) => {
            var p = '', ps = path.split('/').filter(Boolean);
            for (var i = 0; i < ps.length; i++) {
                p += '/' + ps[i];
                try { FS.mkdir(p); } catch (e) {}
            }
        };

        /* Helper: write file + create lowercase pak alias when casing differs */
        var __writeFileWithPakAlias = (dst, data) => {
            FS.writeFile(dst, data, { canRead: true, canWrite: false });
            var m = dst.match(/^(.*\/)([^\/]+)$/);
            if (!m) return;
            var dir = m[1], base = m[2];
            if (!/^pak\d+\.pk3$/i.test(base)) return;
            var lowerBase = base.toLowerCase();
            if (lowerBase === base) return;
            var alias = dir + lowerBase;
            try {
                if (!FS.analyzePath(alias).exists)
                    FS.writeFile(alias, data, { canRead: true, canWrite: false });
            } catch (e) {}
        };

        /* Helper: fetch directory listing as JSON array */
        var __listDir = async (relDir) => {
            try {
                var r = await fetch(cdn + relDir, {
                    cache: 'no-cache',
                    headers: { 'Accept': 'application/json' }
                });
                if (!r.ok) return [];
                var j = await r.json();
                if (Array.isArray(j) && j.length && typeof j[0] === 'object') return j;
                return [];
            } catch (e) { return []; }
        };

        /* Helper: fetch a single file with Cache API, return {dst, data} or null */
        var __fetchOne = async (rel) => {
            var src = cdn + rel, dst = '/' + rel;
            try {
                var res = null;
                if (cache) res = await cache.match(src);
                if (!res) {
                    res = await fetch(src);
                    if (!res.ok) return null;
                    if (cache) try { cache.put(src, res.clone()); } catch (e) {}
                }
                return { dst: dst, data: new Uint8Array(await res.arrayBuffer()) };
            } catch (e) { return null; }
        };

        /* Bounded concurrency pool (max 30 parallel fetches) */
        var __sem = 0, __maxSem = 30, __semQ = [];
        var __acquire = () => __sem < __maxSem ?
            (++__sem, Promise.resolve()) :
            new Promise(r => { __semQ.push(r); });
        var __release = () => {
            __sem--;
            if (__semQ.length) { __sem++; (__semQ.shift())(); }
        };

        /* Walk a server directory: fetch only .pk3 and .cfg files */
        var total = 0, loaded = 0, failed = 0;
        var __walk = async (relDir) => {
            var entries = await __listDir(relDir);
            var promises = [];
            for (var i = 0; i < entries.length; i++) {
                var e = entries[i], name = e.name;
                if (name.startsWith('.')) continue;
                if (e.type === 'directory') continue;
                var ln = name.toLowerCase();
                if (!(ln.endsWith('.pk3') || ln.endsWith('.cfg'))) continue;
                var rel = relDir + name;
                total++;
                promises.push((async (r) => {
                    await __acquire();
                    try {
                        if (FS.analyzePath('/' + r).exists) { loaded++; return; }
                        var result = await __fetchOne(r);
                        if (result) {
                            var cut = result.dst.lastIndexOf('/');
                            if (cut > 0) __mkdirs(result.dst.slice(0, cut));
                            __writeFileWithPakAlias(result.dst, result.data);
                            loaded++;
                        } else { failed++; }
                    } catch (e) { failed++; }
                    finally { __release(); }
                    if ((loaded + failed) % 200 === 0 || loaded + failed === total)
                        console.log('MOHAAjs: Progress: ' + (loaded+failed) + '/' + total + ' (' + failed + ' failed)');
                })(rel));
            }
            await Promise.all(promises);
        };

        /* Write local files from picker/IndexedDB cache into MEMFS.
         * Files arrive with full relative paths (main/Pak0.pk3, mainta/Pak0.pk3, etc). */
        var __lf = (typeof window !== 'undefined' && window.__mohaaLocalFiles) || {};
        var __lfKeys = Object.keys(__lf);
        if (__lfKeys.length > 0) {
            console.log('MOHAAjs: Writing ' + __lfKeys.length + ' local files to MEMFS...');
            for (var __li = 0; __li < __lfKeys.length; __li++) {
                var __lrel = __lfKeys[__li];
                var __ldst = '/' + __lrel;
                var __lcut = __ldst.lastIndexOf('/');
                if (__lcut > 0) __mkdirs(__ldst.slice(0, __lcut));
                try { __writeFileWithPakAlias(__ldst, __lf[__lrel]); } catch (e) {}
            }
            console.log('MOHAAjs: Wrote ' + __lfKeys.length + ' local files to MEMFS');
            if (typeof window !== 'undefined') window.__mohaaLocalFiles = null;
        }

        /* Gap-fill from server: always walk main/, optionally expansion dir.
         * Expansion dirs (mainta/maintt) may not exist on the server —
         * they're provided entirely by local files / IndexedDB cache. */
        var __tg = (typeof window !== 'undefined' && window.__mohaaTargetGame) || 0;
        var __gdMap = { 1: 'mainta', 2: 'maintt' };
        var __expDir = __gdMap[__tg];
        if (__expDir) __mkdirs('/' + __expDir);
        __mkdirs('/main');

        console.log('MOHAAjs: Server gap-fill: scanning /main/ ...');
        await __walk('main/');
        if (__expDir) {
            console.log('MOHAAjs: Server gap-fill: scanning /' + __expDir + '/ ...');
            await __walk(__expDir + '/');
        }

        console.log('MOHAAjs: VFS preload complete: ' + loaded + ' files ready, ' + failed + ' failed');
    })().catch(e => console.error('MOHAAjs: PreRun error', e))
        .finally(() => removeRunDependency(__dep));
});
