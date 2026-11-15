// Validates localization fonts before a build:
//   1) parses every language table in main/modules/locales
//   2) checks every non-ASCII glyph used by the game exists in Nunito-Black.ttf
//   3) checks main/assets/fonts/main.font lists every glyph the game can show
//   4) checks all locales have the same keys as en.lua (the reference locale)
//   5) estimates the Defold SDF glyph cache size (auto-grows to 2048x4096)
// Usage: node tools/check_fonts.js
// Exit code 1 when something is missing, so it can gate a build.
const path = require('path');
const util = require('./font_utils');

const TTF = path.join(util.ROOT, 'main/assets/fonts/Nunito-Black.ttf');
const FONT = path.join(util.ROOT, 'main/assets/fonts/main.font');
const REFERENCE = 'en';

const errors = [];
const warnings = [];

const locales = util.parseLocales();
const langs = Object.keys(locales);
const ttf = util.ttfCodepoints(TTF);
const font = util.readFont(FONT);
const fontChars = font.codepoints;

console.log(`Locales (${langs.length}): ${langs.join(', ')}`);
console.log(`TTF glyphs: ${ttf.size}, main.font characters: ${fontChars.size}`);

const cp = (ch) => 'U+' + ch.codePointAt(0).toString(16).toUpperCase().padStart(4, '0');
const describe = (map) =>
  [...map].map(([ch, key]) => `'${ch}' ${cp(ch)} (${key})`).join(', ');

// ---------------------------------------------------------- per-locale glyphs
for (const lang of langs) {
  const missingTtf = new Map();
  const missingAtlas = new Map();
  for (const key in locales[lang]) {
    for (const ch of locales[lang][key]) {
      const c = ch.codePointAt(0);
      if (c < 32) continue;
      if (c > 126 && !ttf.has(c)) missingTtf.set(ch, key);
      if (!fontChars.has(c)) missingAtlas.set(ch, key);
    }
  }
  if (missingTtf.size) errors.push(`[${lang}] missing in Nunito-Black.ttf: ${describe(missingTtf)}`);
  if (missingAtlas.size) errors.push(`[${lang}] missing in main.font: ${describe(missingAtlas)} (run node tools/gen_font.js)`);
}

// ------------------------------------------------- glyphs hard-coded in screens
const localeSet = new Set(util.localeFiles());
const uiChars = new Map();
for (const [c, where] of util.collectTextChars(util.projectLuaFiles())) {
  if (!localeSet.has(path.join(util.ROOT, where.split(':')[0]))) uiChars.set(String.fromCodePoint(c), where);
}
for (const [ch, where] of uiChars) {
  if (!ttf.has(ch.codePointAt(0))) errors.push(`[ui] '${ch}' ${cp(ch)} not in Nunito-Black.ttf (${where})`);
  if (!fontChars.has(ch.codePointAt(0))) errors.push(`[ui] '${ch}' ${cp(ch)} missing in main.font (${where})`);
}

// Latin letters, digits and punctuation must always be available.
const ascii = [];
for (let c = 32; c < 127; c++) if (!fontChars.has(c)) ascii.push(JSON.stringify(String.fromCharCode(c)));
if (ascii.length) errors.push(`main.font lacks ASCII: ${ascii.join(', ')}`);

// Uppercase forms written in code (labels are often upper-cased by hand).
const cased = [];
for (const lang of langs) {
  for (const key in locales[lang]) {
    for (const ch of locales[lang][key]) {
      const c = ch.codePointAt(0);
      if (c <= 126) continue;
      for (const variant of [ch.toUpperCase(), ch.toLowerCase()]) {
        const vcp = variant.codePointAt(0);
        if (variant.length === 1 && vcp > 126 && !ttf.has(vcp) && !cased.some((x) => x[0] === variant)) {
          cased.push([variant, ch, lang, key]);
        }
      }
    }
  }
}
if (cased.length) {
  warnings.push(
    'case forms missing in the TTF (gen_font.js can only add glyphs the TTF has): ' +
      cased.map(([v, ch, lang]) => `'${v}' ${cp(v)} from '${ch}' (${lang})`).join(', ')
  );
}

// ------------------------------------------------------------ cache estimate
const atlas = util.estimateAtlas(font, fontChars.size);
console.log(
  `Estimated SDF cache: ${atlas.cellW}x${atlas.cellH} px per glyph, ${fontChars.size} glyphs -> ${atlas.width}x${atlas.height}`
);
if (!atlas.fits) errors.push(`Glyph cache needs ${atlas.width}x${atlas.height}, Defold caps dynamic fonts at 2048x4096`);
if (font.cacheWidth && font.cacheHeight && font.cacheWidth * font.cacheHeight < atlas.cellW * atlas.cellH * fontChars.size) {
  errors.push(`main.font cache ${font.cacheWidth}x${font.cacheHeight} is too small for ${fontChars.size} glyphs`);
}

// ------------------------------------------------------------------ key sets
const reference = Object.keys(locales[REFERENCE] || {}).sort();
for (const lang of langs) {
  const keys = Object.keys(locales[lang]);
  const missing = reference.filter((k) => !(k in locales[lang]));
  const extra = keys.filter((k) => !(k in locales[REFERENCE]));
  if (missing.length) errors.push(`[${lang}] missing keys: ${missing.join(', ')}`);
  if (extra.length) errors.push(`[${lang}] keys not in ${REFERENCE}.lua: ${extra.join(', ')}`);
}
const noName = langs.filter((l) => !locales[l].NAME);
if (noName.length) warnings.push(`languages without a native NAME: ${noName.join(', ')}`);

for (const w of warnings) console.warn('WARNING: ' + w);
if (errors.length) {
  console.error('FAILED\n- ' + errors.join('\n- '));
  process.exit(1);
}
console.log('\nOK: every localized glyph is in the TTF and in main.font, key sets match');
