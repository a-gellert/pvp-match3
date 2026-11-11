// Procedural Casual Dark Fantasy art (SDF -> anti-aliased PNG), atlas and sprite_sizes.lua.
// Usage: node tools/gen_sprites.js [preview.png]
const fs = require('fs');
const zlib = require('zlib');

const OUT = 'main/assets/images';
const ATLAS = 'main/assets/game.atlas';
const PREVIEW = process.argv[2];
const ALL = [];
fs.mkdirSync(OUT, { recursive: true });

// ---------- PNG encoder ----------
const CRC_TABLE = (() => {
  const t = new Uint32Array(256);
  for (let n = 0; n < 256; n++) {
    let c = n;
    for (let k = 0; k < 8; k++) c = c & 1 ? 0xedb88320 ^ (c >>> 1) : c >>> 1;
    t[n] = c >>> 0;
  }
  return t;
})();
function crc32(buf) {
  let c = 0xffffffff;
  for (let i = 0; i < buf.length; i++) c = CRC_TABLE[(c ^ buf[i]) & 0xff] ^ (c >>> 8);
  return (c ^ 0xffffffff) >>> 0;
}
function chunk(type, data) {
  const len = Buffer.alloc(4); len.writeUInt32BE(data.length);
  const td = Buffer.concat([Buffer.from(type), data]);
  const crc = Buffer.alloc(4); crc.writeUInt32BE(crc32(td));
  return Buffer.concat([len, td, crc]);
}
function encodePNG(w, h, rgba) {
  const raw = Buffer.alloc((w * 4 + 1) * h);
  for (let y = 0; y < h; y++) {
    raw[y * (w * 4 + 1)] = 0;
    for (let x = 0; x < w * 4; x++) {
      raw[y * (w * 4 + 1) + 1 + x] = Math.max(0, Math.min(255, Math.round(rgba[y * w * 4 + x] * 255)));
    }
  }
  const ihdr = Buffer.alloc(13);
  ihdr.writeUInt32BE(w, 0); ihdr.writeUInt32BE(h, 4);
  ihdr[8] = 8; ihdr[9] = 6;
  return Buffer.concat([
    Buffer.from([0x89, 0x50, 0x4e, 0x47, 0x0d, 0x0a, 0x1a, 0x0a]),
    chunk('IHDR', ihdr),
    chunk('IDAT', zlib.deflateSync(raw, { level: 9 })),
    chunk('IEND', Buffer.alloc(0)),
  ]);
}

// ---------- SDF primitives ----------
const len = (x, y) => Math.sqrt(x * x + y * y);
const clamp01 = v => Math.max(0, Math.min(1, v));
const circle = (cx, cy, r) => (x, y) => len(x - cx, y - cy) - r;
const ellipse = (cx, cy, rx, ry) => (x, y) => (len((x - cx) / rx, (y - cy) / ry) - 1) * Math.min(rx, ry);
const ellipseR = (cx, cy, rx, ry, deg) => {
  const a = deg * Math.PI / 180, ca = Math.cos(a), sa = Math.sin(a);
  return (x, y) => {
    const dx = x - cx, dy = y - cy;
    return (len((dx * ca + dy * sa) / rx, (-dx * sa + dy * ca) / ry) - 1) * Math.min(rx, ry);
  };
};
const ring = (cx, cy, r, t) => (x, y) => Math.abs(len(x - cx, y - cy) - r) - t / 2;
const rbox = (cx, cy, hw, hh, r) => (x, y) => {
  const qx = Math.abs(x - cx) - hw + r, qy = Math.abs(y - cy) - hh + r;
  return len(Math.max(qx, 0), Math.max(qy, 0)) + Math.min(Math.max(qx, qy), 0) - r;
};
const capsule = (ax, ay, bx, by, r) => (x, y) => {
  const pax = x - ax, pay = y - ay, bax = bx - ax, bay = by - ay;
  const d2 = bax * bax + bay * bay || 1;
  const h = clamp01((pax * bax + pay * bay) / d2);
  return len(pax - bax * h, pay - bay * h) - r;
};
const poly = (pts, r = 0) => (x, y) => {
  let d = Infinity, s = 1;
  const n = pts.length;
  for (let i = 0, j = n - 1; i < n; j = i, i++) {
    const [xi, yi] = pts[i], [xj, yj] = pts[j];
    const ex = xj - xi, ey = yj - yi, wx = x - xi, wy = y - yi;
    const h = clamp01((wx * ex + wy * ey) / (ex * ex + ey * ey || 1));
    const bx = wx - ex * h, by = wy - ey * h;
    d = Math.min(d, bx * bx + by * by);
    const c1 = y >= yi, c2 = y < yj, c3 = ex * wy > ey * wx;
    if ((c1 && c2 && c3) || (!c1 && !c2 && !c3)) s = -s;
  }
  return s * Math.sqrt(d) - r;
};
const star = (cx, cy, ro, ri, n = 5, rot = -90, r = 0) => {
  const pts = [];
  for (let i = 0; i < n * 2; i++) {
    const a = (rot + i * 180 / n) * Math.PI / 180;
    const rr = i % 2 ? ri : ro;
    pts.push([cx + Math.cos(a) * rr, cy + Math.sin(a) * rr]);
  }
  return poly(pts, r);
};
const regPoly = (cx, cy, r, sides, rot = -90, round = 0) => {
  const pts = [];
  for (let i = 0; i < sides; i++) {
    const a = (rot + i * 360 / sides) * Math.PI / 180;
    pts.push([cx + Math.cos(a) * r, cy + Math.sin(a) * r]);
  }
  return poly(pts, round);
};
const union = (...fs) => (x, y) => { let m = Infinity; for (const f of fs) m = Math.min(m, f(x, y)); return m; };
const sub = (a, b) => (x, y) => Math.max(a(x, y), -b(x, y));
const inter = (...fs) => (x, y) => { let m = -Infinity; for (const f of fs) m = Math.max(m, f(x, y)); return m; };
const grow = (f, d) => (x, y) => f(x, y) - d;

// ---------- Colors ----------
const H = (hex, a = 1) => {
  const v = parseInt(hex.replace('#', ''), 16);
  return [((v >> 16) & 255) / 255, ((v >> 8) & 255) / 255, (v & 255) / 255, a];
};
const mix = (a, b, t) => a.map((v, i) => v + (b[i] - v) * t);
const vgrad = (c1, c2, y0, y1) => (x, y) => mix(c1, c2, clamp01((y - y0) / (y1 - y0 || 1)));
const rgrad = (cx, cy, r, cIn, cOut) => (x, y) => mix(cIn, cOut, clamp01(len(x - cx, y - cy) / (r || 1)));
const darker = (c, k = 0.72) => [c[0] * k, c[1] * k, c[2] * k, c[3]];
const lighter = (c, k = 0.38) => mix(c, [1, 1, 1, c[3]], k);
const OUTC = H('#0f121d'); // deep dark fantasy ink outline

