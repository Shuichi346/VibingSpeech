# Code Deletion Log

## [2026-04-21] Bug Fix Session — Multi-Language Detection & Safety Improvements

### Critical: Latin-script languages all detected as English
- Sources/VibingSpeech/Audio/TranscriptionEngine.swift — `transcribe()` return type changed from `String` to `(text: String, detectedLanguage: String?)` tuple
- Sources/VibingSpeech/Audio/TranscriptionEngine.swift — `TranscriptionModelStore.transcribe()` now calls `model.transcribeWithLanguage()` instead of `model.transcribe()` to obtain ASR-detected language from `TranscriptionResult.language`
- Sources/VibingSpeech/App/AppState.swift — `detectLanguage(from:configured:)` renamed to `detectLanguage(from:configured:asrDetectedLanguage:)` with three-tier priority: user setting > ASR detection > Unicode heuristic
- Sources/VibingSpeech/App/AppState.swift — Added `normalizeASRLanguage(_:)` private method that maps ASR language names ("french", "japanese", etc.) to ISO 639-1 codes ("fr", "ja", etc.)
- Sources/VibingSpeech/App/AppState.swift — Latin-only text heuristic now returns `"unknown"` instead of `"en"`, delegating to LLM auto-detection
- Sources/VibingSpeech/Models/TextProcessingPreset.swift — `systemPrompt(detectedLanguage:)` signature changed to `systemPrompt(detectedLanguage:asrLanguage:)` with new `asrLanguage: String?` parameter
- Sources/VibingSpeech/Models/TextProcessingPreset.swift — `default` case now uses ASR language name in English template (`"The input text is in {Language}. Respond in {Language}."`) when available, falling back to generic auto-detect instruction only when ASR language is nil
- Sources/VibingSpeech/Models/TextProcessingPreset.swift — Removed `"ko"` case (Korean now handled by `default` case via ASR language template)
- Sources/VibingSpeech/TextProcessing/TextProcessingEngine.swift — `processText(_:preset:detectedLanguage:customPrompt:)` signature changed to `processText(_:preset:detectedLanguage:asrLanguage:customPrompt:)` to pass raw ASR language name through to preset
- Sources/VibingSpeech/App/AppState.swift — `stopRecordingAndTranscribe()` now captures `asrDetectedLanguage` from transcription result and passes it through to `processText(asrLanguage:)`

### Critical: History saved to disk even when retention is set to Never
- Sources/VibingSpeech/App/AppState.swift — `stopRecordingAndTranscribe()` now checks `historyRetention != .never` before calling `history.add(record)`; when retention is `.never`, no `TranscriptionRecord` is created and no data is written to disk

### High: Kanji-only Japanese text detected as Chinese
- Sources/VibingSpeech/App/AppState.swift — Resolved by prioritizing ASR-detected language over Unicode heuristic; Qwen3-ASR's 52-language identification correctly distinguishes Japanese from Chinese regardless of script
- Sources/VibingSpeech/App/AppState.swift — Removed Korean (Hangul) detection from Unicode heuristic fallback; kanji-only text without ASR detection falls through to `"zh"` or `"unknown"`

### High: Right Option / Left Control release detection fails with both modifier keys held
- Sources/VibingSpeech/HotkeyManager/GlobalHotkeyManager.swift — Removed `flags.contains(.maskAlternate)` / `flags.contains(.maskControl)` device-independent flag checks from `handleEvent()`
- Sources/VibingSpeech/HotkeyManager/GlobalHotkeyManager.swift — `flagsChanged` handling now uses keyCode-based toggle: when `keyCode == hotkeyCode`, the `isHotkeyHeld` state is toggled (false→true on first event, true→false on second event), correctly distinguishing left/right modifier keys without relying on aggregate flag masks

### High: Recording starts even when ASR model is not loaded
- Sources/VibingSpeech/App/AppState.swift — `startRecording()` now checks `transcriptionEngine.isModelLoaded` before proceeding; if model is not loaded, sets `lastError` message and returns without starting recording

