// Zero-dependency procedural studio SFX + orchestral music loop generator.
// Style: Clash Royale (royal brass fanfares, tactile wooden UI, war drums, coins/chests)
//      + Empires & Puzzles (crystalline gem chimes, elemental magic, driving battle ostinato).
// Outputs: main/assets/sounds/*.wav, bundle_res/common/lazy/sfx/*.wav, main/sounds.go.
// Usage: node tools/gen_sounds.js
const fs = require('fs');

const OUT = 'main/assets/sounds';
const LAZY_SFX_DIR = 'bundle_res/common/lazy/sfx';
fs.mkdirSync(OUT, { recursive: true });
fs.mkdirSync(LAZY_SFX_DIR, { recursive: true });

const SR = 22050;
const MSR = 16000; // crisp 8kHz bandwidth for lazy music loops with compact bundle size

// Deterministic PRNG so regenerating gives bit-identical WAVs
let seed = 1234567;
const rnd = () => { seed = (seed * 16807) % 2147483647; return seed / 2147483647; };
const noise = () => rnd() * 2 - 1;
const midi = m => 440 * Math.pow(2, (m - 69) / 12);
const sine = (f, t) => Math.sin(2 * Math.PI * f * t);
const tri = (f, t) => 2 * Math.abs(2 * (t * f - Math.floor(t * f + 0.5))) - 1;

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
    buf.writeInt16LE(Math.round(v * 30000), 44 + i * 2);
  }
  return buf;
}

// ----------------------------------------------------------------- DSP toolkit
function biquad(type, f0, q, rate = SR, gainDb = 0) {
  const fc = Math.max(20, Math.min(f0, rate * 0.48));
  const w0 = 2 * Math.PI * fc / rate;
  const cosW0 = Math.cos(w0), sinW0 = Math.sin(w0);
  const alpha = sinW0 / (2 * Math.max(0.1, q));
  let b0, b1, b2, a0, a1, a2;
  if (type === 'lowpass') {
    b0 = (1 - cosW0) / 2; b1 = 1 - cosW0; b2 = b0;
    a0 = 1 + alpha; a1 = -2 * cosW0; a2 = 1 - alpha;
  } else if (type === 'highpass') {
    b0 = (1 + cosW0) / 2; b1 = -(1 + cosW0); b2 = b0;
    a0 = 1 + alpha; a1 = -2 * cosW0; a2 = 1 - alpha;
  } else if (type === 'bandpass') {
    b0 = alpha; b1 = 0; b2 = -alpha;
    a0 = 1 + alpha; a1 = -2 * cosW0; a2 = 1 - alpha;
  } else { // peaking
    const A = Math.pow(10, gainDb / 40);
    b0 = 1 + alpha * A; b1 = -2 * cosW0; b2 = 1 - alpha * A;
    a0 = 1 + alpha / A; a1 = -2 * cosW0; a2 = 1 - alpha / A;
  }
  const inv = 1 / a0;
  const B0 = b0 * inv, B1 = b1 * inv, B2 = b2 * inv, A1 = a1 * inv, A2 = a2 * inv;
  let x1 = 0, x2 = 0, y1 = 0, y2 = 0;
  return (x) => {
    const y = B0 * x + B1 * x1 + B2 * x2 - A1 * y1 - A2 * y2;
    x2 = x1; x1 = x; y2 = y1; y1 = y;
    return y;
  };
}

function mixInto(dst, src, startSec, rate = SR, gain = 1) {
  const s0 = Math.floor(startSec * rate);
  for (let i = 0; i < src.length; i++) {
    const k = s0 + i;
    if (k >= 0 && k < dst.length) dst[k] += src[i] * gain;
  }
}

function normalize(buf, targetPeak = 0.88) {
  let peak = 0;
  for (let i = 0; i < buf.length; i++) {
    const a = Math.abs(buf[i]);
    if (a > peak) peak = a;
  }
  if (peak > 1e-6) {
    const g = targetPeak / peak;
    for (let i = 0; i < buf.length; i++) buf[i] *= g;
  }
  // Short boundary fade (2ms) so zero clicks ever occur
  const fade = Math.min(48, Math.floor(buf.length * 0.1));
  for (let i = 0; i < fade; i++) {
    const k = i / fade;
    buf[i] *= k;
    buf[buf.length - 1 - i] *= k;
  }
  return buf;
}

function reverb(samples, wet = 0.28, decay = 0.78, rate = SR) {
  const combDelays = [1116, 1188, 1277, 1356].map(d => Math.max(8, Math.floor(d * rate / 44100)));
  const combBufs = combDelays.map(len => new Float32Array(len));
  const combIdx = [0, 0, 0, 0];
  const combStore = [0, 0, 0, 0];
  const apDelays = [225, 556].map(d => Math.max(8, Math.floor(d * rate / 44100)));
  const apBufs = apDelays.map(len => new Float32Array(len));
  const apIdx = [0, 0];
  const out = new Float32Array(samples.length);
  for (let i = 0; i < samples.length; i++) {
    const x = samples[i];
    let sum = 0;
    for (let c = 0; c < 4; c++) {
      const ptr = combIdx[c];
      const r = combBufs[c][ptr];
      combStore[c] = r * 0.78 + combStore[c] * 0.22;
      combBufs[c][ptr] = x + combStore[c] * decay;
      combIdx[c] = (ptr + 1) % combDelays[c];
      sum += r;
    }
    let ap = sum * 0.25;
    for (let a = 0; a < 2; a++) {
      const ptr = apIdx[a];
      const r = apBufs[a][ptr];
      const w = ap + r * 0.5;
      apBufs[a][ptr] = w;
      ap = r - w * 0.5;
      apIdx[a] = (ptr + 1) % apDelays[a];
    }
    out[i] = x * (1 - wet) + ap * wet;
  }
  return out;
}

