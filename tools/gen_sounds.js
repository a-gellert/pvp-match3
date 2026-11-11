// Zero-dependency procedural WAV SFX + seamless music loop generator, writes main/sounds.go.
// Usage: node tools/gen_sounds.js
const fs = require('fs');

const OUT = 'main/assets/sounds';
fs.mkdirSync(OUT, { recursive: true });
const SR = 22050;

// Deterministic noise so regenerating gives identical files.
let seed = 1234567;
const rnd = () => { seed = (seed * 16807) % 2147483647; return seed / 2147483647; };
const noise = () => rnd() * 2 - 1;

function wavBuffer(samples, rate) {
  const n = samples.length;
  const buf = Buffer.alloc(44 + n * 2);
  buf.write('RIFF', 0);
  buf.writeUInt32LE(36 + n * 2, 4);
  buf.write('WAVEfmt ', 8);
  buf.writeUInt32LE(16, 16);
  buf.writeUInt16LE(1, 20);
  buf.writeUInt16LE(1, 22);
  buf.writeUInt32LE(rate, 24);
  buf.writeUInt32LE(rate * 2, 28);
  buf.writeUInt16LE(2, 32);
  buf.writeUInt16LE(16, 34);
  buf.write('data', 36);
  buf.writeUInt32LE(n * 2, 40);
  for (let i = 0; i < n; i++) {
    const v = Math.max(-1, Math.min(1, samples[i]));
    buf.writeInt16LE(Math.round(v * 26000), 44 + i * 2);
  }
  return buf;
}

function writeWav(name, dur, sampleFn) {
  const n = Math.floor(SR * dur);
  const s = new Float32Array(n);
  for (let i = 0; i < n; i++) s[i] = sampleFn(i / SR, dur);
  fs.writeFileSync(`${OUT}/${name}.wav`, wavBuffer(s, SR));
}

const env = (t, d) => Math.exp(-t / (d * 0.35)) * Math.min(1, t * 80);
const sine = (f, t) => Math.sin(2 * Math.PI * f * t);
const tri = (f, t) => 2 * Math.abs(2 * (t * f - Math.floor(t * f + 0.5))) - 1;
const bell = (f, t, k = 3) => (sine(f, t) + 0.5 * sine(f * 2.01, t) + 0.25 * sine(f * 3.02, t)) * Math.exp(-t * k);
const seq = (t, notes, step) => notes[Math.min(notes.length - 1, Math.floor(t / step))];

