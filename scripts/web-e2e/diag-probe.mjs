/**
 * Quick diagnostic probe — runs against the current live web export to
 * determine what state the engine is stuck in and capture useful info.
 */
import { chromium } from 'playwright';

const baseUrl = process.env.BASE_URL || 'http://127.0.0.1:8086';
const url = new URL('/mohaa.html', baseUrl);
url.searchParams.set('map', 'dm/mohdm1');
url.searchParams.set('com_target_game', '0');
url.searchParams.set('webdriver', '1');

const httpIssues = [];
const consoleErrors = [];
const allLogs = [];

const browser = await chromium.launch({ headless: true, executablePath: '/usr/bin/chromium-browser' });
const page = await browser.newPage();

page.on('console', (msg) => {
  const text = msg.text();
  allLogs.push(`[${msg.type()}] ${text}`);
  if (msg.type() === 'error') consoleErrors.push(text);
});

page.on('response', (response) => {
  if (response.status() >= 400) {
    httpIssues.push(`HTTP ${response.status()}: ${response.request().method()} ${response.url()}`);
    console.log(`[404+] HTTP ${response.status()}: ${response.url()}`);
  }
});

page.on('requestfailed', (request) => {
  httpIssues.push(`FAILED: ${request.method()} ${request.url()} :: ${request.failure()?.errorText}`);
});

console.log(`Navigating to ${url.toString()}`);
await page.goto(url.toString(), { waitUntil: 'domcontentloaded', timeout: 60000 });

// Click through the loader
await page.waitForSelector('#mohaa-loader', { state: 'visible', timeout: 30000 }).catch(() => {});
const playBtn = await page.locator('#mohaa-play-btn').isVisible().catch(() => false);
if (playBtn) { console.log('Clicking Play'); await page.click('#mohaa-play-btn'); }
await new Promise(r => setTimeout(r, 2000));
const skipBtn = await page.locator('#mohaa-skip-btn').isVisible().catch(() => false);
if (skipBtn) { console.log('Clicking Skip'); await page.click('#mohaa-skip-btn'); }

console.log('Waiting 30s for engine to boot and load map...');

// Poll engine state every 5 seconds for 30 seconds
for (let i = 0; i < 6; i++) {
  await new Promise(r => setTimeout(r, 5000));
  
  const state = await page.evaluate(() => ({
    // New continuous state vars (from updated Main.gd)
    serverState: typeof window.__mohaaServerState === 'number' ? window.__mohaaServerState : 'N/A',
    currentMap: typeof window.__mohaaCurrentMap === 'string' ? window.__mohaaCurrentMap : 'N/A',
    engineInit: !!window.__mohaaEngineInit,
    // Existing vars
    mapLoaded: typeof window.__mohaaMapLoaded === 'string' ? window.__mohaaMapLoaded : null,
    engineError: typeof window.__mohaaEngineError === 'string' ? window.__mohaaEngineError : null,
    startupArgs: typeof window.__mohaaStartupArgs === 'string' ? window.__mohaaStartupArgs : null,
    launchMap: typeof window.__mohaaLaunchMap === 'string' ? window.__mohaaLaunchMap : null,
  })).catch(() => ({ error: 'page evaluate failed' }));

  console.log(`[${(i+1)*5}s] ${JSON.stringify(state)}`);
  
  if (state.mapLoaded) {
    console.log('Map loaded! Done.');
    break;
  }
  if (state.engineError) {
    console.log('Engine error detected! Stopping.');
    break;
  }
}

// Capture recent stdout
const stdout = await page.evaluate(() => {
  const arr = Array.isArray(window.__mohaaStdout) ? window.__mohaaStdout : [];
  return arr.slice(-100);
}).catch(() => []);

console.log('\n=== HTTP Issues ===');
if (httpIssues.length > 0) {
  for (const issue of httpIssues) console.log(issue);
} else {
  console.log('(none)');
}

console.log('\n=== Console Errors ===');
if (consoleErrors.length > 0) {
  for (const err of consoleErrors) console.log(err);
} else {
  console.log('(none)');
}

console.log('\n=== Recent Engine Stdout (last 100 lines) ===');
if (stdout.length > 0) {
  for (const line of stdout) console.log(line);
} else {
  console.log('(no stdout captured — __mohaaStdout may not be set up)');
}

console.log('\n=== Last 50 Console Logs ===');
for (const log of allLogs.slice(-50)) console.log(log);

await browser.close();