function canvas(w, h) {
  const px = new Float32Array(w * h * 4);
  const blend = (x, y, c, cov) => {
    const a = c[3] * cov;
    if (a <= 0.001) return;
    const i = (y * w + x) * 4;
    const oa = px[i + 3];
    const na = a + oa * (1 - a);
    if (na <= 0.0001) return;
    px[i] = (c[0] * a + px[i] * oa * (1 - a)) / na;
    px[i + 1] = (c[1] * a + px[i + 1] * oa * (1 - a)) / na;
    px[i + 2] = (c[2] * a + px[i + 2] * oa * (1 - a)) / na;
    px[i + 3] = na;
  };
  const fill = (sdf, col, aa = 1.15) => {
    const cfn = typeof col === 'function' ? col : () => col;
    for (let y = 0; y < h; y++) for (let x = 0; x < w; x++) {
      const d = sdf(x + 0.5, y + 0.5);
      if (d < aa) blend(x, y, cfn(x + 0.5, y + 0.5), clamp01(0.5 - d / aa));
    }
  };
  const stroke = (sdf, col, width = 2.5, aa = 1.15) => {
    const hw = width / 2;
    fill((x, y) => Math.abs(sdf(x, y)) - hw, col, aa);
  };
  const outlined = (sdf, col, ow = 2.5, oc = OUTC) => {
    fill(grow(sdf, ow), oc);
    fill(sdf, col);
  };
  const parts = (list, ow = 2.5, oc = OUTC) => {
    const sil = union(...list.map(p => p[0]));
    fill(grow(sil, ow), oc);
    for (const [s, c] of list) fill(s, c);
  };
  const save = (name) => {
    fs.writeFileSync(`${OUT}/${name}.png`, encodePNG(w, h, px));
    ALL.push({ name, w, h, px });
  };
  return { w, h, px, fill, stroke, outlined, parts, save };
}

// ======================================================================= UI & PANELS
{ // panel_dark (96x96 slice-9, border 22)
  const c = canvas(96, 96);
  const outer = rbox(48, 48, 44, 44, 14);
  c.outlined(outer, vgrad(H('#242c42'), H('#161b29'), 6, 90), 3);
  c.stroke(rbox(48, 48, 41, 41, 12), H('#4a587a', 0.8), 2.5);
  c.stroke(rbox(48, 48, 37, 37, 10), H('#0d1019', 0.6), 2);
  c.save('panel_dark');
}
{ // panel_stone (96x96 slice-9, border 24) - heavy board frame
  const c = canvas(96, 96);
  const outer = rbox(48, 48, 45, 45, 16);
  c.outlined(outer, vgrad(H('#2e3752'), H('#181d2c'), 4, 92), 3);
  c.stroke(rbox(48, 48, 42, 42, 13), H('#b68c44', 0.85), 3);
  c.fill(rbox(48, 48, 36, 36, 9), H('#111521'));
  for (const [rx, ry] of [[14, 14], [82, 14], [14, 82], [82, 82]]) {
    c.outlined(circle(rx, ry, 4.2), H('#e8b84b'), 1.8);
  }
  c.save('panel_stone');
}
for (const [name, c1, c2, rim] of [
  ['card_common', '#45506b', '#272e40', '#8b99b8'],
  ['card_rare', '#634329', '#2b1f21', '#f09a36'],
  ['card_epic', '#4e2c75', '#211638', '#d273ff'],
  ['card_legendary', '#1d5a73', '#2d1c4a', '#52f0ff'],
]) {
  const c = canvas(96, 96);
  c.outlined(rbox(48, 48, 44, 44, 14), vgrad(H(c1), H(c2), 6, 90), 3);
  c.stroke(rbox(48, 48, 40, 40, 11), H(rim), 3.5);
  c.fill(rbox(48, 48, 35, 35, 8), H('#151926', 0.85));
  if (name === 'card_epic' || name === 'card_legendary') {
    const stud = name === 'card_legendary' ? H('#52f0ff') : H('#ffd644');
    for (const [rx, ry] of [[14, 14], [82, 14], [14, 82], [82, 82]]) c.fill(circle(rx, ry, 4.2), stud);
  }
  c.save(name);
}
for (const [name, top, bot, hi] of [
  ['btn_gold', '#f2bd47', '#b56d1c', '#ffe89c'],
  ['btn_purple', '#9d5ce6', '#56299e', '#d6b0ff'],
  ['btn_crimson', '#e6485c', '#8c1c31', '#ff9aa8'],
  ['btn_dark', '#35405e', '#20273b', '#5d6e99'],
]) {
  const c = canvas(96, 64);
  c.fill(rbox(48, 35, 44, 25, 13), H('#090b12', 0.55));
  const body = rbox(48, 31, 44, 24, 13);
  c.outlined(body, vgrad(H(top), H(bot), 8, 54), 3);
  c.stroke(rbox(48, 31, 41, 21, 11), H(hi, 0.45), 2);
  c.fill(rbox(48, 15, 34, 4, 2), H(hi, 0.35));
  c.save(name);
}
{ // btn_round
  const c = canvas(88, 88);
  c.fill(circle(44, 47, 38), H('#090b12', 0.55));
  c.outlined(circle(44, 43, 37), vgrad(H('#435073'), H('#21283d'), 8, 78), 3);
  c.stroke(circle(44, 43, 33), H('#8d9cc4', 0.5), 2);
  c.save('btn_round');
}
{ // cell_bg (board tile slot)
  const c = canvas(128, 128);
  c.fill(rbox(64, 64, 59, 59, 16), vgrad(H('#1d2438'), H('#141928'), 6, 122));
  c.stroke(rbox(64, 64, 57, 57, 15), H('#2d3854', 0.7), 2);
  c.save('cell_bg');
}
{ // bar_bg & bar_fill & square & FX
  const c1 = canvas(64, 28);
  c1.outlined(rbox(32, 14, 29, 11, 7), H('#101420'), 2);
  c1.stroke(rbox(32, 14, 27, 9, 6), H('#384463'), 1.5);
  c1.save('bar_bg');

  const c2 = canvas(64, 28);
  c2.fill(rbox(32, 14, 27, 9, 5), vgrad(H('#ffffff'), H('#cccccc'), 4, 24));
  c2.save('bar_fill');

  const sq = canvas(16, 16);
  sq.fill((x, y) => -1, H('#ffffff'));
  sq.save('square');

  const gl = canvas(128, 128);
  gl.fill((x, y) => len(x - 64, y - 64) - 62, (x, y) => {
    const t = clamp01(1 - len(x - 64, y - 64) / 62);
    return [1, 1, 1, t * t * 0.9];
  });
  gl.save('glow');

  const sp = canvas(64, 64);
  sp.fill(star(32, 32, 28, 7, 4, 0, 1.5), (x, y) => [1, 1, 1, clamp01(1 - len(x - 32, y - 32) / 30)]);
  sp.save('spark');

  const rg = canvas(128, 128);
  rg.fill(ring(64, 64, 52, 10), (x, y) => [1, 1, 1, clamp01(1 - Math.abs(len(x - 64, y - 64) - 52) / 7)]);
  rg.save('ring');

  const pf = canvas(64, 64);
  pf.fill(circle(32, 32, 28), (x, y) => [1, 1, 1, clamp01(1 - len(x - 32, y - 32) / 28) * 0.75]);
  pf.save('puff');
}

