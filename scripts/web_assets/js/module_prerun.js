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
        /* ── VFS preload progress overlay ──
         * Reuses the Godot #status overlay (already visible from setStatusMode('progress'))
         * and adds a descriptive text + repurposes the progress bar for file download tracking.
         * This prevents users seeing a "frozen" black screen during pk3 downloads. */
        var __statusEl = (typeof document !== 'undefined') ? document.getElementById('status') : null;
        var __progressBar = (typeof document !== 'undefined') ? document.getElementById('status-progress') : null;
        var __vfsText = null;
        var __bytesLoaded = 0;
        if (__statusEl) {
            __statusEl.style.visibility = 'visible';
            __vfsText = document.createElement('div');
            __vfsText.id = 'mohaa-vfs-status';
            __vfsText.style.cssText = 'color:#e0e0e0;font-family:"Noto Sans","Droid Sans",Arial,sans-serif;font-size:14px;text-align:center;padding:0 1rem;z-index:1;position:absolute;bottom:5%;left:0;right:0;';
            __vfsText.textContent = 'Preparing game files\u2026';
            __statusEl.appendChild(__vfsText);
            if (__progressBar) {
                __progressBar.style.display = 'block';
                __progressBar.removeAttribute('value');
                __progressBar.removeAttribute('max');
            }
        }
        var __formatBytes = function(b) {
            if (b < 1048576) return (b / 1024).toFixed(0) + ' KB';
            return (b / 1048576).toFixed(1) + ' MB';
        };
        var __setVfsStatus = function(msg) {
            if (__vfsText) __vfsText.textContent = msg;
        };
        var __updateDownloadProgress = function() {
            if (!__vfsText) return;
            var done = loaded + failed;
            var sizeStr = __bytesLoaded > 0 ? ' \u2014 ' + __formatBytes(__bytesLoaded) + ' downloaded' : '';
            __vfsText.textContent = 'Downloading game files: ' + done + '/' + total + sizeStr;
            if (__progressBar && total > 0) {
                __progressBar.value = done;
                __progressBar.max = total;
            }
        };
        var __cleanupVfsOverlay = function() {
            if (__vfsText) { __vfsText.remove(); __vfsText = null; }
        };

        /* Resolve CDN base URL from multiple sources (first wins):
         *   1. window.MOHAA_CDN_URL — set by Docker runtime config script
         *   2. URL parameter ?cdn_url=...
         *   3. GODOT_CONFIG.CDN_URL (Godot 4.6+)
         *   4. MOHAA_CONFIG.CDN_URL (legacy Godot)
         *   5. Default: /assets (nginx autoindex in Docker) */
        var cdn = (typeof window !== 'undefined' && window.MOHAA_CDN_URL)
            || (typeof URLSearchParams !== 'undefined' && (new URLSearchParams(window.location.search)).get('cdn_url'))
            || (typeof GODOT_CONFIG !== 'undefined' && GODOT_CONFIG['CDN_URL'])
            || (typeof MOHAA_CONFIG !== 'undefined' && MOHAA_CONFIG['CDN_URL'])
            || '/assets';
        if (cdn && !cdn.endsWith('/')) cdn += '/';
        console.log('MOHAAjs: CDN base URL:', cdn);

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

        /* Helper: fetch directory listing as JSON array.
         * Tries three approaches in order:
         *   1. Static manifest.json in the directory (works on any CDN/static host)
         *   2. nginx autoindex JSON (requires autoindex_format json)
         *   3. Returns [] — caller will fall back to known-filename probing */
        var __listDir = async (relDir) => {
            /* 1. Try static manifest.json (deployer-created).
             *    In CDN-only mode (no local assets), the manifest is the ONLY way
             *    to discover files. Without it, only known pk3 names are probed
             *    and ALL loose files (sounds, music, configs) are missed. */
            var manifestUrl = cdn + relDir + 'manifest.json';
            try {
                var mr = await fetch(manifestUrl, { cache: 'no-cache' });
                if (mr.ok) {
                    var mtxt = await mr.text();
                    var mj = JSON.parse(mtxt);
                    if (Array.isArray(mj) && mj.length) {
                        /* Normalise entries: accept both [{name:"foo"},...] and ["foo",...] */
                        var entries = mj.map(function(e) {
                            if (typeof e === 'string') return { name: e, type: 'file' };
                            return e;
                        });
                        console.log('MOHAAjs: Using manifest.json for ' + relDir + ' (' + entries.length + ' entries)');
                        return entries;
                    }
                }
                console.warn('MOHAAjs: manifest.json for ' + relDir + ' returned empty or invalid data');
            } catch (e) {
                console.warn('MOHAAjs: manifest.json not found at ' + manifestUrl + ' — loose files (sounds, music, configs) will NOT be downloaded. Generate manifests with: scripts/generate-manifests.sh');
            }

            /* 2. Try nginx autoindex JSON */
            var url = cdn + relDir;
            try {
                var r = await fetch(url, {
                    cache: 'no-cache',
                    headers: { 'Accept': 'application/json' }
                });
                if (!r.ok) {
                    console.warn('MOHAAjs: Directory listing failed:', url, 'status:', r.status, r.statusText);
                    return [];
                }
                var txt = await r.text();
                try {
                    var j = JSON.parse(txt);
                } catch (pe) {
                    console.warn('MOHAAjs: Directory listing not JSON:', url, '(got', txt.substring(0, 200), ')');
                    return [];
                }
                if (Array.isArray(j) && j.length && typeof j[0] === 'object') return j;
                console.warn('MOHAAjs: Directory listing unexpected format:', url, j);
                return [];
            } catch (e) {
                console.warn('MOHAAjs: Directory listing fetch error:', url, e.message || e);
                return [];
            }
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
                var buf = await res.arrayBuffer();
                __bytesLoaded += buf.byteLength;
                return { dst: dst, data: new Uint8Array(buf) };
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

        /* Known MOHAA pk3 filenames per game directory.  Used as fallback
         * when the CDN doesn't support JSON directory listing (autoindex). */
        var __knownPaks = {
            'main/':    ['Pak0.pk3','Pak1.pk3','Pak2.pk3','Pak3.pk3','Pak4.pk3','Pak5.pk3','Pak6.pk3'],
            'mainta/':  ['Pak0.pk3','Pak1.pk3','Pak2.pk3','Pak3.pk3'],
            'maintt/':  ['Pak0.pk3','Pak1.pk3','Pak2.pk3','Pak3.pk3']
        };

        /* Fetch a list of files by known names (HEAD probe then GET).
         * Returns synthetic entries compatible with __walk's loop. */
        var __probeKnownPaks = async (relDir) => {
            var known = __knownPaks[relDir];
            if (!known) return [];
            console.warn('MOHAAjs: No manifest.json for ' + relDir + ' — falling back to ' + known.length + ' known pk3 names ONLY. Loose files (sounds, music, configs) will NOT be downloaded!');
            console.warn('MOHAAjs: Generate manifests with: scripts/generate-manifests.sh <asset-dir> && scripts/deploy-cdn.sh');
            var entries = [];
            var probes = known.map(async (name) => {
                try {
                    var url = cdn + relDir + name;
                    var r = await fetch(url, { method: 'HEAD' });
                    if (r.ok) entries.push({ name: name, type: 'file' });
                } catch (e) {}
            });
            await Promise.all(probes);
            return entries;
        };

        var __walk = async (relDir) => {
            var entries = await __listDir(relDir);
            if (entries.length === 0) {
                /* Fallback: CDN has no directory listing — probe known pk3 names */
                entries = await __probeKnownPaks(relDir);
            }
            var promises = [];
            for (var i = 0; i < entries.length; i++) {
                var e = entries[i], name = e.name;
                if (name.startsWith('.')) continue;
                if (e.type === 'directory') continue;
                /* Manifest entries include all files (sounds, music, videos, configs, pk3s).
                 * Only skip hidden files and the manifest itself. */
                if (name === 'manifest.json') continue;
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
                    __updateDownloadProgress();
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
            __setVfsStatus('Loading cached game files\u2026');
            if (__progressBar) { __progressBar.max = __lfKeys.length; __progressBar.value = 0; }
            for (var __li = 0; __li < __lfKeys.length; __li++) {
                var __lrel = __lfKeys[__li];
                var __ldst = '/' + __lrel;
                var __lcut = __ldst.lastIndexOf('/');
                if (__lcut > 0) __mkdirs(__ldst.slice(0, __lcut));
                try { __writeFileWithPakAlias(__ldst, __lf[__lrel]); } catch (e) {}
                if (__progressBar) __progressBar.value = __li + 1;
                __setVfsStatus('Loading cached files: ' + (__li + 1) + '/' + __lfKeys.length);
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
        __setVfsStatus('Scanning server for game files\u2026');
        await __walk('main/');
        if (__expDir) {
            console.log('MOHAAjs: Server gap-fill: scanning /' + __expDir + '/ ...');
            __setVfsStatus('Scanning server for expansion files\u2026');
            await __walk(__expDir + '/');
        }

        console.log('MOHAAjs: VFS preload complete: ' + loaded + ' files ready, ' + failed + ' failed');
        if (loaded === 0 && __lfKeys.length === 0) {
            console.error('MOHAAjs: WARNING — No game files loaded! The engine will not work correctly.');
            console.error('MOHAAjs: Check that the CDN URL (' + cdn + ') serves pk3 files.');
            console.error('MOHAAjs: Either enable nginx autoindex_format json, or place Pak0.pk3-Pak6.pk3 at ' + cdn + 'main/');
            __setVfsStatus('Warning: No game files found. Check CDN configuration.');
        } else {
            __setVfsStatus('Starting engine\u2026');
        }
    })().catch(e => console.error('MOHAAjs: PreRun error', e))
        .finally(() => { __cleanupVfsOverlay(); removeRunDependency(__dep); });
});
