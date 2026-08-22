# Changelog

## Unreleased

- Added an explicit Stop Recording command, made asynchronous recording startup cancellable, refreshed microphone permission before capture, and serialized startup with idle model unloading.
- Replaced per-buffer nearest-neighbor microphone resampling with one persistent `AVAudioConverter`, and drained ordered live-audio delivery before finalization so tail buffers are not dropped or reordered.
- Connected saved hotwords to the bounded, sanitized context passed to the final Qwen3-ASR transcription.
- Moved history disk I/O to an actor-backed JSON Lines journal with legacy-array migration, append-only normal saves, startup and timed retention pruning, and corrupt-file preservation.
- Fixed multi-row hotword deletion, corrupt hotword-file preservation, and word counts for mixed CJK and Latin text.
- Made release archives fail when their embedded Version or Build does not match Xcode's resolved Identity settings.
- Migrated Text Processing (LLM) to `mlx-community/Qwen3.5-4B-MLX-4bit`, disabled thinking through the model's chat template, and applied Qwen3.5's recommended general Instruct sampling settings.
- Switched Qwen3-ASR downloads to the `mlx-community` MLX repositories for the 0.6B 8-bit, 1.7B 4-bit, and 1.7B 8-bit models, and refreshed their displayed download-size estimates.
- Migrated ASR from `speech-swift` to `mlx-audio-swift` `0.1.3`, resolved the shared MLX runtime to `mlx-swift` `0.31.6`, removed app-level VAD segmentation, and preserved the existing Qwen3-ASR model selections.
- Changed Live Transcription to use the native Qwen streaming session for the review overlay while always batch-transcribing the complete recording for the final LLM, paste, and history result.
- Prevented cancellation during live-session drain, ASR, or LLM work from inserting or saving a late result.
- Fixed Save History retention so changing the dropdown immediately prunes timed history or removes `history.json` for Never instead of waiting for the next saved transcription.
- Hardened ASR and Text Processing model loading so stale async completions cannot replace newer model state, and previous model resources are explicitly unloaded before replacement.
- Updated Swift package pins to `mlx-audio-swift` `0.1.3`, `mlx-swift-lm` `3.31.4`, and transitive `mlx-swift` `0.31.6` after tagged-source/API review, Debug tests, and a signing-disabled Release build.
- Updated direct Swift package pins to `speech-swift` `0.0.19` and `swift-transformers` `1.3.3` after package resolution, Debug tests, and Release build verification succeeded.
- Fixed Microphone settings so selecting a non-default input device now applies that Core Audio device to the recording engine instead of only changing the displayed device name.
- Added an optional Live Transcription mode that shows provisional and confirmed ASR text in a bottom overlay while recording, keeps target-app insertion paste-on-stop only, and runs final ASR and Text Processing once on the complete recording.
- Centered the compact recording overlay's processing spinner while preserving the bottom-centered 150 x 33 panel layout.
- Fixed Launch at Login startup initialization so menu-bar, hotkey, microphone permission, and ASR loading services start from `NSApplicationDelegate.applicationDidFinishLaunching(_:)` instead of waiting for the SwiftUI content view to appear.
- Fixed the archive signing prerequisite for Launch at Login by hardening the runtime on nested code and the app itself for `SMAppService` launchd startup.
- Restored microphone authorization prompts for hardened archive builds by signing the app with the macOS Audio Input entitlement.
- Expanded sidebar navigation row hit targets so clicking empty space within a row now changes the selected section.
- Moved the Appearance selector from Home to Other and fixed app-wide Light/Dark/System changes so AppKit and SwiftUI surfaces update together.
- Fixed Model Auto-Unload memory release so idle ASR unload drains live inference, releases the ASR reference, and clears MLX's cache; Text Processing (LLM) also clears the cache after releasing its model container.
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
- Fixed a Swift concurrency crash when microphone tap callbacks from AVAudioEngine ran on AVFAudio's realtime queue during recording.

### Dependency notes

- 2026-08-20: The pinned `mlx-audio-swift` `0.1.3` `Qwen3ASRModel.generate` API accepts a `context` argument. Saved hotwords now populate that argument for the final batch transcription after bounded sanitization; streaming review remains unchanged.
- 2026-08-08: `mlx-audio-swift` `0.1.3` supplies `MLXAudioSTT`, Qwen3-ASR batch generation, and the review-only streaming session. `MLXAudioSTT` contains `MLXAudioVAD` transitively, but the app does not directly import, configure, or load a VAD model; final inference receives the complete 16 kHz capture. `mlx-swift` is resolved to `0.31.6`, compatible with both `mlx-audio-swift` and `mlx-swift-lm` `3.31.4`.
- 2026-05-30: `speech-swift` `0.0.19` is used for the Qwen3ASR, AudioCommon, and SpeechVAD products. Hotwords are persisted locally, but the public `Qwen3ASRModel.transcribe` examples do not document a prompt-bias or hotword context parameter, so the app does not claim active ASR biasing until that API is confirmed.
- 2026-05-30: Text Processing uses `mlx-swift-lm` `3.31.3`, `swift-huggingface` `0.9.0`, and `swift-transformers` `1.3.3` to load `mlx-community/Qwen3-4B-Instruct-2507-4bit`.
- 2026-07-01: `speech-swift` `0.0.21` keeps the app-used Qwen3ASR, AudioCommon, and SpeechVAD APIs compatible. `mlx-swift-lm` `3.31.4` keeps the app-used downloader, tokenizer, model-container, `GenerateParameters`, and `ChatSession.respond` APIs compatible while resolving transitive `mlx-swift` to `0.31.5`.
- 2026-05-20: Xcode GUI Archive can compile `speech-swift` for x86_64 under Release package settings, which fails on `Float16` usage in `SpeechVAD`. Use `script/archive.sh` or the equivalent `xcodebuild archive` command with `ARCHS=arm64` instead.