// ======================================================================= 5 ELEMENTAL GEMS (128x128)
function makeGem(name, shape, cTop, cBot, innerShape, innerCol) {
  const c = canvas(128, 128);
  c.fill((x, y) => shape(x, y - 5), H('#070910', 0.45)); // drop shadow
  c.outlined(shape, vgrad(H(cTop), H(cBot), 14, 114), 4.5, OUTC);
  c.fill(grow(shape, -8), vgrad(lighter(H(cTop), 0.2), darker(H(cBot), 0.85), 18, 108));
  c.stroke(grow(shape, -5), lighter(H(cTop), 0.55), 2.5);
  // Inner crisp tactical emblem
  c.fill(innerShape, H(innerCol, 0.92));
  c.stroke(innerShape, OUTC, 1.5);
  // Glossy specular top highlight
  c.fill(ellipseR(44, 34, 14, 6, -28), [1, 1, 1, 0.62]);
  c.fill(circle(32, 46, 3.8), [1, 1, 1, 0.5]);
  c.save(name);
}

// Red = Damage 1 (Ruby sword/triangle cut)
makeGem('gem_red',
  poly([[64, 12], [110, 38], [100, 96], [64, 116], [28, 96], [18, 38]], 6),
  '#ff4a64', '#9e122b',
  union(poly([[64, 34], [76, 76], [64, 88], [52, 76]]), rbox(64, 82, 18, 4, 2), rbox(64, 92, 4, 8, 2)),
  '#ffd0d6'
);

// Yellow = Damage 2 (Topaz diamond + lightning bolt)
makeGem('gem_yellow',
  poly([[64, 10], [116, 64], [64, 118], [12, 64]], 7),
  '#ffe14d', '#cf7310',
  poly([[68, 30], [46, 66], [63, 66], [56, 98], [82, 60], [65, 60]], 1.5),
  '#fff8cc'
);

// Purple = Damage 3 (Amethyst octagon + arcane flame/star)
makeGem('gem_purple',
  regPoly(64, 64, 52, 8, 22.5, 5),
  '#d26eff', '#5d1aa8',
  star(64, 64, 24, 11, 4, -45, 2),
  '#f5d6ff'
);

// Green = Heal (Emerald tear/shield + heart/cross)
makeGem('gem_green',
  regPoly(64, 64, 50, 6, -90, 8),
  '#4ef296', '#148249',
  union(rbox(64, 64, 20, 7, 3), rbox(64, 64, 7, 20, 3)),
  '#e0ffec'
);

// Blue = Shield (Sapphire kite shield + chevron)
makeGem('gem_blue',
  poly([[64, 14], [108, 32], [102, 84], [64, 116], [26, 84], [20, 32]], 6),
  '#54bfff', '#1859ba',
  poly([[64, 36], [88, 52], [84, 78], [64, 94], [44, 78], [40, 52]], 3),
  '#d9f2ff'
);

// Special Gem overlays & Prism
{
  const lh = canvas(128, 128);
  lh.outlined(union(rbox(64, 64, 56, 8, 4), poly([[8, 64], [24, 50], [24, 78]]), poly([[120, 64], [104, 50], [104, 78]])), H('#ffe57a'), 2.5);
  lh.save('spec_line_h');

  const lv = canvas(128, 128);
  lv.outlined(union(rbox(64, 64, 8, 56, 4), poly([[64, 8], [50, 24], [78, 24]]), poly([[64, 120], [50, 104], [78, 104]])), H('#ffe57a'), 2.5);
  lv.save('spec_line_v');

  const bm = canvas(128, 128);
  bm.stroke(circle(64, 64, 48), H('#ff9d3b'), 7);
  bm.stroke(circle(64, 64, 48), H('#fff0a8'), 2.5);
  bm.save('spec_bomb');

  const pr = canvas(128, 128);
  pr.outlined(circle(64, 64, 48), rgrad(64, 64, 48, H('#2d1f47'), H('#121324')), 4.5);
  const cols = ['#ff4a64', '#ffe14d', '#d26eff', '#4ef296', '#54bfff'];
  for (let i = 0; i < 5; i++) {
    const a = (-90 + i * 72) * Math.PI / 180;
    pr.outlined(circle(64 + Math.cos(a) * 26, 64 + Math.sin(a) * 26, 11), H(cols[i]), 2);
  }
  pr.outlined(star(64, 64, 16, 7, 5), H('#ffffff'), 2);
  pr.save('gem_prism');
}

// ======================================================================= CHESTS (128x128)
function makeChest(name, woodTop, woodBot, trim, gemCol) {
  const c = canvas(128, 128);
  c.fill(ellipse(64, 108, 46, 10), H('#070910', 0.5));
  const body = rbox(64, 76, 44, 28, 10);
  const lid = rbox(64, 48, 46, 20, 12);
  const strapL = rbox(34, 64, 7, 40, 3);
  const strapR = rbox(94, 64, 7, 40, 3);
  const lock = rbox(64, 68, 12, 14, 5);
  c.parts([
    [body, vgrad(H(woodTop), H(woodBot), 48, 104)],
    [lid, vgrad(lighter(H(woodTop), 0.15), H(woodTop), 28, 68)],
    [strapL, H(trim)], [strapR, H(trim)],
    [rbox(64, 64, 46, 4, 2), darker(H(trim), 0.7)],
    [lock, lighter(H(trim), 0.2)],
  ], 4);
  if (gemCol) c.outlined(circle(64, 68, 6.5), H(gemCol), 2);
  c.fill(rbox(64, 35, 30, 4, 2), [1, 1, 1, 0.3]);
  c.save(name);
}
makeChest('chest_wood', '#7a4b2a', '#472814', '#8e97a8', null);
makeChest('chest_silver', '#43587a', '#24314a', '#b9d4ff', '#4fb8ff');
makeChest('chest_royal', '#432863', '#201233', '#f2bd47', '#d26eff');

// ======================================================================= COMMANDER FACE ICONS (128x128)
function makePortraitFrame(c, rimCol, bgTop, bgBot) {
  c.fill(circle(64, 67, 55), H('#070910', 0.55));
  c.outlined(circle(64, 64, 54), vgrad(H(bgTop), H(bgBot), 12, 116), 4.5);
  c.stroke(circle(64, 64, 50), H(rimCol), 5);
}

