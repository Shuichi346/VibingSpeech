# Code Deletion Log

## [2026-04-18] mlx-swift-lm v3 Upgrade & Qwen3.5-4B Migration

### mlx-swift-lm 2.31.3 → 3.31.3 Upgrade
- Package.swift — `mlx-swift-lm` dependency updated from `exact: "2.31.3"` to `exact: "3.31.3"`
- Package.swift — Added `swift-huggingface` (≥ 0.9.0) and `swift-transformers` (≥ 1.3.0) as new dependencies (required by mlx-swift-lm v3 decoupled tokenizer/downloader architecture)
- Package.swift — Added `MLXHuggingFace`, `HuggingFace`, `Tokenizers` products to target dependencies

### Text Processing Model Changed: Qwen3-4B-Instruct-2507-4bit → Qwen3.5-4B-MLX-4bit
- Sources/VibingSpeech/TextProcessing/TextProcessingEngine.swift — `modelId` changed from `"mlx-community/Qwen3-4B-Instruct-2507-4bit"` to `"mlx-community/Qwen3.5-4B-MLX-4bit"`
- Sources/VibingSpeech/TextProcessing/TextProcessingEngine.swift — `estimatedSize` updated from `"~2.5 GB"` to `"~2.9 GB"`

### mlx-swift-lm v3 API Migration
- Sources/VibingSpeech/TextProcessing/TextProcessingEngine.swift — `LLMModelFactory.shared.loadContainer(configuration:)` replaced with `LLMModelFactory.shared.loadContainer(from: #hubDownloader(), using: #huggingFaceTokenizerLoader(), configuration:)` (v3 requires explicit downloader and tokenizer loader)
- Sources/VibingSpeech/TextProcessing/TextProcessingEngine.swift — Added imports: `MLXHuggingFace`, `HuggingFace`, `Tokenizers` (required by v3 macro-based integration)

### Qwen3.5 Thinking Mode Disabled
- Sources/VibingSpeech/TextProcessing/TextProcessingEngine.swift — `ChatSession` now initialized with `additionalContext: ["enable_thinking": false]` to disable reasoning mode via Jinja chat template
- Sources/VibingSpeech/TextProcessing/TextProcessingEngine.swift — Added `stripThinkTags(_:)` private method to remove residual `<think>...</think>` tags from model output as a safety measure

### GenerateParameters Updated for Qwen3.5 Non-Thinking Optimal Settings
- Sources/VibingSpeech/TextProcessing/TextProcessingEngine.swift — `GenerateParameters` changed:
  - `temperature`: 0.7 → 0.7 (unchanged)
  - `topP`: 0.8 → 0.8 (unchanged)
  - `topK`: 20 → 20 (unchanged)
  - `minP`: 0.0 → 0.0 (unchanged)
  - `repetitionPenalty`: 1.05 → removed (Qwen3.5 non-thinking recommends 1.0 = disabled)
  - `repetitionContextSize`: 64 → removed (no longer needed)
  - `presencePenalty`: not set → 1.5 (newly added, Qwen3.5 non-thinking recommendation)
  - `presenceContextSize`: not set → 64 (newly added)

### UI Updates
- Sources/VibingSpeech/Views/MainWindow/HomeView.swift — Model label changed from `"Qwen3-4B-Instruct-2507 (4-bit)"` to `"Qwen3.5-4B (4-bit, thinking off)"`

### Documentation Updates
- README.md — Dependencies table updated with new packages (`swift-huggingface`, `swift-transformers`) and version (`mlx-swift-lm` 3.31.3)
- README.md — Text Processing section updated: model name, download size, non-thinking parameter description
- README.md — Model cache location updated: directory name `Qwen3.5-4B-MLX-4bit`
- README.md — Credits updated: `Qwen3-4B-Instruct-2507` → `Qwen3.5-4B`
- README.md — Features list updated: model name in LLM Text Processing bullet

### Removed / Replaced
- Properties removed: 0
- Methods removed: 0
- Methods added: 1 (`stripThinkTags` in TextProcessingEngine)
- Imports added: 3 (`MLXHuggingFace`, `HuggingFace`, `Tokenizers`)
- Dependencies added: 2 (`swift-huggingface`, `swift-transformers`)

### Impact
- Files modified: 4 (Package.swift, TextProcessingEngine.swift, HomeView.swift, README.md)
- Files added: 0
- Files deleted: 0

### Compatibility Notes
- `speech-swift` (≥ 0.0.9) depends on `mlx-swift` from `"0.30.0"`, which allows resolution to 0.31.x
- `mlx-swift-lm` (3.31.3) depends on `mlx-swift` `.upToNextMinor(from: "0.31.3")`, resolving to 0.31.x
- SPM resolves both to `mlx-swift` 0.31.3 — no version conflict
- `Qwen3.5-4B-MLX-4bit` has `model_type: "qwen3_5"`, registered in `LLMTypeRegistry` as `Qwen35Model` (supported since mlx-swift-lm 3.31.3)
- Chat template at `chat_template.jinja` includes `enable_thinking` conditional (lines 147–153), confirmed compatible with `additionalContext` passthrough

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
