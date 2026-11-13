// Browser smoke test: serves a web bundle, mocks the Poki SDK, drives Edge/Chrome over CDP.
// Usage:
//   node tools/web_smoke.js <bundle_dir> <out_dir> [--size=405x720] [--screen=home|cards|map|shop|quests|battle|pvp|chest|win|road|stage|trial|trial_battle|trial_win]
//        [--secs=7] [--lang=ru] [--fresh=1] [--cfg=pvp.autoplay=1] [--steps="wait:2;click:200,640;shot:after;drag:100,300,160,300"]
// Without --steps it waits --secs and saves <screen>_<WxH>.png. Lua errors (ERROR:SCRIPT) are counted.
const fs = require('fs');
const path = require('path');
const http = require('http');
const { spawn } = require('child_process');

const [, , BUNDLE, OUT, ...rest] = process.argv;
const opt = { size: '405x720', secs: '7', screen: '', lang: 'ru', fresh: '1', steps: '' };
for (const a of rest) {
  const m = a.match(/^--(\w+)=(.*)$/);
  if (m) opt[m[1]] = m[2];
}
const [VW, VH] = opt.size.split('x').map(Number);
const PORT = 8760 + Math.floor(Math.random() * 400);
const DBG_PORT = 9360 + Math.floor(Math.random() * 400);
const BROWSER = (process.env.BROWSER_PATH && fs.existsSync(process.env.BROWSER_PATH) ? process.env.BROWSER_PATH : null) || [
  'C:/Program Files (x86)/Microsoft/Edge/Application/msedge.exe',
  'C:/Program Files/Microsoft/Edge/Application/msedge.exe',
  'C:/Program Files/Google/Chrome/Application/chrome.exe',
  'C:/Program Files (x86)/Google/Chrome/Application/chrome.exe',
  ...(() => {
    try {
      const coreDir = 'C:/Program Files (x86)/Microsoft/EdgeCore';
      if (fs.existsSync(coreDir)) {
        const sub = fs.readdirSync(coreDir).filter(f => fs.existsSync(path.join(coreDir, f, 'msedge.exe'))).pop();
        if (sub) return [path.join(coreDir, sub, 'msedge.exe')];
      }
    } catch {}
    return [];
  })(),
].find(p => p && fs.existsSync(p));

if (!BROWSER) { console.error('No Edge/Chrome found'); process.exit(1); }
fs.mkdirSync(OUT, { recursive: true });

const POKI_MOCK = `<script>
window.PokiSDK = {
  init: () => Promise.resolve(),
  gameLoadingProgress() {}, gameLoadingFinished() { console.log('[poki] loaded'); },
  gameplayStart() { console.log('[poki] gameplayStart'); },
  gameplayStop() { console.log('[poki] gameplayStop'); },
  commercialBreak(cb) { console.log('[poki] commercialBreak'); if (cb) cb(); return Promise.resolve(); },
  rewardedBreak() { console.log('[poki] rewardedBreak'); return Promise.resolve(true); },
  measure(a, b, c) { console.log('[poki] measure', a, b, c); },
  setDebug() {}, captureError(e) { console.log('[poki] err', e); },
  getURLParam() { return null; }, getDeviceInfo() { return { category: 'mobile' }; }, movePill() {},
};
window.addEventListener('load', () => setTimeout(() => { if (window.poki_sdk_loaded) poki_sdk_loaded(); }, 40));
</script>`;

