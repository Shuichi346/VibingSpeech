# VibingSpeech

VibingSpeech is a native macOS dictation utility designed for Apple Silicon. It runs as a menu-bar resident app, records from a global hotkey, shows a floating recording overlay, keeps hotwords and history locally, and inserts the final text into the frontmost app through the pasteboard and a synthesized Cmd+V.

## Requirements

- macOS 26 or newer
- Apple Silicon Mac
- Xcode 26.5 or newer
- Microphone permission
- Accessibility permission for the global hotkey and cross-app paste

## Build

```sh
./script/build_and_run.sh --verify
```

The Xcode project is the release path. SwiftPM-only release builds are intentionally not used.

## Archive

Xcode GUI Archive is not reliable while the app depends on `speech-swift` because Release package builds can compile `SpeechVAD` for x86_64 and fail on `Float16`. Archive Apple Silicon builds from the command line instead:

```sh
./script/archive.sh
```

The script writes `build/VibingSpeech.xcarchive` and `build/VibingSpeech.app`. The output is arm64-only and intended for Apple Silicon Macs.

## Permissions

On first launch, allow microphone access. To enable global hotkeys and cross-app insertion, open System Settings > Privacy & Security > Accessibility and enable VibingSpeech.

## Privacy

Audio, hotwords, settings, and transcription history stay on device. The only network activity expected by the final ASR/LLM integration is first-run model download from Hugging Face.

## Signing

The app is configured for local/ad-hoc personal-use signing with App Sandbox disabled. Developer ID signing and notarization are not configured until a valid signing identity is available.