// ----------------------------------------------------------------- Instruments
// Royal Brass (Trumpet / French Horn / War Horn)
function brass(freq, dur, gain = 0.5, bright = 1.0, rate = SR) {
  const n = Math.floor(dur * rate);
  const out = new Float32Array(n);
  const f1 = biquad('peaking', 460, 2.0, rate, 5);
  const f2 = biquad('peaking', 1200 * bright, 2.5, rate, 7);
  const lp = biquad('lowpass', Math.min(rate * 0.45, freq * (4.2 * bright + 1.5)), 0.85, rate);
  let ph1 = 0, ph2 = 0.13;
  for (let i = 0; i < n; i++) {
    const t = i / rate;
    const atk = Math.min(1, t / 0.018);
    const rel = Math.min(1, (dur - t) / Math.min(0.08, dur * 0.25));
    const sus = 0.75 + 0.25 * Math.exp(-t * 4);
    const vib = t > 0.09 ? Math.sin(2 * Math.PI * 5.2 * t) * 0.007 : 0;
    const scoop = t < 0.025 ? -0.025 * (1 - t / 0.025) : 0; // lip attack scoop
    const cf = freq * (1 + vib + scoop);
    ph1 = (ph1 + cf / rate) % 1;
    ph2 = (ph2 + (cf * 1.003) / rate) % 1;
    const saw1 = 2 * ph1 - 1;
    const saw2 = 2 * ph2 - 1;
    let s = Math.tanh((saw1 + saw2 * 0.55) * 1.6);
    if (t < 0.016) s += noise() * 0.22 * (1 - t / 0.016); // brass lip chiff
    s = lp(f2(f1(s)));
    out[i] = s * atk * rel * sus * gain;
  }
  return out;
}

// Staccato String Ensemble (Cellos / Violas)
function staccatoString(freq, dur, gain = 0.4, rate = SR) {
  const n = Math.floor(dur * rate);
  const out = new Float32Array(n);
  const body = biquad('peaking', 300, 1.8, rate, 5);
  const lp = biquad('lowpass', 2400, 0.8, rate);
  let p1 = 0, p2 = 0.27, p3 = 0.61;
  for (let i = 0; i < n; i++) {
    const t = i / rate;
    const env = Math.min(1, t / 0.006) * Math.exp(-t / (dur * 0.42)) * Math.min(1, (dur - t) / 0.02);
    p1 = (p1 + freq * 0.996 / rate) % 1;
    p2 = (p2 + freq / rate) % 1;
    p3 = (p3 + freq * 1.004 / rate) % 1;
    const s = ((2 * p1 - 1) + (2 * p2 - 1) + (2 * p3 - 1)) * 0.33;
    out[i] = lp(body(s)) * env * gain;
  }
  return out;
}

// Sustained String / Warm Choir Pad
function stringPad(notes, dur, gain = 0.14, rate = SR) {
  const n = Math.floor(dur * rate);
  const out = new Float32Array(n);
  const lp = biquad('lowpass', 1500, 0.7, rate);
  const hp = biquad('highpass', 110, 0.7, rate);
  const phases = notes.map((_, k) => [(k * 0.17) % 1, (k * 0.41) % 1]);
  for (let i = 0; i < n; i++) {
    const t = i / rate;
    const env = Math.min(1, t / 0.35) * Math.min(1, (dur - t) / 0.45);
    let v = 0;
    for (let k = 0; k < notes.length; k++) {
      const f = midi(notes[k]);
      phases[k][0] = (phases[k][0] + f * 0.997 / rate) % 1;
      phases[k][1] = (phases[k][1] + f * 1.003 / rate) % 1;
      v += (2 * phases[k][0] - 1) + (2 * phases[k][1] - 1);
    }
    out[i] = hp(lp(v / notes.length)) * env * gain;
  }
  return out;
}

// Karplus-Strong Harp / Lute Pluck
function harp(freq, dur, gain = 0.4, bright = 0.995, rate = SR) {
  const n = Math.floor(dur * rate);
  const p = Math.max(2, Math.round(rate / freq));
  const line = new Float32Array(p);
  for (let i = 0; i < p; i++) line[i] = noise();
  const out = new Float32Array(n);
  let idx = 0;
  for (let i = 0; i < n; i++) {
    const a = line[idx], b = line[(idx + 1) % p];
    line[idx] = 0.5 * (a + b) * bright;
    const t = i / rate;
    const atk = Math.min(1, t / 0.003);
    const tail = Math.min(1, (dur - t) / 0.03);
    out[i] = a * gain * atk * tail;
    idx = (idx + 1) % p;
  }
  return out;
}

// Crystal Gem / Glockenspiel Chime (Modal Resonance)
function crystal(freq, dur, gain = 0.55, rate = SR) {
  const n = Math.floor(dur * rate);
  const out = new Float32Array(n);
  const tickHp = biquad('highpass', 2400, 1.0, rate);
  for (let i = 0; i < n; i++) {
    const t = i / rate;
    const tail = Math.min(1, (dur - t) / 0.02);
    const tick = t < 0.005 ? tickHp(noise()) * 0.35 * (1 - t / 0.005) : 0;
    const s1 = sine(freq, t) * Math.exp(-t * 7.5);
    const s2 = sine(freq * 2.0, t) * Math.exp(-t * 12) * 0.4;
    const s3 = sine(freq * 2.756, t) * Math.exp(-t * 20) * 0.32;
    const s4 = sine(freq * 5.404, t) * Math.exp(-t * 36) * 0.16;
    out[i] = (tick + s1 + s2 + s3 + s4) * tail * gain;
  }
  return out;
}