### High: Non-atomic JSON writes risk file corruption
- Sources/VibingSpeech/Persistence/HistoryStore.swift — `save()` changed from `data.write(to: fileURL)` to `data.write(to: fileURL, options: .atomic)`
- Sources/VibingSpeech/Persistence/HotwordStore.swift — `save()` changed from `data.write(to: fileURL)` to `data.write(to: fileURL, options: .atomic)`
- Sources/VibingSpeech/Persistence/HistoryStore.swift — `load()` no longer implicitly overwrites corrupted files; on decode failure, sets `records = []` in memory but preserves the existing file on disk
- Sources/VibingSpeech/Persistence/HotwordStore.swift — `load()` no longer implicitly overwrites corrupted files; on decode failure, sets `hotwords = []` in memory but preserves the existing file on disk
- Sources/VibingSpeech/Persistence/HistoryStore.swift — `load()` now checks `FileManager.default.fileExists(atPath:)` before attempting to read, avoiding unnecessary error path for first launch
- Sources/VibingSpeech/Persistence/HotwordStore.swift — `load()` now checks `FileManager.default.fileExists(atPath:)` before attempting to read, avoiding unnecessary error path for first launch

### Medium: Text Processing toggle ON/OFF race leaves model in memory
- Sources/VibingSpeech/App/AppState.swift — Added `textProcessingToggleGeneration: UInt64` counter to serialize toggle operations
- Sources/VibingSpeech/App/AppState.swift — `setTextProcessingEnabled(_:)` now captures generation counter before async work; on completion, checks if generation matches and discards stale results (unloads model if setting was toggled back to OFF during load)

### Medium: UI shows Text Processing ON after model load failure at startup
- Sources/VibingSpeech/App/AppState.swift — `setup()` now sets `settings.textProcessingEnabled = false` when `textProcessingEngine.loadModel()` fails during initial setup

### Medium: Korean (`ko`) removed from backend to match UI
- Sources/VibingSpeech/App/AppState.swift — Removed `"ko"` → `"Korean"` case from `asrLanguageHint(from:)`
- Sources/VibingSpeech/App/AppState.swift — Removed Hangul range detection from `detectLanguage()` Unicode heuristic
- Sources/VibingSpeech/Models/TextProcessingPreset.swift — Removed `"ko"` case from `systemPrompt()` switch; Korean is now handled by `default` case using ASR language name template

### Impact
- Files modified: 6 (AppState.swift, TranscriptionEngine.swift, TextProcessingPreset.swift, TextProcessingEngine.swift, HistoryStore.swift, HotwordStore.swift)
- Files added: 0
- Files deleted: 0
- Methods added: 1 (normalizeASRLanguage in AppState)
- Methods signature changed: 4 (TranscriptionEngine.transcribe, TextProcessingPreset.systemPrompt, TextProcessingEngine.processText, AppState.detectLanguage)
- Properties added: 1 (textProcessingToggleGeneration in AppState)
- Language cases removed from systemPrompt: 1 (ko)
- Language cases removed from asrLanguageHint: 1 (ko)
- Language cases removed from detectLanguage heuristic: 1 (Korean/Hangul)


## [2026-04-19] Bug Fix Session — Remaining Issues Resolution

### Critical: detectLanguage() returns "unknown" for English/Latin text
- Sources/VibingSpeech/App/AppState.swift — `detectLanguage(from:configured:)` now returns `"en"` when `latinCount > 0` instead of falling through to `"unknown"`
- Sources/VibingSpeech/App/AppState.swift — Latin character detection broadened from `scalar.isASCII && scalar.properties.isAlphabetic` to `scalar.properties.isAlphabetic && scalar.value < 0x0250` (covers accented Latin characters)
- Sources/VibingSpeech/Models/TextProcessingPreset.swift — `systemPrompt(detectedLanguage:)` added `"ko"` case with Korean instruction
- Sources/VibingSpeech/Models/TextProcessingPreset.swift — `default` case changed from `"Respond in the same language as the input text."` to `"Detect the language of the input text and always respond in that same language."`

