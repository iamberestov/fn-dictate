// Runs speech engines over the recorded clips and reports word error rate (WER) and timing.
// Needs clips from `node tests/local/record.ts`. Models download on first use (hundreds of MB to ~1.6 GB).
// Usage: node tests/local/stt.ts [engine ...]
//   engines: apple, parakeet, parakeet-hint, whisper, whisper-turbo   (default: all)
import { spawn, spawnSync } from "node:child_process";
import { existsSync, mkdirSync, readFileSync, writeFileSync } from "node:fs";
import { dirname, join } from "node:path";
import { fileURLToPath } from "node:url";

type Clip = { id: string; lang: string; text: string };

const here = dirname(fileURLToPath(import.meta.url));
const pkg = join(here, "..", "..", "tools", "stt-bench");
const bin = join(pkg, ".build", "release", "stt-bench");
const corpus: Clip[] = JSON.parse(readFileSync(join(here, "corpus.json"), "utf8"));
const clips = corpus.filter((c) => existsSync(join(here, "audio", `${c.id}.wav`)));

const ENGINES: Record<string, string[]> = {
  apple: ["apple"],
  parakeet: ["parakeet"],
  "parakeet-hint": ["parakeet-hint"],
  whisper: ["whisper", "--model", "large-v3-v20240930_626MB"],
  "whisper-turbo": ["whisper", "--model", "large-v3-v20240930_turbo"],
};
const wanted = process.argv.slice(2).length ? process.argv.slice(2) : Object.keys(ENGINES);
for (const w of wanted) if (!ENGINES[w]) { console.error(`unknown engine ${w}`); process.exit(2); }
if (!clips.length) { console.error("no clips in tests/local/audio; run record.ts first"); process.exit(2); }

if (!existsSync(bin)) {
  console.log("building stt-bench (first time takes a few minutes)...");
  if (spawnSync("swift", ["build", "-c", "release"], { cwd: pkg, stdio: "inherit" }).status !== 0) process.exit(1);
}

// Lowercase, ё->е, strip punctuation. Digits stay digits, so "15:30" vs "пятнадцать тридцать" counts as an error.
const words = (s: string) =>
  s.toLowerCase().replace(/ё/g, "е").replace(/[^\p{L}\p{N}\s]/gu, " ").split(/\s+/).filter(Boolean);

function wer(ref: string, hyp: string): number | null {
  const r = words(ref), h = words(hyp);
  if (!r.length) return null;
  const d = Array.from({ length: r.length + 1 }, (_, i) => [i, ...Array(h.length).fill(0)]);
  for (let j = 1; j <= h.length; j++) d[0][j] = j;
  for (let i = 1; i <= r.length; i++)
    for (let j = 1; j <= h.length; j++)
      d[i][j] = Math.min(d[i - 1][j] + 1, d[i][j - 1] + 1, d[i - 1][j - 1] + (r[i - 1] === h[j - 1] ? 0 : 1));
  return d[r.length][h.length] / r.length;
}

async function runEngine(name: string) {
  const input = clips.map((c) => `${join(here, "audio", `${c.id}.wav`)}\t${c.lang}`).join("\n") + "\n";
  const child = spawn(bin, ENGINES[name], { stdio: ["pipe", "pipe", "inherit"] });
  child.stdin.end(input);
  let buffer = "";
  const events: any[] = [];
  child.stdout.on("data", (d) => {
    buffer += d;
    let i;
    while ((i = buffer.indexOf("\n")) >= 0) {
      const line = buffer.slice(0, i);
      buffer = buffer.slice(i + 1);
      try { events.push(JSON.parse(line)); } catch { console.log(`  ${line}`); }
    }
  });
  const code = await new Promise<number>((r) => child.on("exit", (c) => r(c ?? 1)));
  return { events, code };
}

const median = (xs: number[]) => (xs.length ? [...xs].sort((a, b) => a - b)[Math.floor(xs.length / 2)] : 0);
const pct = (x: number | null) => (x === null ? "  n/a" : `${(x * 100).toFixed(1).padStart(5)}%`);
const summary: any[] = [];

for (const name of wanted) {
  console.log(`\n=== ${name}`);
  const { events, code } = await runEngine(name);
  const load = events.find((e) => e.event === "load");
  if (code !== 0 || load?.error) { console.log(`  failed: ${load?.error ?? `exit ${code}`}`); continue; }
  const warm = events.find((e) => e.event === "warmup");
  const done = events.find((e) => e.event === "done");
  console.log(`  load ${load.loadMs} ms, first transcription ${warm?.ms ?? "?"} ms, memory ${done?.residentMB ?? load.residentMB} MB`);
  const rows: { id: string; lang: string; wer: number | null; ms: number; text: string }[] = [];
  for (const e of events.filter((e) => e.event === "clip")) {
    const clip = clips.find((c) => `${c.id}.wav` === e.file)!;
    if (e.error) { console.log(`  ERR  ${clip.id}: ${e.error}`); continue; }
    const w = wer(clip.text, e.text);
    rows.push({ id: clip.id, lang: clip.lang, wer: w, ms: e.ms, text: e.text });
    const silent = clip.text === "" ? (e.text ? "  <- hallucinated text on silence" : "  (empty, correct)") : "";
    console.log(`  ${clip.id.padEnd(11)} ${pct(w)} ${String(e.ms).padStart(6)} ms  ${e.text}${silent}`);
  }
  const scored = rows.filter((r) => r.wer !== null).map((r) => r.wer as number);
  const avg = scored.reduce((a, b) => a + b, 0) / (scored.length || 1);
  const byLang = ["ru", "en", "uk"].map((l) => {
    const x = rows.filter((r) => r.lang === l && r.wer !== null).map((r) => r.wer as number);
    return `${l} ${pct(x.length ? x.reduce((a, b) => a + b, 0) / x.length : null).trim()}`;
  }).join(", ");
  console.log(`  mean WER ${pct(avg).trim()} (${byLang}), median ${median(rows.map((r) => r.ms))} ms`);
  summary.push({ engine: name, loadMs: load.loadMs, firstMs: warm?.ms, memoryMB: done?.residentMB, meanWer: avg, medianMs: median(rows.map((r) => r.ms)), rows });
}

console.log("\n=== summary");
console.log("engine          mean WER   median ms   load ms   memory MB");
for (const s of summary)
  console.log(`${s.engine.padEnd(15)} ${pct(s.meanWer)}   ${String(s.medianMs).padStart(9)}   ${String(s.loadMs).padStart(7)}   ${String(s.memoryMB).padStart(9)}`);

const dir = join(here, "results");
mkdirSync(dir, { recursive: true });
const file = join(dir, `stt-${new Date().toISOString().replace(/[:.]/g, "-")}.json`);
writeFileSync(file, JSON.stringify(summary, null, 2));
console.log(`\nsaved ${file}`);
