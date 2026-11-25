# Changelog

## 2026-11-25

### Fixed

- Normalized Bullet Points markers and spacing without rewriting the model’s text, including note lines returned without bullet markers.
- Fixed signed app startup with the bundled CTranscribe framework by adding the library-validation exception required for ad-hoc signatures under Hardened Runtime. Enabled signing in the Debug run script, verified bundle signatures, and checked sustained startup; added archive entitlement checks.
- Fixed Auto language selection for native Nemotron streaming while preserving explicit language choices.

### Added

- Added a Home preparation indicator for the initial Nemotron download and model loading.

### Changed

- Switched Text Processing from Qwen3.5 2B Q8_0 to Qwen3 4B Instruct 2507 Q4_K_M after comparison, applied its recommended sampling settings with presence penalty disabled, and removed redundant thinking-mode configuration.
- Rewrote the built-in Text Processing prompts in concise English without examples: Fix Typos requests minimal corrections, and Bullet Points preserves spoken ideas and list items with a heading only when the source introduces one.
- Replaced only the Text Processing model with Qwen3.5 2B Q8_0 from Unsloth, retaining non-thinking-only generation and applying its recommended text sampling parameters.
- Replaced live Qwen3-ASR MLX inference with Nemotron 3.5 ASR Streaming 0.6B Q8_0 through the bundled transcribe.cpp runtime, with Japanese/Auto language support and a fixed Live Model display.
- Preserved native committed/tentative text boundaries in the live overlay and finalized buffered audio before the separate complete-recording ASR pass.
- Configured public package resolution in build scripts to avoid macOS Keychain authentication prompts.

### Removed

- Removed the MLX runtime and package dependencies, former live model picker/settings, unused segment-buffer implementation, and compatibility mappings for retired ASR models.

## 2026-11-24

### Added

- Added a separate live MLX model picker and shared Hugging Face GGUF caching with SHA-256 verification.
- Added an app-owned llama.cpp server with six nondefault port candidates, authenticated readiness checks, and shutdown on disable, cancellation, idle unload, and app exit.

### Changed

- Updated the app identity to version 2.3.0 (build 2) in both Debug and Release configurations.
- Refreshed the English and Japanese READMEs with the current model/runtime split, setup and usage, cache and server lifecycle, temporary-directory test command, and ad-hoc archive signing; repaired Japanese navigation anchors and labeled screenshots from the earlier model configuration.
- Switched final ASR to transcribe.cpp with multilingual Granite Speech 5.0 470M Q8_0 and Qwen3-ASR 1.7B Q8_0, while retaining MLX models for live review.
- Replaced Qwen3.5 MLX Text Processing with LFM3 1.7B Q6_K through llama.cpp in non-thinking mode.
- Migrated removed ASR settings while preserving saved history and its original model identifiers.

### Removed

- Removed the Qwen3-ASR 1.7B 4-bit model selection and obsolete MLX Text Processing implementation and direct package links.

## DATE UNKNOWN

### Fixed

- Fixed external microphone recording while Bluetooth headphones are selected for playback by binding an input-only Core Audio unit directly to the chosen microphone.
- Fixed multi-row hotword deletion, corrupt hotword-file preservation, and word counts for mixed CJK and Latin text.
- Prevented cancellation during live-session drain, ASR, or LLM work from inserting or saving a late result.
- Fixed Save History retention so changing the dropdown immediately prunes timed history or removes `history.json` for Never instead of waiting for the next saved transcription.
- Hardened ASR and Text Processing model loading so stale async completions cannot replace newer model state, and previous model resources are explicitly unloaded before replacement.
- Fixed Microphone settings so selecting a non-default input device now applies that Core Audio device to the recording engine instead of only changing the displayed device name.
- Fixed Launch at Login startup initialization so menu-bar, hotkey, microphone permission, and ASR loading services start from `NSApplicationDelegate.applicationDidFinishLaunching(_:)` instead of waiting for the SwiftUI content view to appear.
- Fixed the archive signing prerequisite for Launch at Login by hardening the runtime on nested code and the app itself for `SMAppService` launchd startup.
- Restored microphone authorization prompts for hardened archive builds by signing the app with the macOS Audio Input entitlement.
- Fixed Model Auto-Unload memory release so idle ASR unload drains live inference, releases the ASR reference, and clears MLX's cache; Text Processing (LLM) also clears the cache after releasing its model container.
- Fixed a Text Processing (LLM) model compatibility error by removing the incorrect Qwen3Chat/Qwen3.5 path and using Qwen3 Instruct 2507 with its recommended sampling settings.
- Fixed the menu-bar Show Window action so the main window reappears after the user closes it.
- Fixed a Swift concurrency crash when microphone tap callbacks from AVAudioEngine ran on AVFAudio's realtime queue during recording.
- Replaced per-buffer nearest-neighbor microphone resampling with one persistent `AVAudioConverter`, and drained ordered live-audio delivery before finalization so tail buffers are not dropped or reordered.
- Made release archives fail when their embedded Version or Build does not match Xcode's resolved Identity settings.
- Centered the compact recording overlay's processing spinner while preserving the bottom-centered 150 x 33 panel layout.
- Expanded sidebar navigation row hit targets so clicking empty space within a row now changes the selected section.

