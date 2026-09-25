// Screenshot every screen and every topic visualization.
// Usage: node tool/e2e/audit.js <outDir> [dark]
const fs = require('fs');
const path = require('path');
const { launch, wait, labels, connect, back, openEcho, setText, openActions, tap } = require('./lib');

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
  let lastErrors = 0;
  const shot = async name => {
    await page.screenshot({ path: `${out}/${name}${suffix}.png` });
    if (errors.length > lastErrors) {
      console.log(`!! errors while on ${name}: ${errors.length - lastErrors}`);
      lastErrors = errors.length;
    }
    console.log(`[${name}]`, JSON.stringify(await labels(page)).slice(0, 300));
  };
  // Return to the Topics tab after a failed step so later steps can run
  const recover = async () => {
    for (let i = 0; i < 4; i++) {
      await page.keyboard.press('Escape').catch(() => {});
      await wait(page, 300);
      if (await page.getByRole('tab', { name: 'Topics' }).count()) {
        await page.getByRole('tab', { name: 'Topics' }).click();
        return;
      }
      const backBtn = page.getByRole('button', { name: 'Back' });
      if (await backBtn.count()) await backBtn.first().click().catch(() => {});
      await wait(page, 600);
    }
  };
  const step = async (name, fn) => {
    try { await fn(); } catch (e) {
      console.log(`!! ${name}: ${e.message.split('\n')[0]}`);
      await page.screenshot({ path: `${out}/FAIL_${name.replace(/\//g, '_')}${suffix}.png` }).catch(() => {});
      await recover();
    }
  };

  await shot('00_home');

  // Model viewer with the sample files (works without a robot)
  const MODELS = [
    ['50_model_urdf', ['arm.urdf']],
    ['51_model_stl', ['cube.stl']],
    ['52_model_dae', ['pyramid.dae']],
    ['53_model_urdf_meshes', ['mesh_robot.urdf', 'cube.stl', 'pyramid.dae']],
    ['54_model_urdf_missing_meshes', ['mesh_robot.urdf']],
  ];
  for (const [name, files] of MODELS) {
    await step(name, async () => {
      await page.getByText('Model Viewer').click();
      await wait(page, 1200);
      const [chooser] = await Promise.all([
        page.waitForEvent('filechooser'),
        page.getByRole('button', { name: /Load File/ }).click(),
      ]);
      await chooser.setFiles(files.map(f => path.join(__dirname, 'models', f)));
      await wait(page, 2500);
      await shot(name);
      await back(page);
    });
  }

  // Connection errors: nothing listens on port 1
  await step('connect-fail', async () => {
    await page.getByText('Topic Monitor').click();
    await wait(page, 1200);
    await setText(page, page.getByRole('textbox').first(), 'localhost:1');
    await page.getByRole('button', { name: /^connect$/i }).last().click();
    await wait(page, 9000);
    await shot('01_connect_failed');
    await back(page);
  });

  await connect(page);
  await shot('02_topics');

  for (const [i, topic] of TOPICS.entries()) {
    await step(topic, async () => {
      await openEcho(page, topic);
      const name = `1${String(i).padStart(2, '0')}_echo${topic.replace(/\//g, '_')}`;
      await shot(name);
      // Second shot further down for long visualizations
      await page.mouse.move(206, 500);
      await page.mouse.wheel(0, 650);
      await wait(page, 600);
      await page.screenshot({ path: `${out}/${name}_scrolled${suffix}.png` });
      await back(page);
    });
  }

  await step('publish', async () => {
    await openActions(page, '/cmd_vel');
    await shot('19_topic_actions');
    await page.getByRole('button', { name: /^Publish/ }).click();
    await wait(page, 1500);
    await shot('20_publish_joystick');
    await tap(page, page.getByRole('button', { name: 'JSON' }));
    await wait(page, 1000);
    await shot('21_publish_json');
    await back(page);
  });

  await step('publish-template', async () => {
    await openActions(page, '/goal_pose');
    await page.getByRole('button', { name: /^Publish/ }).click();
    await wait(page, 2000);
    await shot('22_publish_pose_template');
    await back(page);
  });

  await step('graph', async () => {
    await openActions(page, '/scan');
    await page.getByRole('button', { name: /^Show in Graph/ }).click();
    await wait(page, 2500);
    await shot('30_graph_highlight');
    // Tap the middle of the canvas area to hit a node is unreliable; open via fit + tap first node label
    await page.getByRole('button', { name: 'Fit to screen' }).click();
    await wait(page, 800);
    await shot('31_graph_fit');
  });

  await step('settings', async () => {
    await page.getByRole('button', { name: 'Settings' }).first().click();
    await wait(page, 1000);
    await shot('40_settings');
  });

  console.log('errors:', errors.length ? errors : 'none');
  await browser.close();
})();