{ // face_hero (Iron Knight Commander)
  const c = canvas(128, 128);
  makePortraitFrame(c, '#58c4ff', '#1e2c4a', '#101626');
  const helm = union(circle(64, 58, 30), rbox(64, 76, 26, 20, 8));
  const crest = poly([[64, 12], [75, 36], [53, 36]], 3);
  const visor = poly([[42, 60], [64, 52], [86, 60], [82, 82], [64, 92], [46, 82]], 3);
  c.parts([
    [crest, H('#38a3ff')],
    [helm, vgrad(H('#7e90b3'), H('#45516e'), 28, 96)],
    [visor, H('#161b29')],
  ], 3.5);
  c.fill(ellipseR(52, 66, 6.5, 3.2, 12), H('#6ee7ff'));
  c.fill(ellipseR(76, 66, 6.5, 3.2, -12), H('#6ee7ff'));
  c.fill(rbox(64, 80, 12, 3, 1.5), H('#7e90b3'));
  c.save('face_hero');
}
{ // face_goblin
  const c = canvas(128, 128);
  makePortraitFrame(c, '#e6485c', '#3d2229', '#1c1118');
  const earL = poly([[20, 48], [44, 52], [40, 68]], 3);
  const earR = poly([[108, 48], [84, 52], [88, 68]], 3);
  const head = ellipse(64, 66, 28, 26);
  const helm = rbox(64, 42, 26, 11, 6);
  c.parts([[earL, H('#599e42')], [earR, H('#599e42')], [head, vgrad(H('#6ec452'), H('#3e782e'), 40, 92)], [helm, H('#6a7285')]], 3.5);
  c.fill(ellipseR(52, 62, 6, 4, 15), H('#ffe14d'));
  c.fill(ellipseR(76, 62, 6, 4, -15), H('#ffe14d'));
  c.fill(circle(53, 62, 2.2), H('#111')); c.fill(circle(75, 62, 2.2), H('#111'));
  c.fill(rbox(64, 80, 15, 5, 3), H('#241418'));
  c.fill(poly([[53, 76], [56, 82], [59, 76]]), H('#f3eee6'));
  c.fill(poly([[69, 76], [72, 82], [75, 76]]), H('#f3eee6'));
  c.save('face_goblin');
}
{ // face_skeleton (Lich Crown)
  const c = canvas(128, 128);
  makePortraitFrame(c, '#c45cff', '#2d1c47', '#130e1f');
  const crown = poly([[40, 44], [44, 22], [54, 34], [64, 18], [74, 34], [84, 22], [88, 44]], 2);
  const skull = union(circle(64, 62, 26), rbox(64, 82, 16, 12, 5));
  c.parts([[skull, vgrad(H('#ebe5d8'), H('#aba294'), 36, 94)], [crown, H('#e8b84b')]], 3.5);
  c.fill(circle(53, 62, 7.5), H('#181324')); c.fill(circle(75, 62, 7.5), H('#181324'));
  c.fill(circle(53, 62, 3.5), H('#d26eff')); c.fill(circle(75, 62, 3.5), H('#d26eff'));
  c.fill(poly([[64, 70], [60, 77], [68, 77]]), H('#181324'));
  c.fill(rbox(64, 86, 12, 2.5, 1), H('#3a3342'));
  c.save('face_skeleton');
}
{ // face_orc
  const c = canvas(128, 128);
  makePortraitFrame(c, '#ff6b4a', '#42201c', '#1a0e10');
  const head = rbox(64, 64, 28, 28, 14);
  const jaw = rbox(64, 82, 30, 13, 8);
  c.parts([[head, vgrad(H('#994b3b'), H('#632c24'), 36, 92)], [jaw, H('#78382e')]], 3.5);
  c.fill(rbox(64, 52, 22, 4, 2), H('#2b1312'));
  c.fill(circle(52, 60, 4.5), H('#ff9d3b')); c.fill(circle(76, 60, 4.5), H('#ff9d3b'));
  c.outlined(poly([[42, 82], [47, 68], [52, 82]]), H('#f3eee6'), 2);
  c.outlined(poly([[76, 82], [81, 68], [86, 82]]), H('#f3eee6'), 2);
  c.save('face_orc');
}
{ // face_necromancer
  const c = canvas(128, 128);
  makePortraitFrame(c, '#d26eff', '#26183b', '#0f0b1a');
  const hood = poly([[64, 20], [98, 54], [94, 96], [34, 96], [30, 54]], 6);
  const inner = poly([[64, 34], [84, 58], [78, 88], [50, 88], [44, 58]], 4);
  c.parts([[hood, vgrad(H('#58308c'), H('#2d184a'), 20, 96)], [inner, H('#0c0914')]], 3.5);
  c.fill(ellipseR(54, 62, 6.5, 3.2, 16), H('#ff59e9'));
  c.fill(ellipseR(74, 62, 6.5, 3.2, -16), H('#ff59e9'));
  c.save('face_necromancer');
}
{ // face_dragon
  const c = canvas(128, 128);
  makePortraitFrame(c, '#ff4a64', '#401522', '#170a10');
  const hornL = poly([[42, 44], [22, 16], [52, 34]], 2);
  const hornR = poly([[86, 44], [106, 16], [76, 34]], 2);
  const head = poly([[64, 28], [92, 52], [82, 94], [64, 102], [46, 94], [36, 52]], 5);
  c.parts([[hornL, H('#e8b84b')], [hornR, H('#e8b84b')], [head, vgrad(H('#8f2438'), H('#4a1220'), 28, 102)]], 3.5);
  c.fill(ellipseR(50, 58, 7, 3.5, 22), H('#ffd644'));
  c.fill(ellipseR(78, 58, 7, 3.5, -22), H('#ffd644'));
  c.fill(poly([[52, 82], [64, 72], [76, 82], [64, 90]]), H('#c94053'));
  c.save('face_dragon');
}

// ======================================================================= SQUAD SPRITES (160x128, 1-5 warriors!)
function drawWarrior(c, cx, cy, scale, opts) {
  const s = scale;
  const { armor, accent, weapon, shield, hood, horns } = opts;
  const parts = [];
  // shadow
  c.fill(ellipse(cx, cy + 26 * s, 16 * s, 5 * s), H('#070910', 0.48));
  // weapon behind/side
  if (weapon === 'spear') {
    parts.push([capsule(cx + 12 * s, cy + 20 * s, cx + 16 * s, cy - 28 * s, 2.2 * s), H('#9aa6bf')]);
    parts.push([poly([[cx + 16 * s, cy - 36 * s], [cx + 20 * s, cy - 24 * s], [cx + 12 * s, cy - 24 * s]]), H('#e3ebff')]);
  } else if (weapon === 'axe') {
    parts.push([capsule(cx + 13 * s, cy + 16 * s, cx + 17 * s, cy - 22 * s, 2.5 * s), H('#965c32')]);
    parts.push([poly([[cx + 16 * s, cy - 26 * s], [cx + 30 * s, cy - 22 * s], [cx + 26 * s, cy - 13 * s], [cx + 30 * s, cy - 4 * s], [cx + 15 * s, cy - 8 * s]]), H('#a9b6d1')]);
  } else if (weapon === 'bow') {
    const bowArc = inter(ring(cx + 5 * s, cy - 2 * s, 18 * s, 3.2 * s), (x) => cx + 11 * s - x);
    parts.push([bowArc, H('#e8b84b')]);
    parts.push([capsule(cx + 11 * s, cy - 18 * s, cx + 11 * s, cy + 14 * s, 1.1 * s), H('#cbd4e8')]);
    parts.push([capsule(cx + 8 * s, cy - 2 * s, cx + 26 * s, cy - 2 * s, 1.5 * s), H('#f5e6c4')]);
  } else if (weapon === 'crossbow') {
    parts.push([capsule(cx + 6 * s, cy + 2 * s, cx + 24 * s, cy + 2 * s, 2.5 * s), H('#8c5832')]);
    parts.push([capsule(cx + 18 * s, cy - 12 * s, cx + 18 * s, cy + 14 * s, 2.4 * s), H('#b7c4de')]);
  } else if (weapon === 'staff') {
    parts.push([capsule(cx + 13 * s, cy + 22 * s, cx + 13 * s, cy - 20 * s, 2.2 * s), H('#724a9c')]);
    parts.push([circle(cx + 13 * s, cy - 24 * s, 6 * s), H(accent)]);
  } else if (weapon === 'halberd') {
    parts.push([capsule(cx + 15 * s, cy + 22 * s, cx + 15 * s, cy - 30 * s, 2.5 * s), H('#d4a74a')]);
    parts.push([poly([[cx + 15 * s, cy - 38 * s], [cx + 22 * s, cy - 22 * s], [cx + 12 * s, cy - 20 * s]]), H('#f0f5ff')]);
  }
  // torso & legs
  parts.push([rbox(cx - 5 * s, cy + 18 * s, 4 * s, 8 * s, 2 * s), darker(H(armor), 0.78)]);
  parts.push([rbox(cx + 5 * s, cy + 18 * s, 4 * s, 8 * s, 2 * s), darker(H(armor), 0.78)]);
  parts.push([rbox(cx, cy + 2 * s, 12 * s, 14 * s, 6 * s), H(armor)]);
  // head / helmet / hood
  if (horns) {
    parts.push([poly([[cx - 7 * s, cy - 18 * s], [cx - 15 * s, cy - 31 * s], [cx - 3 * s, cy - 21 * s]]), H('#ebe1cc')]);
    parts.push([poly([[cx + 7 * s, cy - 18 * s], [cx + 15 * s, cy - 31 * s], [cx + 3 * s, cy - 21 * s]]), H('#ebe1cc')]);
  }
  if (hood) {
    parts.push([poly([[cx, cy - 26 * s], [cx + 13 * s, cy - 8 * s], [cx - 13 * s, cy - 8 * s]], 3 * s), lighter(H(armor), 0.14)]);
    parts.push([circle(cx, cy - 12 * s, 7 * s), H('#10121c')]);
  } else {
    parts.push([circle(cx, cy - 14 * s, 10 * s), lighter(H(armor), 0.25)]);
    parts.push([rbox(cx, cy - 14 * s, 8 * s, 3 * s, 1.5 * s), H('#10121c')]);
  }
  if (shield) {
    parts.push([rbox(cx - 11 * s, cy + 3 * s, 7 * s, 10 * s, 4 * s), H(accent)]);
  }
  c.parts(parts, 2.6);
  // glowing eyes
  c.fill(circle(cx - 3 * s, cy - 14 * s, 1.9 * s), H(accent));
  c.fill(circle(cx + 3 * s, cy - 14 * s, 1.9 * s), H(accent));
}

