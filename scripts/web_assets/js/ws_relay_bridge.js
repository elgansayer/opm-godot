/* ═══════ OpenMoHAA WebSocket Relay Bridge ═══════ */
/* Injected into mohaa.js by patch_web_js.py.
 * Provides globalThis._opm_ws_* functions called from the GDExtension
 * SIDE_MODULE (net_ws.c) via the Emscripten stub resolver's globalThis
 * fallback.  Module.HEAPU8 / UTF8ToString are accessed at call time
 * (not registration time) — available after WASM init completes. */
(function() {
    var _opmWsRelay = null;
    var _opmWsRecvQueue = [];
    var _opmWsConnected = false;

    function _getModule() {
        return (typeof Module !== 'undefined' && Module) || globalThis.Module || null;
    }

    /**
     * _opm_ws_open(url_ptr) — Connect to a WebSocket relay server.
     * @param url_ptr  WASM pointer to a NUL-terminated C string
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
                console.log('mohaa-ws: Connected to relay:', url);
            };
            _opmWsRelay.onclose = function(ev) {
                _opmWsConnected = false;
                console.log('mohaa-ws: Disconnected from relay, code=' + ev.code);
            };
            _opmWsRelay.onerror = function(ev) {
                console.error('mohaa-ws: WebSocket error:', ev);
            };
            _opmWsRelay.onmessage = function(ev) {
                if (ev.data instanceof ArrayBuffer && ev.data.byteLength >= 6) {
                    _opmWsRecvQueue.push(new Uint8Array(ev.data));
                }
            };
            return 1;
        } catch (e) {
            console.error('mohaa-ws: Failed to create WebSocket:', e);
            return 0;
        }
    };

    /** _opm_ws_close() — Close the relay connection. */
    globalThis._opm_ws_close = function() {
        if (_opmWsRelay) {
            try { _opmWsRelay.close(1000, 'shutdown'); } catch (e) {}
            _opmWsRelay = null;
        }
        _opmWsConnected = false;
        _opmWsRecvQueue = [];
    };

    /**
     * _opm_ws_send(data_ptr, length) — Send binary via relay.
     * @returns 1 on success, 0 on failure
     */
    globalThis._opm_ws_send = function(data_ptr, length) {
        if (!_opmWsRelay || !_opmWsConnected) return 0;
        if (length <= 0 || length > 65536) return 0;
        try {
            var M = _getModule();
            var heap = M ? M.HEAPU8 : (typeof HEAPU8 !== 'undefined' ? HEAPU8 : null);
            if (!heap) { console.error('mohaa-ws: Send: no HEAPU8'); return 0; }
            var data = heap.slice(data_ptr, data_ptr + length);
            _opmWsRelay.send(data.buffer);
            return 1;
        } catch (e) {
            console.error('mohaa-ws: Send failed:', e);
            return 0;
        }
    };

    /**
     * _opm_ws_recv(data_ptr, maxlen) — Receive next queued binary message.
     * @returns Number of bytes written, or 0 if empty
     */
    globalThis._opm_ws_recv = function(data_ptr, maxlen) {
        if (_opmWsRecvQueue.length === 0) return 0;
        var pkt = _opmWsRecvQueue.shift();
        var len = Math.min(pkt.length, maxlen);
        var M = _getModule();
        var heap = M ? M.HEAPU8 : (typeof HEAPU8 !== 'undefined' ? HEAPU8 : null);
        if (!heap) { console.error('mohaa-ws: Recv: no HEAPU8'); return 0; }
        heap.set(pkt.subarray(0, len), data_ptr);
        return len;
    };

    /** _opm_ws_status() — @returns 1 if connected, 0 otherwise */
    globalThis._opm_ws_status = function() {
        return (_opmWsConnected && _opmWsRelay &&
                _opmWsRelay.readyState === WebSocket.OPEN) ? 1 : 0;
    };

    /** _opm_ws_is_secure() — @returns 1 if page served over HTTPS, 0 otherwise */
    globalThis._opm_ws_is_secure = function() {
        try {
            return (window.location.protocol === 'https:') ? 1 : 0;
        } catch (e) {
            return 0;
        }
    };

    /* Register without underscore prefix too — stub resolver tries both. */
    globalThis.opm_ws_open       = globalThis._opm_ws_open;
    globalThis.opm_ws_close      = globalThis._opm_ws_close;
    globalThis.opm_ws_send       = globalThis._opm_ws_send;
    globalThis.opm_ws_recv       = globalThis._opm_ws_recv;
    globalThis.opm_ws_status     = globalThis._opm_ws_status;
    globalThis.opm_ws_is_secure  = globalThis._opm_ws_is_secure;

    console.log('mohaa-ws: WebSocket relay bridge registered on globalThis');
})();
/* ═══════ End OpenMoHAA WebSocket Relay Bridge ═══════ */
