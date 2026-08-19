# Notes

## 2026-08-09

- `script/archive.sh` now resolves both Xcode settings before archiving and rejects a copied `.app` whose embedded Version or Build differs. `Info.plist` continues to expand `MARKETING_VERSION` and `CURRENT_PROJECT_VERSION` into the bundle version keys.
- Text Processing moved to `mlx-community/Qwen3.5-4B-MLX-4bit`. The pinned `mlx-swift-lm` `3.31.4` already supports the model's `qwen3_5` architecture.
- `TextProcessingBackend` disables Qwen3.5 thinking by passing `enable_thinking=false` through `ChatSession.additionalContext`; the model's `chat_template.jinja` consumes that value and emits the non-thinking assistant prefix.
- The model keeps `chat_template.jinja` separate from `tokenizer_config.json`. `mlx-swift-lm` includes `*.jinja` in its tokenizer download patterns, and `swift-transformers` merges the downloaded template into its in-memory tokenizer configuration.
- Generation now preserves Qwen3.5's recommended general Instruct settings: `temperature=0.7`, `topP=0.8`, `topK=20`, `minP=0`, `presencePenalty=1.5`, and `repetitionPenalty=1.0`. No prompt-mode switches or response stripping are used.
- The signing-disabled Debug test run passed all 20 tests, and the signing-disabled arm64 Release build passed.

## 2026-08-08

- Qwen3-ASR repository IDs moved from `aufklarer` to the three supported `mlx-community` variants. The pinned `mlx-audio-swift` `0.1.3` loader already supports their config, tokenizer, quantization, and safetensors layout, so `ASRService` required no loading-path changes.
- Changing the Hugging Face repository IDs causes the `mlx-community` snapshots to download into separate cache entries; existing `aufklarer` snapshots are neither reused nor removed automatically.
- The ASR backend was migrated from `speech-swift` `0.0.21` to `mlx-audio-swift` `0.1.3` after reading tag `v0.1.3` source at commit `d302a5c6080d2bb97bae38c7418f82abb76013b6`; the app now links `MLXAudioSTT` and preserves the existing Qwen3-ASR selections and persisted variant values.
- App-level VAD was removed. The native `StreamingInferenceSession` now drives only the review overlay, is stopped and drained before model reuse, and its text is discarded; the complete mono 16 kHz capture is always passed separately to `Qwen3ASRModel.generate` for the final result.
- Full-buffer generation preserves one Qwen3-ASR context up to the library's 1,200-second default. Longer recordings are independently split at low-energy boundaries by `mlx-audio-swift`, with no transcript context carried across those splits.
- ASR unload now drains live inference, releases Swift model references, and clears `MLX.Memory` because `mlx-audio-swift` `0.1.3` does not expose `Qwen3ASRModel.unload()`. Recording-operation generation checks prevent canceling during live drain, ASR, or LLM work from producing a late paste or history record.
- `mlx-swift` was updated to `0.31.6` at revision `0bb916c67f4b9e5c682cbe02a42c701c93ab5021`. The existing constraints in `mlx-audio-swift` `0.1.3` and `mlx-swift-lm` `3.31.4` both accept that version.
- `xcodebuild -quiet -skipPackagePluginValidation -project VibingSpeech.xcodeproj -scheme VibingSpeech -configuration Debug -destination 'platform=macOS,arch=arm64' -derivedDataPath DerivedData CODE_SIGNING_ALLOWED=NO test` passed all 20 tests, and the matching signing-disabled Release build passed. The skip flag accepted the official package's changed build-plugin fingerprint in the noninteractive build.

## 2026-07-01

- Release notes were checked before updating pins. `speech-swift` `0.0.20` and `0.0.21` focus on Nemotron/Parakeet/CoreML ASR additions and performance fixes; the app-used `Qwen3ASRModel.fromPretrained`, `transcribeWithLanguage`, `SileroVADModel`, `VADConfig`, and `StreamingVADProcessor` APIs remain compatible.
- `mlx-swift-lm` `3.31.4` is a feature/fix release. The app-used `Downloader`, `TokenizerLoader`, `Tokenizer`, `LLMModelFactory.shared.loadContainer`, `GenerateParameters`, `ChatSession`, and `respond(to:)` signatures remain compatible.
- `mlx-swift` `0.31.5` release notes call out a newer Swift tools requirement for SwiftPM users; the current Xcode 26.5 / Swift 6.3 toolchain resolves the package graph successfully.
- Xcode package resolution updated `speech-swift` to `0.0.21`, `mlx-swift-lm` to `3.31.4`, transitive `mlx-swift` to `0.31.5`, and transitive `swift-syntax` to `603.0.2`; `speech-swift` also adds transitive `WhisperKit` `1.0.0`.
- `xcodebuild -quiet -skipPackagePluginValidation -project VibingSpeech.xcodeproj -scheme VibingSpeech -configuration Debug -destination 'platform=macOS,arch=arm64' CODE_SIGNING_ALLOWED=NO test` passed all 20 tests. The same Release build command with `build` also passed. The skip flag is required because Xcode otherwise asks to enable the `mlx-swift` `CudaBuild` package plugin before compiling.

