// Records the test clips from corpus.json into tests/local/audio/<id>.wav.
// Usage: node tests/local/record.ts [--redo] [id ...]
import { spawn, spawnSync } from "node:child_process";
import { existsSync, mkdirSync, readFileSync } from "node:fs";
import { createInterface } from "node:readline/promises";
import { dirname, join } from "node:path";
import { fileURLToPath } from "node:url";

type Clip = { id: string; lang: string; text: string; note?: string };

const here = dirname(fileURLToPath(import.meta.url));
const root = join(here, "..", "..");
const audioDir = join(here, "audio");
const bin = join(root, "build", "tools", "record");
const corpus: Clip[] = JSON.parse(readFileSync(join(here, "corpus.json"), "utf8"));

const args = process.argv.slice(2);
const redo = args.includes("--redo");
const only = args.filter((a) => !a.startsWith("--"));

mkdirSync(audioDir, { recursive: true });
mkdirSync(dirname(bin), { recursive: true });
if (!existsSync(bin)) {
  console.log("compiling the recorder...");
  const r = spawnSync("swiftc", ["-O", join(root, "tools", "record", "record.swift"), "-o", bin], { stdio: "inherit" });
  if (r.status !== 0) process.exit(1);
}

const rl = createInterface({ input: process.stdin, output: process.stdout });
const todo = corpus.filter((c) => (only.length ? only.includes(c.id) : true) && (redo || !existsSync(join(audioDir, `${c.id}.wav`))));
console.log(`${todo.length} clip(s) to record. Speak at a normal pace, as you would while dictating.\n`);

for (const [i, clip] of todo.entries()) {
  console.log(`--- ${i + 1}/${todo.length}: ${clip.id} (${clip.lang})${clip.note ? `  [${clip.note}]` : ""}`);
  console.log(clip.text ? `Read this:\n\n  ${clip.text}\n` : "(say nothing)\n");
  await rl.question("Press Enter to start recording... ");
  const child = spawn(bin, [join(audioDir, `${clip.id}.wav`)], { stdio: ["pipe", "pipe", "inherit"] });
  const started = new Promise<void>((resolve) => child.stdout.on("data", (d) => String(d).includes("recording") && resolve()));
  const exited = new Promise<number>((resolve) => child.on("exit", (code) => resolve(code ?? 1)));
  await Promise.race([started, exited.then(() => {})]);
  await rl.question("Recording. Press Enter to stop... ");
  child.stdin.write("\n");
  const code = await exited;
  if (code !== 0) {
    console.error(`recorder failed (exit ${code})`);
    process.exit(1);
  }
  console.log("");
}
rl.close();
console.log("Done. Clips are in tests/local/audio/.");
