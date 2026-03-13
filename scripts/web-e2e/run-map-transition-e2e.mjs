/**
 * Web E2E test: map transition.
 *
 * 1. Loads TARGET_MAP (default: dm/mohdm1)
 * 2. Waits until it is fully loaded
 * 3. Sends a console command to change to SECOND_MAP (default: dm/mohdm2)
 * 4. Waits until the second map is loaded
 * 5. Repeats steps 3-4 for NUM_ROTATIONS total transitions
 * 6. Verifies no crashes / std::terminate occurred
 *
 * Environment variables:
 *   BASE_URL          - Web server URL (default: http://127.0.0.1:8086)
 *   TARGET_MAP        - First map to load (default: dm/mohdm1)
 *   SECOND_MAP        - Map to transition to (default: dm/mohdm2)
 *   COM_TARGET_GAME   - Game variant 0/1/2 (default: 0)
 *   E2E_TIMEOUT_MS    - Per-step timeout (default: 240000)
 *   BROWSER_EXECUTABLE - Browser path (auto-detect if empty)
 *   NUM_ROTATIONS     - Number of map transitions to perform (default: 1)
 */
import process from 'node:process';
import { chromium } from 'playwright';

const baseUrl = process.env.BASE_URL || 'http://127.0.0.1:8086';
const targetMap = process.env.TARGET_MAP || 'dm/mohdm1';
const secondMap = process.env.SECOND_MAP || 'dm/mohdm2';
const targetGame = process.env.COM_TARGET_GAME || '0';
const timeoutMs = Number(process.env.E2E_TIMEOUT_MS || '240000');
const browserExecutable = process.env.BROWSER_EXECUTABLE || '';
const numRotations = Number(process.env.NUM_ROTATIONS || '1');

const url = new URL('/mohaa.html', baseUrl);
url.searchParams.set('map', targetMap);
url.searchParams.set('com_target_game', targetGame);
url.searchParams.set('webdriver', '1');

const errors = [];
const logs = [];
let pageClosed = false;
let pageCrashed = false;

// Patterns that are noisy but not actionable failures
const BENIGN_CONSOLE = [
  /Failed to load resource:.*40[34]/i,
  /Failed to execute 'put' on 'Cache'/i,
  /Service[- ]?[Ww]orker/i,
  /favicon/i,
  /Blocking on the main thread is very dangerous/i,
  /^Uncaught \(in promise\)\s*$/i,
  /WrongDocumentError/i,
  /SecurityError.*pointer.*lock/i,
  /SecurityError.*exited the lock/i,
];
const isBenign = (text) => BENIGN_CONSOLE.some((re) => re.test(text));

const browser = await chromium.launch({
  headless: true,
  executablePath: browserExecutable || undefined,
});
const context = await browser.newContext();
const page = await context.newPage();

