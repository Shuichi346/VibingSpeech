# Changelog

## Unreleased

- Clarified Model Auto-Unload so the Other settings copy now states that idle timeout unloads both ASR and Text Processing (LLM) when Text Processing is on, and only ASR when Text Processing is off.
- Added an Other sidebar settings screen with adjustable idle model unloading and Launch at Login, and wired Text Processing (LLM) to load `mlx-community/Qwen3-4B-Instruct-2507-4bit` through `mlx-swift-lm`.
- Fixed a Text Processing (LLM) model compatibility error by removing the incorrect Qwen3Chat/Qwen3.5 path and using Qwen3 Instruct 2507 with its recommended sampling settings.
- Added source-specific History copy controls for LLM-edited text, transcription text, and original ASR text, with distinct icons and copied-state feedback.
- Added visible ASR and LLM preparation indicators so model downloads and loading are no longer silent, and fixed the LLM loading indicator so it clears when the text processor becomes ready.
- Fixed the menu-bar Show Window action so the main window reappears after the user closes it.
- Refined the main macOS window UI with a native gray sidebar, subtle source-list selection, grouped settings sections, a fixed 760 x 560 content size, scrollable detail panes, and a working sidebar collapse/restore control.
- Moved the recording overlay to a compact bottom-centered capsule, removed phase text, and made the waveform respond more visibly to microphone input levels.
- Created the native macOS Xcode project and app scaffold.
- Added menu-bar lifecycle, global hotkey service, microphone capture, overlay, pasteboard insertion, local settings, hotwords, and history persistence.
- Added focused unit coverage for model metadata, word counting, settings persistence, history retention, hotword validation, text processing cleanup, and pasteboard restoration.
- Documented the `speech-swift` `Float16` Xcode GUI Archive failure and added an arm64-only command-line archive workflow for Apple Silicon builds.
- Fixed a Swift concurrency crash when microphone tap callbacks from AVAudioEngine ran on AVFAudio's realtime queue during recording.

### Dependency notes

- 2026-05-20: `speech-swift` `0.0.15` is used for the Qwen3ASR and AudioCommon products. Hotwords are persisted locally, but the public `Qwen3ASRModel.transcribe` examples do not document a prompt-bias or hotword context parameter, so the app does not claim active ASR biasing until that API is confirmed.
- 2026-05-20: Text Processing uses `mlx-swift-lm` `3.31.3`, `swift-huggingface` `0.9.0`, and `swift-transformers` `1.3.0` to load `mlx-community/Qwen3-4B-Instruct-2507-4bit`.
- 2026-05-20: Xcode GUI Archive can compile `speech-swift` for x86_64 under Release package settings, which fails on `Float16` usage in `SpeechVAD`. Use `script/archive.sh` or the equivalent `xcodebuild archive` command with `ARCHS=arm64` instead.
