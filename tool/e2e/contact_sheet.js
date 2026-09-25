// Combine screenshots into one contact-sheet PNG for quick review.
// Usage: node tool/e2e/contact_sheet.js <out.png> <cols> <img...>
const fs = require('fs');
const path = require('path');
const { chromium } = require('playwright');
const [out, cols, ...imgs] = process.argv.slice(2);
(async () => {
  const b = await chromium.launch();
  const p = await b.newPage({ viewport: { width: 280 * Number(cols), height: 600 } });
  const cells = imgs.map(f => `<figure><img src="data:image/png;base64,${fs.readFileSync(f).toString('base64')}"><figcaption>${path.basename(f, '.png')}</figcaption></figure>`).join('');
  await p.setContent(`<style>body{margin:0;display:grid;grid-template-columns:repeat(${cols},280px);background:#ddd;font:11px sans-serif}
    figure{margin:4px}img{width:272px;display:block;border:1px solid #999}figcaption{padding:2px}</style>${cells}`);
  await p.waitForTimeout(500);
  await p.screenshot({ path: out, fullPage: true });
  await b.close();
})();
