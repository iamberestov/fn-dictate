# FnDictate

Hold **Fn** on your Mac, speak, release. What you said is cleaned up (fillers and false starts removed, punctuation fixed), translated if you want, and pasted into whatever text field is focused.

- **Fn** (hold) – record while held, paste on release
- **Fn + Shift** – start recording hands-free; press Fn again to stop
- **Esc** – cancel

## Install

Needs a Mac with Apple silicon, macOS 26 or newer, and Node.js.

```bash
npx github:iamberestov/fn-dictate
```

This puts `FnDictate.app` in `~/Applications` and starts it. Run the same command again to update.

On first launch the Settings window opens:

1. **Provider** – where the text cleanup and translation runs:
   - *Claude – API key* or *OpenAI / Codex – API key*: paste your key; it is stored in your Keychain.
   - *Claude Code CLI* or *Codex CLI*: no key, uses the CLI you are already signed in to.
2. **I speak / Paste as** – your spoken language and the language to paste (or *Same as spoken* to skip translation).
3. **Test**, then **Save**.

Then grant what macOS asks for (the Settings window shows what is missing):

| Permission | Why |
| --- | --- |
| Microphone | record while Fn is held |
| Speech Recognition | turn speech into text |
| Input Monitoring | notice the Fn key |
| Accessibility | paste into the focused field |

Also set **System Settings → Keyboard → Press 🌐 key to → Do Nothing**, so Fn doesn't open the emoji picker.

Settings are always in the menu bar icon → **Settings…**

## Where your data goes

- **Speech to text** uses Apple's speech recognition. Languages with an on-device model (English, among others) stay on the Mac; others, such as Russian, are sent to Apple, like macOS dictation.
- **Cleanup and translation** sends the transcript to the provider you chose (Anthropic or OpenAI, directly or through their CLI).
- Nothing else leaves the Mac. The debug log (off by default) writes transcripts to `~/Library/Logs/FnDictate.log`.

## Uninstall

```bash
npx github:iamberestov/fn-dictate uninstall
```

## Build from source

```bash
./build.sh      # builds build/FnDictate.app
./release.sh    # builds and packs dist/FnDictate.app.zip for the installer
```

`build.sh` signs with a code-signing certificate named `FnDictate Dev` when your Keychain has one (create it in Keychain Access → Certificate Assistant → Create a Certificate, type *Code Signing*). A stable signature keeps macOS permissions across rebuilds; without it the app is signed ad hoc and the permissions reset on every build.
