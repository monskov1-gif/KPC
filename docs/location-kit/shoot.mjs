// Screenshots for the critic cycle.
//   node shoot.mjs <url> <out-prefix> '<json shots>'
//   shots: [{ "name": "evening", "state": "evening", "cam": [0,1.6,4.6], "look": [0,1,-1.6], "js": "…" }, …]
// Needs a static server in the folder with the page (e.g. `python3 -m http.server 8765`) and Playwright
// (PWPATH = path to the playwright package, e.g. `export PWPATH=$(npm root -g)/playwright`).
// Software GL (swiftshader) is slow: shoot sequentially, never in parallel; use ?low=1 there.
import { createRequire } from 'module';
const require = createRequire(import.meta.url);
const { chromium } = require(process.env.PWPATH || 'playwright');
const [url, prefix, json = '[{"name":"evening","state":"evening"}]', w = '1280', h = '760'] = process.argv.slice(2);
const shots = JSON.parse(json);
const b = await chromium.launch({ args: ['--use-gl=angle', '--use-angle=swiftshader', '--enable-unsafe-swiftshader'] });
const p = await b.newPage({ viewport: { width: +w, height: +h } });
const errs = [];
p.on('pageerror', (e) => errs.push(e.message));
p.on('console', (m) => { if (m.type() === 'error') errs.push(m.text()); });
for (const s of shots) {
  const q = new URLSearchParams();
  if (s.state) q.set('state', s.state);
  if (s.cam) q.set('cam', s.cam.join(','));
  if (s.look) q.set('look', s.look.join(','));
  for (const [k, v] of Object.entries(s.params || {})) q.set(k, v);
  await p.goto(`${url}${url.includes('?') ? '&' : '?'}${q}`);
  await p.waitForFunction(() => window.__ready, null, { timeout: 120000 });
  if (s.js) await p.evaluate(s.js);
  await p.waitForTimeout(+(process.env.WAIT || 1200));
  const out = `${prefix}_${s.name}.png`;
  await p.screenshot({ path: out });
  console.log(out);
}
if (errs.length) console.log('ERRORS:\n' + errs.slice(0, 8).join('\n'));
await b.close();