page.on('console', (msg) => {
  const text = msg.text();
  logs.push(text);
  if (msg.type() === 'error' && !isBenign(text)) {
    errors.push(`console error: ${text}`);
  }
  if (/ENGINE ERROR|libc\+\+abi.*terminat|Aborted\(native code/i.test(text)) {
    errors.push(`fatal marker: ${text}`);
  }
});

page.on('pageerror', (err) => {
  const msg = err?.message || String(err);
  if (!isBenign(msg)) {
    errors.push(`page error: ${msg}`);
  }
});

page.on('close', () => { pageClosed = true; errors.push('page close event'); });
page.on('crash', () => { pageCrashed = true; errors.push('page crash event'); });

/** Wait until window.__mohaaMapLoaded matches the given map name (case-insensitive). */
async function waitForMap(mapName, label) {
  console.log(`[map-e2e] Waiting for ${label}: ${mapName}`);
  await page.waitForFunction(
    ({ expected }) => {
      if (typeof window.__mohaaEngineError === 'string' && window.__mohaaEngineError.length > 0) {
        throw new Error(`engine error: ${window.__mohaaEngineError}`);
      }
      const loaded = typeof window.__mohaaMapLoaded === 'string' ? window.__mohaaMapLoaded : '';
      return loaded.toLowerCase() === expected.toLowerCase();
    },
    { expected: mapName },
    { timeout: timeoutMs },
  );
  console.log(`[map-e2e] ${label} loaded: ${mapName}`);
}

try {
  // ── Step 1: Navigate and start ──
  console.log(`[map-e2e] Navigating to ${url.toString()}`);
  await page.goto(url.toString(), { waitUntil: 'domcontentloaded', timeout: timeoutMs });

  await page.waitForSelector('#mohaa-loader', { state: 'visible', timeout: 60000 });

  const playVisible = await page.locator('#mohaa-play-btn').isVisible().catch(() => false);
  if (playVisible) {
    console.log('[map-e2e] Clicking Play');
    await page.click('#mohaa-play-btn');
  }
  const skipVisible = await page.locator('#mohaa-skip-btn').isVisible().catch(() => false);
  if (skipVisible) {
    console.log('[map-e2e] Clicking Skip');
    await page.click('#mohaa-skip-btn');
  }

  // ── Step 2: Wait for first map ──
  await waitForMap(targetMap, 'first map');

  // Check for errors after first load
  const errorsAfterFirst = errors.filter((e) => /fatal marker|page crash/.test(e));
  if (errorsAfterFirst.length > 0) {
    throw new Error(`Fatal errors after first map:\n${errorsAfterFirst.join('\n')}`);
  }

  // ── Step 3+: Rotate between maps ──
  const maps = [secondMap, targetMap]; // alternating targets
  let currentMap = targetMap;

  for (let rotation = 1; rotation <= numRotations; rotation++) {
    const nextMap = maps[(rotation - 1) % maps.length];
    console.log(`[map-e2e] Rotation ${rotation}/${numRotations}: ${currentMap} → ${nextMap}`);

    // Reset the map-loaded marker so we detect the NEW map load
    await page.evaluate(() => {
      window.__mohaaMapLoaded = '';
      window.__mohaaMapLoadedLog = '';
    });

    // Send the map command via the JS→engine bridge
    await page.evaluate((cmd) => {
      window.__mohaaPendingCommand = cmd;
    }, `devmap ${nextMap}`);

    // Wait for the new map
    await waitForMap(nextMap, `rotation ${rotation} map`);

    // Check for fatal errors after each rotation
    const rotationErrors = errors.filter((e) => /fatal marker|page crash|page close/.test(e));
    if (rotationErrors.length > 0) {
      throw new Error(`Fatal errors during rotation ${rotation}:\n${rotationErrors.join('\n')}`);
    }

    console.log(`[map-e2e] Rotation ${rotation}/${numRotations} OK`);
    currentMap = nextMap;
  }

  console.log(`[map-e2e] PASS — ${numRotations} map rotation(s) successful`);
} catch (err) {
  const tail = logs.slice(-200).join('\n');
  console.error('[map-e2e] FAIL:', err?.message || String(err));
  if (pageCrashed) console.error('[map-e2e] Page crashed during run');
  if (pageClosed) console.error('[map-e2e] Page closed during run');
  if (errors.length > 0) {
    console.error('[map-e2e] Captured errors:');
    for (const e of errors.slice(-20)) console.error('  ', e);
  }
  if (tail) {
    console.error('[map-e2e] Recent console output:');
    console.error(tail);
  }
  if (!page.isClosed()) {
    const stdoutTail = await page.evaluate(() => {
      const arr = Array.isArray(window.__mohaaStdout) ? window.__mohaaStdout : [];
      // Return MAPTRANS + error lines, plus last 40 general lines
      const interesting = arr.filter(l => l.includes('[MAPTRANS]') || /error|ERR_DROP|Com_Error|CG_Init|longjmp|abort/i.test(l));
      const tail = arr.slice(-40);
      return [...interesting, '--- TAIL ---', ...tail];
    }).catch(() => []);
    if (stdoutTail.length > 0) {
      console.error('[map-e2e] Recent engine/stdout:');
      console.error(stdoutTail.join('\n'));
    }
  }
  process.exitCode = 1;
} finally {
  await context.close();
  await browser.close();
}
