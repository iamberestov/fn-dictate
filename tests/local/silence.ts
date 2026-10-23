// Measures loudness of each recorded clip to pick a silence-gate threshold for Whisper.
// Usage: node tests/local/silence.ts
import { readdirSync, readFileSync } from "node:fs";
import { dirname, join } from "node:path";
import { fileURLToPath } from "node:url";

const dir = join(dirname(fileURLToPath(import.meta.url)), "audio");
const FRAME_MS = 30;

console.log("clip         seconds  rms dBFS  peak dBFS  p90 frame dBFS  frames >-45 dBFS  frames >-35 dBFS");
for (const file of readdirSync(dir).filter((f) => f.endsWith(".wav")).sort()) {
  const buf = readFileSync(join(dir, file));
  const dataAt = buf.indexOf("data") + 8; // 16 kHz mono 16-bit PCM from tools/record
  const n = (buf.length - dataAt) >> 1;
  const sample = (i: number) => buf.readInt16LE(dataAt + i * 2) / 32768;
  const frame = (16000 * FRAME_MS) / 1000;
  const db = (x: number) => (x > 0 ? 20 * Math.log10(x) : -120);
  let sum = 0, peak = 0;
  const frames: number[] = [];
  for (let f = 0; f + frame <= n; f += frame) {
    let s = 0;
    for (let i = f; i < f + frame; i++) { const v = sample(i); s += v * v; peak = Math.max(peak, Math.abs(v)); }
    sum += s;
    frames.push(db(Math.sqrt(s / frame)));
  }
  const sorted = [...frames].sort((a, b) => a - b);
  const p90 = sorted[Math.floor(sorted.length * 0.9)] ?? -120;
  const share = (t: number) => `${((frames.filter((x) => x > t).length / frames.length) * 100).toFixed(0)}%`;
  console.log(
    `${file.replace(".wav", "").padEnd(12)} ${(n / 16000).toFixed(1).padStart(7)}  ${db(Math.sqrt(sum / (frames.length * frame))).toFixed(1).padStart(8)}  ${db(peak).toFixed(1).padStart(9)}  ${p90.toFixed(1).padStart(14)}  ${share(-45).padStart(16)}  ${share(-35).padStart(16)}`,
  );
}
