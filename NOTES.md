# Notes

## 2026-05-30

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
- Text Processing now uses `mlx-swift-lm` `3.31.3` with `mlx-community/Qwen3-4B-Instruct-2507-4bit`. This replaces the incorrect `Qwen3Chat` and Qwen3.5 loading attempts.
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
