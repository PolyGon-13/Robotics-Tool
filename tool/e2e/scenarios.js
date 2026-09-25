// Connection-lifecycle scenarios with pass/fail checks.
// Needs the mock server (tool/e2e/mock_rosbridge.py) and the web build running.
// Usage: node tool/e2e/scenarios.js [scenarioName ...]
const { execSync } = require('child_process');
const fs = require('fs');
const { launch, wait, labels, connect, openEcho, openActions } = require('./lib');

const mockPid = () => Number(process.env.MOCK_PID ||
  execSync("pgrep -o -f 'python3 .*mock_rosbridge.py'").toString().trim());
const signalMock = sig => process.kill(mockPid(), sig);
const MOCK_LOG = process.env.MOCK_LOG || 'mock.log';
/** Mock-server log lines appended after [fromLine]. */
const mockOps = fromLine => fs.readFileSync(MOCK_LOG, 'utf8').trim().split('\n')
  .slice(fromLine).map(l => { try { return JSON.parse(l); } catch { return {}; } });
const logLength = () => fs.existsSync(MOCK_LOG) ? fs.readFileSync(MOCK_LOG, 'utf8').trim().split('\n').length : 0;

const has = (ls, re) => ls.some(l => re.test(l));

const SCENARIOS = {
  // Joystick drives /cmd_vel while held and sends zero on release.
  async joystickPublishesAndStops(page) {
    if (!fs.existsSync(MOCK_LOG)) throw new Error(`set MOCK_LOG (mock server stdout), tried ${MOCK_LOG}`);
    await connect(page);
    await openActions(page, '/cmd_vel');
    await page.getByRole('button', { name: /^Publish/ }).click();
    await wait(page, 1500);
    const start = logLength();
    // The pad (280 px) sits 16 px above the STOP button, centered horizontally
    const stop = await page.getByRole('button', { name: /STOP/ }).boundingBox();
    const cx = stop.x + stop.width / 2, cy = stop.y - 16 - 140;
    await page.mouse.move(cx, cy);
    await page.mouse.down();
    await page.mouse.move(cx, cy - 100, { steps: 5 });
    await wait(page, 800);
    await page.mouse.up();
    await wait(page, 600);
    const pubs = mockOps(start).filter(o => o.op === 'publish' && o.topic === '/cmd_vel');
    const moving = pubs.filter(o => o.lin > 0);
    if (moving.length < 3) throw new Error(`expected forward commands while held, got ${JSON.stringify(pubs.slice(0, 5))}`);
    const tail = pubs.slice(pubs.lastIndexOf(moving[moving.length - 1]) + 1);
    if (tail.length < 1 || tail.some(o => o.lin !== 0 || o.ang !== 0)) {
      throw new Error(`expected only zero commands after release, got ${JSON.stringify(tail)}`);
    }
  },

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

  // Link dies without closing the socket: the app must drop it on its own
  // (keepalive probe) and warn, then recover when the server answers again.
  async deadLinkDetected(page) {
    await connect(page);
    await openEcho(page, '/battery_voltage');
    const from = logLength();
    signalMock('SIGHUP');             // server stops answering, sockets stay open
    try {
      await wait(page, 8000);         // 3 s idle + 2 s probe + slack
      const ops = mockOps(from);
      const silentAt = ops.findIndex(o => o.ev === 'silent');
      const dropped = ops.slice(silentAt).find(o => o.ev === 'client_disconnected');
      if (silentAt < 0 || !dropped) throw new Error('app did not drop the dead connection');
      const delay = dropped.t - ops[silentAt].t;
      if (delay > 7) throw new Error(`dead link detected only after ${delay.toFixed(1)} s`);
      const ls = await labels(page);
      if (!has(ls, /Disconnected|reconnecting|No data/i)) {
        throw new Error(`no warning on screen; labels=${JSON.stringify(ls).slice(0, 300)}`);
      }
    } finally {
      signalMock('SIGHUP');           // back to normal
    }
    await wait(page, 9000);
    const a = await page.screenshot();
    await wait(page, 2500);
    if (a.equals(await page.screenshot())) throw new Error('stream did not resume after the link came back');
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