// War Drum / Timpani
function warDrum(freq, dur, gain = 0.7, rate = SR) {
  const n = Math.floor(dur * rate);
  const out = new Float32Array(n);
  const lp = biquad('lowpass', 650, 0.9, rate);
  let ph = 0;
  for (let i = 0; i < n; i++) {
    const t = i / rate;
    const f = freq * (1 + 1.45 * Math.exp(-t * 36));
    ph += f / rate;
    const skin = Math.sin(2 * Math.PI * ph) * Math.exp(-t * 5.8);
    const mode2 = Math.sin(2 * Math.PI * ph * 1.59) * Math.exp(-t * 14) * 0.35;
    const beater = t < 0.015 ? lp(noise()) * 0.55 * (1 - t / 0.015) : 0;
    out[i] = Math.tanh((skin + mode2 + beater) * 1.35) * Math.min(1, t * 200) * Math.min(1, (dur - t) / 0.03) * gain;
  }
  return out;
}

// Military Marching Snare
function snare(dur, gain = 0.45, rate = SR) {
  const n = Math.floor(dur * rate);
  const out = new Float32Array(n);
  const bp = biquad('bandpass', 3000, 1.2, rate);
  const hp = biquad('highpass', 1200, 0.8, rate);
  let ph = 0;
  for (let i = 0; i < n; i++) {
    const t = i / rate;
    const f = 175 + 140 * Math.exp(-t * 45);
    ph += f / rate;
    const shell = Math.sin(2 * Math.PI * ph) * Math.exp(-t * 24) * 0.55;
    const wires = hp(bp(noise())) * Math.exp(-t * 16) * 1.4;
    out[i] = (shell + wires) * Math.min(1, t * 250) * Math.min(1, (dur - t) / 0.015) * gain;
  }
  return out;
}

// Orchestral Crash Cymbal
function cymbal(dur, gain = 0.35, rate = SR) {
  const n = Math.floor(dur * rate);
  const out = new Float32Array(n);
  const hp = biquad('highpass', 3600, 0.8, rate);
  const modes = [412, 683, 1029, 1511, 2287, 3413];
  for (let i = 0; i < n; i++) {
    const t = i / rate;
    let metal = 0;
    for (let m = 0; m < modes.length; m++) metal += sine(modes[m], t);
    const sig = hp(noise() * (0.65 + 0.35 * (metal / modes.length)));
    const env = Math.min(1, t * 80) * Math.exp(-t / (dur * 0.36)) * Math.min(1, (dur - t) / 0.05);
    out[i] = sig * env * gain;
  }
  return out;
}

// Shaker / Tambourine
function shaker(gain = 0.25, rate = SR) {
  const dur = 0.065;
  const n = Math.floor(dur * rate);
  const out = new Float32Array(n);
  const hp = biquad('highpass', 4800, 1.0, rate);
  for (let i = 0; i < n; i++) {
    const t = i / rate;
    out[i] = hp(noise()) * Math.min(1, t * 200) * Math.exp(-t * 65) * gain;
  }
  return out;
}

// Helper to render a fanfare / melody buffer with reverb
function renderScore(dur, events, wet = 0.32, decay = 0.76, rate = SR) {
  const buf = new Float32Array(Math.floor(dur * rate));
  for (const [t, samples] of events) mixInto(buf, samples, t, rate, 1);
  return normalize(reverb(buf, wet, decay, rate));
}

