// Writes main/assets/fonts/main.font covering every glyph in main/modules/i18n.lua.
const fs = require('fs');

let chars = '';
for (let c = 32; c < 127; c++) chars += String.fromCharCode(c);
const used = new Set([...fs.readFileSync('main/modules/i18n.lua', 'utf8')].filter(ch => ch.codePointAt(0) > 126));
for (const ch of [...used]) { used.add(ch.toUpperCase()); used.add(ch.toLowerCase()); }
chars += [...used].filter(ch => ch.length === 1 && ch.codePointAt(0) > 126).sort().join('');

const esc = [...Buffer.from(chars, 'utf8')].map(b => {
  if (b === 0x22) return '\\"';
  if (b === 0x5c) return '\\\\';
  if (b < 32 || b > 126) return '\\' + b.toString(8).padStart(3, '0');
  return String.fromCharCode(b);
}).join('');

const font = [
  'font: "/main/assets/fonts/Nunito-Black.ttf"',
  'material: "/builtins/fonts/font-df.material"',
  'size: 44',
  'outline_alpha: 1.0',
  'outline_width: 4.0',
  'shadow_blur: 0',
  'output_format: TYPE_DISTANCE_FIELD',
  'render_mode: MODE_MULTI_LAYER',
  `characters: "${esc}"`,
  '',
].join('\n');
fs.writeFileSync('main/assets/fonts/main.font', font);
console.log(`${[...chars].length} glyphs written to main.font`);
