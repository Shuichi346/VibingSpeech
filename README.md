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

- macOS 15.0+ (Sonoma)
- Apple Silicon (M1 or later)
- Xcode 15+ / Command Line Tools
- Swift 5.9+

## Build & Run

```bash
git clone https://github.com/yourusername/VibingSpeech.git
cd VibingSpeech
make build
make run
```

First launch will automatically download the selected ASR model (≈1GB for default model).

## Permissions

VibingSpeech requires two permissions:

1. **Accessibility Permission:** Required for global hotkey detection and text insertion
2. **Microphone Permission:** Required for audio recording

You will be prompted to grant these permissions on first launch. If you miss the prompts, you can enable them later in System Settings → Privacy & Security.

## How to Use

1. Launch the app - you'll see a microphone icon in your menu bar
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

### Metal shader error on build
```
xcodebuild -downloadComponent MetalToolchain
```

### Global hotkey not working
Make sure Accessibility permission is enabled in System Settings → Privacy & Security → Accessibility.

### App can't be opened because developer cannot be verified
```
xattr -cr /path/to/VibingSpeech.app
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

- **speech-swift** (Apache 2.0) - https://github.com/soniqo/speech-swift
- **Qwen3-ASR** - Alibaba Cloud
- **MLX** - Apple Machine Learning Explore

## License

MIT
