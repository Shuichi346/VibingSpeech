<table>
  <thead>
    <tr>
      <th style="text-align:center"><a href="README_ja.md">日本語</a></th>
      <th style="text-align:center"><a href="README.md">English</a></th>
    </tr>
  </thead>
</table>

# VibingSpeech

VibingSpeech is a native macOS dictation utility for Apple Silicon Macs. It runs as a menu-bar resident app, starts recording from a global hotkey, transcribes speech locally with Qwen3-ASR, optionally refines the text, and pastes the result into the frontmost app through the system pasteboard.

## Contents

- [Preview](#preview)
- [Features](#features)
- [Tech Stack](#tech-stack)
- [Requirements](#requirements)
- [Build and Run](#build-and-run)
- [Usage](#usage)
- [Testing](#testing)
- [Archive](#archive)
- [Project Structure](#project-structure)
- [Permissions and Privacy](#permissions-and-privacy)
- [Troubleshooting](#troubleshooting)
- [License](#license)

## Preview

<img src="githubreadme/ui-main.png" alt="VibingSpeech home screen" width="480">

<img src="githubreadme/ui-hotwords.png" alt="VibingSpeech hotwords screen" width="480">

<img src="githubreadme/ui-history.png" alt="VibingSpeech history screen" width="480">

## Features

- Global recording hotkey with short-press toggle mode and long-press hold mode.
- Floating recording overlay with live audio level feedback and transcription state.
- Local ASR model selection for Qwen3-ASR 0.6B and 1.7B MLX variants.
- Optional local text cleanup presets for typo correction, bullet points, or a custom prompt.
- Local hotword list for names, terms, and proper nouns.
- Local transcription history with retention settings, search, copy, delete, and clear actions.
- Pasteboard-safe text insertion into the active app with clipboard restoration.
- Menu-bar lifecycle with no Dock icon.
- Apple Silicon guard at launch.

## Tech Stack

- SwiftUI and AppKit for the macOS app, menu-bar item, and recording overlay.
- AVFoundation for microphone capture and audio conversion.
- Carbon and Core Graphics event taps for global hotkeys and simulated paste.
- `speech-swift` `0.0.15` for Qwen3-ASR and audio support.
- `mlx-swift-lm` `3.31.3` with `mlx-swift` `0.31.3` for local Qwen3 text processing.
- JSON files in Application Support for local history and hotword persistence.

## Requirements

- Apple Silicon Mac.
- macOS 26.0 or newer.
- Xcode 26.5 or newer.
- Microphone permission.
- Accessibility permission for the global hotkey and cross-app paste.

## Build and Run

Use the project script from the repository root:

```sh
./script/build_and_run.sh --verify
```

The script builds `VibingSpeech.xcodeproj`, launches the Debug app bundle, and verifies that the `VibingSpeech` process is running.

Other supported modes:

```sh
./script/build_and_run.sh
./script/build_and_run.sh --logs
./script/build_and_run.sh --telemetry
./script/build_and_run.sh --debug
```

The Xcode project is the primary build path. SwiftPM-only release builds are intentionally not used for this app.

## Usage

1. Launch VibingSpeech.
2. Allow microphone access when macOS prompts for it.
3. Enable VibingSpeech in System Settings > Privacy & Security > Accessibility.
4. Choose a recording hotkey, language mode, ASR model, microphone, and history retention from the Home screen.
5. Press the recording hotkey in any app. Release or press again to stop, then VibingSpeech transcribes and pastes the final text.

The default hotkey is Right Option. Escape cancels an active recording.

## Testing

Run the app unit tests with:

```sh
xcodebuild -project VibingSpeech.xcodeproj \
  -scheme VibingSpeech \
  -configuration Debug \
  -destination 'platform=macOS,arch=arm64' \
  -derivedDataPath DerivedData \
  CODE_SIGNING_ALLOWED=NO \
  -only-testing:VibingSpeechTests \
  test
```

The current tests cover model metadata, language normalization, word counting, text cleanup, short-audio ASR guarding, settings persistence, history retention, corrupt history recovery, hotword validation, and pasteboard restoration.

## Archive

Do not use the Xcode GUI Archive button while the app depends on `speech-swift`. Release package builds can compile `SpeechVAD` for x86_64 and fail on `Float16`.

Use the archive script instead:

```sh
./script/archive.sh
```

The script writes:

- `build/VibingSpeech.xcarchive`
- `build/VibingSpeech.app`

The archive workflow passes `ARCHS=arm64` and produces an Apple Silicon-only app.

## Project Structure

```text
VibingSpeech/
├── VibingSpeech.xcodeproj
├── VibingSpeech/
│   ├── App/              # app entry point and coordinator
│   ├── Core/             # shared app enums and helpers
│   ├── Models/           # domain models
│   ├── Persistence/      # settings, history, and hotword stores
│   ├── Resources/        # Info.plist and asset catalogs
│   ├── Services/         # hotkey, audio, ASR, text insertion, permissions
│   ├── Support/          # formatting helpers
│   └── Views/            # SwiftUI views and overlay panel
├── VibingSpeechTests/
├── VibingSpeechUITests/
├── docs/
└── script/
```

## Permissions and Privacy

VibingSpeech requires microphone access for recording. Accessibility permission is required for the global hotkey and for inserting text into the frontmost app.

Audio samples, hotwords, settings, and transcription history are stored locally. Network access is expected when the ASR model is downloaded from Hugging Face for first use.

## Troubleshooting

If the hotkey does not work, enable VibingSpeech in System Settings > Privacy & Security > Accessibility, then use Retry Hotkey Setup in the app.

If a recording starts and stops immediately, VibingSpeech discards audio that is too short for ASR instead of sending it to `speech-swift`.

If archive fails from Xcode's GUI, use `./script/archive.sh` from Terminal so the arm64-only package build settings are applied.

## License

VibingSpeech is licensed under the MIT License. See [LICENSE](LICENSE).
