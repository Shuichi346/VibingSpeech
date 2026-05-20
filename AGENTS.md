# AGENTS.md

Project instructions for coding agents working in this repository.

- Treat `VibingSpeech.xcodeproj` as the primary build project for this macOS app.
- Do not use the Xcode GUI Archive button for `speech-swift` builds. Use `script/archive.sh` so `ARCHS=arm64` is passed to Swift package builds and the `SpeechVAD` `Float16` x86_64 archive failure is avoided.
- Keep archive outputs under `build/`, which is intentionally ignored by Git.
- The app is Apple Silicon only while it depends on `speech-swift` `Qwen3ASR`/`AudioCommon`; do not add Intel Mac support unless the dependency is guarded or replaced.
- Keep AVAudioEngine tap callbacks non-main-actor isolated. In `VibingSpeech/Services/Services.swift`, create microphone tap blocks outside `@MainActor` recorder methods and hop to `MainActor` only after copying/converting audio samples.
- Keep the recording overlay compact and bottom-centered. Its 150 x 33 panel geometry lives in `VibingSpeech/Views/RecordingOverlay.swift`, and the overlay should not show phase text unless that UI direction changes explicitly.
