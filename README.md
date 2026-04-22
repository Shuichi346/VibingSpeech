<table>
  <thead>
    <tr>
      <th style="text-align:center"><a href="README.md">English</a></th>
      <th style="text-align:center"><a href="README_jp.md">日本語</a></th>
    </tr>
  </thead>
</table>

<h1 align="center">VibingSpeech</h1>

<p align="center">
  <strong>Fully on-device macOS voice input app.</strong><br>
  After recording is complete, AI performs batch analysis of the context, enabling transcription with higher accuracy than real-time methods. Since it converts text after understanding the meaning of entire sentences, misconversions of homonyms are significantly reduced. Global hotkey → Record → Transcribe (Qwen3-ASR) → Optional LLM text processing → Paste at cursor.
</p>

<p align="center">
  <img src="https://img.shields.io/badge/platform-macOS%2015%2B-blue" alt="Platform">
  <img src="https://img.shields.io/badge/chip-Apple%20Silicon-black" alt="Apple Silicon">
  <img src="https://img.shields.io/badge/license-MIT-green" alt="License">
  <img src="https://img.shields.io/badge/swift-6.2-orange" alt="Swift">
</p>

---

## Screenshots

<p align="center">
  <img src="docs/README_PNG/UI_main.png" alt="Home — Settings & Status" width="500">
  <br>
  <em>Home — Configure ASR model, text processing, hotkey, and more.</em>
</p>

<p align="center">
  <img src="docs/README_PNG/UI_Hotwords.png" alt="Hotwords — Custom Vocabulary" width="500">
  <br>
  <em>Hotword dictionary for proper nouns &amp; terms.</em>
</p>

<p align="center">
  <img src="docs/README_PNG/UI_History.png" alt="History — Transcription Log" width="500">
  <br>
  <em>Searchable transcription history.</em>
</p>

---

## Features

- ✅ **Global Hotkey** — Hold Right Option to record, release to transcribe (short press for toggle mode)
- ✅ **On-Device Transcription** — Qwen3-ASR models, zero cloud calls, 52-language auto-detection
- ✅ **ASR Model Selection** — Switch between 0.6B (8-bit, ~1 GB), 1.7B (4-bit, ~2.1 GB), and 1.7B (8-bit, ~2.3 GB)
- ✅ **LLM Text Processing** — Optional on-device post-processing via Qwen3.5-4B-MLX-4bit (thinking disabled)
- ✅ **Processing Presets** — "Fix Typos", "Bullet Points", or fully custom prompts
- ✅ **Floating Overlay** — Animated waveform indicator during recording
- ✅ **Hotword Dictionary** — Add custom terms to improve recognition accuracy
- ✅ **Transcription History** — View, copy, and manage past transcriptions
- ✅ **Menu Bar Resident** — Runs in background with no Dock icon
- ✅ **Privacy First** — All processing stays on your Mac, nothing leaves the device

## Requirements

- macOS 15.0+ (Sequoia) — tested on macOS 26 (Tahoe)
- Apple Silicon (M1 or later)
- **Xcode 26+** (full installation from App Store — Command Line Tools alone are not sufficient)
- Internet connection (for first-time model downloads, ~1–4.8 GB)

> **Note:** This app uses AppKit, SwiftUI, AVFoundation, CoreAudio, and Metal frameworks. The full Xcode installation is required to provide the macOS SDK and Metal Toolchain support.

## Setup Guide (From Scratch)

If this is your first time setting up a development environment on your Mac, follow these steps in order.

### Step 1: Install Xcode

1. Open the **App Store** on your Mac
2. Search for **Xcode** and install it (requires Apple ID, ~30 GB download)
3. Launch Xcode once and agree to the license agreement
4. Wait for Xcode to finish installing additional components

Verify:

```bash
# Open Terminal (Applications → Utilities → Terminal)
xcode-select -p
# Expected: /Applications/Xcode.app/Contents/Developer
```

If the path points elsewhere, run:

```bash
sudo xcode-select -s /Applications/Xcode.app
```

> **Why full Xcode?** This project depends on macOS SDK frameworks (AppKit, SwiftUI, AVFoundation, CoreAudio) and the Metal Toolchain. Command Line Tools alone do not include the Metal Toolchain, and `swift build` may fail to locate required frameworks.

