// Shared helpers for the font/localization tooling:
//   - parse the per-language tables in main/modules/locales
//   - read the glyph coverage of a TTF (cmap formats 4 and 12)
//   - read the `characters` string of a Defold .font resource
const fs = require('fs');
const path = require('path');

const ROOT = path.join(__dirname, '..');

function walk(dir, ext, out = []) {
  for (const entry of fs.readdirSync(dir, { withFileTypes: true })) {
    const p = path.join(dir, entry.name);
    if (entry.isDirectory()) walk(p, ext, out);
    else if (p.endsWith(ext)) out.push(p);
  }
  return out;
}

// Every .lua file that can show text (locales, HUD helpers, ...).
function projectLuaFiles() {
  return walk(path.join(ROOT, 'main'), '.lua').sort();
}

function localeFiles() {
  const dir = path.join(ROOT, 'main/modules/locales');
  return fs
    .readdirSync(dir)
    .filter((f) => f.endsWith('.lua'))
    .sort()
    .map((f) => path.join(dir, f));
}

// Returns { ru: { NAME: "Русский", ... }, ... }.
function parseLocales() {
  const locales = {};
  for (const file of localeFiles()) {
    const code = path.basename(file, '.lua');
    const table = {};
    for (const line of fs.readFileSync(file, 'utf8').split(/\r?\n/)) {
      const m = line.match(/^\t([A-Za-z0-9_]+) = "(.*)",$/);
      if (m) table[m[1]] = m[2];
    }
    locales[code] = table;
  }
  return locales;
}

// Lua source string -> JS string (octal UTF-8 escapes, \n, \" and \\).
function luaUnescape(lua) {
  const bytes = [];
  for (let i = 0; i < lua.length; i++) {
    const ch = lua[i];
    if (ch === '\\') {
      const oct = lua.slice(i + 1).match(/^([0-7]{1,3})/);
      if (oct) {
        bytes.push(parseInt(oct[1], 8));
        i += oct[1].length;
        continue;
      }
      const next = lua[i + 1];
      if (next === 'n') { bytes.push(10); i++; continue; }
      if (next === 't') { bytes.push(9); i++; continue; }
      if (next === '"' || next === '\\') { bytes.push(next.charCodeAt(0)); i++; continue; }
    }
    for (const b of Buffer.from(ch, 'utf8')) bytes.push(b);
  }
  return Buffer.from(bytes).toString('utf8');
}

function escFontChar(byte) {
  if (byte === 0x22) return '\\"';
  if (byte === 0x5c) return '\\\\';
  if (byte < 32 || byte > 126) return '\\' + byte.toString(8).padStart(3, '0');
  return String.fromCharCode(byte);
}

function utf8Escape(text) {
  return [...Buffer.from(text, 'utf8')].map(escFontChar).join('');
}

function readFont(file) {
  const text = fs.readFileSync(file, 'utf8');
  const field = (name) => {
    const m = text.match(new RegExp('^' + name + ': (.*)$', 'm'));
    return m ? m[1].trim() : null;
  };
  const characters = luaUnescape((field('characters') || '').replace(/^"|"$/g, ''));
  return {
    characters,
    codepoints: new Set([...characters].map((ch) => ch.codePointAt(0))),
    size: parseFloat(field('size') || '0'),
    outline: parseFloat(field('outline_width') || '0'),
    shadowBlur: parseFloat(field('shadow_blur') || '0'),
    cacheWidth: parseInt(field('cache_width') || '0', 10),
    cacheHeight: parseInt(field('cache_height') || '0', 10),
  };
}

