<table>
  <thead>
    <tr>
      <th style="text-align:center"><a href="README_ja.md">日本語</a></th>
      <th style="text-align:center"><a href="README.md">English</a></th>
    </tr>
  </thead>
</table>

# VibingSpeech

Local voice dictation for Apple Silicon Macs. Record from a global hotkey, transcribe with Granite Speech or Qwen3-ASR, optionally refine the text with Qwen3.5, and paste it into the app you are using.

VibingSpeech lives in the menu bar. Audio and text inference run on your Mac; models download when first needed.

## Contents

- [Features](#features)
- [Requirements](#requirements)
- [Build and run](#build-and-run)
- [Usage](#usage)
- [Models](#models)
- [Privacy and model lifecycle](#privacy-and-model-lifecycle)
- [Screenshots](#screenshots)
- [Testing](#testing)
- [Release archive and signing](#release-archive-and-signing)
- [Troubleshooting](#troubleshooting)
- [Project structure](#project-structure)
- [License](#license)

## Features

- Tap the recording hotkey to start and stop, or hold it while speaking. Press Escape to cancel.
- Choose a microphone independently of the macOS default, including when Bluetooth headphones are used for playback.
- Review an optional live transcript above the compact recording overlay. Final text is pasted once after recording stops.
- Apply typo correction, bullet-point formatting, or a custom instruction with optional local Text Processing.
- Supply vocabulary hints to final Qwen3-ASR transcription through Hotwords.
- Search transcription history and copy either edited text or the original ASR result. Choose how long history is retained.
- Configure appearance, Launch at Login, sound feedback, and idle model unloading.

## Requirements

- An **Apple Silicon Mac** running **macOS 26.0 or later**. Intel Macs are unsupported.
- Xcode with Swift 6.2 or later. Development was verified with Xcode 27.2 and Swift 6.4.2.
- Microphone permission for recording and Accessibility permission for global hotkeys and cross-app paste.
- Internet access for initial dependency and model downloads, plus disk space for the selected models.
- `llama` for optional Text Processing. If it is missing, the app runs `curl -LsSf https://llama.app/install.sh | sh`. An existing installation is used without replacement.

## Build and run

Clone or download this repository, then run from its root:

```sh
./script/build_and_run.sh --verify
```

The script stops any running VibingSpeech process, builds the Debug app through `VibingSpeech.xcodeproj` with ad-hoc signing, verifies the app and native framework signatures, launches it, and checks that it stays running for five seconds. Build products are stored in `DerivedData/`. The Xcode project is the primary build entry point; the local Swift package supplies the native ASR wrapper.

Debug and Release keep Hardened Runtime enabled. Ad-hoc signatures have no Team ID, so the app includes the Disable Library Validation entitlement to load its bundled `CTranscribe.framework`.

Build scripts select the netrc package authorization provider to avoid Keychain prompts when fetching public dependencies.

Use `./script/build_and_run.sh` for a normal launch, or pass `--logs`, `--telemetry`, or `--debug` for diagnostics.

## Usage

1. Launch VibingSpeech and allow microphone access.
2. Enable it in **System Settings → Privacy & Security → Accessibility**.
3. In **Home**, choose a microphone and **Final ASR Model**. Wait for model preparation to finish.
4. Place the cursor in a text field, for example in Notes. Tap **Right Option**, speak, then tap it again to stop and paste the result.

Right Option is the default hotkey; Left Control is also available. A long press records until the key is released. **Escape** cancels recording or processing.

Enable **Live Transcription** to review text while speaking with **Nemotron 3.5 ASR Streaming 0.6B**. The Live Model row shows the fixed Q8_0 model. On first use, Home shows model preparation while the roughly 750 MB download and loading finish; recording starts afterward. Live text is never pasted. After stopping, the complete mono 16 kHz recording is transcribed in one native batch call, then optionally processed by the LLM before insertion. Model input limits are reported as errors rather than silently truncating audio.

Enable **Text Processing (LLM)** to select **Fix Typos**, **Bullet Points**, or **Custom**. The Language setting controls the requested output language; Auto follows the detected language when available, otherwise the input text.

Use **Hotwords** for final Qwen3-ASR vocabulary hints; Granite CTC does not support prompt hints. Use **History** for saved dictations and **Other** for appearance, Launch at Login, and Model Auto-Unload.

## Models

Final ASR and live review use separate models. Qwen MLX live models and the former 1.7B 4-bit option have been removed. Retired model preferences are not migrated; an unknown saved final-ASR selection uses the current default.

| Purpose | Model | Format | Runtime | Approximate download |
| --- | --- | --- | --- | --- |
| Final ASR, default | [Granite Speech 5.0 470M TurboCTC](https://huggingface.co/vladers/granite-speech-5.0-470m-turboctc-GGUF) | GGUF Q8_0 | transcribe.cpp | 520 MB |
| Final ASR | [Qwen3-ASR 1.7B](https://huggingface.co/handy-computer/Qwen3-ASR-1.7B-gguf) | GGUF Q8_0 | transcribe.cpp | 2.2 GB |
| Live review | [Nemotron 3.5 ASR Streaming 0.6B](https://huggingface.co/handy-computer/nemotron-3.5-asr-streaming-0.6b-gguf) | GGUF Q8_0 | transcribe.cpp | 750 MB |
| Optional Text Processing | [Qwen3.5 2B](https://huggingface.co/unsloth/Qwen3.5-2B-GGUF) | GGUF Q8_0 | llama.cpp, non-thinking | 2.0 GB |

The GGUF filenames are:

- `granite-speech-5.0-470m-turboctc-Q8_0.gguf`
- `Qwen3-ASR-1.7B-Q8_0.gguf`
- `nemotron-3.5-asr-streaming-0.6b-Q8_0.gguf`
- `Qwen3.5-2B-Q8_0.gguf`

Text Processing uses only non-thinking text generation with `temperature=1.0`, `top_p=1.0`, `top_k=20`, `min_p=0.0`, `presence_penalty=2.0`, and `repeat_penalty=1.0` (llama.cpp’s name for repetition penalty). Thinking is disabled through both `--reasoning off` and `chat_template_kwargs.enable_thinking=false`. These match the [model’s recommended non-thinking text settings](https://huggingface.co/Qwen/Qwen3.5-2B#best-practices).

Qwen3-ASR must use the **handy-computer** conversion. The ggml-org conversion has a different layout intended for llama.cpp and is not interchangeable with this transcribe.cpp model.

Live review uses the transcribe.cpp conversion of Nemotron 3.5, with Japanese and multilingual streaming, explicit language selection or Auto, and 240 ms lookahead. It loads when live transcription is used, alongside the selected final ASR model. The stream remains review-only; the final ASR model processes the complete recording separately after stop.

Both live and final ASR use transcribe.cpp `v0.4.2` through a checksum-pinned XCFramework. The app no longer depends on MLX. NVIDIA's official `nemo-speech` installation is not required or modified. Its GGUF format differs from the transcribe.cpp conversion, so an existing official model download cannot be reused directly.

## Privacy and model lifecycle

Audio and inference stay local. Settings, Hotwords, and history are stored on your Mac. Model downloads and the optional llama installer require network access.

GGUF files use the shared `~/.cache/huggingface/hub` snapshots/blobs cache with SHA-256 verification. These public models need no token entry in the app. Existing credentials from `HF_TOKEN` or the Hugging Face token file are honored; `HF_TOKEN_PATH` and `HF_HOME` can locate that token file.

Text Processing starts its own llama server on `127.0.0.1` with a private API key. It tries ports **49271, 49283, 49307, 49319, 49331, and 49349**, avoiding llama defaults and leaving other applications' servers untouched.

**Model Auto-Unload** defaults to five idle minutes. At the configured timeout, ASR models unload and the owned llama server stops. Setting the delay to Off disables this idle timeout. The server also stops when Text Processing is disabled, processing is canceled, or the app exits. Downloaded cache files remain available for later use.

## Screenshots

These screenshots show an earlier model configuration. Model names and some explanatory text differ from the current implementation; use the Models section above for current selections.

<img src="githubreadme/ui-main.png" alt="Home settings with recording controls and model selection in an earlier version" width="480">

<details>
<summary>Hotwords, History, and Other settings</summary>

<img src="githubreadme/ui-hotwords.png" alt="Hotwords list and entry field" width="480">

<img src="githubreadme/ui-history.png" alt="History with retention, search, and original ASR text" width="480">

<img src="githubreadme/ui-other.png" alt="Appearance, idle unloading, and Launch at Login settings" width="480">

</details>

## Testing

Run unit tests without loading models or requesting microphone permission:

```sh
xcodebuild -project VibingSpeech.xcodeproj \
  -packageAuthorizationProvider netrc \
  -scheme VibingSpeech \
  -configuration Debug \
  -destination 'platform=macOS,arch=arm64' \
  -derivedDataPath /tmp/VibingSpeech-Tests \
  CODE_SIGNING_ALLOWED=NO \
  -only-testing:VibingSpeechTests \
  test
```

The native streaming package also has isolated tests:

```sh
swift test --package-path Packages/TranscribeRuntime --disable-keychain
```

The four package tests include two model-free checks and two real-model integration checks. The real-model checks are opt-in: set `VIBINGSPEECH_TEST_NEMOTRON_GGUF` to the compatible Q8_0 file and `VIBINGSPEECH_TEST_NEMOTRON_PCM` to mono 16 kHz little-endian float32 PCM. Without those fixtures, only the model-free checks run.

The temporary build location avoids the macOS Documents access prompt encountered when XCTest loads the embedded native framework from a repository under Documents. The shared test action passes `--ui-testing` to keep startup independent of model downloads and microphone hardware.

Tests cover settings persistence, prompt construction, ordered live audio delivery, history retention and recovery, verified GGUF caching, server port fallback, authentication, cancellation, and shutdown. The opt-in microphone test is skipped unless a test device is configured. UI automation requires a trusted macOS development-signing identity; an ad-hoc archive signature does not supply that identity.

## Release archive and signing

Create a release bundle with:

```sh
./script/archive.sh
```

The script replaces its previous outputs at `build/VibingSpeech.xcarchive` and `build/VibingSpeech.app`. It builds for arm64, signs nested code before the app using **ad-hoc signing** (`--sign -`), enables Hardened Runtime, and preserves the Audio Input and Disable Library Validation entitlements. It verifies the signature, runtime flag, both required entitlements, and embedded Version/Build against Xcode settings.

Change the app version through `MARKETING_VERSION` and `CURRENT_PROJECT_VERSION` in `VibingSpeech.xcodeproj`. Keep the corresponding `Info.plist` placeholders intact. This workflow creates an ad-hoc signed local bundle, not a notarized Developer ID distribution.

## Troubleshooting

| Symptom | Check |
| --- | --- |
| Hotkey or paste does not work | Enable Accessibility access, then use **Retry Hotkey Setup** in Home. |
| Selected microphone is unavailable | Reconnect it or select another input, then start a new recording. Device selection is applied at recording start. |
| Text Processing cannot start | Check the status message and that `llama` is installed and supports Qwen3.5. An outdated installation reports a startup error rather than being replaced automatically. |
| All inference ports are occupied | Free one of the listed ports or close another VibingSpeech instance, then retry. |
| Models unload while the app is idle | Adjust **Other → Model Auto-Unload**, or set it to Off. |
| A very brief recording produces no text | Audio shorter than the ASR minimum is discarded. |
| XCTest waits before app startup | Use the temporary derived-data location in the Testing command. |

## Project structure

| Path | Responsibility |
| --- | --- |
| `VibingSpeech.xcodeproj` | Primary app, unit-test, and UI-test targets |
| `VibingSpeech/App` | App lifecycle and recording coordinator |
| `VibingSpeech/Services` | Microphone capture, ASR, llama server, model downloads, permissions, and paste |
| `VibingSpeech/Persistence` | Settings, history journal, and Hotwords |
| `VibingSpeech/Views` | SwiftUI screens and recording overlays |
| `Packages/TranscribeRuntime` | Native transcribe.cpp model ownership, inference, and cancellation |
| `script` | Build/run and release archive entry points |

The app uses SwiftUI, AppKit, Core Audio, AVFoundation, Carbon, and ServiceManagement.

## License

VibingSpeech is [MIT licensed](LICENSE). Libraries and model weights have their own licenses; review them separately. Bundled transcribe.cpp notices are in [TranscribeThirdPartyNotices.txt](VibingSpeech/Resources/TranscribeThirdPartyNotices.txt).