### Step 2: Install Metal Toolchain

Starting with Xcode 26, the **Metal Toolchain is no longer bundled** and must be installed separately. VibingSpeech depends on MLX Swift, which compiles Metal shaders at build time.

**Install via Xcode UI:**

1. Open Xcode → Settings → Components
2. Find **Metal Toolchain** under "Other Components"
3. Click **Get**

**Install via command line:**

```bash
xcodebuild -downloadComponent metalToolchain
```

Verify:

```bash
xcrun metal --version
# Expected: metal version 32.x.x
```

> **Note:** If the toolchain doesn't register after download, try:
> ```bash
> xcodebuild -downloadComponent metalToolchain -exportPath /tmp/MetalExport/
> xcodebuild -importComponent metalToolchain -importPath /tmp/MetalExport/*.exportedBundle
> ```

### Step 3: Verify Tools

After installing Xcode, `git`, `swift`, and `make` are all available. Verify:

```bash
git --version
# Expected: git version 2.x.x

swift --version
# Expected: Apple Swift version 6.2.x

make --version
# Expected: GNU Make 3.x.x or 4.x.x
```

## Build & Run

```bash
git clone https://github.com/Shuichi346/VibingSpeech.git
cd VibingSpeech
make build
make run
```

`make build` compiles the Swift package and builds the MLX Metal shader library (`mlx.metallib`). The shader build is cached and only recompiles when sources change.

To create a standalone `.app` bundle:

```bash
make app
open VibingSpeech.app

# Or install to /Applications
cp -r VibingSpeech.app /Applications/
```

### First Launch

On first launch, VibingSpeech automatically downloads the required AI models. **An internet connection is required.**

- **ASR model** (default 0.6B): ~1 GB download
- **Text processing model** (if enabled): ~2.9 GB download

Download progress is shown in the app window. This is a one-time download; models are cached locally for future use.

## Model Cache Location

VibingSpeech downloads two types of models on first launch. Each is cached in a different location on your Mac.

### ASR Model (Qwen3-ASR)