const SOUNDS = [
  ['button', 0.08, (t, d) => sine(520 - t * 900, t) * env(t, d) * 0.55],
  ['tap', 0.06, (t, d) => sine(640 + t * 800, t) * env(t, d) * 0.45],
  ['blocked', 0.14, (t, d) => tri(170 - t * 220, t) * env(t, d) * 0.5],
  ['match', 0.22, (t, d) => (sine(523, t) + 0.6 * sine(659, t) + 0.4 * sine(784, t)) * 0.3 * env(t, d)],
  ['hit', 0.18, (t, d) => (tri(140 * Math.exp(-t * 8), t) + noise() * 0.45) * env(t, d) * 0.7],
  ['arrow', 0.17, (t, d) => ((sine(180 + t * 420, t) * 0.25) + noise() * 0.65 * Math.exp(-t * 14)) * env(t, d) * 0.75],
  ['spell', 0.32, (t, d) => (sine(587 + Math.sin(t * 28) * 140, t) + 0.45 * sine(880 + t * 360, t) + noise() * 0.15) * 0.36 * env(t, d)],
  ['slash', 0.16, (t, d) => ((tri(260 * Math.exp(-t * 10), t) * 0.4) + noise() * 0.65 * Math.min(1, t * 40)) * env(t, d) * 0.75],
  ['dash', 0.14, (t, d) => (tri(110 + t * 180, t) * 0.5 + noise() * 0.3) * env(t, d) * 0.55],
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
  // --- meta / juice
  ['coin', 0.16, (t) => (t < 0.05 ? bell(1318, t, 30) : bell(1760, t - 0.05, 22)) * 0.4],
  ['star', 0.5, (t) => {
    const f = seq(t, [1046, 1318, 1568, 2093], 0.07);
    const lt = t % 0.07;
    return (bell(f, lt, 14) * 0.5 + bell(f * 0.5, t, 4) * 0.2) * Math.min(1, (0.5 - t) * 8);
  }],
  ['whoosh', 0.28, (t, d) => {
    const k = Math.sin(Math.PI * t / d);
    return noise() * 0.5 * k * k * (0.6 + 0.4 * sine(3 + t * 30, t));
  }],
  ['combo', 0.3, (t, d) => (sine(659 + t * 900, t) + 0.5 * sine(988 + t * 1200, t)) * 0.3 * env(t, d)],
  ['levelup', 0.9, (t, d) => {
    const f = seq(t, [523, 659, 784, 1046, 1046], 0.11);
    const lt = t % 0.11;
    return (bell(f, Math.min(lt, t), 5) * 0.45 + tri(f / 2, t) * 0.12) * Math.min(1, (d - t) * 3) * Math.min(1, t * 200);
  }],
  ['quest', 0.45, (t) => (bell(880, t, 6) * 0.35 + (t > 0.12 ? bell(1318, t - 0.12, 6) * 0.35 : 0))],
  ['flip', 0.12, (t, d) => (noise() * 0.5 * Math.exp(-t * 40) + sine(900 - t * 3000, t) * 0.25) * env(t, d)],
  ['turn', 0.5, (t) => (bell(220, t, 4) * 0.35 + bell(330, t, 5) * 0.2)],
  ['notify', 0.25, (t) => bell(1568, t, 10) * 0.3],
  // --- squads vs squads
  ['death', 0.6, (t, d) => (tri(95 * Math.exp(-t * 2.5), t) * 0.55 + noise() * 0.45 * Math.exp(-t * 7)
    + bell(196, t, 6) * 0.2) * Math.min(1, t * 120) * (1 - t / d)],
  ['crit', 0.22, (t, d) => (bell(1245, t, 16) * 0.35 + noise() * 0.4 * Math.exp(-t * 30) + tri(180 * Math.exp(-t * 9), t) * 0.35) * env(t, d)],
  ['turn_you', 0.55, (t) => (bell(523, t, 6) * 0.3 + (t > 0.09 ? bell(784, t - 0.09, 5) * 0.32 : 0) + bell(1046, t, 9) * 0.08)],
  ['turn_enemy', 0.6, (t) => (bell(147, t, 3) * 0.42 + bell(208, t, 4) * 0.22 + noise() * 0.06 * Math.exp(-t * 10))],
];

for (const [name, dur, fn] of SOUNDS) writeWav(name, dur, fn);

