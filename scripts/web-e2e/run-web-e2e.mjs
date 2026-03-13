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
url.searchParams.set('webdriver', '1');

const errors = [];
const logs = [];
const httpIssues = [];
let pageClosed = false;
let pageCrashed = false;

const browser = await chromium.launch({
  headless: true,
  executablePath: browserExecutable || undefined,
});
const context = await browser.newContext();
const page = await context.newPage();

// Benign patterns: browser resource 404s, Cache API blips, service worker noise,
// Emscripten pthreads main-thread blocking warning, Godot audio autoplay rejections
const BENIGN_CONSOLE = [
  /Failed to load resource:.*404/i,
  /Failed to load resource:.*403/i,
  /Failed to execute 'put' on 'Cache'/i,
  /Service[- ]?[Ww]orker/i,
  /favicon/i,
  /Blocking on the main thread is very dangerous/i,
  /^Uncaught \(in promise\)\s*$/i,
];
const isBenign = (text) => BENIGN_CONSOLE.some((re) => re.test(text));

page.on('console', (msg) => {
  const text = msg.text();
  logs.push(text);
  if (msg.type() === 'error' && !isBenign(text)) {
    errors.push(`console error: ${text}`);
  }
  // Only flag genuine engine/WASM load failures, not browser asset 404s
  if (/ENGINE ERROR|OpenMoHAA unresolved symbol|FAILED to load.*\.wasm|FAILED to load.*cgame/i.test(text)) {
    errors.push(`runtime error marker: ${text}`);
  }
});

page.on('requestfailed', (request) => {
  const failure = request.failure();
  httpIssues.push(`request failed: ${request.method()} ${request.url()} :: ${failure?.errorText || 'unknown'}`);
});

page.on('response', (response) => {
  const status = response.status();
  if (status >= 400) {
    httpIssues.push(`http ${status}: ${response.request().method()} ${response.url()}`);
  }
});

page.on('pageerror', (err) => {
  const msg = err?.message || String(err);
  // Skip benign browser/Cache API errors that don't affect engine execution
  if (!isBenign(msg)) {
    errors.push(`page error: ${msg}`);
  }
});

page.on('close', () => {
  pageClosed = true;
  errors.push('page close event fired');
});

page.on('crash', () => {
  pageCrashed = true;
  errors.push('page crash event fired');
});

try {
  console.log(`[web-e2e] Navigating to ${url.toString()}`);
  await page.goto(url.toString(), { waitUntil: 'domcontentloaded', timeout: timeoutMs });

  await page.waitForSelector('#mohaa-loader', { state: 'visible', timeout: 60000 });

  const playVisible = await page.locator('#mohaa-play-btn').isVisible().catch(() => false);
  if (playVisible) {
    console.log('[web-e2e] Clicking Play');
    await page.click('#mohaa-play-btn');
  }

  const skipVisible = await page.locator('#mohaa-skip-btn').isVisible().catch(() => false);
  if (skipVisible) {
    console.log('[web-e2e] Clicking Skip (server files path)');
    await page.click('#mohaa-skip-btn');
  }

  const startupInfo = await page.evaluate(() => ({
    startupArgs: typeof window.__mohaaStartupArgs === 'string' ? window.__mohaaStartupArgs : '',
    launchMap: typeof window.__mohaaLaunchMap === 'string' ? window.__mohaaLaunchMap : '',
    search: window.location.search,
  }));
  console.log(`[web-e2e] Startup args: ${startupInfo.startupArgs}`);
  console.log(`[web-e2e] Launch map var: ${startupInfo.launchMap}`);
  console.log(`[web-e2e] URL search: ${startupInfo.search}`);
  const startupStdout = await page.evaluate(() => {
    const arr = Array.isArray(window.__mohaaStdout) ? window.__mohaaStdout : [];
    return arr.filter((line) => /Startup args|Startup map|Extra engine cmds|Starting at main menu/.test(String(line))).slice(-20);
  }).catch(() => []);
  if (startupStdout.length > 0) {
    console.log('[web-e2e] Startup stdout markers:');
    console.log(startupStdout.join('\n'));
  }

  console.log('[web-e2e] Waiting for map-loaded signal');
  await page.waitForFunction(() => {
    if (typeof window.__mohaaEngineError === 'string' && window.__mohaaEngineError.length > 0) {
      throw new Error(`engine error: ${window.__mohaaEngineError}`);
    }
    const jsBridgeSignal = typeof window.__mohaaMapLoaded === 'string' && window.__mohaaMapLoaded.length > 0;
    const stdoutSignal = typeof window.__mohaaMapLoadedLog === 'string' && window.__mohaaMapLoadedLog.length > 0;
    return jsBridgeSignal || stdoutSignal;
  }, null, {
    timeout: timeoutMs,
  });

  const loadedMap = await page.evaluate(() => {
    if (typeof window.__mohaaMapLoaded === 'string' && window.__mohaaMapLoaded.length > 0) {
      return window.__mohaaMapLoaded;
    }
    const line = typeof window.__mohaaMapLoadedLog === 'string' ? window.__mohaaMapLoadedLog : '';
    const i = line.indexOf('->');
    return i >= 0 ? line.slice(i + 2).trim() : '';
  });
  console.log(`[web-e2e] Map loaded: ${loadedMap}`);

  if (!loadedMap.toLowerCase().includes(targetMap.toLowerCase())) {
    throw new Error(`Loaded map '${loadedMap}' does not match expected '${targetMap}'`);
  }

  if (errors.length > 0) {
    throw new Error(`Runtime errors detected:\n${errors.join('\n')}`);
  }

  console.log('[web-e2e] PASS');
} catch (err) {
  const tail = logs.slice(-200).join('\n');
  console.error('[web-e2e] FAIL:', err?.message || String(err));
  if (pageCrashed) {
    console.error('[web-e2e] Page crashed during run');
  }
  if (pageClosed) {
    console.error('[web-e2e] Page closed during run');
  }
  if (httpIssues.length > 0) {
    console.error('[web-e2e] HTTP/request issues:');
    console.error(httpIssues.join('\n'));
  }
  if (tail) {
    console.error('[web-e2e] Recent console output:');
    console.error(tail);
  }
  if (!page.isClosed()) {
    const stdoutTail = await page.evaluate(() => {
      const arr = Array.isArray(window.__mohaaStdout) ? window.__mohaaStdout : [];
      return arr.slice(-80);
    }).catch(() => []);
    if (stdoutTail.length > 0) {
      console.error('[web-e2e] Recent engine/stdout output:');
      console.error(stdoutTail.join('\n'));
    }
  }
  process.exitCode = 1;
} finally {
  await context.close();
  await browser.close();
}