## 2026-05-30

- Save History previously applied retention only when saving a new record; changing the dropdown to One Day, One Week, or Never did not immediately prune visible/persisted history. `HistoryRepository.applyRetention(_:)` now applies dropdown changes immediately, and `.never` removes the persisted file.
- ASR model replacement now invalidates stale load completions and calls model/VAD unload paths before storing a new model, so rapid model changes or idle unloads cannot leave old resources active.
- Text Processing load requests are now coalesced and canceled on disable/idle unload to avoid duplicate LLM loads and stale ready-state updates.
- The first Xcode MCP test run after the refactor still hit the local Team ID test-bundle signing mismatch; `xcodebuild -project VibingSpeech.xcodeproj -scheme VibingSpeech -configuration Debug -destination 'platform=macOS,arch=arm64' CODE_SIGNING_ALLOWED=NO test` passed all 18 tests.
- Direct package releases were checked before updating pins: `speech-swift` latest was `0.0.19`, `swift-transformers` latest was `1.3.3`, while `mlx-swift-lm` `3.31.3` and `swift-huggingface` `0.9.0` were already current.
- Updating `speech-swift` from `0.0.15` to `0.0.19` and `swift-transformers` from `1.3.0` to `1.3.3` resolved cleanly, passed `xcodebuild ... Debug ... test`, and passed an arm64 Release build with signing disabled.
- Microphone selection previously updated `settings.microphoneID` and the picker display, but `MicrophoneRecorder.start(selectedDeviceID:)` never applied that ID to `AVAudioEngine`, so recording continued from the current/default Core Audio input.
- `MicrophoneRecorder` now enumerates Core Audio input devices by `kAudioDevicePropertyDeviceUID` and sets `kAudioOutputUnitProperty_CurrentDevice` on the input audio unit before reading the input format or installing the tap.
- Xcode MCP build passed after the microphone-device fix. The Xcode MCP test runner still did not run tests because `VibingSpeechTests.xctest` failed to load with the local Team ID signing mismatch.

## 2026-05-25

- Live Transcription was added as an off-by-default setting on Home while preserving the existing record-stop-transcribe-paste path when the setting is disabled.
- The live path uses `SpeechVAD` with Qwen3 ASR to update an overlay-only transcript during recording; it does not paste partial or finalized chunks into the target app before stop.
- Text Processing (LLM) remains final-only for Live Transcription: raw ASR is shown during recording, then the complete accumulated transcript is processed once after stop when LLM is enabled.
- The compact 150 x 33 recording overlay remains the anchor, and the live transcript uses a separate bottom-centered pop-up above it only while recording.
- The processing-state spinner in `RecordingOverlayView` was centered inside the compact capsule with a fixed-width `ZStack`, while the recording-state icon and waveform layout stayed unchanged.
- Xcode MCP build passed after the live transcription change. The Xcode MCP test runner still hit the local Team ID test-bundle signing mismatch, while `xcodebuild -project VibingSpeech.xcodeproj -scheme VibingSpeech -configuration Debug -destination 'platform=macOS,arch=arm64' CODE_SIGNING_ALLOWED=NO test` passed all 17 tests.

## 2026-05-23

- The remaining Launch at Login failure was not that launchd failed to start the app. `ps`, Background Task Management, and unified logs showed `/Applications/VibingSpeech.app` launching at login, but the process idled without the menu-bar item, global hotkey, microphone permission flow, or ASR loading.
- The root cause was that app-wide startup lived in `ContentView.task`, so an `LSUIElement` login-item launch could create a background process without ever running `AppCoordinator.startup()` until the SwiftUI window was explicitly opened.
- `VibingSpeech/App/VibingSpeechApp.swift` now owns `AppCoordinator` from an `NSApplicationDelegate` and calls `startup()` from `applicationDidFinishLaunching(_:)`; the SwiftUI view no longer triggers startup.
- The menu-bar Show Window path now handles the case where startup has run but the main SwiftUI window has not yet been registered by discovering a suitable `NSApp.windows` entry and registering it before showing.
- The 2026-05-22 Hardened Runtime fix remains a valid archive/signing prerequisite for login-item launch, but it was not the complete root cause of the later "process exists but menu bar and hotkey do not work" behavior.

## 2026-05-22