### Critical: AppDelegate.appState declared with `!` — crash risk on pre-initialization access
- Sources/VibingSpeech/App/AppDelegate.swift — `appState` type changed from `AppState!` (implicitly unwrapped optional) to `AppState?` (regular optional)
- Sources/VibingSpeech/App/AppDelegate.swift — `AppState()` creation moved out of `Task` block to synchronous initialization at the start of `applicationDidFinishLaunching`
- Sources/VibingSpeech/App/AppDelegate.swift — `showWindow()` now guards on `appState` being non-nil before proceeding
- Sources/VibingSpeech/App/AppDelegate.swift — `onRecordingStateChanged` callback setup moved into the `Task` block after `await state.setup()`

### High: AVAudioConverter input block data duplication when called multiple times
- Sources/VibingSpeech/Audio/AudioCaptureManager.swift — Added `var inputConsumed = false` flag inside `installTap` closure
- Sources/VibingSpeech/Audio/AudioCaptureManager.swift — Input block now returns `nil` with `.noDataNow` on subsequent calls after the first, preventing audio data duplication during sample rate conversion
- Sources/VibingSpeech/Audio/AudioCaptureManager.swift — Added `guard capacity > 0` and `guard frameCount > 0` safety checks

### Medium: asrLanguageHint() expanded for Korean
- Sources/VibingSpeech/App/AppState.swift — `asrLanguageHint(from:)` added `"ko"` → `"Korean"` mapping
- Sources/VibingSpeech/App/AppState.swift — `"auto"` case made explicit (returns `nil`)

### Medium: OverlayState.deinit Timer.invalidate() called nonisolated
- Sources/VibingSpeech/Views/Overlay/RecordingOverlayPanel.swift — `OverlayState.deinit` changed to capture timer into local variable and dispatch `invalidate()` via `DispatchQueue.main.async` for thread-safe cleanup

### Medium: Hotwords context text format suboptimal for ASR decoder prompt prefix
- Sources/VibingSpeech/Persistence/HotwordStore.swift — `recognitionContext` format changed from `"Recognize these terms accurately when they are spoken: word1, word2"` to `"Key terms: word1, word2"` (concise word-list format for decoder prompt prefix)

### Low: No user notification on save() failure
- Sources/VibingSpeech/Persistence/HistoryStore.swift — Added `lastSaveError: String?` property, set on save failure, cleared on success
- Sources/VibingSpeech/Persistence/HotwordStore.swift — Added `lastSaveError: String?` property, set on save failure, cleared on success

### Low: Microphone list fetched every View re-render
- Sources/VibingSpeech/Views/MainWindow/HomeView.swift — Added `@State private var cachedMicrophones` populated in `.onAppear`
- Sources/VibingSpeech/Views/MainWindow/HomeView.swift — Microphone `Picker` now iterates over cached list instead of calling `AudioCaptureManager.availableMicrophones()` on every `body` evaluation

### Low: Package.swift platforms and README requirements inconsistent
- README.md — Requirements changed from `macOS 26.0+ (Tahoe)` to `macOS 15.0+ (Sequoia) — tested on macOS 26 (Tahoe)`, aligning with `Package.swift` `.macOS("15.0")` and Makefile `LSMinimumSystemVersion`
- README.md — Platform badge updated from `macOS%2026%2B` to `macOS%2015%2B`

### Not changed (confirmed safe)
- Issue #6 (Qwen3.5-4B-MLX-4bit VLM compatibility): `model_type: "qwen3_5"` is registered in `LLMTypeRegistry` as `Qwen35Model`; vision weights are sanitized during LLM weight loading. No code change needed.
- Issue #9 (ChatSession created every time): By design — independent transcription context, no benefit from KV cache reuse.
- Issue #14 (GlobalHotkeyManager thread safety): CGEventTap callback runs on main RunLoop via `CFRunLoopAddSource(CFRunLoopGetMain(), ...)`. Practically safe.

### Impact
- Files modified: 7 (AppDelegate.swift, AppState.swift, AudioCaptureManager.swift, TextProcessingPreset.swift, HotwordStore.swift, HistoryStore.swift, HomeView.swift, RecordingOverlayPanel.swift, README.md)
- Files added: 0
- Files deleted: 0
- Properties added: 2 (lastSaveError in HistoryStore, lastSaveError in HotwordStore)
- Properties added to View: 1 (cachedMicrophones in HomeView)
- Language cases removed from systemPrompt: 7 (fr, de, es, pt, ru, ar, it)
- Language cases removed from asrLanguageHint: 7 (fr, de, es, pt, ru, ar, it)