// ----------------------------------------------------------------- music loop
// Dark-fantasy loop: Am - F - C - G | Am - F - G - E, 96 BPM, 8 bars.
// Rendered twice and the 2nd pass is kept, so reverb tails wrap and the loop is seamless.
const MSR = 11025;
const BPM = 96;
const BEAT = 60 / BPM;
const BAR = BEAT * 4;
const BARS = 8;
const LOOP = BAR * BARS;
const N = Math.floor(LOOP * MSR);
const buf = new Float32Array(N * 2);
const midi = m => 440 * Math.pow(2, (m - 69) / 12);
const CHORDS = [
  [57, 60, 64], [53, 57, 60], [48, 52, 55], [55, 59, 62],
  [57, 60, 64], [53, 57, 60], [55, 59, 62], [52, 56, 59],
];
const add = (start, samples) => {
  const s0 = Math.floor(start * MSR);
  for (let i = 0; i < samples.length; i++) {
    const k = s0 + i;
    if (k >= 0 && k < buf.length) buf[k] += samples[i];
  }
};
// Karplus-Strong pluck (harp / lute)
function pluck(freq, dur, gain) {
  const n = Math.floor(dur * MSR);
  const p = Math.max(2, Math.round(MSR / freq));
  const line = new Float32Array(p);
  for (let i = 0; i < p; i++) line[i] = noise();
  const out = new Float32Array(n);
  let idx = 0;
  for (let i = 0; i < n; i++) {
    const a = line[idx], b = line[(idx + 1) % p];
    const v = 0.5 * (a + b) * 0.994;
    line[idx] = v;
    out[i] = a * gain;
    idx = (idx + 1) % p;
  }
  return out;
}
function pad(notes, dur, gain) {
  const n = Math.floor(dur * MSR);
  const out = new Float32Array(n);
  let lp = 0;
  for (let i = 0; i < n; i++) {
    const t = i / MSR;
    let v = 0;
    for (const m of notes) {
      const f = midi(m);
      v += tri(f * 0.997, t) + tri(f * 1.003, t) + 0.5 * sine(f * 0.5, t);
    }
    const a = Math.min(1, t / 0.6) * Math.min(1, (dur - t) / 0.8);
    lp += (v - lp) * 0.08; // one-pole low-pass: warm, dark pad
    out[i] = lp * a * gain;
  }
  return out;
}
function bass(m, dur, gain) {
  const n = Math.floor(dur * MSR);
  const out = new Float32Array(n);
  const f = midi(m);
  for (let i = 0; i < n; i++) {
    const t = i / MSR;
    out[i] = (sine(f, t) + 0.3 * tri(f, t)) * Math.min(1, t * 60) * Math.exp(-t * 1.6) * gain;
  }
  return out;
}
function drum(dur, gain) {
  const n = Math.floor(dur * MSR);
  const out = new Float32Array(n);
  for (let i = 0; i < n; i++) {
    const t = i / MSR;
    out[i] = (sine(55 + 90 * Math.exp(-t * 30), t) * Math.exp(-t * 9) + noise() * 0.15 * Math.exp(-t * 40)) * gain;
  }
  return out;
}
function shaker(gain) {
  const n = Math.floor(0.06 * MSR);
  const out = new Float32Array(n);
  let hp = 0, prev = 0;
  for (let i = 0; i < n; i++) {
    const x = noise();
    hp = 0.6 * (hp + x - prev); prev = x;
    out[i] = hp * Math.exp(-i / MSR * 70) * gain;
  }
  return out;
}
const ARP = [0, 1, 2, 1, 2, 0, 1, 2];
for (let pass = 0; pass < 2; pass++) {
  const t0 = pass * LOOP;
  CHORDS.forEach((ch, b) => {
    const tb = t0 + b * BAR;
    add(tb, pad(ch, BAR + 0.6, 0.045));
    add(tb, bass(ch[0] - 12, BEAT * 2, 0.22));
    add(tb + BEAT * 2, bass(ch[0] - 12, BEAT * 2, 0.18));
    add(tb, drum(0.5, 0.32));
    add(tb + BEAT * 2.5, drum(0.4, 0.2));
    for (let k = 0; k < 8; k++) {
      const note = ch[ARP[k]] + 12 + (k === 7 && b % 2 === 1 ? 12 : 0);
      add(tb + k * BEAT / 2, pluck(midi(note), 1.4, b >= 4 ? 0.16 : 0.12));
      if (k % 2 === 1) add(tb + k * BEAT / 2, shaker(0.05));
    }
    if (b === 3 || b === 7) {
      // little melodic turn at phrase ends
      [ch[2] + 24, ch[1] + 24, ch[0] + 24].forEach((m, i) => add(tb + BEAT * (2 + i * 0.5), pluck(midi(m), 1.2, 0.1)));
    }
  });
}
// Simple feedback echo for space (wraps inside the doubled buffer)
const D = Math.floor(BEAT * 0.75 * MSR);
for (let i = D; i < buf.length; i++) buf[i] += buf[i - D] * 0.28;
const loop = buf.slice(N, N * 2);
let peak = 0;
for (const v of loop) peak = Math.max(peak, Math.abs(v));
for (let i = 0; i < loop.length; i++) loop[i] = loop[i] / peak * 0.8;
fs.writeFileSync(`${OUT}/music.wav`, wavBuffer(loop, MSR));

const comp = (name, group, looping, gain) =>
  `embedded_components {\n  id: "${name}"\n  type: "sound"\n  data: "sound: \\"/main/assets/sounds/${name}.wav\\"\\n"\n  "looping: ${looping}\\n"\n  "group: \\"${group}\\"\\n"\n  "gain: ${gain}\\n"\n}\n`;
const go = SOUNDS.map(([name]) => comp(name, 'sfx', 0, '1.0')).join('') + comp('music', 'music', 1, '0.55');
fs.writeFileSync('main/sounds.go', go);
console.log(`Generated ${SOUNDS.length} SFX + music loop (${(LOOP).toFixed(1)}s, ${(loop.length * 2 / 1024).toFixed(0)} KB) + main/sounds.go`);