- `SMAppService.mainApp.register()` successfully registered the Launch at Login item, and an older archived VibingSpeech build lacked Hardened Runtime because the final `codesign --force --deep --sign -` in `script/archive.sh` did not pass `--options runtime`.
- Comparing `codesign -dvv` flags showed an important archive-signing difference: the correctly launching SwiftClip.app had `flags=0x10002(adhoc,runtime)`, while that VibingSpeech archive had `flags=0x2(adhoc)`.
- On macOS 13 and later, `SMAppService` does not require Hardened Runtime at registration time, but Launch at Login archive validation should keep Hardened Runtime enabled because login-item startup depends on the generated app bundle satisfying launchd/security policy.
- `script/archive.sh` now adds `--options runtime` to each `codesign` call, signs nested dylibs, frameworks, and XPC-style bundles before the app without `--deep`, and fails if `codesign -dvv` does not show the `runtime` flag.
- After Hardened Runtime was added to the archive signature, the microphone permission prompt stopped appearing because the app signature did not include the Audio Input entitlement. The project now signs with `com.apple.security.device.audio-input`, and `script/archive.sh` passes the same app entitlements when it re-signs the archived bundle.

## 2026-05-21

- Sidebar navigation rows missed clicks in empty row space because the custom plain `Button` hit area followed the label content. `SidebarRow` now fills the available width and uses a rectangular `contentShape` while keeping the existing visual highlight.
- Appearance mode changes previously relied on SwiftUI `.preferredColorScheme`, which did not clear AppKit window appearance when returning from Dark to System and did not affect AppKit-owned surfaces such as the recording overlay panel, menu bar item, or alerts. `AppCoordinator` now drives a single `AppearanceService` that maps `SettingsStore.appearanceMode` to `NSApp.appearance`, and `ContentView` no longer applies a separate preferred color scheme.
- Model Auto-Unload previously dropped Swift references without forcing MLX-backed model memory to release. `ASRService.unload()` now calls `Qwen3ASRModel.unload()`, and `TextProcessingBackend.unload()` clears `MLX.Memory` cache after releasing the LLM container.
- Model Auto-Unload behavior was made explicit in `AppCoordinator`: when Text Processing is enabled and ready, the idle timeout unloads both ASR and LLM; when Text Processing is disabled, only ASR remains subject to the standby idle unload.
- The Other settings footer previously mentioned only ASR even though the idle path could unload a ready LLM. The copy now describes the ASR-plus-LLM and ASR-only cases separately.

## 2026-05-20

