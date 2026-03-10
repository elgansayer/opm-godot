import process from 'node:process';
import { chromium } from 'playwright';

const baseUrl = process.env.BASE_URL || 'http://127.0.0.1:8086';
const targetMap = process.env.TARGET_MAP || 'dm/mohdm1';
const targetGame = process.env.COM_TARGET_GAME || '0';
const timeoutMs = Number(process.env.E2E_TIMEOUT_MS || '240000');
const browserExecutable = process.env.BROWSER_EXECUTABLE || '';

const url = new URL('/mohaa.html', baseUrl);
url.searchParams.set('map', targetMap);
url.searchParams.set('com_target_game', targetGame);

const errors = [];
const logs = [];

const browser = await chromium.launch({
  headless: true,
  executablePath: browserExecutable || undefined,
});
const context = await browser.newContext();
const page = await context.newPage();

page.on('console', (msg) => {
  const text = msg.text();
  logs.push(text);
  if (msg.type() === 'error') {
    errors.push(`console error: ${text}`);
  }
  if (/ENGINE ERROR|OpenMoHAA unresolved symbol|FAILED to load/i.test(text)) {
    errors.push(`runtime error marker: ${text}`);
  }
});

page.on('pageerror', (err) => {
  errors.push(`page error: ${err?.message || String(err)}`);
});

try {
  console.log(`[web-e2e] Navigating to ${url.toString()}`);
  await page.goto(url.toString(), { waitUntil: 'domcontentloaded', timeout: timeoutMs });

  await page.waitForSelector('#opm-loader', { state: 'visible', timeout: 60000 });

  const playVisible = await page.locator('#opm-play-btn').isVisible().catch(() => false);
  if (playVisible) {
    console.log('[web-e2e] Clicking Play');
    await page.click('#opm-play-btn');
  }

  const skipVisible = await page.locator('#opm-skip-btn').isVisible().catch(() => false);
  if (skipVisible) {
    console.log('[web-e2e] Clicking Skip (server files path)');
    await page.click('#opm-skip-btn');
  }

  console.log('[web-e2e] Waiting for map-loaded signal');
  await page.waitForFunction(() => typeof window.__opmMapLoaded === 'string' && window.__opmMapLoaded.length > 0, null, {
    timeout: timeoutMs,
  });

  const loadedMap = await page.evaluate(() => window.__opmMapLoaded || '');
  console.log(`[web-e2e] Map loaded: ${loadedMap}`);

  if (!loadedMap.toLowerCase().includes(targetMap.toLowerCase())) {
    throw new Error(`Loaded map '${loadedMap}' does not match expected '${targetMap}'`);
  }

  if (errors.length > 0) {
    throw new Error(`Runtime errors detected:\n${errors.join('\n')}`);
  }

  console.log('[web-e2e] PASS');
} catch (err) {
  const tail = logs.slice(-40).join('\n');
  console.error('[web-e2e] FAIL:', err?.message || String(err));
  if (tail) {
    console.error('[web-e2e] Recent console output:');
    console.error(tail);
  }
  process.exitCode = 1;
} finally {
  await context.close();
  await browser.close();
}
