/**
 * run-web-connect-e2e.mjs — Web E2E test: connect to real MOHAA servers via relay.
 *
 * Usage:
 *   BASE_URL=http://127.0.0.1:8086 \
 *   SERVERS="78.108.16.74:12203,217.182.199.4:12203" \
 *   CONNECT_TIMEOUT_MS=60000 \
 *   SETTLE_MS=3000 \
 *     node run-web-connect-e2e.mjs
 *
 * The test navigates to mohaa.html?connect=<ip>&webdriver=1 for each server,
 * waits for window.__mohaaMapLoaded to be set (indicating successful connection
 * and map load), then disconnects and moves to the next server.
 *
 * Requires: Playwright, a running Docker stack (nginx + relay on port 8086),
 *           and game assets mounted into the container.
 */
import process from 'node:process';
import { chromium } from 'playwright';

const baseUrl = process.env.BASE_URL || 'http://127.0.0.1:8086';
const serverList = (process.env.SERVERS || '78.108.16.74:12203,217.182.199.4:12203').split(',').map(s => s.trim()).filter(Boolean);
const connectTimeoutMs = Number(process.env.CONNECT_TIMEOUT_MS || '60000');
const settleMs = Number(process.env.SETTLE_MS || '3000');
const browserExecutable = process.env.BROWSER_EXECUTABLE || '';

const results = [];

console.log(`[web-connect-e2e] Testing ${serverList.length} server(s) via ${baseUrl}`);
console.log(`[web-connect-e2e] Timeout: ${connectTimeoutMs}ms, settle: ${settleMs}ms`);

const browser = await chromium.launch({
  headless: true,
  executablePath: browserExecutable || undefined,
});

for (const server of serverList) {
  const start = Date.now();
  let status = 'FAIL';
  let detail = '';

  const url = new URL('/mohaa.html', baseUrl);
  url.searchParams.set('connect', server);
  url.searchParams.set('webdriver', '1');

  console.log(`\n[web-connect-e2e] Connecting to ${server} ...`);

  const context = await browser.newContext();
  const page = await context.newPage();

  const errors = [];
  let pageCrashed = false;

  // Benign console patterns (same as existing e2e)
  const BENIGN_CONSOLE = [
    /Failed to load resource:.*40[34]/i,
    /Failed to execute 'put' on 'Cache'/i,
    /Service[- ]?[Ww]orker/i,
    /favicon/i,
    /Blocking on the main thread is very dangerous/i,
    /^Uncaught \(in promise\)\s*$/i,
    /mohaa-ws:.*WebSocket error/i,
    /mohaa-ws:.*WebSocket close/i,
  ];
  const isBenign = (text) => BENIGN_CONSOLE.some((re) => re.test(text));

  page.on('console', (msg) => {
    const text = msg.text();
    if (msg.type() === 'error' && !isBenign(text)) {
      errors.push(text);
    }
    if (/ENGINE ERROR|FAILED to load.*\.wasm|FAILED to load.*cgame/i.test(text)) {
      errors.push(`runtime: ${text}`);
    }
  });

  page.on('pageerror', (err) => {
    const msg = err?.message || String(err);
    if (!isBenign(msg)) errors.push(`pageerror: ${msg}`);
  });

  page.on('crash', () => {
    pageCrashed = true;
    errors.push('page crashed');
  });

  try {
    // Navigate
    await page.goto(url.toString(), { waitUntil: 'domcontentloaded', timeout: 60000 });

    // Click Play button if visible (asset loader screen)
    const playVisible = await page.locator('#mohaa-play-btn').isVisible().catch(() => false);
    if (playVisible) {
      console.log(`[web-connect-e2e]   Clicking Play`);
      await page.click('#mohaa-play-btn');
    }
    const skipVisible = await page.locator('#mohaa-skip-btn').isVisible().catch(() => false);
    if (skipVisible) {
      console.log(`[web-connect-e2e]   Clicking Skip`);
      await page.click('#mohaa-skip-btn');
    }

    // Diagnostic logging while waiting
    const diagInterval = setInterval(async () => {
      try {
        if (page.isClosed()) { clearInterval(diagInterval); return; }
        const diag = await page.evaluate(() => ({
          engineInit: !!window.__mohaaEngineInit,
          serverState: typeof window.__mohaaServerState === 'number' ? window.__mohaaServerState : -1,
          mapLoaded: typeof window.__mohaaMapLoaded === 'string' ? window.__mohaaMapLoaded : null,
          engineError: typeof window.__mohaaEngineError === 'string' ? window.__mohaaEngineError : null,
        }));
        console.log(`[web-connect-e2e]   DIAG: init=${diag.engineInit} sv=${diag.serverState} map=${diag.mapLoaded} err=${diag.engineError}`);
      } catch { /* page may be navigating */ }
    }, 10000);

    // Wait for map loaded
    try {
      await page.waitForFunction(() => {
        if (typeof window.__mohaaEngineError === 'string' && window.__mohaaEngineError.length > 0) {
          throw new Error(`engine error: ${window.__mohaaEngineError}`);
        }
        return (typeof window.__mohaaMapLoaded === 'string' && window.__mohaaMapLoaded.length > 0) ||
               (typeof window.__mohaaMapLoadedLog === 'string' && window.__mohaaMapLoadedLog.length > 0);
      }, null, { timeout: connectTimeoutMs });

      // Settle time
      await new Promise(r => setTimeout(r, settleMs));

      const elapsed = ((Date.now() - start) / 1000).toFixed(1);
      const mapName = await page.evaluate(() => window.__mohaaMapLoaded || '').catch(() => '');
      status = 'PASS';
      detail = `map loaded in ${elapsed}s (${mapName})`;
    } finally {
      clearInterval(diagInterval);
    }

    if (pageCrashed) {
      status = 'FAIL';
      detail = 'page crashed';
    } else if (status !== 'PASS' && errors.length > 0) {
      status = 'FAIL';
      detail = `runtime errors: ${errors[0]}`;
    }
  } catch (err) {
    const elapsed = ((Date.now() - start) / 1000).toFixed(1);
    if (/timeout/i.test(err?.message || '')) {
      detail = `timeout after ${elapsed}s`;
    } else {
      detail = err?.message || String(err);
    }
  } finally {
    await page.close().catch(() => {});
    await context.close().catch(() => {});
  }

  results.push({ server, status, detail });
  console.log(`[web-connect-e2e] ${status} connect: ${server} (${detail})`);
}

await browser.close();

// Summary
console.log('\n========================================');
console.log(' Web Connect E2E Results');
console.log('========================================');
const passed = results.filter(r => r.status === 'PASS').length;
const failed = results.filter(r => r.status === 'FAIL').length;
console.log(`Passed: ${passed}`);
console.log(`Failed: ${failed}`);
console.log('');
for (const r of results) {
  console.log(`WebConnectTest: ${r.status} connect: ${r.server} (${r.detail})`);
}
console.log('');
if (passed === results.length) {
  console.log(`RESULT: PASS (${passed}/${results.length} servers connected)`);
} else if (passed > 0) {
  console.log(`RESULT: PARTIAL PASS (${passed}/${results.length} servers connected)`);
} else {
  console.log(`RESULT: FAIL (0/${results.length} servers connected)`);
}

process.exit(failed === results.length ? 1 : 0);