function drawWolf(c, cx, cy, s) {
  c.fill(ellipse(cx, cy + 18 * s, 18 * s, 5 * s), H('#070910', 0.48));
  const body = ellipse(cx, cy + 4 * s, 16 * s, 9 * s);
  const head = circle(cx + 12 * s, cy - 6 * s, 9 * s);
  const ear1 = poly([[cx + 8 * s, cy - 12 * s], [cx + 6 * s, cy - 22 * s], [cx + 13 * s, cy - 14 * s]]);
  const ear2 = poly([[cx + 14 * s, cy - 11 * s], [cx + 15 * s, cy - 21 * s], [cx + 19 * s, cy - 12 * s]]);
  const tail = poly([[cx - 14 * s, cy], [cx - 26 * s, cy - 10 * s], [cx - 18 * s, cy + 6 * s]], 2);
  const legs = union(rbox(cx - 9 * s, cy + 13 * s, 3 * s, 7 * s, 1.5), rbox(cx + 9 * s, cy + 13 * s, 3 * s, 7 * s, 1.5));
  c.parts([[tail, H('#593349')], [legs, H('#3f2233')], [body, H('#6e3b53')], [ear1, H('#8c4763')], [ear2, H('#8c4763')], [head, H('#8c4763')]], 2.6);
  c.fill(circle(cx + 15 * s, cy - 7 * s, 2.4 * s), H('#ff4a64'));
}

// 9 Squads (1 to 5 units!)
{ // 1. Red Militia (5 warriors)
  const c = canvas(160, 128);
  for (const [x, y, s] of [[42, 46, 0.72], [80, 42, 0.72], [118, 46, 0.72], [58, 78, 0.85], [102, 78, 0.85]]) {
    drawWarrior(c, x, y, s, { armor: '#4c5875', accent: '#ff4a64', weapon: 'spear', shield: true });
  }
  c.save('squad_red_militia');
}
{ // 2. Red Wolves (4 wolves)
  const c = canvas(160, 128);
  for (const [x, y, s] of [[46, 46, 0.75], [110, 44, 0.75], [52, 84, 0.9], [108, 84, 0.9]]) {
    drawWolf(c, x, y, s);
  }
  c.save('squad_red_wolves');
}
{ // 3. Red Berserkers (2 hulking horned warriors)
  const c = canvas(160, 128);
  for (const [x, y, s] of [[52, 68, 1.15], [108, 68, 1.15]]) {
    drawWarrior(c, x, y, s, { armor: '#96283e', accent: '#ff704a', weapon: 'axe', shield: false, horns: true });
  }
  c.save('squad_red_berserk');
}
{ // 4. Yellow Archers (4 archers)
  const c = canvas(160, 128);
  for (const [x, y, s] of [[44, 46, 0.75], [112, 46, 0.75], [56, 80, 0.88], [104, 80, 0.88]]) {
    drawWarrior(c, x, y, s, { armor: '#7d6237', accent: '#ffd644', weapon: 'bow', hood: true });
  }
  c.save('squad_yellow_archers');
}
{ // 5. Yellow Witch Hunters (3 crossbowmen)
  const c = canvas(160, 128);
  for (const [x, y, s] of [[42, 56, 0.85], [118, 56, 0.85], [80, 78, 0.98]]) {
    drawWarrior(c, x, y, s, { armor: '#554a6e', accent: '#ffe14d', weapon: 'crossbow', hood: false });
  }
  c.save('squad_yellow_crossbow');
}
{ // 6. Yellow Amber Templars (2 knights)
  const c = canvas(160, 128);
  for (const [x, y, s] of [[52, 66, 1.15], [108, 66, 1.15]]) {
    drawWarrior(c, x, y, s, { armor: '#c79736', accent: '#fff199', weapon: 'halberd', shield: true });
  }
  c.save('squad_yellow_paladin');
}
{ // 7. Purple Cultists (3 mages)
  const c = canvas(160, 128);
  for (const [x, y, s] of [[42, 56, 0.84], [118, 56, 0.84], [80, 76, 0.96]]) {
    drawWarrior(c, x, y, s, { armor: '#4d2b7a', accent: '#d26eff', weapon: 'staff', hood: true });
  }
  c.save('squad_purple_cultists');
}
{ // 8. Purple Necromancers (2 necros)
  const c = canvas(160, 128);
  for (const [x, y, s] of [[52, 66, 1.12], [108, 66, 1.12]]) {
    drawWarrior(c, x, y, s, { armor: '#2f1e4f', accent: '#62ff9e', weapon: 'staff', hood: true });
  }
  c.save('squad_purple_necro');
}
{ // 9. Purple Amethyst Colossus (1 giant golem!)
  const c = canvas(160, 128);
  c.fill(ellipse(80, 114, 42, 10), H('#070910', 0.55));
  const torso = poly([[42, 34], [118, 34], [104, 86], [56, 86]], 8);
  const head = rbox(80, 26, 16, 14, 6);
  const armL = rbox(34, 62, 14, 24, 8);
  const armR = rbox(126, 62, 14, 24, 8);
  const legL = rbox(64, 98, 11, 14, 5);
  const legR = rbox(96, 98, 11, 14, 5);
  c.parts([
    [legL, H('#31284a')], [legR, H('#31284a')],
    [armL, H('#4d3e73')], [armR, H('#4d3e73')],
    [torso, vgrad(H('#69539e'), H('#362957'), 34, 86)],
    [head, H('#4d3e73')],
  ], 4);
  c.outlined(poly([[80, 44], [94, 60], [80, 76], [66, 60]]), H('#d26eff'), 2);
  c.fill(circle(74, 26, 3.5), H('#ff73ff'));
  c.fill(circle(86, 26, 3.5), H('#ff73ff'));
  c.save('squad_purple_golem');
}

