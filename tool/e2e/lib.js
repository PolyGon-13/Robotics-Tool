// Shared Playwright helpers for driving the Flutter web build.
const { chromium } = require('playwright');

const APP_URL = process.env.APP_URL || 'http://localhost:8080/';
const ROS_HOST = process.env.ROS_HOST || 'localhost';

async function launch({ dark = false } = {}) {
  const browser = await chromium.launch({ args: ['--enable-unsafe-swiftshader'] });
  const page = await browser.newPage({
    viewport: { width: 412, height: 860 },   // typical Android phone (dp)
    deviceScaleFactor: 1,
    locale: 'en-US',                          // headless Chromium has no locale otherwise
    colorScheme: dark ? 'dark' : 'light',
  });
  const errors = [];
  page.on('pageerror', e => errors.push(e.message));
  page.on('console', m => {
    if (/EXCEPTION|Assertion|Another exception|overflowed/i.test(m.text())) errors.push(m.text().slice(0, 400));
  });
  await page.goto(APP_URL);
  await page.waitForSelector('flt-semantics', { state: 'attached', timeout: 30000 });
  await page.waitForTimeout(800);
  return { browser, page, errors };
}

const wait = (page, ms) => page.waitForTimeout(ms);

/** Visible semantic labels, for asserting what is on screen. */
function labels(page) {
  return page.$$eval('flt-semantics', es => [...new Set(es.map(e =>
    (e.getAttribute('aria-label') ||
      (e.childNodes.length === 1 && e.firstChild.nodeType === 3 ? e.textContent : '') || '').trim()
  ).filter(Boolean))]);
}

async function connect(page, { host = ROS_HOST } = {}) {
  await page.getByText('Topic Monitor').click();
  await wait(page, 1200);
  const ip = page.getByRole('textbox').first();
  await ip.click();
  await ip.fill(host);
  await wait(page, 200);
  await page.getByRole('button', { name: /^connect$/i }).last().click();
  await wait(page, 3500);
}

async function back(page) {
  await page.getByRole('button', { name: 'Back' }).first().click();
  await wait(page, 800);
}

module.exports = { launch, wait, labels, connect, back };