## [2026-04-19] Bug Fix Session — Previous Review Findings

### CGEventTap Memory Leak Fix
- Sources/VibingSpeech/HotkeyManager/GlobalHotkeyManager.swift — CGEventTap callback return value changed from `Unmanaged.passRetained(event)` to `Unmanaged.passUnretained(event)` (eliminated per-event retain leak)

### Hotwords ASR Integration
- Sources/VibingSpeech/Persistence/HotwordStore.swift — Added `recognitionContext` computed property that formats hotword list into a context string for ASR prompt injection
- Sources/VibingSpeech/App/AppState.swift — `stopRecordingAndTranscribe()` now passes `hotwords.recognitionContext` to `transcriptionEngine.transcribe(context:)`
- Sources/VibingSpeech/Audio/TranscriptionEngine.swift — `transcribe()` signature updated to accept `context: String?` parameter, forwarded to `Qwen3ASRModel.transcribe(context:)`

### Microphone Selection Fix
- Sources/VibingSpeech/Audio/AudioCaptureManager.swift — Added `configureInputDevice(_:)` private method that calls `audioEngine.inputNode.auAudioUnit.setDeviceID()` with the selected device
- Sources/VibingSpeech/Audio/AudioCaptureManager.swift — Added `defaultInputDeviceID()` static method using CoreAudio `kAudioHardwarePropertyDefaultInputDevice`
- Sources/VibingSpeech/Audio/AudioCaptureManager.swift — `startRecording(microphoneID:)` now calls `configureInputDevice()` before installing the audio tap

### Accessibility Permission Handling Overhaul
- Sources/VibingSpeech/HotkeyManager/GlobalHotkeyManager.swift — `start(keyCode:)` changed from silent failure to `throws` (throws `GlobalHotkeyError`)
- Sources/VibingSpeech/HotkeyManager/GlobalHotkeyManager.swift — Added `GlobalHotkeyError` enum (`accessibilityPermissionRequired`, `failedToCreateEventTap`)
- Sources/VibingSpeech/HotkeyManager/GlobalHotkeyManager.swift — Added `isRunning` property and `lastErrorMessage` property
- Sources/VibingSpeech/App/AppState.swift — Added `hotkeyErrorMessage` property, `isHotkeyReady` computed property, `isAccessibilityGranted` property
- Sources/VibingSpeech/App/AppState.swift — Added `configureHotkeyMonitoring(promptIfNeeded:)` private method that handles permission check, start, and error reporting
- Sources/VibingSpeech/App/AppState.swift — Added `retryHotkeySetup()` and `openAccessibilitySettings()` public methods
- Sources/VibingSpeech/Utilities/PermissionChecker.swift — `requestAccessibilityIfNeeded()` changed to return `Bool` with `prompt` parameter; added `openAccessibilitySettings()` method
- Sources/VibingSpeech/Views/MainWindow/HomeView.swift — Added hotkey status indicator (green dot when active, orange warning with "Open Accessibility Settings" and "Retry Hotkey Setup" buttons when inactive)

### Transcription Off-MainActor Migration
- Sources/VibingSpeech/Audio/TranscriptionEngine.swift — Introduced `TranscriptionModelStore` private actor to hold `Qwen3ASRModel` and run `transcribe()` off the MainActor
- Sources/VibingSpeech/Audio/TranscriptionEngine.swift — `transcribe()` changed from synchronous to `async`, delegating to `modelStore.transcribe()`
- Sources/VibingSpeech/App/AppState.swift — `stopRecordingAndTranscribe()` updated to `await` the async transcription call inside a `Task(priority: .userInitiated)`

### Initial Window Display Before Model Load
- Sources/VibingSpeech/App/AppDelegate.swift — `applicationDidFinishLaunching` reordered: `showWindow()` is now called before `await appState.setup()` so model download progress is visible immediately