// ======================================================================= CURRENCIES, BOOSTERS & UI ICONS
{ // icon_gold
  const c = canvas(64, 64);
  c.outlined(circle(32, 32, 24), vgrad(H('#ffe14d'), H('#c97a16'), 8, 56), 3);
  c.stroke(circle(32, 32, 17), H('#fff3a8', 0.7), 2);
  c.fill(rbox(32, 32, 3, 10, 1.5), H('#94520c'));
  c.save('icon_gold');
}
{ // icon_diamond
  const c = canvas(64, 64);
  c.outlined(poly([[20, 14], [44, 14], [56, 28], [32, 54], [8, 28]], 2), vgrad(H('#8ceeff'), H('#1d82e6'), 14, 54), 3);
  c.stroke(poly([[20, 14], [32, 28], [44, 14]]), H('#ffffff', 0.65), 2);
  c.save('icon_diamond');
}
{ // icon_prestige (winged dark-gold crown)
  const c = canvas(64, 64);
  const crown = poly([[12, 46], [10, 20], [23, 30], [32, 14], [41, 30], [54, 20], [52, 46]], 2);
  c.outlined(crown, vgrad(H('#ffd644'), H('#b56b16'), 14, 46), 3);
  c.outlined(circle(32, 36, 5), H('#d26eff'), 1.5);
  c.save('icon_prestige');
}
{ // icon_move_orb
  const c = canvas(48, 48);
  c.outlined(circle(24, 24, 17), rgrad(20, 18, 18, H('#8cf0ff'), H('#2178d6')), 3);
  c.fill(circle(18, 17, 5), [1, 1, 1, 0.7]);
  c.save('icon_move_orb');
}
{ // icon_sword, icon_shield, icon_heart
  const sw = canvas(64, 64);
  sw.parts([
    [capsule(16, 48, 25, 39, 3), H('#965c32')],
    [capsule(19, 34, 30, 45, 3), H('#e8b84b')],
    [poly([[52, 10], [54, 18], [30, 42], [22, 34], [46, 10]]), H('#e3ebff')],
  ], 2.8);
  sw.save('icon_sword');

  const sh = canvas(64, 64);
  sh.outlined(poly([[32, 10], [52, 20], [48, 42], [32, 54], [16, 42], [12, 20]], 3), vgrad(H('#54bfff'), H('#1b5ec2'), 10, 54), 3);
  sh.save('icon_shield');

  const ht = canvas(64, 64);
  ht.outlined(union(circle(22, 24, 12), circle(42, 24, 12), poly([[12, 28], [52, 28], [32, 52]], 2)), vgrad(H('#ff596c'), H('#a61731'), 12, 52), 3);
  ht.save('icon_heart');
}
{ // Boosters: boost_shuffle, boost_hammer, boost_moves
  const b1 = canvas(88, 88);
  b1.outlined(circle(44, 44, 34), vgrad(H('#3b4c7a'), H('#1d243b'), 10, 78), 3);
  b1.stroke(ring(44, 44, 18, 5), H('#70e1ff'), 5);
  b1.fill(poly([[44, 16], [56, 26], [44, 34]]), H('#70e1ff'));
  b1.save('boost_shuffle');

  const b2 = canvas(88, 88);
  b2.outlined(circle(44, 44, 34), vgrad(H('#5e3748'), H('#2b1721'), 10, 78), 3);
  b2.parts([[capsule(26, 62, 52, 36, 4.5), H('#b07943')], [rbox(52, 32, 16, 10, 4), H('#c4d0e8')]], 3);
  b2.save('boost_hammer');

  const b3 = canvas(88, 88);
  b3.outlined(circle(44, 44, 34), vgrad(H('#35594c'), H('#182e29'), 10, 78), 3);
  b3.outlined(poly([[32, 22], [56, 22], [44, 44], [56, 66], [32, 66], [44, 44]], 2), H('#ffd644'), 3);
  b3.save('boost_moves');
}
{ // Small UI icons
  const ad = canvas(64, 64);
  ad.outlined(rbox(32, 32, 24, 18, 7), H('#e8b84b'), 3);
  ad.fill(poly([[26, 22], [44, 32], [26, 42]]), H('#161926'));
  ad.save('icon_ad');

  const pa = canvas(64, 64);
  pa.outlined(union(rbox(23, 32, 5, 16, 2), rbox(41, 32, 5, 16, 2)), H('#f3eee6'), 3);
  pa.save('icon_pause');

  const cl = canvas(64, 64);
  cl.outlined(union(capsule(18, 18, 46, 46, 4.5), capsule(46, 18, 18, 46, 4.5)), H('#ff6e7f'), 3);
  cl.save('icon_close');

  const ck = canvas(64, 64);
  ck.outlined(union(capsule(16, 34, 28, 46, 4.5), capsule(28, 46, 48, 20, 4.5)), H('#4ef296'), 3);
  ck.save('icon_check');

  const lk = canvas(64, 64);
  lk.stroke(circle(32, 24, 11), H('#9aa6bf'), 6);
  lk.outlined(rbox(32, 42, 16, 13, 5), H('#9aa6bf'), 3);
  lk.save('icon_lock');

  const gr = canvas(64, 64);
  gr.outlined(star(32, 32, 23, 17, 8, 0, 2), H('#c4cde0'), 3);
  gr.fill(circle(32, 32, 8), H('#1b2234'));
  gr.save('icon_gear');

  const hd = canvas(72, 72);
  hd.outlined(union(rbox(34, 44, 14, 14, 7), capsule(26, 40, 26, 14, 6)), H('#fff2df'), 3.5);
  hd.save('icon_hand');

  const pv = canvas(64, 64);
  pv.parts([
    [capsule(16, 48, 48, 16, 3.5), H('#ff6e7f')],
    [capsule(48, 48, 16, 16, 3.5), H('#ff6e7f')],
    [capsule(15, 36, 28, 49, 2.5), H('#e8b84b')],
    [capsule(49, 36, 36, 49, 2.5), H('#e8b84b')],
  ], 2.8);
  pv.save('icon_pvp');

  const mp = canvas(64, 64);
  mp.outlined(poly([[12, 18], [26, 12], [40, 18], [52, 12], [52, 46], [40, 52], [26, 46], [12, 52]], 2), H('#e8b84b'), 3);
  mp.save('icon_map');

  const cd = canvas(64, 64);
  cd.outlined(rbox(26, 34, 13, 18, 4), H('#7c8db5'), 3);
  cd.outlined(rbox(38, 30, 13, 18, 4), H('#e8b84b'), 3);
  cd.save('icon_cards');

  const snd = canvas(64, 64);
  snd.outlined(union(rbox(18, 32, 6, 9, 2), poly([[24, 23], [38, 13], [38, 51], [24, 41]])), H('#dbe4f5'), 2.8);
  snd.stroke(inter(circle(38, 32, 10), (x) => 40 - x), H('#70e1ff'), 3.5);
  snd.save('icon_sound');

  const sndOff = canvas(64, 64);
  sndOff.outlined(union(rbox(18, 32, 6, 9, 2), poly([[24, 23], [38, 13], [38, 51], [24, 41]])), H('#7d879e'), 2.8);
  sndOff.outlined(capsule(16, 16, 48, 48, 3), H('#ff596c'), 2);
  sndOff.save('icon_sound_off');

  const mus = canvas(64, 64);
  mus.outlined(union(circle(22, 46, 7), circle(42, 42, 7), rbox(27, 30, 2.5, 16, 1), rbox(47, 26, 2.5, 16, 1), capsule(27, 15, 47, 11, 3)), H('#ffd644'), 2.5);
  mus.save('icon_music');

  const musOff = canvas(64, 64);
  musOff.outlined(union(circle(22, 46, 7), circle(42, 42, 7), rbox(27, 30, 2.5, 16, 1), rbox(47, 26, 2.5, 16, 1), capsule(27, 15, 47, 11, 3)), H('#7d879e'), 2.5);
  musOff.outlined(capsule(16, 16, 48, 48, 3), H('#ff596c'), 2);
  musOff.save('icon_music_off');

  const glb = canvas(64, 64);
  glb.outlined(circle(32, 32, 22), H('#4fb8ff'), 2.8);
  glb.stroke(ellipse(32, 32, 10, 22), H('#1b3d6e'), 2.5);
  glb.stroke(rbox(32, 32, 22, 1, 0), H('#1b3d6e'), 2.5);
  glb.save('icon_globe');

  const rbg = canvas(48, 48);
  rbg.outlined(circle(24, 24, 20), H('#121724'), 2.5);
  rbg.stroke(circle(24, 24, 17), H('#48577a', 0.85), 2);
  rbg.save('rune_bg');

  const brn = canvas(48, 48);
  brn.outlined(poly([[24, 5], [38, 25], [32, 41], [24, 43], [16, 41], [10, 25]], 4), vgrad(H('#ffd644'), H('#ff422e'), 6, 42), 2.5);
  brn.fill(circle(24, 30, 6), H('#fff099'));
  brn.save('icon_burn');

  const psn = canvas(48, 48);
  psn.outlined(poly([[24, 7], [37, 27], [33, 40], [24, 43], [15, 40], [11, 27]], 4), vgrad(H('#7bff78'), H('#189e3c'), 8, 42), 2.5);
  psn.fill(circle(21, 25, 3), H('#c8ffbd'));
  psn.save('icon_poison');

  const frz = canvas(48, 48);
  frz.outlined(star(24, 24, 19, 8, 6, 0, 1.5), vgrad(H('#a8f4ff'), H('#2d88ff'), 6, 42), 2.5);
  frz.save('icon_freeze');
}

