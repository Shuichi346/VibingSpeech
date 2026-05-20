# Notes

## 2026-05-20

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