### ASR Model Switch UI Safety
- Sources/VibingSpeech/App/AppState.swift — Added `pendingModelVariant` property to track in-progress model switch
- Sources/VibingSpeech/App/AppState.swift — Added `selectedModelForUI` computed property that returns `pendingModelVariant ?? currentVariant ?? settings.selectedModel`
- Sources/VibingSpeech/App/AppState.swift — `switchModel()` now sets `pendingModelVariant` during load and only updates `settings.selectedModel` on success
- Sources/VibingSpeech/Views/MainWindow/HomeView.swift — ASR Model Picker bound to `appState.selectedModelForUI` with `.disabled` during loading or recording

### Recording Hotkey Setting Applied at Startup
- Sources/VibingSpeech/App/AppState.swift — `configureHotkeyMonitoring()` now passes `settings.recordingHotkey.keyCode` to `hotkeyManager.start()` instead of hardcoded `KeyCode.rightOption`
- Sources/VibingSpeech/App/AppState.swift — Added `updateRecordingHotkey(_:)` method that updates both the setting and the live hotkey manager
- Sources/VibingSpeech/Persistence/SettingsStore.swift — Added `keyCode` and `symbol` computed properties to `RecordingHotkey` enum

### Language Hint Passed to ASR
- Sources/VibingSpeech/App/AppState.swift — Added `asrLanguageHint(from:)` private method that maps language codes to ASR language hint strings
- Sources/VibingSpeech/Audio/TranscriptionEngine.swift — `transcribe()` signature updated to accept `languageHint: String?`, forwarded to `Qwen3ASRModel.transcribe(language:)`

### History Pruning at Startup
- Sources/VibingSpeech/App/AppState.swift — `init()` now calls `history.pruneIfNeeded(retention: settings.historyRetention)` immediately after creating stores

### Clipboard Restoration Safety
- Sources/VibingSpeech/TextInsertion/TextInsertionService.swift — Added `snapshotPasteboard(_:)` private method that captures all pasteboard items and their typed data before overwriting
- Sources/VibingSpeech/TextInsertion/TextInsertionService.swift — Added `restorePasteboard(_:on:onlyIfChangeCountMatches:)` private method that only restores if `changeCount` has not changed (another app hasn't written to clipboard in the interim)
- Sources/VibingSpeech/TextInsertion/TextInsertionService.swift — All early-return paths (CGEvent creation failure) now call `restorePasteboard()` before returning

### Event Tap Recovery
- Sources/VibingSpeech/HotkeyManager/GlobalHotkeyManager.swift — `handleEvent()` now checks for `tapDisabledByTimeout` and `tapDisabledByUserInput` event types
- Sources/VibingSpeech/HotkeyManager/GlobalHotkeyManager.swift — Added `recoverEventTap()` private method that re-enables the tap and resets `isHotkeyHeld` state

### Error Display in UI
- Sources/VibingSpeech/Views/MainWindow/MainContentView.swift — Added `.safeAreaInset(edge: .bottom)` error banner that shows `appState.lastError` with a "Dismiss" button
- Sources/VibingSpeech/App/AppState.swift — Added `clearLastError()` method

### Impact
- Files modified: 10 (AppDelegate.swift, AppState.swift, AudioCaptureManager.swift, TranscriptionEngine.swift, GlobalHotkeyManager.swift, PermissionChecker.swift, TextInsertionService.swift, SettingsStore.swift, HomeView.swift, MainContentView.swift, HotwordStore.swift)
- Files added: 0
- Files deleted: 0
- Methods added: 14 (configureInputDevice, defaultInputDeviceID, configureHotkeyMonitoring, retryHotkeySetup, openAccessibilitySettings, updateRecordingHotkey, asrLanguageHint, clearLastError, snapshotPasteboard, restorePasteboard, recoverEventTap, recognitionContext, selectedModelForUI, isHotkeyReady)
- Properties added: 5 (hotkeyErrorMessage, isAccessibilityGranted, pendingModelVariant, isRunning, lastErrorMessage)
- Enums added: 1 (GlobalHotkeyError)


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
