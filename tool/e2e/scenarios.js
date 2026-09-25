// Connection-lifecycle scenarios with pass/fail checks.
// Needs the mock server (tool/e2e/mock_rosbridge.py) and the web build running.
// Usage: node tool/e2e/scenarios.js [scenarioName ...]
const { execSync } = require('child_process');
const { launch, wait, labels, connect } = require('./lib');

const mockPid = () => Number(process.env.MOCK_PID ||
  execSync("pgrep -o -f 'python3 .*mock_rosbridge.py'").toString().trim());
const signalMock = sig => process.kill(mockPid(), sig);

async function openEcho(page, topic) {
  await page.getByText(topic).first().click();
  await wait(page, 700);
  const echo = page.getByText('Topic Echo');
  if (await echo.count()) await echo.first().click();   // older UI: action sheet first
  await wait(page, 3000);
}

const has = (ls, re) => ls.some(l => re.test(l));

const SCENARIOS = {
  // Disconnect, stay idle past the 30s topic refresh, reconnect.
  async reconnectShowsTopics(page) {
    await connect(page);
    await page.getByRole('button', { name: 'Settings' }).first().click();
    await wait(page, 1000);
    await page.getByRole('button', { name: /disconnect/i }).click();
    await wait(page, 35000);
    await connect(page);
    await wait(page, 1500);
    const ls = await labels(page);
    if (has(ls, /Not connected/)) throw new Error('stale "Not connected" error after reconnect');
    if (!has(ls, /^\/scan/)) throw new Error('topic list empty after reconnect');
  },

  // Link drops while a topic is open: stream must resume after auto-reconnect.
  async streamResumesAfterDrop(page) {
    await connect(page);
    await openEcho(page, '/battery_voltage');
    await wait(page, 9000);            // past the initial 10s connect timeout
    signalMock('SIGUSR1');
    await wait(page, 6000);
    const a = await page.screenshot();
    await wait(page, 2500);
    const b = await page.screenshot();
    if (a.equals(b)) throw new Error('visualization frozen after reconnect');
  },

  // Link drops ~8.5s after connecting: reconnect must not be cancelled by the connect timeout.
  async dropNearConnectTimeout(page) {
    await connect(page);
    await wait(page, 4500);
    signalMock('SIGUSR1');
    await wait(page, 6000);
    const ls = await labels(page);
    if (has(ls, /^Topic Monitor$/)) throw new Error('kicked back to home screen');
  },

  // Publisher stalls: the echo screen must say data is stale.
  async staleDataWarning(page) {
    await connect(page);
    await openEcho(page, '/battery_voltage');
    signalMock('SIGUSR2');             // pause streams
    try {
      await wait(page, 5000);
      const ls = await labels(page);
      if (!has(ls, /No data/i)) throw new Error(`no stale-data warning; labels=${JSON.stringify(ls).slice(0, 300)}`);
    } finally {
      signalMock('SIGUSR2');           // resume
    }
    await wait(page, 2000);
    if (has(await labels(page), /No data/i)) throw new Error('stale warning did not clear after resume');
  },
};

(async () => {
  const names = process.argv.slice(2).length ? process.argv.slice(2) : Object.keys(SCENARIOS);
  let failed = 0;
  for (const name of names) {
    const { browser, page, errors } = await launch();
    try {
      await SCENARIOS[name](page);
      if (errors.length) throw new Error(`Flutter errors: ${errors.slice(0, 3).join(' | ')}`);
      console.log(`PASS ${name}`);
    } catch (e) {
      failed++;
      console.log(`FAIL ${name}: ${e.message}`);
      await page.screenshot({ path: `e2e-fail-${name}.png` }).catch(() => {});
    } finally {
      await browser.close();
    }
  }
  process.exit(failed ? 1 : 0);
})();