// ======================================================================= META / RETENTION UI
{ // Stars (campaign rating)
  const s1 = canvas(64, 64);
  s1.fill(star(32, 35, 27, 12, 5, -90, 3), H('#090b12', 0.5));
  s1.outlined(star(32, 32, 27, 12, 5, -90, 3), vgrad(H('#fff09a'), H('#e89a1c'), 8, 56), 3);
  s1.fill(star(28, 26, 9, 4, 5, -90, 1), [1, 1, 1, 0.55]);
  s1.save('icon_star');

  const s0 = canvas(64, 64);
  s0.outlined(star(32, 32, 27, 12, 5, -90, 3), H('#2a3147'), 3);
  s0.stroke(star(32, 32, 22, 10, 5, -90, 2), H('#47557a', 0.8), 2);
  s0.save('icon_star_empty');
}
{ // icon_calendar (daily login)
  const c = canvas(64, 64);
  c.outlined(rbox(32, 36, 23, 21, 6), vgrad(H('#f3eee6'), H('#c9c2b6'), 15, 57), 3);
  c.fill(rbox(32, 22, 23, 7, 5), H('#e6485c'));
  c.fill(rbox(32, 18, 21, 3, 2), H('#ff9aa8', 0.6));
  for (const x of [21, 43]) c.outlined(capsule(x, 10, x, 20, 3), H('#9aa6bf'), 2);
  for (let i = 0; i < 3; i++) for (let j = 0; j < 2; j++) c.fill(rbox(20 + i * 12, 36 + j * 10, 3.5, 3, 1), H('#4a587a'));
  c.fill(rbox(44, 46, 4.5, 4, 1.2), H('#e8b84b'));
  c.save('icon_calendar');
}
{ // icon_quest (parchment scroll with seal)
  const c = canvas(64, 64);
  c.parts([
    [rbox(32, 32, 18, 22, 3), vgrad(H('#f3e3bd'), H('#cfb486'), 10, 54)],
    [capsule(12, 12, 52, 12, 5), H('#b68c44')],
    [capsule(12, 52, 52, 52, 5), H('#b68c44')],
  ], 3);
  for (let i = 0; i < 3; i++) c.fill(rbox(30, 22 + i * 8, 11, 1.4, 0.7), H('#7a5a32', 0.8));
  c.outlined(circle(43, 42, 6), H('#e6485c'), 2);
  c.save('icon_quest');
}
{ // icon_gift (free chest)
  const c = canvas(64, 64);
  c.outlined(rbox(32, 40, 21, 16, 3), vgrad(H('#b95cff'), H('#5a2a9e'), 24, 56), 3);
  c.outlined(rbox(32, 24, 24, 6, 3), H('#d26eff'), 3);
  c.fill(rbox(32, 38, 5, 18, 1), H('#ffd644'));
  c.fill(rbox(32, 24, 5, 6, 1), H('#ffd644'));
  c.outlined(union(ellipseR(23, 14, 9, 5, -25), ellipseR(41, 14, 9, 5, 25)), H('#ffd644'), 2.5);
  c.save('icon_gift');
}
{ // icon_fire (win streak)
  const c = canvas(64, 64);
  const flame = union(circle(32, 42, 15), poly([[17, 40], [24, 16], [30, 26], [36, 6], [47, 30], [47, 42]], 3));
  c.outlined(flame, vgrad(H('#ffe36b'), H('#ff422e'), 8, 56), 3);
  c.fill(union(circle(32, 46, 8), poly([[24, 46], [30, 30], [40, 46]], 2)), H('#fff7c2'));
  c.save('icon_fire');
}
{ // icon_shop (bag)
  const c = canvas(64, 64);
  c.stroke(inter(circle(32, 22, 10), (x, y) => y - 22), H('#b68c44'), 4);
  c.outlined(poly([[12, 24], [52, 24], [56, 56], [8, 56]], 4), vgrad(H('#f2bd47'), H('#b56d1c'), 24, 56), 3);
  c.outlined(circle(32, 40, 7), H('#ffe89c'), 2);
  c.save('icon_shop');
}
{ // icon_trophy (cup)
  const c = canvas(64, 64);
  c.stroke(union(ring(14, 24, 7, 3.5), ring(50, 24, 7, 3.5)), H('#b56d1c'), 3);
  c.parts([
    [poly([[16, 10], [48, 10], [46, 30], [32, 40], [18, 30]], 4), vgrad(H('#ffe36b'), H('#d0821c'), 10, 40)],
    [rbox(32, 44, 4, 6, 1), H('#d0821c')],
    [rbox(32, 54, 13, 5, 2), H('#8a5a2a')],
  ], 3);
  c.fill(rbox(25, 20, 2.5, 7, 1.2), [1, 1, 1, 0.5]);
  c.save('icon_trophy');
}
{ // league_badge (white, tinted per league) 96x96
  const c = canvas(96, 96);
  const shield = poly([[48, 8], [84, 20], [80, 56], [48, 88], [16, 56], [12, 20]], 8);
  c.fill(grow(shield, 4), H('#0c0f18'));
  c.fill(shield, vgrad(H('#ffffff'), H('#9aa0ad'), 10, 88));
  c.stroke(poly([[48, 16], [76, 25], [73, 54], [48, 79], [23, 54], [20, 25]], 6), H('#ffffff', 0.7), 3);
  c.fill(star(48, 46, 17, 8, 5, -90, 2), H('#2a3147', 0.55));
  c.save('league_badge');
}
{ // badge_dot (notification) 40x40
  const c = canvas(40, 40);
  c.fill(circle(20, 20, 18), H('#ffffff'));
  c.fill(circle(20, 20, 15), vgrad(H('#ff6b7d'), H('#c41d3a'), 6, 34));
  c.save('badge_dot');
}
{ // icon_back (arrow left) / icon_play
  const c = canvas(64, 64);
  c.outlined(union(capsule(18, 32, 46, 32, 5), capsule(18, 32, 30, 20, 5), capsule(18, 32, 30, 44, 5)), H('#f3eee6'), 3);
  c.save('icon_back');
  const p = canvas(64, 64);
  p.outlined(poly([[22, 14], [50, 32], [22, 50]], 4), H('#f3eee6'), 3);
  p.save('icon_play');
}
{ // node_stage (campaign medallion, neutral stone + gold rim) 96x96
  const c = canvas(96, 96);
  c.fill(circle(48, 52, 40), H('#05070c', 0.55));
  c.outlined(circle(48, 47, 39), vgrad(H('#e8b84b'), H('#8a5a20'), 10, 86), 3);
  c.fill(circle(48, 47, 31), vgrad(H('#3a4566'), H('#1b2133'), 18, 78));
  c.stroke(circle(48, 47, 31), H('#0c0f18', 0.8), 2);
  c.fill(ellipse(40, 32, 14, 6), [1, 1, 1, 0.12]);
  c.save('node_stage');
}
{ // path_dot 24x24
  const c = canvas(24, 24);
  c.fill(circle(12, 12, 9), H('#ffffff'));
  c.save('path_dot');
}
{ // rays (reward sunburst) 256x256
  const c = canvas(256, 256);
  c.fill((x, y) => {
    const a = Math.atan2(y - 128, x - 128);
    const k = Math.abs(Math.sin(a * 8));
    return (0.62 - k) * 40;
  }, (x, y) => [1, 1, 1, clamp01(1 - len(x - 128, y - 128) / 126) * 0.9]);
  c.save('rays');
}
{ // vignette 128x128 (transparent center -> dark edges), stretched over screens
  const c = canvas(128, 128);
  c.fill((x, y) => -1, (x, y) => {
    const d = len((x - 64) / 64, (y - 64) / 64);
    const t = clamp01((d - 0.55) / 0.85);
    return [0.02, 0.03, 0.06, t * t * 0.95];
  });
  c.save('vignette');
}
{ // edge_glow 128x128: white edges, transparent centre (tint it: low-HP warning, skill flashes)
  const c = canvas(128, 128);
  c.fill((x, y) => -1, (x, y) => {
    const d = len((x - 64) / 64, (y - 64) / 64);
    const t = clamp01((d - 0.62) / 0.7);
    return [1, 1, 1, t * 0.95];
  });
  c.save('edge_glow');
}
{ // bg_glow: soft light blob for backgrounds 64x128
  const c = canvas(64, 128);
  c.fill((x, y) => -1, (x, y) => {
    const t = clamp01(1 - len((x - 32) / 32, (y - 64) / 64));
    return [1, 1, 1, t * t * 0.8];
  });
  c.save('bg_glow');
}
{ // tab_active (nav highlight, slice-9)
  const t = canvas(96, 96);
  t.outlined(rbox(48, 48, 44, 44, 18), vgrad(H('#3b4766'), H('#232a40'), 6, 90), 3);
  t.stroke(rbox(48, 48, 40, 40, 15), H('#e8b84b', 0.9), 3);
  t.fill(rbox(48, 22, 30, 6, 4), H('#ffffff', 0.12));
  t.save('tab_active');
}

