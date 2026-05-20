# AGENTS.md

Project instructions for coding agents working in this repository.

- Treat `VibingSpeech.xcodeproj` as the primary build project for this macOS app.
- Do not use the Xcode GUI Archive button for `speech-swift` builds. Use `script/archive.sh` so `ARCHS=arm64` is passed to Swift package builds and the `SpeechVAD` `Float16` x86_64 archive failure is avoided.
- Keep archive outputs under `build/`, which is intentionally ignored by Git.
- The app is Apple Silicon only while it depends on `speech-swift` `Qwen3ASR`/`AudioCommon`; do not add Intel Mac support unless the dependency is guarded or replaced.