// ----------------------------------------------------------------- SFX Library
function buildSounds() {
  const map = {};

  // 1. button: Clash Royale snappy wooden/stone pop
  {
    const dur = 0.075;
    const out = new Float32Array(Math.floor(dur * SR));
    const wood = biquad('bandpass', 270, 2.2, SR);
    const snap = biquad('highpass', 2400, 1.0, SR);
    let ph = 0;
    for (let i = 0; i < out.length; i++) {
      const t = i / SR;
      const f = 260 + 180 * Math.exp(-t * 95);
      ph += f / SR;
      const pop = Math.sin(2 * Math.PI * ph) * Math.exp(-t * 48);
      const click = t < 0.006 ? snap(noise()) * 0.7 * (1 - t / 0.006) : 0;
      const cav = wood(noise()) * Math.exp(-t * 65) * 1.4;
      out[i] = (pop * 0.65 + click + cav) * Math.min(1, t * 400);
    }
    map.button = normalize(out, 0.78);
  }

  // 2. tap: Empires & Puzzles delicate gemstone/tile touch
  {
    const dur = 0.055;
    const out = new Float32Array(Math.floor(dur * SR));
    const tickHp = biquad('highpass', 3000, 1.1, SR);
    for (let i = 0; i < out.length; i++) {
      const t = i / SR;
      const tick = t < 0.004 ? tickHp(noise()) * 0.55 * (1 - t / 0.004) : 0;
      const body = (sine(780, t) * 0.55 + sine(1560, t) * 0.25) * Math.exp(-t * 62);
      out[i] = (tick + body) * Math.min(1, t * 450);
    }
    map.tap = normalize(out, 0.72);
  }

  // 3. blocked: Tactile double wooden knock descending
  {
    const dur = 0.16;
    const out = new Float32Array(Math.floor(dur * SR));
    const knock = (f0, d) => {
      const buf = new Float32Array(Math.floor(d * SR));
      const bp = biquad('bandpass', f0 * 1.4, 2.4, SR);
      let ph = 0;
      for (let i = 0; i < buf.length; i++) {
        const t = i / SR;
        ph += (f0 * (1 - t * 1.8)) / SR;
        buf[i] = (Math.sin(2 * Math.PI * ph) * 0.7 + bp(noise()) * 0.9) * Math.exp(-t * 38) * Math.min(1, t * 300);
      }
      return buf;
    };
    mixInto(out, knock(195, 0.075), 0);
    mixInto(out, knock(140, 0.085), 0.07);
    map.blocked = normalize(out, 0.80);
  }

  // 4. match: Empires & Puzzles crystalline gem match (scales cleanly up on cascade)
  {
    const dur = 0.34;
    const out = new Float32Array(Math.floor(dur * SR));
    mixInto(out, crystal(midi(76), 0.32, 0.65), 0);       // E5
    mixInto(out, crystal(midi(83), 0.30, 0.35), 0.014);   // B5 harmonic shimmer
    mixInto(out, crystal(midi(88), 0.26, 0.22), 0.026);   // E6 top sparkle
    map.match = normalize(reverb(out, 0.22, 0.72), 0.86);
  }

  // 5. combo: Big match / cascade 3+ shimmering arpeggio + magic burst
  {
    const notes = [76, 80, 83, 88, 92]; // E5 G#5 B5 E6 G#6
    const ev = notes.map((m, i) => [i * 0.045, crystal(midi(m), 0.35, 0.45)]);
    ev.push([0, harp(midi(64), 0.45, 0.35)]);
    map.combo = renderScore(0.55, ev, 0.32, 0.78);
  }

  // 6. hit: Meaty combat strike (kick punch + armor crunch)
  {
    const dur = 0.22;
    const out = new Float32Array(Math.floor(dur * SR));
    const bp = biquad('bandpass', 650, 1.1, SR);
    const lp = biquad('lowpass', 2200, 0.8, SR);
    let ph = 0;
    for (let i = 0; i < out.length; i++) {
      const t = i / SR;
      const f = 60 + 170 * Math.exp(-t * 48);
      ph += f / SR;
      const thud = Math.sin(2 * Math.PI * ph) * Math.exp(-t * 16);
      const snap = t < 0.012 ? lp(noise()) * 1.1 * (1 - t / 0.012) : 0;
      const crunch = bp(noise()) * Math.exp(-t * 22) * 0.9;
      out[i] = Math.tanh((thud * 0.95 + snap + crunch) * 1.4) * Math.min(1, t * 350);
    }
    map.hit = normalize(reverb(out, 0.14, 0.65), 0.90);
  }

  // 7. crit: Anvil hammer crash + sub boom + bright steel ring
  {
    const dur = 0.38;
    const out = new Float32Array(Math.floor(dur * SR));
    mixInto(out, warDrum(52, 0.35, 0.85), 0);
    mixInto(out, crystal(1180, 0.32, 0.45), 0);
    mixInto(out, crystal(1890, 0.26, 0.30), 0.006);
    const bp = biquad('bandpass', 1800, 1.3, SR);
    for (let i = 0; i < Math.floor(0.18 * SR); i++) {
      const t = i / SR;
      out[i] += bp(noise()) * Math.exp(-t * 26) * 0.75;
    }
    map.crit = normalize(reverb(out, 0.24, 0.74), 0.92);
  }

  // 8. slash: Razor-sharp steel sword cut
  {
    const dur = 0.20;
    const out = new Float32Array(Math.floor(dur * SR));
    const steel = biquad('bandpass', 3200, 3.2, SR);
    const air = biquad('bandpass', 900, 0.9, SR);
    for (let i = 0; i < out.length; i++) {
      const t = i / SR;
      const env = Math.sin(Math.PI * Math.min(1, t / 0.14)) * Math.exp(-t * 9);
      const shing = steel(noise()) * Math.exp(-t * 18) * 1.6;
      const swish = air(noise()) * env * 1.1;
      const bite = t > 0.04 && t < 0.09 ? sine(2850, t) * 0.18 * Math.exp(-(t - 0.04) * 45) : 0;
      out[i] = shing + swish + bite;
    }
    map.slash = normalize(reverb(out, 0.16, 0.68), 0.88);
  }

  // 9. arrow: Bowstring twang + whistling arrow flight
  {
    const dur = 0.22;
    const out = new Float32Array(Math.floor(dur * SR));
    mixInto(out, harp(175, 0.16, 0.7, 0.985), 0);
    const whistle = biquad('bandpass', 2600, 3.8, SR);
    for (let i = 0; i < out.length; i++) {
      const t = i / SR;
      if (t > 0.015) {
        const lt = t - 0.015;
        const air = whistle(noise()) * Math.min(1, lt * 60) * Math.exp(-lt * 18);
        const w = sine(2600 - lt * 4500, t) * 0.12 * Math.exp(-lt * 22);
        out[i] += air * 1.4 + w;
      }
    }
    map.arrow = normalize(out, 0.86);
  }

  // 10. spell: Arcane magic projectile swirl + shimmer
  {
    const dur = 0.40;
    const out = new Float32Array(Math.floor(dur * SR));
    const bp = biquad('bandpass', 1400, 1.5, SR);
    for (let i = 0; i < out.length; i++) {
      const t = i / SR;
      const env = Math.min(1, t * 35) * Math.exp(-t * 5.2);
      const fm = sine(520 + sine(18, t) * 90 + t * 550, t);
      const fm2 = sine(1040 + sine(24, t) * 140 + t * 800, t) * 0.45;
      const dust = bp(noise()) * Math.exp(-t * 7) * 0.45;
      out[i] = (fm + fm2 + dust) * env;
    }
    mixInto(out, crystal(midi(84), 0.30, 0.25), 0.05);
    map.spell = normalize(reverb(out, 0.32, 0.78), 0.86);
  }

  // 11. dash: Fast aerodynamic lunge whoosh
  {
    const dur = 0.16;
    const out = new Float32Array(Math.floor(dur * SR));
    const lp = biquad('bandpass', 620, 0.9, SR);
    for (let i = 0; i < out.length; i++) {
      const t = i / SR;
      const k = Math.sin(Math.PI * t / dur);
      out[i] = lp(noise()) * k * k * 1.4 + sine(160 - t * 400, t) * 0.2 * k;
    }
    map.dash = normalize(out, 0.82);
  }

  // 12. heal: Warm ascending celestial harp & chime cascade
  {
    const notes = [65, 69, 72, 76, 79, 84]; // F4 A4 C5 E5 G5 C6
    const ev = notes.map((m, i) => [i * 0.048, harp(midi(m), 0.42, 0.38)]);
    ev.push([0.08, crystal(midi(79), 0.38, 0.28)]);
    ev.push([0.18, crystal(midi(84), 0.38, 0.32)]);
    map.heal = renderScore(0.60, ev, 0.38, 0.82);
  }

  // 13. shield: Heavy medieval iron/bronze shield clang
  {
    const dur = 0.35;
    const out = new Float32Array(Math.floor(dur * SR));
    const f0 = 330;
    const partials = [1.0, 1.48, 2.13, 2.89, 3.74];
    const gains = [0.65, 0.45, 0.35, 0.25, 0.15];
    const decays = [8, 12, 16, 22, 30];
    for (let i = 0; i < out.length; i++) {
      const t = i / SR;
      let v = t < 0.01 ? noise() * 0.5 * (1 - t / 0.01) : 0;
      for (let p = 0; p < partials.length; p++) {
        v += sine(f0 * partials[p], t) * gains[p] * Math.exp(-t * decays[p]);
      }
      out[i] = Math.tanh(v * 1.3) * Math.min(1, t * 350);
    }
    mixInto(out, warDrum(95, 0.15, 0.35), 0);
    map.shield = normalize(reverb(out, 0.25, 0.74), 0.88);
  }

  // 14. turn_you: Clash Royale iconic royal trumpet fanfare!
  {
    const ev = [
      [0.00, brass(midi(72), 0.11, 0.55, 1.1)], // C5
      [0.09, brass(midi(76), 0.11, 0.60, 1.15)], // E5
      [0.18, brass(midi(79), 0.12, 0.65, 1.2)], // G5
      [0.29, brass(midi(84), 0.42, 0.80, 1.3)], // C6 held
      [0.29, brass(midi(72), 0.40, 0.45, 0.9)], // C5 harmony
      [0.29, warDrum(73.4, 0.28, 0.45)],
    ];
    map.turn_you = renderScore(0.76, ev, 0.34, 0.80);
  }

  // 15. turn_enemy: Dark enemy war horn + heavy taiko strike
  {
    const ev = [
      [0.00, warDrum(55, 0.45, 0.85)],
      [0.00, brass(midi(38), 0.55, 0.65, 0.65)], // D2 ominous horn
      [0.04, brass(midi(45), 0.55, 0.55, 0.70)], // A2 fifth
      [0.24, brass(midi(37), 0.42, 0.45, 0.60)], // C#2 dissonant drop
    ];
    map.turn_enemy = renderScore(0.74, ev, 0.35, 0.80);
  }

  // 16. win: Grand Clash Royale royal victory fanfare!
  {
    const ev = [
      // Timpani roll -> crash
      [0.00, warDrum(65, 0.22, 0.55)],
      [0.12, snare(0.14, 0.35)],
      [0.22, snare(0.14, 0.45)],
      [0.32, snare(0.14, 0.55)],
      // Trumpet fanfare: G4 -> C5 -> E5 -> G5 -> C6!
      [0.00, brass(midi(67), 0.14, 0.55, 1.1)],
      [0.14, brass(midi(72), 0.14, 0.60, 1.15)],
      [0.28, brass(midi(76), 0.14, 0.65, 1.2)],
      [0.44, brass(midi(79), 0.20, 0.75, 1.25)],
      [0.64, brass(midi(84), 0.72, 0.85, 1.35)],
      // Full victory brass chord on C6 hit
      [0.64, brass(midi(60), 0.70, 0.45, 0.9)],
      [0.64, brass(midi(67), 0.70, 0.45, 0.95)],
      [0.64, brass(midi(76), 0.70, 0.50, 1.1)],
      [0.64, warDrum(65.4, 0.55, 0.80)],
      [0.64, cymbal(0.85, 0.42)],
      // Sparkle finish
      [0.72, crystal(midi(88), 0.45, 0.26)],
      [0.82, crystal(midi(91), 0.45, 0.26)],
      [0.92, crystal(midi(96), 0.45, 0.30)],
    ];
    map.win = renderScore(1.45, ev, 0.36, 0.82);
  }

  // 17. lose: Sombre minor descending brass + muffled war drum
  {
    const ev = [
      [0.00, warDrum(52, 0.45, 0.7)],
      [0.00, brass(midi(57), 0.24, 0.55, 0.75)], // A3
      [0.22, brass(midi(53), 0.24, 0.55, 0.70)], // F3
      [0.44, brass(midi(50), 0.24, 0.55, 0.65)], // D3
      [0.66, brass(midi(49), 0.48, 0.60, 0.58)], // C#3
      [0.66, brass(midi(38), 0.48, 0.45, 0.50)], // D2 low shadow
    ];
    map.lose = renderScore(1.18, ev, 0.34, 0.80);
  }

  // 18. coin: Triple metallic gold coin clink
  {
    const ping = (f, d) => {
      const buf = new Float32Array(Math.floor(d * SR));
      for (let i = 0; i < buf.length; i++) {
        const t = i / SR;
        const s = sine(f, t) * Math.exp(-t * 22) + sine(f * 1.48, t) * 0.45 * Math.exp(-t * 32)
          + sine(f * 2.11, t) * 0.25 * Math.exp(-t * 45);
        buf[i] = s * Math.min(1, t * 500);
      }
      return buf;
    };
    const out = new Float32Array(Math.floor(0.28 * SR));
    mixInto(out, ping(3720, 0.14), 0.00);
    mixInto(out, ping(4480, 0.14), 0.048);
    mixInto(out, ping(5270, 0.18), 0.095);
    map.coin = normalize(reverb(out, 0.18, 0.65), 0.82);
  }

  // 19. star: Sparkling pentatonic glockenspiel cascade
  {
    const notes = [84, 86, 88, 91, 93, 96]; // C6 D6 E6 G6 A6 C7
    const ev = notes.map((m, i) => [i * 0.055, crystal(midi(m), 0.34, 0.42)]);
    map.star = renderScore(0.62, ev, 0.30, 0.78);
  }

  // 20. whoosh: Smooth cinematic UI swoosh
  {
    const dur = 0.28;
    const out = new Float32Array(Math.floor(dur * SR));
    const bp = biquad('bandpass', 850, 0.9, SR);
    for (let i = 0; i < out.length; i++) {
      const t = i / SR;
      const k = Math.sin(Math.PI * t / dur);
      out[i] = bp(noise()) * k * k * 1.3;
    }
    map.whoosh = normalize(out, 0.76);
  }

  // 21. death: Armored collapse + deep thud + battlefield echo
  {
    const ev = [
      [0.00, warDrum(48, 0.55, 0.9)],
      [0.02, crystal(420, 0.25, 0.22)], // armor rattle
      [0.09, crystal(310, 0.25, 0.18)],
      [0.00, brass(midi(45), 0.50, 0.40, 0.55)],
    ];
    map.death = renderScore(0.66, ev, 0.36, 0.80);
  }

  // 22. levelup (lazy): Grand celebratory fanfare + glockenspiel bells
  {
    const ev = [
      [0.00, warDrum(65, 0.3, 0.65)],
      [0.00, brass(midi(67), 0.12, 0.55, 1.1)],
      [0.10, brass(midi(72), 0.12, 0.60, 1.15)],
      [0.20, brass(midi(76), 0.12, 0.65, 1.2)],
      [0.32, brass(midi(79), 0.16, 0.72, 1.25)],
      [0.46, brass(midi(84), 0.55, 0.85, 1.35)],
      [0.46, brass(midi(72), 0.55, 0.50, 1.0)],
      [0.46, cymbal(0.65, 0.38)],
      [0.46, crystal(midi(84), 0.40, 0.45)],
      [0.54, crystal(midi(88), 0.40, 0.40)],
      [0.62, crystal(midi(91), 0.40, 0.40)],
      [0.70, crystal(midi(96), 0.45, 0.45)],
    ];
    map.levelup = renderScore(1.15, ev, 0.35, 0.82);
  }

  // 23. chest (lazy): Lock snap + rising magical shimmer + golden fanfare burst
  {
    const ev = [
      // Heavy wooden/iron lock click
      [0.00, warDrum(140, 0.10, 0.55)],
      // Rising magical harp gliss
      [0.06, harp(midi(60), 0.35, 0.35)],
      [0.11, harp(midi(64), 0.35, 0.35)],
      [0.16, harp(midi(67), 0.35, 0.35)],
      [0.21, harp(midi(72), 0.35, 0.40)],
      // Golden loot burst!
      [0.28, brass(midi(72), 0.48, 0.65, 1.25)],
      [0.28, brass(midi(79), 0.48, 0.60, 1.25)],
      [0.28, cymbal(0.65, 0.32)],
      [0.28, crystal(midi(84), 0.48, 0.42)],
      [0.35, crystal(midi(88), 0.45, 0.38)],
      [0.42, crystal(midi(91), 0.45, 0.38)],
      [0.49, crystal(midi(96), 0.45, 0.40)],
    ];
    map.chest = renderScore(0.95, ev, 0.36, 0.82);
  }

  // 24. upgrade (lazy): Ascending power chord + golden ring
  {
    const ev = [
      [0.00, brass(midi(67), 0.14, 0.50, 1.1)],
      [0.10, brass(midi(72), 0.14, 0.55, 1.15)],
      [0.20, brass(midi(79), 0.35, 0.70, 1.25)],
      [0.20, crystal(midi(84), 0.35, 0.45)],
      [0.26, crystal(midi(91), 0.32, 0.35)],
    ];
    map.upgrade = renderScore(0.58, ev, 0.30, 0.78);
  }

  // 25. quest (lazy): Crisp double royal bell chime
  {
    const ev = [
      [0.00, crystal(midi(78), 0.32, 0.55)], // F#5
      [0.11, crystal(midi(85), 0.38, 0.65)], // C#6
      [0.11, harp(midi(73), 0.38, 0.30)],
    ];
    map.quest = renderScore(0.52, ev, 0.28, 0.78);
  }

  // 26. flip (lazy): Card foil snap + subtle air swoosh
  {
    const dur = 0.15;
    const out = new Float32Array(Math.floor(dur * SR));
    const bp = biquad('bandpass', 2200, 1.5, SR);
    for (let i = 0; i < out.length; i++) {
      const t = i / SR;
      const snap = t < 0.015 ? bp(noise()) * 1.4 * (1 - t / 0.015) : 0;
      const swish = bp(noise()) * Math.sin(Math.PI * t / dur) * 0.45;
      const tone = sine(880 - t * 2400, t) * 0.22 * Math.exp(-t * 32);
      out[i] = snap + swish + tone;
    }
    map.flip = normalize(out, 0.80);
  }

  // 27. turn (lazy): Deep medieval tower bell toll
  {
    const ev = [
      [0.00, crystal(midi(57), 0.55, 0.55)],
      [0.00, crystal(midi(64), 0.50, 0.35)],
    ];
    map.turn = renderScore(0.58, ev, 0.34, 0.80);
  }

  // 28. notify (lazy): Clear friendly notification chime
  {
    const ev = [
      [0.00, crystal(midi(79), 0.22, 0.50)], // G5
      [0.08, crystal(midi(86), 0.28, 0.55)], // D6
    ];
    map.notify = renderScore(0.38, ev, 0.24, 0.75);
  }

  return map;
}

