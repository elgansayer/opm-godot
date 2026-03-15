#!/usr/bin/env node
/**
 * mohaa_relay.js — WebSocket-to-UDP relay for MOHAA web clients
 *
 * Bridges browser WebSocket connections to native UDP MOHAA servers.
 * Each binary WebSocket message carries a 6-byte address header:
 *   [4 bytes IPv4 address][2 bytes port (big-endian)][N bytes MOHAA packet]
 *
 * Usage:
 *   npm install
 *   node mohaa_relay.js [port]          # default: 12300
 *
 * Then in the web client:
 *   +set net_ws_relay ws://<relay-host>:<port>
 *
 * Security: The relay only forwards UDP datagrams. It does not inspect or
 * modify packet contents. Restrict access via firewall rules if needed.
 */

'use strict';

const http = require('http');
const { WebSocketServer, WebSocket } = require('ws');
const dgram = require('dgram');
const { Buffer } = require('buffer');

const RELAY_PORT = parseInt(process.argv[2] || '12300', 10);
const ADDR_HEADER_SIZE = 6;

/* Maximum number of concurrent WebSocket clients */
const MAX_CLIENTS = 64;

/* Idle timeout: close the UDP socket if no traffic for 5 minutes */
const UDP_IDLE_TIMEOUT_MS = 5 * 60 * 1000;

const startTime = Date.now();
let clientCount = 0;

/* HTTP server handles health checks; WebSocket upgrades are delegated to wss. */
const server = http.createServer((req, res) => {
    if (req.url === '/health') {
        const uptime = Math.floor((Date.now() - startTime) / 1000);
        res.writeHead(200, { 'Content-Type': 'application/json' });
        res.end(JSON.stringify({ status: 'ok', clients: clientCount, maxClients: MAX_CLIENTS, uptime }));
        return;
    }
    res.writeHead(426, { 'Content-Type': 'text/plain' });
    res.end('Upgrade Required\n');
});

const wss = new WebSocketServer({ noServer: true, maxPayload: 65536 });

server.on('upgrade', (req, socket, head) => {
    wss.handleUpgrade(req, socket, head, (ws) => {
        wss.emit('connection', ws, req);
    });
});

server.listen(RELAY_PORT, () => {
    console.log(`mohaa-relay: Listening on port ${RELAY_PORT}`);
    console.log(`mohaa-relay: Health check: http://localhost:${RELAY_PORT}/health`);
    console.log(`mohaa-relay: Web clients should set: +set net_ws_relay ws://<this-host>:${RELAY_PORT}`);
});

wss.on('connection', (ws, req) => {
    if (clientCount >= MAX_CLIENTS) {
        console.warn('mohaa-relay: Max clients reached, rejecting connection');
        ws.close(1013, 'Server full');
        return;
    }

    const clientAddr = req.socket.remoteAddress;
    const clientPort = req.socket.remotePort;
    const clientId = `${clientAddr}:${clientPort}`;
    clientCount++;

    console.log(`mohaa-relay: Client connected: ${clientId} (${clientCount}/${MAX_CLIENTS})`);

    /* Each WebSocket client gets its own UDP socket for communication
       with game servers. This preserves per-client source port identity
       so the game server can distinguish multiple web clients. */
    const udp = dgram.createSocket('udp4');
    let lastActivity = Date.now();
    let idleTimer = null;

    udp.on('error', (err) => {
        console.error(`mohaa-relay: UDP error for ${clientId}: ${err.message}`);
    });

    /* UDP -> WebSocket: when game server responds, forward to web client */
    udp.on('message', (msg, rinfo) => {
        if (ws.readyState !== WebSocket.OPEN) return;

        lastActivity = Date.now();

        const parts = rinfo.address.split('.');
        if (parts.length !== 4) return; /* IPv4 only */

        const header = Buffer.alloc(ADDR_HEADER_SIZE);
        header[0] = parseInt(parts[0], 10);
        header[1] = parseInt(parts[1], 10);
        header[2] = parseInt(parts[2], 10);
        header[3] = parseInt(parts[3], 10);
        header.writeUInt16BE(rinfo.port, 4);

        try {
            ws.send(Buffer.concat([header, msg]), { binary: true });
        } catch (err) {
            console.error(`mohaa-relay: WS send error for ${clientId}: ${err.message}`);
        }
    });

    udp.bind(0, () => {
        /* Enable broadcast so LAN server scans (255.255.255.255) work */
        udp.setBroadcast(true);
    });

    /* WebSocket -> UDP: when web client sends, forward to game server */
    ws.on('message', (data) => {
        /* Only process binary messages with at least the address header */
        if (typeof data === 'string' || data.length < ADDR_HEADER_SIZE) return;

        lastActivity = Date.now();

        const buf = Buffer.isBuffer(data) ? data : Buffer.from(data);
        const destIp = `${buf[0]}.${buf[1]}.${buf[2]}.${buf[3]}`;
        const destPort = buf.readUInt16BE(4);
        const payload = buf.slice(ADDR_HEADER_SIZE);

        /* Basic validation: port must be > 0 and < 65536 */
        if (destPort <= 0 || destPort >= 65536) return;

        udp.send(payload, destPort, destIp, (err) => {
            if (err) {
                console.error(`mohaa-relay: UDP send to ${destIp}:${destPort} failed: ${err.message}`);
            }
        });
    });

    /* Clean up on disconnect */
    const cleanup = () => {
        if (idleTimer) clearInterval(idleTimer);
        try { udp.close(); } catch (e) { /* ignore */ }
        clientCount--;
        console.log(`mohaa-relay: Client disconnected: ${clientId} (${clientCount}/${MAX_CLIENTS})`);
    };

    ws.on('close', cleanup);
    ws.on('error', (err) => {
        console.error(`mohaa-relay: WS error for ${clientId}: ${err.message}`);
        cleanup();
    });

    /* Idle timeout: close UDP socket if no traffic for a while */
    idleTimer = setInterval(() => {
        if (Date.now() - lastActivity > UDP_IDLE_TIMEOUT_MS) {
            console.log(`mohaa-relay: Closing idle client ${clientId}`);
            ws.close(1000, 'Idle timeout');
        }
    }, 30000);
});

wss.on('error', (err) => {
    console.error(`mohaa-relay: WS server error: ${err.message}`);
});

server.on('error', (err) => {
    console.error(`mohaa-relay: HTTP server error: ${err.message}`);
    process.exit(1);
});

/* Graceful shutdown */
function shutdown() {
    console.log('mohaa-relay: Shutting down...');
    wss.clients.forEach((ws) => ws.close(1001, 'Server shutting down'));
    wss.close();
    server.close(() => process.exit(0));
}

process.on('SIGINT', shutdown);
process.on('SIGTERM', shutdown);
