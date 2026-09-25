// Screenshot every screen and every topic visualization.
// Usage: node tool/e2e/audit.js <outDir> [dark]
const fs = require('fs');
const { launch, wait, labels, connect, back } = require('./lib');

const out = process.argv[2] || 'e2e-shots';
const dark = process.argv[3] === 'dark';
const suffix = dark ? '_dark' : '';
fs.mkdirSync(out, { recursive: true });

const TOPICS = [
  '/scan', '/odom', '/cmd_vel', '/imu/data', '/joint_states', '/battery_state',
  '/battery_voltage', '/camera/image_raw', '/camera/image_raw/compressed', '/camera/depth/image_raw',
  '/ultrasonic/front', '/goal_pose', '/robot_status', '/emergency_stop', '/tf',
];

(async () => {
  const { browser, page, errors } = await launch({ dark });
  const shot = async name => {
    await page.screenshot({ path: `${out}/${name}${suffix}.png` });
    console.log(`[${name}]`, JSON.stringify(await labels(page)).slice(0, 300));
  };

  await shot('00_home');
  await connect(page);
  await shot('02_topics');

  for (const [i, topic] of TOPICS.entries()) {
    try {
      const item = page.getByText(topic, { exact: false }).first();
      await item.scrollIntoViewIfNeeded();
      await item.click();
      await wait(page, 700);
      await page.getByText(/Topic Echo|Echo|Visualize/).first().click();
      await wait(page, 3500);
      const name = `1${String(i).padStart(2, '0')}_echo${topic.replace(/\//g, '_')}`;
      await shot(name);
      // Second shot further down for long visualizations
      await page.mouse.move(206, 500);
      await page.mouse.wheel(0, 650);
      await wait(page, 600);
      await page.screenshot({ path: `${out}/${name}_scrolled${suffix}.png` });
      await back(page);
    } catch (e) {
      console.log(`!! ${topic}: ${e.message.split('\n')[0]}`);
      await page.keyboard.press('Escape').catch(() => {});
    }
  }

  // Publish screen for /cmd_vel
  try {
    await page.getByText('/cmd_vel').first().click();
    await wait(page, 700);
    await page.getByText('Publish').first().click();
    await wait(page, 1500);
    await shot('20_publish_cmd_vel');
    await back(page);
  } catch (e) { console.log('!! publish:', e.message.split('\n')[0]); }

  await page.getByRole('tab', { name: 'Graph' }).click();
  await wait(page, 2500);
  await shot('30_graph');

  await page.getByRole('button', { name: 'Settings' }).first().click();
  await wait(page, 1000);
  await shot('40_settings');

  console.log('errors:', errors.length ? errors : 'none');
  await browser.close();
})();
