import { chromium } from 'playwright';

const browser = await chromium.launch({
  headless: true,
  executablePath: '/snap/bin/chromium',
});
const ctx = await browser.newContext();
const page = await ctx.newPage();
const errors = [];
const warnings = [];

page.on('console', (msg) => {
  const t = msg.text();
  if (msg.type() === 'error') errors.push(t.slice(0, 300));
  if (
    t.includes('TLS init stub') ||
    t.includes('_ZTH') ||
    t.includes('RangeError') ||
    t.includes('CxxException')
  )
    warnings.push('[' + msg.type() + '] ' + t.slice(0, 300));
});
page.on('pageerror', (e) =>
  errors.push('[pageerror] ' + e.message.slice(0, 300))
);

await page.goto(
  'http://127.0.0.1:8086/mohaa.html?connect=78.108.16.74:12203&webdriver=1'
);
await page.waitForTimeout(2000);
await page.click('#mohaa-play-btn').catch(() => {});
await page.waitForTimeout(1000);
await page.click('#mohaa-skip-btn').catch(() => {});

for (let i = 0; i < 8; i++) {
  await page.waitForTimeout(5000);
  const state = await page.evaluate(() => ({
    init: !!window.__mohaaEngineInit,
    sv:
      typeof window.__mohaaServerState === 'number'
        ? window.__mohaaServerState
        : -1,
    map: window.__mohaaMapLoaded || null,
  }));
  console.log(
    't=' + (i + 1) * 5 + 's init=' + state.init + ' sv=' + state.sv + ' map=' + state.map
  );
  if (state.map) break;
}

console.log('--- TLS/RangeError messages ---');
for (const w of warnings.slice(0, 15)) console.log(w);
console.log('--- Errors (' + errors.length + ' total, unique) ---');
const uniqueErr = [...new Set(errors)].slice(0, 10);
for (const e of uniqueErr) console.log(e);
await browser.close();