// ----------------------------------------------------------------- Music Loops
// Seamless 2-pass renderer: renders twice and keeps the 2nd pass so reverb tails wrap cleanly.
function renderSeamlessLoop(bars, bpm, renderBar) {
  const beat = 60 / bpm;
  const barDur = beat * 4;
  const loopDur = barDur * bars;
  const N = Math.floor(loopDur * MSR);
  const full = new Float32Array(N * 2);
  for (let pass = 0; pass < 2; pass++) {
    const t0 = pass * loopDur;
    for (let b = 0; b < bars; b++) {
      renderBar(full, b, t0 + b * barDur, beat, barDur);
    }
  }
  const wet = reverb(full, 0.28, 0.76, MSR);
  const loop = wet.slice(N, N * 2);
  // Normalize to -1.5dB (leaves headroom under loud SFX)
  let peak = 0;
  for (let i = 0; i < loop.length; i++) peak = Math.max(peak, Math.abs(loop[i]));
  const g = 0.78 / (peak || 1);
  for (let i = 0; i < loop.length; i++) loop[i] *= g;
  return loop;
}

// 1) Hub / Royal Castle Theme (96 BPM, 8 bars, Am): Clash Royale menu / E&P Stronghold feel
function buildHubMusic() {
  const CHORDS = [
    [57, 60, 64], [53, 57, 60], [48, 52, 55], [55, 59, 62], // Am F C G
    [57, 60, 64], [50, 53, 57], [52, 56, 59], [57, 60, 64], // Am Dm E Am
  ];
  const ARP = [0, 1, 2, 1, 2, 0, 1, 2];
  // Noble horn melody (midi, beat offset, dur in beats)
  const MELODY = {
    0: [[69, 0, 1.5], [72, 1.5, 0.5], [76, 2, 1.5], [74, 3.5, 0.5]],
    1: [[72, 0, 2.0], [69, 2, 1.5], [67, 3.5, 0.5]],
    2: [[64, 0, 1.5], [67, 1.5, 0.5], [72, 2, 2.0]],
    3: [[71, 0, 1.5], [69, 1.5, 0.5], [67, 2, 1.8]],
    4: [[69, 0, 1.5], [72, 1.5, 0.5], [76, 2, 1.5], [79, 3.5, 0.5]],
    5: [[77, 0, 1.5], [76, 1.5, 0.5], [74, 2, 1.8]],
    6: [[76, 0, 1.5], [74, 1.5, 0.5], [71, 2, 1.8]],
    7: [[69, 0, 2.5], [72, 2.5, 0.7], [71, 3.2, 0.7]],
  };

  return renderSeamlessLoop(8, 96, (buf, b, tb, beat, barDur) => {
    const ch = CHORDS[b];
    // Warm string pad
    mixInto(buf, stringPad(ch, barDur + 0.5, 0.14, MSR), tb, MSR);
    // Pizzicato/staccato cello roots
    mixInto(buf, staccatoString(midi(ch[0] - 12), beat * 1.5, 0.34, MSR), tb, MSR);
    mixInto(buf, staccatoString(midi(ch[0] - 12), beat * 1.2, 0.26, MSR), tb + beat * 2, MSR);
    // Light castle frame drum + tambourine
    mixInto(buf, warDrum(62, 0.40, 0.36, MSR), tb, MSR);
    mixInto(buf, warDrum(62, 0.32, 0.24, MSR), tb + beat * 2.5, MSR);
    for (let k = 0; k < 8; k++) {
      const m = ch[ARP[k]] + 12 + (k === 7 && b % 2 === 1 ? 12 : 0);
      mixInto(buf, harp(midi(m), 1.1, b >= 4 ? 0.22 : 0.17, 0.994, MSR), tb + k * beat * 0.5, MSR);
      if (k % 2 === 1) mixInto(buf, shaker(0.14, MSR), tb + k * beat * 0.5, MSR);
    }
    if (MELODY[b]) {
      for (const [m, bo, bd] of MELODY[b]) {
        mixInto(buf, brass(midi(m), bd * beat, 0.22, 0.85, MSR), tb + bo * beat, MSR);
      }
    }
  });
}