// ======================================================================= IMPORT NANO BANANA ART
const ART_DIR = 'main/assets/art';
if (fs.existsSync(ART_DIR)) {
  const byName = new Map(ALL.map(a => [a.name, a]));
  for (const file of fs.readdirSync(ART_DIR).filter(f => f.endsWith('.png')).sort()) {
    const name = file.slice(0, -4);
    const src = `${ART_DIR}/${file}`;
    const buf = fs.readFileSync(src);
    const w = buf.readUInt32BE(16);
    const h = buf.readUInt32BE(20);
    fs.copyFileSync(src, `${OUT}/${file}`);
    const existing = byName.get(name);
    if (existing) {
      existing.w = w; existing.h = h; existing.px = null;
    } else {
      const entry = { name, w, h, px: null };
      ALL.push(entry);
      byName.set(name, entry);
    }
  }
}

// ======================================================================= ATLAS & SIZES
const images = ALL.map(a => `images {\n  image: "/${OUT}/${a.name}.png"\n}\n`).join('');
fs.writeFileSync(ATLAS, images + 'margin: 2\nextrude_borders: 2\ninner_padding: 0\n');
fs.writeFileSync('main/gui/sprite_sizes.lua', '-- generated by tools/gen_sprites.js\nreturn {\n' +
  ALL.map(a => `\t${a.name} = { ${a.w}, ${a.h} },\n`).join('') + '}\n');
console.log(`Generated ${ALL.length} sprites, total pixels: ${ALL.reduce((s, a) => s + a.w * a.h, 0)}`);

if (PREVIEW) {
  const preList = ALL.filter(a => a.px);
  const W = 1280, pad = 10;
  let x = pad, y = pad, rowH = 0;
  const placed = [];
  for (const a of preList) {
    if (x + a.w > W) { x = pad; y += rowH + pad; rowH = 0; }
    placed.push([a, x, y]);
    x += a.w + pad; rowH = Math.max(rowH, a.h);
  }
  const Hh = y + rowH + pad;
  const px = new Float32Array(W * Hh * 4);
  for (let i = 0; i < W * Hh; i++) {
    px[i * 4] = 0.08; px[i * 4 + 1] = 0.1; px[i * 4 + 2] = 0.16; px[i * 4 + 3] = 1;
  }
  for (const [a, ox, oy] of placed) {
    for (let j = 0; j < a.h; j++) for (let i = 0; i < a.w; i++) {
      const s = (j * a.w + i) * 4, d = ((oy + j) * W + ox + i) * 4, al = a.px[s + 3];
      for (let k = 0; k < 3; k++) px[d + k] = a.px[s + k] * al + px[d + k] * (1 - al);
    }
  }
  fs.writeFileSync(PREVIEW, encodePNG(W, Hh, px));
  console.log(`Preview written to ${PREVIEW}`);
}
