# Changelog

## Unreleased

- Moved the recording overlay to a compact bottom-centered capsule, removed phase text, and made the waveform respond more visibly to microphone input levels.
- Created the native macOS Xcode project and app scaffold.
- Added menu-bar lifecycle, global hotkey service, microphone capture, overlay, pasteboard insertion, local settings, hotwords, and history persistence.
- Added focused unit coverage for model metadata, word counting, settings persistence, history retention, hotword validation, text processing cleanup, and pasteboard restoration.
- Documented the `speech-swift` `Float16` Xcode GUI Archive failure and added an arm64-only command-line archive workflow for Apple Silicon builds.
- Fixed a Swift concurrency crash when microphone tap callbacks from AVAudioEngine ran on AVFAudio's realtime queue during recording.

### Dependency notes

- 2026-05-20: `speech-swift` `0.0.15` is used for the Qwen3ASR and AudioCommon products. Hotwords are persisted locally, but the public `Qwen3ASRModel.transcribe` examples do not document a prompt-bias or hotword context parameter, so the app does not claim active ASR biasing until that API is confirmed.
- 2026-05-20: Xcode GUI Archive can compile `speech-swift` for x86_64 under Release package settings, which fails on `Float16` usage in `SpeechVAD`. Use `script/archive.sh` or the equivalent `xcodebuild archive` command with `ARCHS=arm64` instead.
