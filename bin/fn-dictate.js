#!/usr/bin/env node
// Installs FnDictate.app into ~/Applications and launches it.
//   npx github:<user>/fn-dictate            install or update
//   npx github:<user>/fn-dictate uninstall  remove the app, its settings and its stored keys
"use strict";

const { execFileSync, spawnSync } = require("node:child_process");
const fs = require("node:fs");
const os = require("node:os");
const path = require("node:path");

const APP_NAME = "FnDictate.app";
const BUNDLE_ID = "com.igor.fndictate";
const root = path.join(__dirname, "..");
const zip = path.join(root, "dist", "FnDictate.app.zip");
const appsDir = path.join(os.homedir(), "Applications");
const target = path.join(appsDir, APP_NAME);

function fail(message) {
  console.error(`\n✗ ${message}\n`);
  process.exit(1);
}

function run(cmd, args, opts = {}) {
  return spawnSync(cmd, args, { stdio: "ignore", ...opts });
}

function checkPlatform() {
  if (process.platform !== "darwin") fail("FnDictate runs on macOS only.");
  if (process.arch !== "arm64") fail("FnDictate needs a Mac with Apple silicon (M1 or newer).");
  const version = execFileSync("sw_vers", ["-productVersion"], { encoding: "utf8" }).trim();
  if (Number(version.split(".")[0]) < 26) fail(`FnDictate needs macOS 26 or newer (this Mac has ${version}).`);
}

function quit() {
  run("pkill", ["-x", "FnDictate"]);
  spawnSync("sleep", ["0.5"]);
}

function install() {
  checkPlatform();
  if (!fs.existsSync(zip)) fail(`Missing ${zip}. Build it with ./release.sh first.`);
  const updating = fs.existsSync(target);
  quit();
  fs.mkdirSync(appsDir, { recursive: true });
  fs.rmSync(target, { recursive: true, force: true });
  execFileSync("ditto", ["-x", "-k", zip, appsDir]);
  run("xattr", ["-dr", "com.apple.quarantine", target]);
  execFileSync("open", [target]);

  console.log(`
✓ FnDictate ${updating ? "updated" : "installed"} in ~/Applications and started.
`);
  if (!updating) {
    console.log(`Next:
  1. In the Settings window that opens, pick Claude or OpenAI/Codex and paste your
     API key (or choose a signed-in CLI), pick your language, then press Test and Save.
  2. Allow the permissions macOS asks for: Microphone, Speech Recognition,
     Accessibility (to paste) and Input Monitoring (to hear the Fn key).
     The Settings window shows which ones are still missing.
  3. System Settings → Keyboard → "Press 🌐 key to" → Do Nothing.

Then click into any text field, hold Fn, speak, and release.
Settings live in the menu bar icon → Settings…
`);
  }
}

function uninstall() {
  quit();
  fs.rmSync(target, { recursive: true, force: true });
  run("defaults", ["delete", BUNDLE_ID]);
  for (const account of ["anthropic", "openai"]) {
    run("security", ["delete-generic-password", "-s", "FnDictate", "-a", account]);
  }
  console.log(`
✓ FnDictate removed. You can also remove it from System Settings → Privacy & Security
  (Accessibility, Input Monitoring, Microphone).
`);
}

const command = process.argv[2] || "install";
if (command === "install" || command === "update") install();
else if (command === "uninstall") uninstall();
else fail(`Unknown command "${command}". Use install or uninstall.`);
