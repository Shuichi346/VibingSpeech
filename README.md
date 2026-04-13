# VibingSpeech

Fully on-device macOS voice input app. Global hotkey → record → transcribe (Qwen3-ASR) → paste text at cursor. Apple Silicon exclusive.

## Features

- ✅ **Global Hotkey:** Hold Right Option to record, release to transcribe (short press for toggle mode)
- ✅ **On-Device Transcription:** Uses Qwen3-ASR models, runs entirely locally with no cloud calls
- ✅ **Model Selection:** Choose between 0.6B (8-bit, ~1GB) and 1.7B (4-bit, ~2.1GB) models
- ✅ **Floating Overlay:** Animated microphone indicator during recording
- ✅ **Hotword Dictionary:** Add custom terms to improve recognition accuracy
- ✅ **Transcription History:** View and manage past transcriptions with configurable retention
- ✅ **52 Languages:** Automatic language detection
- ✅ **Text Polish:** Lightweight post-processing for cleaner output
- ✅ **Menu Bar Resident:** Runs in background, no Dock icon
- ✅ **Accessibility Friendly:** Works with any application that accepts text input

## Requirements

- macOS 26.0+ (Tahoe)
- Apple Silicon (M1 or later)
- Xcode 26+ / Command Line Tools (with Swift 6.2)
- **Metal Toolchain** (see [Metal Toolchain Setup](#metal-toolchain-setup) below)

## Metal Toolchain Setup

Starting with Xcode 26, the **Metal Toolchain is no longer bundled with Xcode** and must be installed separately. VibingSpeech depends on MLX Swift, which requires Metal shaders to be compiled at build time. Without the Metal Toolchain, the build will fail.

**Install via Xcode UI:**

1. Open Xcode → Settings → Components
2. Find **Metal Toolchain** under "Other Components"
3. Click **Get** to download and install

**Install via command line:**

```bash
xcodebuild -downloadComponent metalToolchain
```

To verify the installation:

```bash
xcrun metal --version
```

If you see a version number (e.g., `metal version 32.x.x`), the toolchain is ready.

> **Note:** On some Xcode 26 versions, the toolchain may not register correctly after download. If you still get errors after installing, try:
> ```bash
> xcodebuild -downloadComponent metalToolchain -exportPath /tmp/MetalExport/
> xcodebuild -importComponent metalToolchain -importPath /tmp/MetalExport/*.exportedBundle
> ```

## Build & Run

```bash
git clone https://github.com/Shuichi346/VibingSpeech.git
cd VibingSpeech
make build
make run
```

`make build` compiles the Swift package and then builds the MLX Metal shader library (`mlx.metallib`). The shader build is cached and only recompiles when source files change.

To create a standalone `.app` bundle:

```bash
make app
open VibingSpeech.app

# Or install to /Applications
cp -r VibingSpeech.app /Applications/
```

First launch will automatically download the selected ASR model (~1 GB for the default 0.6B model).

## Permissions

VibingSpeech requires two permissions:

1. **Accessibility Permission:** Required for global hotkey detection and text insertion
2. **Microphone Permission:** Required for audio recording

You will be prompted to grant these permissions on first launch. If you miss the prompts, you can enable them later in System Settings → Privacy & Security.

## How to Use

1. Launch the app — you'll see a microphone icon in your menu bar
2. **Hold mode:** Press and hold the Right Option key while speaking, release when done
3. **Toggle mode:** Short press Right Option to start recording, press again to stop
4. **Cancel recording:** Press Esc at any time during recording
5. Access settings, hotwords, and history by clicking the menu bar icon → "Show Window"

## Model Selection

| Model | Size | Memory | Accuracy |
|---|---|---|---|
| Qwen3-ASR 0.6B (8-bit) | ~1.0 GB | ~1.5 GB | Good for general use |
| Qwen3-ASR 1.7B (4-bit) | ~2.1 GB | ~3.5 GB | Higher accuracy for complex speech |

## Troubleshooting

### Metal shader build fails

Make sure the Metal Toolchain is installed (see [Metal Toolchain Setup](#metal-toolchain-setup)):

```bash
xcodebuild -downloadComponent metalToolchain
```

If the toolchain is installed but `xcrun metal` still fails, try restarting your terminal or selecting the correct Xcode:

```bash
sudo xcode-select -s /Applications/Xcode.app
```

### `Failed to load the default metallib` at runtime

The Metal shader library was not built. Run:

```bash
make metallib
```

This compiles the `.metal` shader sources from the MLX Swift dependency and places `mlx.metallib` next to the binary.

### Global hotkey not working

Make sure Accessibility permission is enabled in System Settings → Privacy & Security → Accessibility.

### App can't be opened because developer cannot be verified

```bash
xattr -cr VibingSpeech.app
```

## Architecture

```
Sources/VibingSpeech/
├── App/             # @main, AppDelegate, AppState (central state)
├── Audio/           # AudioCaptureManager, TranscriptionEngine
├── HotkeyManager/   # GlobalHotkeyManager (CGEventTap)
├── TextInsertion/   # Clipboard + Cmd+V simulation
├── Persistence/     # UserDefaults settings, JSON history/hotwords
├── Views/           # Main window tabs, floating overlay
├── Models/          # Data models
└── Utilities/       # Permissions, sound feedback, architecture check
```

## Credits

- **speech-swift** (Apache 2.0) — https://github.com/soniqo/speech-swift
- **Qwen3-ASR** — Alibaba Cloud
- **MLX Swift** — Apple Machine Learning Explore

## License

MIT
