# AGENTS.md

Project instructions for coding agents working in this repository.

- Treat `VibingSpeech.xcodeproj` as the primary build project for this macOS app.
- Do not use the Xcode GUI Archive button for `speech-swift` builds. Use `script/archive.sh` so `ARCHS=arm64` is passed to Swift package builds and the `SpeechVAD` `Float16` x86_64 archive failure is avoided.
- Keep archive outputs under `build/`, which is intentionally ignored by Git.
- The app is Apple Silicon only while it depends on `speech-swift` `Qwen3ASR`/`AudioCommon`; do not add Intel Mac support unless the dependency is guarded or replaced.
- Keep AVAudioEngine tap callbacks non-main-actor isolated. In `VibingSpeech/Services/Services.swift`, create microphone tap blocks outside `@MainActor` recorder methods and hop to `MainActor` only after copying/converting audio samples.
- Keep the recording overlay compact and bottom-centered. Its 150 x 33 panel geometry lives in `VibingSpeech/Views/RecordingOverlay.swift`, and the overlay should not show phase text unless that UI direction changes explicitly.
- Keep the main window content size fixed at 760 x 560 via `AppLayout` and `.windowResizability(.contentSize)`. Make overflowing detail content scroll inside the window, and preserve a working sidebar collapse/restore path.
- Preserve `MainWindowController` in `VibingSpeech/App/VibingSpeechApp.swift`: closing the main window should hide it, not destroy it, so the menu-bar Show Window item can restore the same window.
- When SwiftUI views depend on nested `ObservableObject` services such as `TextProcessingService`, pass and observe the service directly instead of only reading it through `AppCoordinator`; otherwise nested `@Published` changes may not refresh loading indicators.
- Keep `TranscriptionRecord.originalASRText` populated for LLM-processed history records so the History tab can copy both the edited text and the original transcription separately.
- For Text Processing (LLM), use `mlx-swift-lm` with `mlx-community/Qwen3-4B-Instruct-2507-4bit`; keep `MLXLLM`, `MLXLMCommon`, `HuggingFace`, and `Tokenizers` linked in `VibingSpeech.xcodeproj`. Do not reintroduce `Qwen3Chat`, Qwen3.5 model normalization, `/think` / `/nothink` prompt switches, or app-side `<think>...</think>` stripping for this non-reasoning model.
