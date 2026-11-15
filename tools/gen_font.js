// Writes main/assets/fonts/main.font covering every glyph shown by the game.
// Sources: all .lua files under main/ (locale tables included) + printable ASCII.
// Only glyphs that exist in Nunito-Black.ttf are emitted; run `node tools/check_fonts.js`
// to fail the build when a translated string needs a glyph the TTF does not have.
const fs = require('fs');
const path = require('path');
const util = require('./font_utils');

const TTF = path.join(util.ROOT, 'main/assets/fonts/Nunito-Black.ttf');
const FONT = path.join(util.ROOT, 'main/assets/fonts/main.font');

const ttf = util.ttfCodepoints(TTF);
const used = util.collectTextChars(util.projectLuaFiles());

const codepoints = new Set();
for (let c = 32; c < 127; c++) codepoints.add(c);

const skipped = [];
for (const [cp, where] of used) {
  if (ttf.has(cp)) {
    codepoints.add(cp);
    // Strings are often written in one case only ("Обычный" needs "ОБЫЧНЫЙ" too).
    const ch = String.fromCodePoint(cp);
    for (const variant of [ch.toUpperCase(), ch.toLowerCase()]) {
      const vcp = variant.codePointAt(0);
      if (variant.length === 1 && vcp > 126 && ttf.has(vcp)) codepoints.add(vcp);
    }
  } else {
    skipped.push(`'${String.fromCodePoint(cp)}' U+${cp.toString(16).toUpperCase()} (${where})`);
  }
}

const chars = [...codepoints].sort((a, b) => a - b).map((cp) => String.fromCodePoint(cp)).join('');
const font = [
  'font: "/main/assets/fonts/Nunito-Black.ttf"',
  'material: "/builtins/fonts/font-df.material"',
  'size: 44',
  'outline_alpha: 1.0',
  'outline_width: 4.0',
  'shadow_blur: 0',
  'output_format: TYPE_DISTANCE_FIELD',
  'render_mode: MODE_MULTI_LAYER',
  `characters: "${util.utf8Escape(chars)}"`,
  '',
].join('\n');
fs.writeFileSync(FONT, font);

const atlas = util.estimateAtlas(util.readFont(FONT), codepoints.size);
console.log(
  `${codepoints.size} glyphs written to main.font (estimated ${atlas.width}x${atlas.height} SDF cache)`
);
if (skipped.length) {
  console.warn(`WARNING: ${skipped.length} characters used in main/ are not in Nunito-Black.ttf:\n  ${skipped.join('\n  ')}`);
  console.warn('Replace them or ship a font with those glyphs before shipping this locale.');
}