// 2) Battle Theme (112 BPM, 16 bars, Dm): Driving War Drums, 16th String Ostinato & Heroic Brass!
function buildBattleMusic() {
  // Dm - Bb - C - Dm | Gm - Dm - Bb - A7 | Dm - F - C - G | Bb - C - Dm - A7
  const CHORDS = [
    [50, 53, 57], [46, 50, 53], [48, 52, 55], [50, 53, 57],
    [43, 46, 50], [50, 53, 57], [46, 50, 53], [45, 49, 52],
    [50, 53, 57], [41, 45, 48], [48, 52, 55], [43, 47, 50],
    [46, 50, 53], [48, 52, 55], [50, 53, 57], [45, 49, 52],
  ];
  const HERO_BRASS = {
    // Section A: Heroic low-mid French horn call
    0: [[62, 0, 1.5], [65, 1.5, 0.5], [69, 2, 1.8]],
    1: [[70, 0, 1.5], [69, 1.5, 0.5], [65, 2, 1.8]],
    2: [[67, 0, 1.5], [65, 1.5, 0.5], [64, 2, 1.8]],
    3: [[62, 0, 3.2]],
    4: [[67, 0, 1.5], [70, 1.5, 0.5], [74, 2, 1.8]],
    5: [[72, 0, 1.5], [69, 1.5, 0.5], [65, 2, 1.8]],
    6: [[70, 0, 1.5], [69, 1.5, 0.5], [67, 2, 1.8]],
    7: [[69, 0, 2.0], [64, 2, 1.8]],
    // Section B: Triumphant Octave-Higher Royal Trumpet Theme!
    8:  [[74, 0, 1.5], [77, 1.5, 0.5], [81, 2, 1.8]],
    9:  [[84, 0, 1.5], [81, 1.5, 0.5], [77, 2, 1.8]],
    10: [[79, 0, 1.5], [77, 1.5, 0.5], [76, 2, 1.8]],
    11: [[74, 0, 1.8], [71, 2, 1.8]],
    12: [[70, 0, 1.5], [74, 1.5, 0.5], [77, 2, 1.8]],
    13: [[79, 0, 1.5], [76, 1.5, 0.5], [72, 2, 1.8]],
    14: [[74, 0, 2.5], [77, 2.5, 0.7], [81, 3.2, 0.7]],
    15: [[81, 0, 1.8], [76, 2, 1.8]],
  };

  return renderSeamlessLoop(16, 112, (buf, b, tb, beat, barDur) => {
    const ch = CHORDS[b];
    const root = ch[0];
    // Pad + Low brass foundation
    mixInto(buf, stringPad(ch, barDur + 0.4, 0.13, MSR), tb, MSR);
    mixInto(buf, brass(midi(root - 12), barDur * 0.9, 0.22, 0.65, MSR), tb, MSR);

    // Driving 16th-note string ostinato (Hans Zimmer / E&P battle momentum)
    const step16 = beat / 4;
    for (let s = 0; s < 16; s++) {
      const accent = (s % 4 === 0) ? 0.34 : (s % 2 === 0 ? 0.22 : 0.15);
      const note = (s === 12 || s === 14) ? ch[1] : root;
      mixInto(buf, staccatoString(midi(note), step16 * 1.15, accent, MSR), tb + s * step16, MSR);
    }

    // War drums + Marching Snare
    mixInto(buf, warDrum(midi(root - 24) * 0.9, 0.38, 0.52, MSR), tb, MSR);
    mixInto(buf, warDrum(midi(root - 24) * 0.9, 0.32, 0.36, MSR), tb + beat * 1.5, MSR);
    mixInto(buf, warDrum(midi(root - 24) * 0.9, 0.36, 0.46, MSR), tb + beat * 2, MSR);
    if (b % 2 === 1) mixInto(buf, warDrum(midi(root - 24), 0.24, 0.34, MSR), tb + beat * 3.5, MSR);

    // Snappy military snare pattern + phrase-end fills
    mixInto(buf, snare(0.14, 0.32, MSR), tb + beat * 1, MSR);
    mixInto(buf, snare(0.14, 0.36, MSR), tb + beat * 3, MSR);
    mixInto(buf, snare(0.10, 0.16, MSR), tb + beat * 2.75, MSR);
    if (b === 3 || b === 7 || b === 11 || b === 15) {
      // Marching snare fill roll!
      for (let r = 0; r < 6; r++) {
        mixInto(buf, snare(0.09, 0.18 + r * 0.04, MSR), tb + beat * (3.0 + r * 0.16), MSR);
      }
    }

    // Cymbal crash at section starts
    if (b === 0 || b === 4 || b === 8 || b === 12) {
      mixInto(buf, cymbal(1.1, 0.26, MSR), tb, MSR);
    }
    // 8th-note high-energy shaker
    for (let k = 0; k < 8; k++) {
      mixInto(buf, shaker(k % 2 === 0 ? 0.12 : 0.08, MSR), tb + k * beat * 0.5, MSR);
    }

    // Heroic French Horn / Trumpet Melody
    if (HERO_BRASS[b]) {
      const bright = b >= 8 ? 1.25 : 0.92;
      const vol = b >= 8 ? 0.30 : 0.26;
      for (const [m, bo, bd] of HERO_BRASS[b]) {
        mixInto(buf, brass(midi(m), bd * beat, vol, bright, MSR), tb + bo * beat, MSR);
      }
    }

    // Harp counterpoint sparkle on section B
    if (b >= 8) {
      for (let k = 0; k < 4; k++) {
        mixInto(buf, harp(midi(ch[k % 3] + 24), 0.7, 0.14, 0.993, MSR), tb + k * beat, MSR);
      }
    }
  });
}

