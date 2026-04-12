# Code Deletion Log

## [2026-04-12] Refactor Session — Dead Code Cleanup

### Unused Imports Removed
- Sources/VibingSpeech/Audio/TranscriptionEngine.swift — `import MLX` (no MLX symbols used directly)

### Unused Properties/Methods Removed
- Sources/VibingSpeech/Utilities/PermissionChecker.swift — `isMicrophoneGranted` (only async `requestMicrophoneAccess` is used)
- Sources/VibingSpeech/HotkeyManager/GlobalHotkeyManager.swift — `longPressThreshold` (duplicate of AppState's property; never read in GlobalHotkeyManager)
- Sources/VibingSpeech/HotkeyManager/GlobalHotkeyManager.swift — `hotkeyPressTime` (written in handleEvent but never read)
- Sources/VibingSpeech/Audio/TranscriptionEngine.swift — `unloadModel()` (never called; `loadModel` already sets `model = nil` internally before loading a new variant)

### Retained With Annotation
- Sources/VibingSpeech/Persistence/HotwordStore.swift — `hotwordTexts` computed property retained with doc comment for future Qwen3-ASR prompt integration

### Performance Improvements
- Sources/VibingSpeech/Models/TranscriptionRecord.swift — `DateFormatter` instances changed from per-call allocation to `static let` (avoids repeated expensive initialization in list views)

### Impact
- Files deleted: 1
- Properties/methods removed: 4
- Imports removed: 1
- Lines of code removed: ~15

### Testing
- [O] `swift build -c release` passes
- [O] `make build && make run` launches correctly
- [O] Menu bar icon visible, hotkey works
- [O] Recording → transcription → paste flow verified
- [O] Hotwords and history screens functional
