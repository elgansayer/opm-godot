import { chromium } from 'playwright'

const browser = await chromium.launch({
  headless: true,
  executablePath: process.env.PLAYWRIGHT_EXECUTABLE_PATH || '/usr/bin/google-chrome',
  args: ['--no-sandbox', '--disable-dev-shm-usage'],
})
const page = await browser.newPage()
const failed = []
const pageErrors = []
const consoleLines = []

page.on('response', (resp) => {
  if (resp.status() >= 400) {
    failed.push(`${resp.status()} ${resp.url()}`)
  }
})
page.on('pageerror', (err) => pageErrors.push(String((err && err.stack) || err)))
page.on('console', (msg) => consoleLines.push(`[${msg.type()}] ${msg.text()}`))

const url = 'http://127.0.0.1:8086/mohaa.html?map=dm%2Fmohdm1&com_target_game=0'
await page.goto(url, { waitUntil: 'domcontentloaded', timeout: 120000 })
await page.click('#mohaa-play-btn')
await page.click('#mohaa-skip-btn')
await page.waitForTimeout(15000)

const state = await page.evaluate(() => ({
  title: document.title,
  startupArgs: window.__mohaaStartupArgs || null,
  launchMap: window.__mohaaLaunchMap || null,
  engineError: window.__mohaaEngineError || null,
  mapLoaded: window.__mohaaMapLoaded || null,
  mapLoadedLog: window.__mohaaMapLoadedLog || null,
  stdoutTail: Array.isArray(window.__mohaaStdout) ? window.__mohaaStdout.slice(-50) : null,
  targetGame: window.__mohaaTargetGame,
  gameDir: window.__mohaaGameDir || null,
  hasModule: typeof window.Module !== 'undefined',
  loaderDisplay: document.getElementById('mohaa-loader')?.style.display || null,
}))

console.log('STATE', JSON.stringify(state, null, 2))
console.log('FAILED_RESPONSES')
for (const line of failed) console.log(line)
console.log('PAGE_ERRORS')
for (const line of pageErrors.slice(0, 20)) console.log(line)
console.log('CONSOLE_TAIL')
for (const line of consoleLines.slice(-120)) console.log(line)

await browser.close()
