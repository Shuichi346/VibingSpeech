# Notes

## 2026-05-20

- Xcode GUI Archive failed after adding `speech-swift` `0.0.15` because Release package builds compiled `SpeechVAD` sources for x86_64, where `Float16` is unavailable on macOS. Normal Run builds succeeded because they built only the active Apple Silicon architecture.
- The failing package files were `Sources/SpeechVAD/CoreMLSileroInference.swift` and `Sources/SpeechVAD/CoreMLWeSpeakerInference.swift`, with errors such as `'Float16' is unavailable in macOS`, initializer mismatch errors, and `Float16` subscript assignment failures.
- App-side `EXCLUDED_ARCHS = x86_64`, `ONLY_ACTIVE_ARCH = YES` for Release, deployment target changes, package updates, and clearing DerivedData did not resolve the GUI Archive failure because Xcode package Release builds are not controlled by the app target's excluded-architecture settings.
- The adopted workaround was to archive from the command line for Apple Silicon only, passing `ARCHS=arm64` directly to `xcodebuild` so the setting applies to Swift package builds. Use `script/archive.sh` for the recorded workflow.
- `-destination "platform=macOS"` is intentional for the archive command. Avoid `generic/platform=macOS` because it can trigger universal package builds, and avoid adding `arch=arm64` to the destination because Xcode 26 rejects that archive destination form.
- The generated archive and `.app` are arm64-only and are appropriate for Apple Silicon Macs. Developer ID distribution still requires a separate signed export and notarization flow.
- `script/archive.sh` was verified on Apple Silicon and produced `build/VibingSpeech.xcarchive` plus an ad-hoc signed `build/VibingSpeech.app`.
- Related SwiftPM/Xcode limitation notes: https://forums.swift.org/t/restrict-macos-builds-to-x86-64-with-swiftpm/42239 and https://forums.swift.org/t/adding-excluded-archs-settings-in-package-swift/60784.