### Added

- Added an explicit Stop Recording command, made asynchronous recording startup cancellable, refreshed microphone permission before capture, and serialized startup with idle model unloading.
- Added an optional Live Transcription mode that shows provisional and confirmed ASR text in a bottom overlay while recording, keeps target-app insertion paste-on-stop only, and runs final ASR and Text Processing once on the complete recording.
- Added an Other sidebar settings screen with adjustable idle model unloading and Launch at Login, and wired Text Processing (LLM) to load `mlx-community/Qwen3-4B-Instruct-2507-4bit` through `mlx-swift-lm`.
- Added source-specific History copy controls for LLM-edited text, transcription text, and original ASR text, with distinct icons and copied-state feedback.
- Added visible ASR and LLM preparation indicators so model downloads and loading are no longer silent, and fixed the LLM loading indicator so it clears when the text processor becomes ready.
- Created the native macOS Xcode project and app scaffold.
- Added menu-bar lifecycle, global hotkey service, microphone capture, overlay, pasteboard insertion, local settings, hotwords, and history persistence.
- Connected saved hotwords to the bounded, sanitized context passed to the final Qwen3-ASR transcription.

### Changed

- Moved history disk I/O to an actor-backed JSON Lines journal with legacy-array migration, append-only normal saves, startup and timed retention pruning, and corrupt-file preservation.
- Migrated Text Processing (LLM) to `mlx-community/Qwen3.5-4B-MLX-4bit`, disabled thinking through the model's chat template, and applied Qwen3.5's recommended general Instruct sampling settings.
- Switched Qwen3-ASR downloads to the `mlx-community` MLX repositories for the 0.6B 8-bit, 1.7B 4-bit, and 1.7B 8-bit models, and refreshed their displayed download-size estimates.
- Migrated ASR from `speech-swift` to `mlx-audio-swift` `0.1.3`, resolved the shared MLX runtime to `mlx-swift` `0.31.6`, removed app-level VAD segmentation, and preserved the existing Qwen3-ASR model selections.
- Changed Live Transcription to use the native Qwen streaming session for the review overlay while always batch-transcribing the complete recording for the final LLM, paste, and history result.
- Updated Swift package pins to `mlx-audio-swift` `0.1.3`, `mlx-swift-lm` `3.31.4`, and transitive `mlx-swift` `0.31.6` after tagged-source/API review, Debug tests, and a signing-disabled Release build.
- Updated direct Swift package pins to `speech-swift` `0.0.19` and `swift-transformers` `1.3.3` after package resolution, Debug tests, and Release build verification succeeded.
- Moved the Appearance selector from Home to Other and fixed app-wide Light/Dark/System changes so AppKit and SwiftUI surfaces update together.
- Clarified Model Auto-Unload so the Other settings copy now states that idle timeout unloads both ASR and Text Processing (LLM) when Text Processing is on, and only ASR when Text Processing is off.
- Refined the main macOS window UI with a native gray sidebar, subtle source-list selection, grouped settings sections, a fixed 760 x 560 content size, scrollable detail panes, and a working sidebar collapse/restore control.
- Moved the recording overlay to a compact bottom-centered capsule, removed phase text, and made the waveform respond more visibly to microphone input levels.