// ----------------------------------------------------------------- Write Output
const LAZY_SFX = new Set(['levelup', 'chest', 'quest', 'upgrade', 'flip', 'turn', 'notify']);
const sfx = buildSounds();

let coreCount = 0;
let lazyCount = 0;
for (const [name, samples] of Object.entries(sfx)) {
  const buf = wavBuffer(samples, SR);
  if (LAZY_SFX.has(name)) {
    fs.writeFileSync(`${LAZY_SFX_DIR}/${name}.wav`, buf);
    lazyCount++;
  } else {
    fs.writeFileSync(`${OUT}/${name}.wav`, buf);
    coreCount++;
  }
}

const hubLoop = buildHubMusic();
const battleLoop = buildBattleMusic();
fs.writeFileSync(`${LAZY_SFX_DIR}/music.wav`, wavBuffer(hubLoop, MSR));
fs.writeFileSync(`${LAZY_SFX_DIR}/music_battle.wav`, wavBuffer(battleLoop, MSR));

const comp = (name, group, looping, gain) =>
  `embedded_components {\n  id: "${name}"\n  type: "sound"\n  data: "sound: \\"/main/assets/sounds/${name}.wav\\"\\n"\n  "looping: ${looping}\\n"\n  "group: \\"${group}\\"\\n"\n  "gain: ${gain}\\n"\n}\n`;
const coreNames = Object.keys(sfx).filter(n => !LAZY_SFX.has(n));
fs.writeFileSync('main/sounds.go', coreNames.map(n => comp(n, 'sfx', 0, '1.0')).join(''));

console.log(
  `Generated ${coreCount} core SFX -> sounds.go, ${lazyCount} lazy SFX + hub music (${(hubLoop.length * 2 / 1024).toFixed(0)} KB) + battle music (${(battleLoop.length * 2 / 1024).toFixed(0)} KB) -> ${LAZY_SFX_DIR}`
);
