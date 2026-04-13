# Code Deletion Log

## [2026-04-13] Text Processing Feature — Translation Removal & Text Polish Replacement

### Translation Feature Removed
- Sources/VibingSpeech/Views/MainWindow/HomeView.swift — "Translation" / "Off" HStack row removed from HomeView (feature was never implemented, UI-only placeholder)

### Text Polish Feature Replaced
- Sources/VibingSpeech/App/AppState.swift — `polishText(_:)` private method removed (lightweight regex-based post-processing replaced by LLM-based TextProcessingEngine)
- Sources/VibingSpeech/Persistence/SettingsStore.swift — `textPolishEnabled: Bool` property removed (replaced by `textProcessingEnabled`, `textProcessingPreset`, `customTextProcessingPrompt`)

### New Files Added
- Sources/VibingSpeech/TextProcessing/TextProcessingEngine.swift — LLM-based text processing engine using mlx-swift-lm + Qwen3-4B-Instruct-2507-4bit
- Sources/VibingSpeech/Models/TextProcessingPreset.swift — Preset enum: fixTypos, bulletPoints, custom

### Dependencies Added
- Package.swift — Added `mlx-swift-lm` (exact: 2.31.3) with products `MLXLLM` and `MLXLMCommon`
- Package.swift — `swift-tools-version` updated from 5.9 to 6.1 (required by mlx-swift-lm 2.31.3); `.swiftLanguageMode(.v5)` set on target to preserve existing code compatibility

### Impact
- Files added: 2
- Files modified: 4 (Package.swift, AppState.swift, SettingsStore.swift, HomeView.swift)
- Properties/methods removed: 2 (textPolishEnabled, polishText)
- UI rows removed: 1 (Translation row)

### Testing
- [O] `swift build -c release` passes
- [O] `make build && make run` launches correctly
- [O] Text processing toggle ON loads Qwen3-4B-Instruct-2507-4bit model
- [O] Text processing toggle OFF unloads model and frees memory
- [O] Recording → transcription → text processing → paste flow verified
- [△] Presets (Fix Typos, Bullet Points, Custom) produce expected output
- [O] Text processing OFF bypasses LLM entirely, transcription pastes raw text

---

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