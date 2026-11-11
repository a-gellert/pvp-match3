// Browser smoke test: serves bundle/web, mocks Poki SDK, captures screenshots via Edge/Chrome CDP.
// Usage: node tools/web_smoke.js <bundle_dir> <out_dir> [--size=360x720] [--screen=battle|hub|map|shop] [--secs=8]
const fs = require('fs');
const path = require('path');
const http = require('http');
const { spawn } = require('child_process');

const [, , BUNDLE, OUT, ...rest] = process.argv;
const opt = { size: '360x720', secs: '7', screen: '', lang: 'ru' };
for (const a of rest) {
  const m = a.match(/^--(\w+)=(.*)$/);
  if (m) opt[m[1]] = m[2];
}
const [VW, VH] = opt.size.split('x').map(Number);
const PORT = 8760 + Math.floor(Math.random() * 100);
const DBG_PORT = 9360 + Math.floor(Math.random() * 100);
const BROWSER = [
  'C:/Program Files (x86)/Microsoft/Edge/Application/msedge.exe',
  'C:/Program Files/Google/Chrome/Application/chrome.exe',
].find(p => fs.existsSync(p));

if (!BROWSER) { console.error('No Edge/Chrome found'); process.exit(1); }
fs.mkdirSync(OUT, { recursive: true });

const POKI_MOCK = `<script>
window.PokiSDK = {
  init: () => Promise.resolve(),
  gameLoadingProgress() {}, gameLoadingFinished() { console.log('[poki] loaded'); },
  gameplayStart() { console.log('[poki] gameplayStart'); },
  gameplayStop() { console.log('[poki] gameplayStop'); },
  commercialBreak(cb) { if (cb) cb(); return Promise.resolve(); },
  rewardedBreak() { return Promise.resolve(true); },
  measure(a, b, c) { console.log('[poki] measure', a, b, c); },
  setDebug() {}, captureError(e) { console.log('[poki] err', e); },
  getURLParam() { return null; }, getDeviceInfo() { return { category: 'mobile' }; }, movePill() {},
};
window.addEventListener('load', () => setTimeout(() => { if (window.poki_sdk_loaded) poki_sdk_loaded(); }, 40));
</script>`;

function patchedIndex() {
  let html = fs.readFileSync(path.join(BUNDLE, 'index.html'), 'utf8');
  html = html.replace(/<script[^>]*poki-sdk[^>]*><\/script>/, POKI_MOCK);
  const args = ['--config=pvp.fresh=1'];
  if (opt.screen) args.push(`--config=pvp.debug_screen=${opt.screen}`);
  if (opt.lang) args.push(`--config=pvp.lang=${opt.lang}`);
  html = html.replace(
    "<script id='engine-setup' type='text/javascript'>",
    `<script id='engine-setup' type='text/javascript'>\nCUSTOM_PARAMETERS["engine_arguments"] = ${JSON.stringify(args)};`
  );
  return html;
}

const MIME = { '.html': 'text/html', '.js': 'application/javascript', '.wasm': 'application/wasm', '.css': 'text/css', '.png': 'image/png' };
const srv = http.createServer((req, res) => {
  const url = req.url.split('?')[0];
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
  const userData = path.join(OUT, '_prof_' + PORT);
  const proc = spawn(BROWSER, [
    '--headless=new', '--disable-gpu', `--remote-debugging-port=${DBG_PORT}`,
    `--window-size=${VW},${VH}`, `--user-data-dir=${userData}`,
    '--no-first-run', '--no-default-browser-check', `http://127.0.0.1:${PORT}/`,
  ], { stdio: 'ignore' });

  const sleep = ms => new Promise(r => setTimeout(r, ms));
  let ws;
  for (let i = 0; i < 30; i++) {
    await sleep(250);
    try {
      const list = await (await fetch(`http://127.0.0.1:${DBG_PORT}/json`)).json();
      const page = list.find(t => t.type === 'page');
      if (page) { ws = new WebSocket(page.webSocketDebuggerUrl); break; }
    } catch {}
  }
  if (!ws) { proc.kill(); srv.close(); console.error('CDP connect failed'); process.exit(1); }

  let msgId = 0;
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
      console.log('[console]', d.params.args.map(a => a.value || a.description).join(' '));
    } else if (d.method === 'Runtime.exceptionThrown') {
      console.error('[js-err]', d.params.exceptionDetails.text);
    }
  });

  await new Promise(r => ws.addEventListener('open', r));
  await cdp('Runtime.enable');
  await cdp('Emulation.setDeviceMetricsOverride', { width: VW, height: VH, deviceScaleFactor: 1, mobile: VW < VH });
  await sleep(Number(opt.secs) * 1000);
  const shot = await cdp('Page.captureScreenshot', { format: 'png' });
  const shotPath = path.join(OUT, `${opt.screen || 'boot'}_${VW}x${VH}.png`);
  fs.writeFileSync(shotPath, Buffer.from(shot.data, 'base64'));
  console.log('Saved screenshot:', shotPath);
  ws.close();
  proc.kill();
  srv.close();
  try { fs.rmSync(userData, { recursive: true, force: true }); } catch {}
});
