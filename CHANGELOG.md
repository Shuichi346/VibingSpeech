# Changelog

## Unreleased

- Created the native macOS Xcode project and app scaffold.
- Added menu-bar lifecycle, global hotkey service, microphone capture, overlay, pasteboard insertion, local settings, hotwords, and history persistence.
- Added focused unit coverage for model metadata, word counting, settings persistence, history retention, hotword validation, text processing cleanup, and pasteboard restoration.

### Dependency notes

- 2026-05-20: `speech-swift` `0.0.15` is used for the Qwen3ASR and AudioCommon products. Hotwords are persisted locally, but the public `Qwen3ASRModel.transcribe` examples do not document a prompt-bias or hotword context parameter, so the app does not claim active ASR biasing until that API is confirmed.