function patchedIndex() {
  let html = fs.readFileSync(path.join(BUNDLE, 'index.html'), 'utf8');
  html = html.replace(/<script[^>]*poki-sdk[^>]*><\/script>/, POKI_MOCK);
  const args = [];
  if (opt.fresh === '1') args.push('--config=pvp.fresh=1');
  if (opt.screen) args.push(`--config=pvp.debug_screen=${opt.screen}`);
  if (opt.lang) args.push(`--config=pvp.lang=${opt.lang}`);
  // Extra engine config, e.g. --cfg=pvp.autoplay=1,pvp.time_offset=3600
  if (opt.cfg) for (const kv of opt.cfg.split(',')) args.push(`--config=${kv}`);
  const re = /(<script id=["']engine-setup["'] type=["']text\/javascript["']>)/;
  if (!re.test(html)) console.error('WARN: engine-setup script tag not found, parameters not injected');
  html = html.replace(re, `$1\nCUSTOM_PARAMETERS["engine_arguments"] = ${JSON.stringify(args)};`);
  return html;
}

const MIME = { '.html': 'text/html', '.js': 'application/javascript', '.wasm': 'application/wasm', '.css': 'text/css', '.png': 'image/png', '.json': 'application/json', '.wav': 'audio/wav' };
const srv = http.createServer((req, res) => {
  const url = decodeURIComponent(req.url.split('?')[0]);
  if (url === '/' || url === '/index.html') {
    res.writeHead(200, { 'Content-Type': 'text/html' });
    res.end(patchedIndex());
    return;
  }
  const fp = path.join(BUNDLE, url);
  if (fs.existsSync(fp) && fs.statSync(fp).isFile()) {
    res.writeHead(200, { 'Content-Type': MIME[path.extname(fp)] || 'application/octet-stream' });
    fs.createReadStream(fp).pipe(res);
  } else { res.writeHead(404); res.end(); }
});

srv.listen(PORT, '127.0.0.1', async () => {
  const userData = path.resolve(OUT, '_prof_' + PORT);
  const proc = spawn(BROWSER, [
    '--headless=new', '--disable-gpu', '--autoplay-policy=no-user-gesture-required', `--remote-debugging-port=${DBG_PORT}`,
    `--window-size=${VW},${VH}`, `--user-data-dir=${userData}`,
    '--no-first-run', '--no-default-browser-check', `http://127.0.0.1:${PORT}/`,
  ], { stdio: 'ignore' });

  const sleep = ms => new Promise(r => setTimeout(r, ms));
  let ws;
  for (let i = 0; i < 40; i++) {
    await sleep(250);
    try {
      const list = await (await fetch(`http://127.0.0.1:${DBG_PORT}/json`)).json();
      const page = list.find(t => t.type === 'page');
      if (page) { ws = new WebSocket(page.webSocketDebuggerUrl); break; }
    } catch {}
  }
  if (!ws) { proc.kill(); srv.close(); console.error('CDP connect failed'); process.exit(1); }

  let msgId = 0;
  let luaErrors = 0;
  const cdp = (method, params = {}) => new Promise(res => {
    const id = ++msgId;
    const onMsg = ev => {
      const d = JSON.parse(ev.data);
      if (d.id === id) { ws.removeEventListener('message', onMsg); res(d.result); }
    };
    ws.addEventListener('message', onMsg);
    ws.send(JSON.stringify({ id, method, params }));
  });
  ws.addEventListener('message', ev => {
    const d = JSON.parse(ev.data);
    if (d.method === 'Runtime.consoleAPICalled') {
      const line = d.params.args.map(a => a.value || a.description).join(' ');
      if (/ERROR|WARNING:SCRIPT|stack traceback/.test(line)) { luaErrors++; console.log('[console]', line); }
      else if (process.env.SMOKE_VERBOSE || /\[poki\]/.test(line)) console.log('[console]', line.trim());
    } else if (d.method === 'Runtime.exceptionThrown') {
      luaErrors++;
      console.error('[js-err]', d.params.exceptionDetails.text, d.params.exceptionDetails.exception && d.params.exceptionDetails.exception.description);
    }
  });

  await new Promise(r => ws.addEventListener('open', r));
  await cdp('Runtime.enable');
  await cdp('Emulation.setDeviceMetricsOverride', { width: VW, height: VH, deviceScaleFactor: 1, mobile: VW < VH });

  const shot = async name => {
    const s = await cdp('Page.captureScreenshot', { format: 'png' });
    const p = path.join(OUT, `${name}_${VW}x${VH}.png`);
    fs.writeFileSync(p, Buffer.from(s.data, 'base64'));
    console.log('Saved screenshot:', p);
  };
  const mouse = (type, x, y) => cdp('Input.dispatchMouseEvent', { type, x, y, button: 'left', clickCount: 1 });
  const touch = (type, touchPoints) => cdp('Input.dispatchTouchEvent', { type, touchPoints });

  if (!opt.steps) {
    await sleep(Number(opt.secs) * 1000);
    await shot(opt.screen || 'boot');
  } else {
    for (const step of opt.steps.split(';').filter(Boolean)) {
      const [cmd, arg = ''] = step.split(':');
      const n = arg.split(',').map(Number);
      if (cmd === 'wait') await sleep(n[0] * 1000);
      else if (cmd === 'shot') await shot(arg || 'step');
      else if (cmd === 'click') {
        await mouse('mouseMoved', n[0], n[1]);
        await mouse('mousePressed', n[0], n[1]);
        await sleep(80);
        await mouse('mouseReleased', n[0], n[1]);
        await sleep(150);
      } else if (cmd === 'touchtap') {
        await cdp('Emulation.setTouchEmulationEnabled', { enabled: true });
        await touch('touchStart', [{ x: n[0], y: n[1], id: 0 }]);
        await sleep(80);
        await touch('touchEnd', []);
        await sleep(150);
      } else if (cmd === 'touchdrag') {
        await cdp('Emulation.setTouchEmulationEnabled', { enabled: true });
        await touch('touchStart', [{ x: n[0], y: n[1], id: 0 }]);
        for (let k = 1; k <= 6; k++) {
          await sleep(25);
          await touch('touchMove', [{ x: n[0] + (n[2] - n[0]) * k / 6, y: n[1] + (n[3] - n[1]) * k / 6, id: 0 }]);
        }
        await touch('touchEnd', []);
        await sleep(150);
      } else if (cmd === 'drag') {
        await mouse('mouseMoved', n[0], n[1]);
        await mouse('mousePressed', n[0], n[1]);
        for (let k = 1; k <= 6; k++) {
          await sleep(25);
          await mouse('mouseMoved', n[0] + (n[2] - n[0]) * k / 6, n[1] + (n[3] - n[1]) * k / 6);
        }
        await mouse('mouseReleased', n[2], n[3]);
        await sleep(150);
      }
    }
  }
  console.log(`Lua/JS errors: ${luaErrors}`);
  ws.close();
  proc.kill();
  srv.close();
  try { fs.rmSync(userData, { recursive: true, force: true }); } catch {}
});
