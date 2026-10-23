#!/usr/bin/env bash
# Installs and checks everything FnDictate needs for local speech and local cleanup.
# Safe to run many times: it skips what is already done.
#
# Flags:
#   --with-qwen4b   also pull qwen3.5:4b (lighter)
#   --with-gemma    also pull gemma4:e4b (good at translation)
# The default model, qwen3:8b, is always pulled.
set -uo pipefail

OLLAMA_URL="${OLLAMA_URL:-http://localhost:11434}"
MODELS=("qwen3:8b")
for arg in "$@"; do
  case "$arg" in
    --with-qwen4b) MODELS+=("qwen3.5:4b") ;;
    --with-gemma) MODELS+=("gemma4:e4b") ;;
    -h|--help) sed -n '2,8p' "$0"; exit 0 ;;
    *) echo "unknown flag: $arg"; exit 2 ;;
  esac
done

ok()   { printf '  [ok]   %s\n' "$*"; }
info() { printf '  [..]   %s\n' "$*"; }
fail() { printf '  [FAIL] %s\n' "$*"; exit 1; }
step() { printf '\n%s\n' "$*"; }

# version_ge A B: true when version A >= B
version_ge() { [ "$(printf '%s\n%s\n' "$2" "$1" | sort -V | head -n1)" = "$2" ]; }

step "1/5 Mac"
[ "$(uname -s)" = "Darwin" ] || fail "macOS only"
[ "$(uname -m)" = "arm64" ] || fail "Apple silicon only"
macos="$(sw_vers -productVersion)"
version_ge "$macos" "26.0" || fail "macOS 26 or newer needed, found $macos"
ok "macOS $macos, $(uname -m)"

step "2/5 Swift toolchain"
if ! xcode-select -p >/dev/null 2>&1; then
  info "Command Line Tools missing, starting the installer"
  xcode-select --install
  fail "finish the installer window, then run this script again"
fi
swift_version="$(swift --version 2>&1 | sed -n 's/.*Swift version \([0-9][0-9.]*\).*/\1/p' | head -n1)"
[ -n "$swift_version" ] || fail "swift did not report a version; try: xcode-select --install"
version_ge "$swift_version" "6.2" || fail "Swift 6.2 or newer needed, found $swift_version (update Command Line Tools or Xcode)"
ok "Swift $swift_version ($(xcode-select -p))"
sdk_major="$(xcrun --show-sdk-version 2>/dev/null | cut -d. -f1)"
if [ "${sdk_major:-0}" -ge 27 ]; then
  sdk26="$(ls -d "$(xcode-select -p)"/SDKs/MacOSX26.*.sdk 2>/dev/null | sort -V | tail -n1)"
  [ -n "$sdk26" ] || fail "default SDK is macOS $sdk_major and no macOS 26 SDK found; the app needs SwiftUI macros from full Xcode or a macOS 26 SDK"
  ok "default SDK is macOS $sdk_major; build.sh will use $(basename "$sdk26")"
fi

step "3/5 Node.js (only for the test scripts)"
command -v node >/dev/null 2>&1 || fail "Node.js not found; install it (for example: brew install node)"
node_version="$(node --version | sed 's/^v//')"
version_ge "$node_version" "20.0" || fail "Node 20 or newer needed, found $node_version"
ok "Node $node_version"

step "4/5 Ollama"
if ! command -v ollama >/dev/null 2>&1; then
  command -v brew >/dev/null 2>&1 || fail "Ollama missing and Homebrew not found; install from https://ollama.com/download and re-run"
  info "installing Ollama with Homebrew"
  brew install --cask ollama || fail "brew install failed"
fi
ok "ollama $(ollama --version 2>&1 | grep -o '[0-9][0-9.]*' | head -n1)"

server_up() { curl -fsS -m 2 "$OLLAMA_URL/api/version" >/dev/null 2>&1; }
if ! server_up; then
  info "server not answering at $OLLAMA_URL, starting it"
  log="${TMPDIR:-/tmp}/fn-dictate-ollama.log"
  nohup ollama serve >"$log" 2>&1 &
  for _ in $(seq 1 30); do server_up && break; sleep 1; done
  server_up || fail "Ollama server did not start (log: $log). Open the Ollama app and re-run"
fi
ok "server answers at $OLLAMA_URL"

step "5/5 Models"
installed="$(curl -fsS -m 5 "$OLLAMA_URL/api/tags" | grep -o '"name":"[^"]*"' | sed 's/"name":"//;s/"$//')"
for model in "${MODELS[@]}"; do
  if printf '%s\n' "$installed" | grep -qx "$model"; then
    ok "$model already pulled"
  else
    info "pulling $model"
    ollama pull "$model" || fail "could not pull $model"
    ok "$model pulled"
  fi
done

# Smoke test: one short request proves the model loads and answers.
info "smoke test with ${MODELS[0]}"
reply="$(curl -fsS -m 120 "$OLLAMA_URL/api/chat" -d "{\"model\":\"${MODELS[0]}\",\"stream\":false,\"think\":false,\"messages\":[{\"role\":\"user\",\"content\":\"Reply with the single word: ready\"}]}" 2>&1)" \
  || fail "chat request failed: $reply"
printf '%s' "$reply" | grep -qi 'ready' || fail "unexpected reply: $reply"
ok "${MODELS[0]} answers"

printf '\nAll set.\n'
