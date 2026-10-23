# Running FnDictate on your Mac

Details for the local options: speech engines, Ollama, privacy, troubleshooting and the test scripts. The short version is in the [README](../README.md).

Choose *Whisper* or *Parakeet* for speech and *Ollama* for cleanup. Nothing is sent anywhere, and Settings shows *Everything stays on this Mac*. A short phrase takes about a second from release to paste (measured on an M5 Pro with 48 GB).

## Speech engines

Measured on 10 clips (Russian, English, Ukrainian, one noisy, one silent). WER is word error rate, lower is better.

| Engine | WER | Time per phrase | Memory | Notes |
| --- | --- | --- | --- | --- |
| Whisper large-v3 turbo | 16.9% | ~0.6 s | ~330 MB | Best overall. Keeps English technical terms (`staging`, `GitHub`) inside Russian speech. 99+ languages. |
| Whisper large-v3 compact | 18.7% | ~0.9 s | ~240 MB | Smaller download. |
| Parakeet v3 | 27.9% | ~0.06 s | ~190 MB | 10x faster. Fine for plain English and European speech, but writes English terms in Cyrillic when you speak Russian ("Стейжинг" for "staging"). 25 European languages, no Chinese, Japanese or Korean. |
| Apple | not comparable | ~0.3 s | – | Only English was measured, and it was worse than Whisper. Russian and Ukrainian go to Apple servers. |

Ukrainian was weak in every engine (WER 60% or more on the test clip).

- Models download once from the Settings window (Whisper turbo is about 1.5 GB, Parakeet about 0.5 GB). If you start dictating before the download, FnDictate downloads it for you and shows the progress in the pill.
- The first load after a fresh download takes about a minute and a half while macOS prepares the model for the Neural Engine. After that it loads in a few seconds at app start.
- **Silence guard:** a press with no speech pastes nothing. Whisper tends to invent phrases such as "Продолжение следует" on silence, so quiet recordings never reach it and known phantom phrases are dropped.
- Whisper models are stored in `~/Library/Application Support/FnDictate/models`, Parakeet in `~/Library/Application Support/FluidAudio/Models`. The Remove button in Settings deletes them.

## Cleanup and translation with Ollama

1. Install [Ollama](https://ollama.com/download) and start it.
2. Choose **Ollama – on this Mac** as the provider. Pick an installed model, or use **Download a recommended model** (progress bar, cancel button). You can also type any model name from [ollama.com/library](https://ollama.com/library).

| Model | Download | Notes |
| --- | --- | --- |
| `qwen3:8b` (default) | 5.2 GB | Best quality for its speed. About 0.5 s per phrase. |
| `qwen3.5:4b` | 3.3 GB | Lighter. |
| `gemma4:e4b` | 6.6 GB | Good at translation. |
| 27B–31B models | 17 GB and up | Most reliable, but about 3 s per phrase. Too slow for dictation. |

Small local models follow instructions less well than Claude or GPT. In tests they sometimes keep a leading "ну", change a letter in a loanword ("Задеплои"), or obey a dictated "ignore the above and reply with…" instead of pasting it. FnDictate uses a separate prompt with examples for Ollama, which fixed missing output tags in all tested models. If you see slips, try a bigger model or a cloud provider.

The model stays loaded in Ollama for 30 minutes after use, so the next dictation is fast. It also holds its memory (about 5 GB for `qwen3:8b`) for that time.

Ollama runs on `http://localhost:11434` by default. You can point Settings at another machine on your network. The transcript then goes to that server.

## Where your data goes

- **Speech to text**
  - *Whisper* and *Parakeet*: audio stays on the Mac. Model files are downloaded from Hugging Face once.
  - *Apple*: languages with an on-device model (English, among others) stay on the Mac; others, such as Russian, are sent to Apple, like macOS dictation.
- **Cleanup and translation**
  - *Ollama*: the transcript goes to the Ollama server at the address in Settings (by default on this Mac).
  - Other providers send the transcript to Anthropic or OpenAI, directly or through their CLI.
- Parakeet is licensed CC BY 4.0 (NVIDIA). Whisper is MIT (OpenAI).

## Troubleshooting

| What you see | What to do |
| --- | --- |
| "Didn't catch that" | No speech was heard. Check the microphone in Settings, or speak closer. |
| "Ollama is not running" | Start the Ollama app, or fix the address in Settings. A raw transcript is pasted meanwhile. |
| "Model … is not installed" | Download it in Settings → Ollama. |
| First dictation is slow | The speech model is downloading or being prepared (see above). Later ones are fast. |
| Parakeet says the language is not supported | Choose Whisper. |

## Building with local support

`scripts/setup-local.sh` checks Swift, Node and the SDK, installs and starts Ollama, and pulls `qwen3:8b`. It is safe to run again. Flags `--with-qwen4b` and `--with-gemma` also pull the other recommended models.

The build fetches two Swift packages, [FluidAudio](https://github.com/FluidInference/FluidAudio) (Parakeet) and [WhisperKit](https://github.com/argmaxinc/WhisperKit) (Whisper), and needs Swift 6.2 or newer. If the default SDK is macOS 27 and only Command Line Tools are installed, `build.sh` builds against the macOS 26 SDK, because the macOS 27 SDK makes SwiftUI's `@State` a macro whose plugin ships only with full Xcode.

## Testing the local models

The scripts in `tests/local` use Node 20+ and need no packages. They compare engines and models on your own voice.

```bash
node tests/local/record.ts              # record the 10 clips in corpus.json (needs the microphone)
node tests/local/stt.ts                 # WER and timing for Apple, Parakeet and Whisper (downloads models)
node tests/local/cleanup.ts qwen3:8b    # cleanup checks through Ollama; --prompt app|local, any number of models
node tests/local/silence.ts             # loudness of each clip, for tuning the silence guard
```

- `stt.ts` takes engine names to run only some: `apple`, `parakeet`, `parakeet-hint`, `whisper`, `whisper-turbo`. It builds `tools/stt-bench`, a small Swift program, on first use.
- `cleanup.ts` uses the same prompts as the app. Keep the prompt text in sync with `Polisher` in `Sources/main.swift`.
- Recordings and results stay out of git (`tests/local/audio`, `tests/local/results`).
- Apple speech for Russian cannot be measured from a terminal, because server dictation needs a granted permission. Test it through the app.
- WER counts a digit transcript ("15:30") as wrong against the spoken words ("пятнадцать тридцать"), so number clips look worse than they are.