Downloaded via [speech-swift](https://github.com/soniqo/speech-swift) and stored in:

```
~/Library/Caches/qwen3-speech/
```

This directory contains the selected ASR model weights (0.6B, 1.7B, etc.). You can override this location by setting the `QWEN3_CACHE_DIR` environment variable.

### Text Processing Model (Qwen3.5-4B)

Downloaded via [mlx-swift-lm](https://github.com/ml-explore/mlx-swift-lm) using the Hugging Face Hub client and stored in:

```
~/.cache/huggingface/hub/
```

The model files are inside a subdirectory named `models--mlx-community--Qwen3.5-4B-MLX-4bit`. You can override this location by setting the `HF_HOME` or `HF_HUB_CACHE` environment variable.

### Freeing Disk Space

If you want to reclaim disk space, simply delete the directories listed above. VibingSpeech will re-download the required models automatically on the next launch. In total, models can occupy approximately **1 – 4.8 GB** depending on your selected ASR variant and whether text processing is enabled.

> **Tip:** The `~/Library` and `~/.cache` folders are hidden by default in Finder. Press `Cmd + Shift + .` in Finder to reveal hidden files, or navigate directly using Finder → Go → Go to Folder (`Cmd + Shift + G`).

## Permissions

VibingSpeech requires two permissions:

1. **Accessibility** — For global hotkey detection and text insertion
2. **Microphone** — For audio recording

You'll be prompted on first launch. To enable later: System Settings → Privacy & Security.

## How to Use

1. Launch the app — a microphone icon appears in your menu bar
2. **Hold mode:** Press and hold Right Option while speaking, release when done
3. **Toggle mode:** Short press Right Option to start, press again to stop
4. **Cancel:** Press Esc at any time during recording
5. Click the menu bar icon → "Show Window" for settings, hotwords, and history

## ASR Model Selection

| Model | Download | Memory | Best for |
|---|---|---|---|
| Qwen3-ASR 0.6B (8-bit) | ~1.0 GB | ~1.5 GB | General use, fast startup |
| Qwen3-ASR 1.7B (4-bit) | ~2.1 GB | ~3.5 GB | Complex speech, higher accuracy |
| Qwen3-ASR 1.7B (8-bit) | ~2.3 GB | ~4.0 GB | Best accuracy, especially for Japanese |


## Text Processing (LLM)

When enabled, transcribed text is post-processed by an on-device LLM before pasting. **When disabled, the LLM is not loaded** — no extra memory, no extra latency. Since this is a small LLM model, it sometimes mistakes what you say for a prompt.

**Model:** [Qwen3.5-4B-MLX-4bit](https://huggingface.co/mlx-community/Qwen3.5-4B-MLX-4bit) (~2.9 GB download, ~3.5 GB memory)

Thinking (reasoning) mode is **disabled** for fast, direct responses. The model uses optimized non-thinking parameters: temperature=0.7, top_p=0.8, top_k=20, presence_penalty=1.5.

| Preset | What it does |
|---|---|
| **Fix Typos** | Corrects spelling, typos, and grammar while preserving meaning |
| **Bullet Points** | Reformats text into a structured bullet-point list |
| **Custom** | Applies a user-defined system prompt for any processing task |

**Processing flow:** Record → Transcribe (ASR) → Detect language → Process (LLM) → Paste

## Troubleshooting

### `swift build` fails with "no such module" errors

Ensure you have the full Xcode installed (not just Command Line Tools) and it is selected:

```bash
sudo xcode-select -s /Applications/Xcode.app
```

### Metal shader build fails

```bash
xcodebuild -downloadComponent metalToolchain
```

If `xcrun metal` still fails after installing, restart your terminal or select the correct Xcode:

```bash
sudo xcode-select -s /Applications/Xcode.app
```

### `Failed to load the default metallib` at runtime

```bash
make metallib
```

### Global hotkey not working

Enable Accessibility in System Settings → Privacy & Security → Accessibility.

### App can't be opened because developer cannot be verified

```bash
xattr -cr VibingSpeech.app
```

### Model download fails or is very slow

Ensure you have a stable internet connection. Models are downloaded from Hugging Face. If you're behind a proxy, set the `HTTP_PROXY` / `HTTPS_PROXY` environment variables.

## Architecture

```
Sources/VibingSpeech/
├── App/              # @main, AppDelegate, AppState (central state)
├── Audio/            # AudioCaptureManager, TranscriptionEngine (Qwen3-ASR)
├── HotkeyManager/    # GlobalHotkeyManager (CGEventTap)
├── TextInsertion/    # Clipboard + Cmd+V simulation
├── TextProcessing/   # LLM text processing (Qwen3.5-4B via mlx-swift-lm)
├── Persistence/      # UserDefaults settings, JSON history/hotwords
├── Views/            # Main window tabs, floating overlay
├── Models/           # Data models, presets
└── Utilities/        # Permissions, sound feedback, architecture check
```

## Dependencies

| Package | Version | Purpose |
|---|---|---|
| [speech-swift](https://github.com/soniqo/speech-swift) | ≥ 0.0.9 | Qwen3-ASR speech recognition |
| [mlx-swift-lm](https://github.com/ml-explore/mlx-swift-lm) | 3.31.3 | LLM inference for text processing |
| [mlx-swift](https://github.com/ml-explore/mlx-swift) | 0.31.x | MLX array framework (shared) |
| [swift-huggingface](https://github.com/huggingface/swift-huggingface) | ≥ 0.9.0 | HuggingFace model downloader (mlx-swift-lm v3) |
| [swift-transformers](https://github.com/huggingface/swift-transformers) | ≥ 1.3.0 | Tokenizer implementation (mlx-swift-lm v3) |

## Credits

- **[speech-swift](https://github.com/soniqo/speech-swift)** (Apache 2.0) — Qwen3-ASR Swift wrapper
- **[mlx-swift-lm](https://github.com/ml-explore/mlx-swift-lm)** (MIT) — LLM inference framework
- **[Qwen3-ASR](https://huggingface.co/collections/aufklarer/qwen3-asr-mlx)** — Alibaba Cloud
- **[Qwen3.5-4B](https://huggingface.co/Qwen/Qwen3.5-4B)** — Alibaba Cloud
- **[MLX Swift](https://github.com/ml-explore/mlx-swift)** — Apple Machine Learning Explore

## License

[MIT](LICENSE)

External models and libraries used by this tool have their own respective licenses.