- Added the Other sidebar settings screen with a persisted `modelUnloadDelayMinutes` value. `0` disables idle unloading, the default is 5 minutes, and the maximum is 60 minutes.
- `AppCoordinator` now keeps both ASR and Text Processing models loaded while recording, transcribing, or text processing is active, then unloads any loaded idle models through the shared inactivity timer.
- The previous `TextProcessingService.process()` implementation did not call an LLM; it returned stripped ASR text for `fixTypos` and `custom`. Text Processing now loads a local LLM and records `wasProcessedByLLM` only when generation succeeds.
- Text Processing now uses `mlx-swift-lm` with `mlx-community/Qwen3-4B-Instruct-2507-4bit`. This replaces the incorrect `Qwen3Chat` and Qwen3.5 loading attempts.
- `Qwen3-4B-Instruct-2507-4bit` is a non-reasoning Qwen3 model and does not need `enable_thinking=false`, `/think`, `/nothink`, or app-side `<think>...</think>` stripping.
- `TextProcessingBackend` loads the model with `LLMModelFactory.shared.loadContainer`, a Hugging Face downloader bridge, and a `swift-transformers` tokenizer bridge. The app target links `MLXLLM`, `MLXLMCommon`, `HuggingFace`, and `Tokenizers`.
- Text Processing generation uses Qwen's recommended instruct settings where `GenerateParameters` supports them: `temperature=0.7`, `topP=0.8`, `topK=20`, `minP=0`, and `maxTokens=16_384`. `presencePenalty` is left unset to avoid avoidable language mixing.
- `xcodebuild -quiet -project VibingSpeech.xcodeproj -scheme VibingSpeech -configuration Debug -destination 'platform=macOS,arch=arm64' CODE_SIGNING_ALLOWED=NO build` and the matching `test` command passed after the LLM/model idle changes.
- History rows now copy by source: the visible `finalText` is copied as the LLM edit when `wasProcessedByLLM` is true, raw ASR text is copied from `originalASRText`, and unprocessed rows copy `finalText` as the transcription.
- `AppCoordinator.finishRecordingAndTranscribe()` now keeps `originalASRText` populated for every LLM-processed record, even when the edited text matches the raw ASR text, so History can still offer a separate transcription copy action.
- Xcode MCP build passed after the History copy update. The MCP test runner could not load `VibingSpeechTests` because of a local Team ID signing mismatch, while `xcodebuild -project VibingSpeech.xcodeproj -scheme VibingSpeech -configuration Debug -destination 'platform=macOS,arch=arm64' CODE_SIGNING_ALLOWED=NO test` passed all 11 tests.
- Model preparation now surfaces in `VibingSpeech/Views/ContentView.swift` through a Home panel, status badge spinner, and inline ASR/LLM rows. `AppCoordinator.loadASRModel()` also tracks `asrModelIsLoading` and ignores stale async completions with a generation token.
- The LLM loading panel originally stayed visible because views read `coordinator.textProcessing.isLoading` without directly observing the nested `TextProcessingService`; `ModelActivityPanel` and `SettingsCard` now receive it as an `@ObservedObject`.
- The menu-bar Show Window action failed after closing the main window because `showMainWindow()` only searched `NSApp.windows` after SwiftUI had removed the window. `MainWindowController` now registers the `NSWindow`, intercepts close with `windowShouldClose`, hides it with `orderOut(nil)`, and restores it with `makeKeyAndOrderFront(nil)`.
- The main window was constrained to a fixed 760 x 560 SwiftUI content size through `AppLayout` and `.windowResizability(.contentSize)` in `VibingSpeech/App/VibingSpeechApp.swift`; detail pages remain scrollable inside that viewport instead of letting the window stretch horizontally.
- The sidebar collapse icon in `VibingSpeech/Views/ContentView.swift` now toggles between the full 146 pt navigation sidebar and a 46 pt restore rail. Keep both states available so users are not trapped after hiding navigation.
- The Home settings list was split into grouped settings sections and the sidebar active item was changed from blue accent selection to a subtle gray source-list highlight to better match macOS settings-style surfaces.
- The recording overlay was changed from a large top-screen status capsule to a 150 x 33 bottom-centered capsule in `VibingSpeech/Views/RecordingOverlay.swift`; the phase text was removed so only the icon and waveform/progress indicator remain.
- The waveform now responds more strongly to speech by applying a small RMS noise floor and higher scaling in `MicrophoneRecorder.rmsLevel(for:)`, then using that normalized level as the primary bar-height driver in `WaveformView`.
- The recording crash with `_swift_task_checkIsolatedSwift` / `dispatch_assert_queue` was caused by creating the AVAudioEngine tap closure inside `@MainActor` `MicrophoneRecorder.start(selectedDeviceID:)`; Swift 6 treated the escaping callback as main-actor isolated even though AVFAudio invoked it on `RealtimeMessenger.mServiceQueue`.
- The fix moved tap callback creation into a non-main-actor `MicrophoneAudioTap` helper, kept raw audio conversion off the recorder actor, and hopped to `MainActor` only through `MicrophoneRecorder.ingest(samples:level:sessionID:)`.
- Xcode GUI Archive failed after adding `speech-swift` `0.0.15` because Release package builds compiled `SpeechVAD` sources for x86_64, where `Float16` is unavailable on macOS. Normal Run builds succeeded because they built only the active Apple Silicon architecture.
- The failing package files were `Sources/SpeechVAD/CoreMLSileroInference.swift` and `Sources/SpeechVAD/CoreMLWeSpeakerInference.swift`, with errors such as `'Float16' is unavailable in macOS`, initializer mismatch errors, and `Float16` subscript assignment failures.
- App-side `EXCLUDED_ARCHS = x86_64`, `ONLY_ACTIVE_ARCH = YES` for Release, deployment target changes, package updates, and clearing DerivedData did not resolve the GUI Archive failure because Xcode package Release builds are not controlled by the app target's excluded-architecture settings.
- The adopted workaround was to archive from the command line for Apple Silicon only, passing `ARCHS=arm64` directly to `xcodebuild` so the setting applies to Swift package builds. Use `script/archive.sh` for the recorded workflow.
- `-destination "platform=macOS"` is intentional for the archive command. Avoid `generic/platform=macOS` because it can trigger universal package builds, and avoid adding `arch=arm64` to the destination because Xcode 26 rejects that archive destination form.
- The generated archive and `.app` are arm64-only and are appropriate for Apple Silicon Macs. Developer ID distribution still requires a separate signed export and notarization flow.
- `script/archive.sh` was verified on Apple Silicon and produced `build/VibingSpeech.xcarchive` plus an ad-hoc signed `build/VibingSpeech.app`.
- Related SwiftPM/Xcode limitation notes: https://forums.swift.org/t/restrict-macos-builds-to-x86-64-with-swiftpm/42239 and https://forums.swift.org/t/adding-excluded-archs-settings-in-package-swift/60784.