function ttfCodepoints(file) {
  const buf = fs.readFileSync(file);
  const numTables = buf.readUInt16BE(4);
  const tables = {};
  for (let i = 0; i < numTables; i++) {
    const off = 12 + i * 16;
    tables[buf.toString('ascii', off, off + 4)] = {
      offset: buf.readUInt32BE(off + 8),
      length: buf.readUInt32BE(off + 12),
    };
  }
  if (!tables.cmap) throw new Error('No cmap table in ' + file);
  const cmap = tables.cmap.offset;
  const count = buf.readUInt16BE(cmap + 2);
  const records = [];
  for (let i = 0; i < count; i++) {
    const rec = cmap + 4 + i * 8;
    records.push({
      platform: buf.readUInt16BE(rec),
      encoding: buf.readUInt16BE(rec + 2),
      offset: cmap + buf.readUInt32BE(rec + 4),
    });
  }
  // Prefer the full Unicode table (format 12) when present, then the BMP table (format 4).
  records.sort((a, b) => {
    const score = (r) => (buf.readUInt16BE(r.offset) === 12 ? 2 : 0) + (r.platform === 3 && r.encoding === 10 ? 1 : 0);
    return score(b) - score(a);
  });
  const points = new Set();
  for (const record of records) {
    const format = buf.readUInt16BE(record.offset);
    if (format === 12) {
      const groups = buf.readUInt32BE(record.offset + 12);
      for (let g = 0; g < groups; g++) {
        const off = record.offset + 16 + g * 12;
        const start = buf.readUInt32BE(off);
        const end = buf.readUInt32BE(off + 4);
        for (let c = start; c <= end; c++) points.add(c);
      }
    } else if (format === 4) {
      const segCount = buf.readUInt16BE(record.offset + 6) / 2;
      const endCodes = record.offset + 14;
      const startCodes = endCodes + segCount * 2 + 2;
      const idDeltas = startCodes + segCount * 2;
      const idRangeOffsets = idDeltas + segCount * 2;
      for (let s = 0; s < segCount; s++) {
        const end = buf.readUInt16BE(endCodes + s * 2);
        const start = buf.readUInt16BE(startCodes + s * 2);
        const delta = buf.readInt16BE(idDeltas + s * 2);
        const rangeOffset = buf.readUInt16BE(idRangeOffsets + s * 2);
        if (start === 0xffff) continue;
        for (let c = start; c <= end; c++) {
          let glyph;
          if (rangeOffset === 0) {
            glyph = (c + delta) & 0xffff;
          } else {
            const addr = idRangeOffsets + s * 2 + rangeOffset + (c - start) * 2;
            if (addr + 1 >= buf.length) continue;
            glyph = buf.readUInt16BE(addr);
            if (glyph !== 0) glyph = (glyph + delta) & 0xffff;
          }
          if (glyph !== 0) points.add(c);
        }
      }
    }
  }
  return points;
}

// Defold grows the glyph cache from 64x64 up to 2048x4096 for dynamic (TTF-backed) fonts
// (see SetupParamsForDynamicFont in res_font.cpp).
function estimateAtlas(font, glyphCount) {
  const padding = font.outline + font.shadowBlur + 2; // FontGenGetBasePadding() == 2
  const cellW = Math.ceil(font.size + 2 * padding);
  const cellH = Math.ceil(font.size + 2 * padding);
  let width = 64;
  let height = 64;
  const area = cellW * cellH * glyphCount;
  while (width * height < area && (width < 2048 || height < 4096)) {
    if (width < height) width *= 2;
    else height *= 2;
  }
  return { width, height, cellW, cellH, fits: width <= 2048 && height <= 4096 };
}

function collectTextChars(files) {
  const chars = new Map(); // codepoint -> first file:line
  for (const file of files) {
    const lines = fs.readFileSync(file, 'utf8').split(/\r?\n/);
    lines.forEach((line, i) => {
      for (const ch of line) {
        const cp = ch.codePointAt(0);
        if (cp > 126 && !chars.has(cp)) chars.set(cp, `${path.relative(ROOT, file)}:${i + 1}`);
      }
    });
  }
  return chars;
}

module.exports = {
  ROOT,
  projectLuaFiles,
  localeFiles,
  parseLocales,
  luaUnescape,
  utf8Escape,
  readFont,
  ttfCodepoints,
  estimateAtlas,
  collectTextChars,
};
