# FnDictate

Hold **Fn** on your Mac, speak, release. What you said is cleaned up (fillers and false starts removed, punctuation fixed), translated if you want, and pasted into whatever text field is focused.

- **Fn** (hold) – record while held, paste on release
- **Fn + Shift** – start recording hands-free; press Fn again to stop
- **Esc** – cancel

It can run in the cloud, fully on your Mac, or mixed. You choose in Settings.

## Install

Needs a Mac with Apple silicon, macOS 26 or newer, and Node.js.

```bash
npx github:iamberestov/fn-dictate
```

This puts `FnDictate.app` in `/Applications` (or `~/Applications` if your account can't write there) and starts it. Run the same command again to update.

## Set up

On first launch the Settings window opens. Settings are always in the menu bar icon → **Settings…**

1. **Provider** – where cleanup and translation run:
   - *Claude – API key* or *OpenAI / Codex – API key*: paste your key; it is stored in your Keychain.
   - *Claude Code CLI* or *Codex CLI*: no key, uses the CLI you are already signed in to.
   - *Ollama – on this Mac*: a local model, no key.
2. **Speech to text** – *Whisper* (default on a fresh install) and *Parakeet* run on your Mac; *Apple* is built in and is what you keep if you used FnDictate before.
3. **I speak / Paste as** – your spoken language and the language to paste (or *Same as spoken* to skip translation).
4. **Test**, then **Save**.

Choose *Whisper* or *Parakeet* plus *Ollama* to keep everything on your Mac. Models, speeds and caveats are in [docs/local.md](docs/local.md).

Then grant what macOS asks for (the Settings window shows what is missing):

| Permission | Why |
| --- | --- |
| Microphone | record while Fn is held |
| Input Monitoring | notice the Fn key |
| Accessibility | paste into the focused field |
| Speech Recognition | only for the *Apple* speech engine |

Also set **System Settings → Keyboard → Press 🌐 key to → Do Nothing**, so Fn doesn't open the emoji picker.

## Where your data goes

- **Speech to text:** *Whisper* and *Parakeet* keep audio on the Mac. *Apple* keeps languages with an on-device model (English, among others) on the Mac and sends others, such as Russian, to Apple, like macOS dictation.
- **Cleanup and translation:** *Ollama* sends the transcript to your Ollama server (by default on this Mac). Other providers send it to Anthropic or OpenAI, directly or through their CLI.
- Nothing else leaves the Mac. The debug log (off by default) writes transcripts to `~/Library/Logs/FnDictate.log`.

## Troubleshooting

- **Menu shows `Accessibility ✗` after you granted it:** the grant belongs to an older build. Quit FnDictate, run `tccutil reset Accessibility com.igor.fndictate`, start it and allow again. This happens after every rebuild of an ad-hoc signed build (see below).
- Anything else: turn on the debug log in Settings and read `~/Library/Logs/FnDictate.log`. Local-model problems are covered in [docs/local.md](docs/local.md#troubleshooting).

## Uninstall

```bash
npx github:iamberestov/fn-dictate uninstall
```

Downloaded speech models stay on disk. Remove them in Settings first, or see [docs/local.md](docs/local.md#speech-engines) for the folders.

## Build from source

```bash
./build.sh      # builds build/FnDictate.app
./release.sh    # builds and packs dist/FnDictate.app.zip for the installer
```

Needs Swift 6.2 or newer (Xcode or the Command Line Tools). For the local options see [docs/local.md](docs/local.md#building-with-local-support); to compare local models on your own voice see [docs/local.md](docs/local.md#testing-the-local-models).

`build.sh` signs with a code-signing certificate named `FnDictate Dev` when your Keychain has one (create it in Keychain Access → Certificate Assistant → Create a Certificate, type *Code Signing*). A stable signature keeps macOS permissions across rebuilds; without it the app is signed ad hoc and the permissions reset on every build.
