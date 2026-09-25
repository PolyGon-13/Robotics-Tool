// Shared Playwright helpers for driving the Flutter web build.
const { chromium } = require('playwright');

const APP_URL = process.env.APP_URL || 'http://localhost:8080/';
const ROS_HOST = process.env.ROS_HOST || 'localhost';
const ROS_PORT = Number(process.env.ROS_PORT || 9090);

async function launch({ dark = false } = {}) {
  const browser = await chromium.launch({ args: ['--enable-unsafe-swiftshader'] });
  const page = await browser.newPage({
    viewport: { width: Number(process.env.VIEW_W || 412), height: 860 },   // Android phone (dp); VIEW_W=360 for small phones
    deviceScaleFactor: 1,
    locale: 'en-US',                          // headless Chromium has no locale otherwise
    colorScheme: dark ? 'dark' : 'light',
  });
  const errors = [];
  // Name the step that produced an error (set by the scripts via errors.step)
  errors.step = '';
  page.on('pageerror', e => errors.push(e.message));
  page.on('console', m => {
    // Keep the first report in full (it has the stack); repeats are short
    if (/EXCEPTION|Assertion|Another exception|overflowed/i.test(m.text())) {
      errors.push(m.text().slice(0, errors.length ? 400 : 6000));
    }
  });
  await page.goto(APP_URL);
  await page.waitForSelector('flt-semantics', { state: 'attached', timeout: 30000 });
  await page.waitForTimeout(800);
  return { browser, page, errors };
}

const wait = (page, ms) => page.waitForTimeout(ms);

/** Visible semantic labels, for asserting what is on screen. */
function labels(page) {
  return page.$$eval('flt-semantics', es => [...new Set(es.map(e => {
    const aria = e.getAttribute('aria-label');
    if (aria) return aria.trim();
    // Leaf nodes: text lives directly inside (possibly wrapped in a span)
    return e.querySelector('flt-semantics') ? '' : (e.innerText || e.textContent || '').trim();
  }).filter(Boolean))]);
}

/** Replace a Flutter text field's content (fill() appends on Flutter web). */
async function setText(page, field, text) {
  await field.click();
  await page.keyboard.press('End');
  for (let i = 0; i < 64; i++) await page.keyboard.press('Backspace');
  await page.keyboard.type(text);
}

async function connect(page, { host = ROS_HOST, port = ROS_PORT } = {}) {
  await page.getByText('Topic Monitor').click();
  await wait(page, 1200);
  await setText(page, page.getByRole('textbox').first(), host);
  const portField = page.getByRole('textbox').nth(1);
  if (await portField.count()) await setText(page, portField, String(port));
  await wait(page, 200);
  await page.getByRole('button', { name: /^connect$/i }).last().click();
  await wait(page, 3500);
}

/** Tap a topic in the list; handles the older UI that showed an action sheet first. */
const escapeRe = s => s.replace(/[.*+?^${}()|[\]\\/]/g, '\\$&');

/** The list tile for [topic] (its accessible name starts with the topic name). */
const topicTile = (page, topic) =>
  page.getByRole('button', { name: new RegExp('^' + escapeRe(topic) + '\\s') }).first();

/**
 * Bring [locator] into the visible list area by scrolling with the mouse
 * wheel (Flutter web lists do not react to DOM scrollIntoView), then return
 * its box.
 */
async function scrollTo(page, locator, { top = 150, bottom = 760 } = {}) {
  let dir = 1; // lazily built lists: off-screen items do not exist yet
  let lastSig = '';
  for (let i = 0; i < 30; i++) {
    const box = (await locator.count()) ? await locator.boundingBox() : null;
    if (box && box.y >= top && box.y + box.height <= bottom) return box;
    let dy;
    if (box) {
      dy = box.y - (top + bottom) / 2;
    } else {
      const sig = JSON.stringify(await labels(page));
      if (sig === lastSig) dir = -dir; // hit the end: turn around
      lastSig = sig;
      dy = 400 * dir;
    }
    await page.mouse.move(206, 450);
    await page.mouse.wheel(0, Math.max(-600, Math.min(600, dy)));
    await wait(page, 350);
  }
  throw new Error('could not scroll element into view');
}

async function openEcho(page, topic) {
  const box = await scrollTo(page, topicTile(page, topic));
  await page.mouse.click(box.x + box.width / 3, box.y + box.height / 2);
  await wait(page, 700);
  const echo = page.getByText('Topic Echo');
  if (await echo.count()) await echo.first().click();
  await wait(page, 3000);
}

/** Click the center of [locator] with the mouse (Flutter web may fail Playwright's actionability checks). */
async function tap(page, locator) {
  const box = await locator.first().boundingBox({ timeout: 5000 });
  if (!box) throw new Error('element has no box');
  await page.mouse.click(box.x + box.width / 2, box.y + box.height / 2);
  await wait(page, 500);
}

/** Open the action sheet of a topic in the list. */
async function openActions(page, topic) {
  const box = await scrollTo(page, page.getByRole('button', { name: `More actions for ${topic}` }));
  await page.mouse.click(box.x + box.width / 2, box.y + box.height / 2);
  await wait(page, 700);
}

async function back(page) {
  await tap(page, page.getByRole('button', { name: 'Back' }));
  await wait(page, 500);
}

module.exports = { launch, wait, labels, connect, back, openEcho, openActions, topicTile, setText, tap };
