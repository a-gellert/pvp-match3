// Zero-dependency procedural WAV SFX generator + main/sounds.go writer.
const fs = require('fs');

const OUT = 'main/assets/sounds';
fs.mkdirSync(OUT, { recursive: true });
const SR = 22050;

function writeWav(name, dur, sampleFn) {
  const n = Math.floor(SR * dur);
  const buf = Buffer.alloc(44 + n * 2);
  buf.write('RIFF', 0);
  buf.writeUInt32LE(36 + n * 2, 4);
  buf.write('WAVEfmt ', 8);
  buf.writeUInt32LE(16, 16);
  buf.writeUInt16LE(1, 20);
  buf.writeUInt16LE(1, 22);
  buf.writeUInt32LE(SR, 24);
  buf.writeUInt32LE(SR * 2, 28);
  buf.writeUInt16LE(2, 32);
  buf.writeUInt16LE(16, 34);
  buf.write('data', 36);
  buf.writeUInt32LE(n * 2, 40);
  for (let i = 0; i < n; i++) {
    const t = i / SR;
    const v = Math.max(-1, Math.min(1, sampleFn(t, dur)));
    buf.writeInt16LE(Math.round(v * 24000), 44 + i * 2);
  }
  fs.writeFileSync(`${OUT}/${name}.wav`, buf);
}

const env = (t, d) => Math.exp(-t / (d * 0.35)) * Math.min(1, t * 80);
const sine = (f, t) => Math.sin(2 * Math.PI * f * t);
const tri = (f, t) => 2 * Math.abs(2 * (t * f - Math.floor(t * f + 0.5))) - 1;

const SOUNDS = [
  ['button', 0.08, (t, d) => sine(520 - t * 900, t) * env(t, d) * 0.55],
  ['tap', 0.06, (t, d) => sine(640 + t * 800, t) * env(t, d) * 0.45],
  ['blocked', 0.14, (t, d) => tri(170 - t * 220, t) * env(t, d) * 0.5],
  ['match', 0.22, (t, d) => (sine(523, t) + 0.6 * sine(659, t) + 0.4 * sine(784, t)) * 0.3 * env(t, d)],
  ['hit', 0.18, (t, d) => (tri(140 * Math.exp(-t * 8), t) + (Math.random() - 0.5) * 0.45) * env(t, d) * 0.7],
  ['arrow', 0.17, (t, d) => ((sine(180 + t * 420, t) * 0.25) + (Math.random() - 0.5) * 0.65 * Math.exp(-t * 14)) * env(t, d) * 0.75],
  ['spell', 0.32, (t, d) => (sine(587 + Math.sin(t * 28) * 140, t) + 0.45 * sine(880 + t * 360, t) + (Math.random() - 0.5) * 0.15) * 0.36 * env(t, d)],
  ['slash', 0.16, (t, d) => ((tri(260 * Math.exp(-t * 10), t) * 0.4) + (Math.random() - 0.5) * 0.65 * Math.min(1, t * 40)) * env(t, d) * 0.75],
  ['dash', 0.14, (t, d) => (tri(110 + t * 180, t) * 0.5 + (Math.random() - 0.5) * 0.3) * env(t, d) * 0.55],
  ['heal', 0.28, (t, d) => (sine(440 + t * 500, t) + 0.5 * sine(880 + t * 600, t)) * 0.35 * env(t, d)],
  ['shield', 0.22, (t, d) => (sine(320 + t * 240, t) + 0.4 * tri(640, t)) * 0.4 * env(t, d)],
  ['upgrade', 0.35, (t, d) => sine(t < 0.12 ? 523 : (t < 0.22 ? 659 : 784), t) * env(t, d) * 0.5],
  ['chest', 0.45, (t, d) => (sine(392, t) + sine(523, t) + sine(784, t)) * 0.28 * Math.min(1, t * 40) * (1 - t / d)],
  ['win', 0.6, (t, d) => {
    const f = t < 0.15 ? 523 : (t < 0.3 ? 659 : (t < 0.45 ? 784 : 1046));
    return (sine(f, t) + 0.3 * tri(f * 0.5, t)) * 0.4 * (1 - t / d);
  }],
  ['lose', 0.55, (t, d) => {
    const f = t < 0.2 ? 330 : (t < 0.38 ? 277 : 220);
    return tri(f, t) * 0.38 * (1 - t / d);
  }],
];

for (const [name, dur, fn] of SOUNDS) writeWav(name, dur, fn);

const go = SOUNDS.map(([name]) =>
  `embedded_components {\n  id: "${name}"\n  type: "sound"\n  data: "sound: \\"/main/assets/sounds/${name}.wav\\"\\n"\n  "looping: 0\\n"\n  "group: \\"sfx\\"\\n"\n  "gain: 1.0\\n"\n}\n`
).join('');
fs.writeFileSync('main/sounds.go', go);
console.log(`Generated ${SOUNDS.length} WAV sounds + main/sounds.go`);
