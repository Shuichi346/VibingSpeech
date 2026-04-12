## Development Environment

- Mac mini M4 (Apple Silicon, 24GB Unified Memory, macOS 26.3 (Tahoe))
- Character encoding: UTF-8
- GPU: Use `mps` or `cpu` (`cuda` is not available)

## Development Policy

- The user cannot write code on their own. Keep explanations simple and clear.
- Output only one optimal code pattern. Do not present multiple alternatives.
- After outputting code, always debug first, then refactor to ensure maintainability.
- Use well-known open-source libraries when available to avoid reinventing the wheel. However, avoid libraries whose updates have stalled or that are obscure, as they pose security risks.

## Git Operations

- Create a `.gitignore` at the repository root.
- Always include OS-specific entries `.DS_Store` and `Thumbs.db` in `.gitignore`.
- Place `.gitkeep` in empty directories.
- Create a `CHANGELOG.md`.
- Create a `README.md`.


# Implementation Plan: VibingSpeech — macOS Voice Input App

The final deliverable is `VibingSpeech.app`.

**Overview:**
Vibing uses a cloud connection. Build a new locally-complete, Apple Silicon-exclusive macOS voice input app with functionality similar to Vibing. Use the `Qwen3ASR` module from the `speech-swift` package as the ASR engine, with the ability to switch between Qwen3-ASR-0.6B (8-bit MLX) and Qwen3-ASR-1.7B (4-bit MLX) in the settings screen. A global hotkey enables voice transcription from any active application, and a floating microphone icon is displayed on screen during recording. After transcription completes, the text is pasted at the cursor position in the active application. The app runs entirely on-device with no cloud communication whatsoever.

**Stated Assumptions:**

1. The app name is `VibingSpeech`. It can be changed if the user requests it.
2. The minimum deployment target is macOS 14.0 (Sonoma) (speech-swift requirement: macOS 14+).
3. Swift 5.9 or later and Xcode 15 or later are required.
4. Sandbox is **disabled** (CGEventTap is used for global hotkeys, which requires Accessibility permissions and is incompatible with App Sandbox).
5. The build uses `swift build` (SPM) as the primary tool. No Xcode project files are generated. Development is assumed to be done in VSCode.
6. LLM-Powered Rewriting and Translation features are cloud-dependent features of Vibing. For this project, they are limited to "Text Polish" — a local, lightweight post-processing step (e.g., punctuation normalization). Full LLM rewriting is a future enhancement.
7. Hotwords functionality is implemented using Qwen3-ASR's prompt control. However, if the `transcribe` API does not directly support a hotwords parameter, only the UI will be built, with actual functionality deferred to a future update.
8. The text insertion method uses NSPasteboard (clipboard) and simulates Cmd+V to paste into the active application.
9. License is MIT.

**Requirements:**

1. **R1**: A global hotkey (default: Right Option key) starts/stops voice recording from any active application. Long press = hold mode (release to stop), short press = toggle mode (press again to stop).
2. **R2**: During recording, a floating microphone icon overlay is displayed on screen, with visual feedback of the recording state (including a recognition animation).
3. **R3**: Two models are selectable: Qwen3-ASR-0.6B (8-bit MLX) and Qwen3-ASR-1.7B (4-bit MLX). Switchable in the settings screen.
4. **R4**: The transcription result text is pasted (inserted) at the cursor position in the active application.
5. **R5**: The app runs as a menu bar resident app and does not show an icon in the Dock (LSUIElement = true).
6. **R6**: A UI screen for managing a hotword dictionary (custom vocabulary) with add and delete functionality.
7. **R7**: A UI screen for displaying transcription history. History retention settings are selectable (Forever / 1 week / 1 day / Never).
8. **R8**: The home screen displays today's word count, total word count, recording hotkey display, language setting, appearance mode setting (System / Light / Dark), and microphone selection.
9. **R9**: Recording cancellation via the Esc key is supported.
10. **R10**: Automatic detection of 52 languages is supported (native Qwen3-ASR feature).
11. **R11**: Apple Silicon (M1 or later) only. On Intel Macs, an error message is displayed at launch and the app terminates.
12. **R12**: Models are automatically downloaded from HuggingFace on first use and cached in `~/Library/Caches/qwen3-speech/`.
13. **R13**: The project structure is suitable for publishing on GitHub under the MIT license.
14. **R14**: Sound feedback (recording start/stop sounds) can be toggled on or off in settings.

**Tech Stack and Conventions:**

| Item | Value |
|---|---|
| Language | Swift 5.9+ |
| UI Framework | SwiftUI (macOS 14+) |
| AppKit Integration | NSStatusBar (menu bar), NSPanel (floating window), CGEventTap (global hotkey) |
| Speech Recognition | `speech-swift` package (`Qwen3ASR` module) |
| Audio Capture | AVAudioEngine (resampled to 16kHz mono) |
| Package Manager | Swift Package Manager |
| Build System | `swift build -c release` (VSCode compatible) |
| File Naming | PascalCase (matching Swift type names) |
| Persistence | UserDefaults (settings), JSON files (history & hotwords) |
| Minimum OS | macOS 14.0 (Sonoma) |
| Target Architecture | arm64 only |

**Boundaries:**

```
✅ Always:
  - Use existing speech-swift APIs (Qwen3ASRModel.fromPretrained, transcribe) as-is
  - Use SF Symbols for UI icons
  - Protect UI updates with @MainActor
  - Include MIT license headers in all files

⚠️ Ask First:
  - Adding external dependencies other than speech-swift
  - Changing Info.plist entitlements
  - Using macOS 15+ exclusive APIs

🚫 Never:
  - Perform network communication (except for model download)
  - Send user audio data externally
  - Behave as if it works correctly on Intel Macs
  - Enable App Sandbox (incompatible with CGEventTap)
```

**Architecture Changes:**

New project. Build the following directory tree:

```
VibingSpeech/
├── Package.swift
├── LICENSE
├── README.md
├── Makefile
├── Sources/
│   └── VibingSpeech/
│       ├── App/
│       │   ├── VibingSpeechApp.swift          # @main, NSApplication delegate
│       │   ├── AppDelegate.swift              # NSStatusBar, menu bar setup
│       │   └── AppState.swift                 # App-wide ObservableObject state
│       ├── Audio/
│       │   ├── AudioCaptureManager.swift      # AVAudioEngine microphone input management
│       │   └── TranscriptionEngine.swift      # Qwen3ASR wrapper, model switching
│       ├── HotkeyManager/
│       │   ├── GlobalHotkeyManager.swift      # Global hotkey via CGEventTap
│       │   └── KeyCodeConstants.swift         # Key code constants
│       ├── TextInsertion/
│       │   └── TextInsertionService.swift     # Text insertion via clipboard
│       ├── Persistence/
│       │   ├── SettingsStore.swift            # UserDefaults wrapper
│       │   ├── HistoryStore.swift             # Transcription history persistence
│       │   └── HotwordStore.swift             # Hotword dictionary persistence
│       ├── Views/
│       │   ├── MainWindow/
│       │   │   ├── MainContentView.swift      # Tab container (Home/Hotwords/History)
│       │   │   ├── HomeView.swift             # Home screen
│       │   │   ├── HotwordsView.swift         # Hotword management screen
│       │   │   └── HistoryView.swift          # History screen
│       │   └── Overlay/
│       │       └── RecordingOverlayPanel.swift # Floating microphone icon (NSPanel)
│       ├── Models/
│       │   ├── TranscriptionRecord.swift      # History data model
│       │   ├── Hotword.swift                  # Hotword data model
│       │   └── ASRModelVariant.swift          # Model selection enum
│       └── Utilities/
│           ├── ArchitectureCheck.swift        # Apple Silicon check
│           ├── SoundFeedback.swift            # Sound effect playback
│           └── PermissionChecker.swift        # Accessibility/microphone permission check
└── Resources/
    ├── Assets.xcassets/                       # App icon
    └── Sounds/
        ├── start_recording.aiff
        └── stop_recording.aiff
```

**Agent Summary:**

| Agent | Step Count | Phases Involved |
|---|---|---|
| coding-agent | 22 | 1, 2, 3, 4, 5, 6 |
| devops-agent | 3 | 1, 7 |
| documentation-agent | 2 | 7 |
| review-agent | 7 | 1, 2, 3, 4, 5, 6, 7 |

---

## Implementation Steps

### Phase 1: Project Foundation
**Purpose:** Create the SPM project skeleton, resolve the speech-swift dependency, and reach a state where an empty app builds and launches.

**Step 1.1: Create Package.swift**
- **Agent:** coding-agent
- **Location:** `VibingSpeech/Package.swift`
- **Action:** Create the Swift Package Manager manifest file.
- **Details:**
  - `platforms`: `.macOS(.v14)`
  - `name`: `"VibingSpeech"`
  - Add `speech-swift` as a dependency: `.package(url: "https://github.com/soniqo/speech-swift", from: "0.0.9")`
  - Define an executableTarget `"VibingSpeech"` with `path: "Sources/VibingSpeech"`
  - Target dependencies: `.product(name: "Qwen3ASR", package: "speech-swift")`, `.product(name: "AudioCommon", package: "speech-swift")`
  - `swiftLanguageVersions: [.v5]`
- **Dependencies:** None
- **Verification:** `cd VibingSpeech && swift package resolve` downloads dependency packages and completes without errors.
- **Complexity:** Low
- **Risk:** Low

**Step 1.2: Create Makefile**
- **Agent:** devops-agent
- **Location:** `VibingSpeech/Makefile`
- **Action:** Create a Makefile for build and run operations.
- **Details:**
  - `build` target: Execute `swift build -c release`. Include a troubleshooting comment in case a `Failed to load the default metallib` error occurs with speech-swift's Metal shader library (normally auto-built as an SPM dependency).
  - `debug` target: `swift build`
  - `run` target: `.build/release/VibingSpeech`
  - `clean` target: `swift package clean`
  - Set `.PHONY` appropriately.
- **Dependencies:** Step 1.1
- **Verification:** `make build` completes without errors (given an empty main file exists).
- **Complexity:** Low
- **Risk:** Low

**Step 1.3: Create App Entry Point and AppDelegate**
- **Agent:** coding-agent
- **Location:** `Sources/VibingSpeech/App/VibingSpeechApp.swift`, `Sources/VibingSpeech/App/AppDelegate.swift`
- **Action:** Create the minimal configuration for a macOS menu bar resident app.
- **Details:**
  - `VibingSpeechApp.swift`: Define `@main struct VibingSpeechApp`. Use `@NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate`. The `body` contains only `Settings { EmptyView() }` as an empty Settings scene (the main window is managed manually from AppDelegate).
  - `AppDelegate.swift`: A class conforming to `NSObject, NSApplicationDelegate`.
    - Inside `applicationDidFinishLaunching`:
      - (a) Call `NSApp.setActivationPolicy(.accessory)` to hide the Dock icon (used instead of Info.plist's LSUIElement — since Info.plist handling is cumbersome with SPM builds, this is done in code).
      - (b) Create a status bar item with `NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)`.
      - (c) Set the status bar item button's image to `NSImage(systemSymbolName: "mic.fill", accessibilityDescription: "VibingSpeech")`.
      - (d) Create a status bar item menu (NSMenu). Menu items: "Show Window" (show main window), separator, "Quit" (`NSApp.terminate(nil)`).
    - Main window creation is implemented in Phase 4. At this stage, "Show Window" simply calls `print("Show window")`.
  - Info.plist equivalent: Since SPM's executableTarget cannot directly embed Info.plist, `NSApp.setActivationPolicy(.accessory)` is used as a substitute.
- **Dependencies:** Step 1.1
- **Verification:** `swift build` compiles without errors and running `.build/debug/VibingSpeech` displays a microphone icon in the menu bar. The app terminates when "Quit" is selected.
- **Complexity:** Medium
- **Risk:** Low

**Step 1.4: Apple Silicon Architecture Check**
- **Agent:** coding-agent
- **Location:** `Sources/VibingSpeech/Utilities/ArchitectureCheck.swift`
- **Action:** Create a utility that displays an error dialog and terminates the app when launched on an Intel Mac.
- **Details:**
  - Define `enum ArchitectureCheck` (enum because no instantiation is needed).
  - `static var isAppleSilicon: Bool` property: Returns `true` with `#if arch(arm64)`, `false` with `#else`.
  - `static func ensureAppleSilicon()` method: If `isAppleSilicon` is `false`, display an `NSAlert` (message: "VibingSpeech requires Apple Silicon (M1 or later). This Mac is not supported.") and call `NSApp.terminate(nil)`.
  - Call `ArchitectureCheck.ensureAppleSilicon()` at the beginning of `AppDelegate.applicationDidFinishLaunching`.
- **Dependencies:** Step 1.3
- **Verification:** On an arm64 environment, `swift build` succeeds and the app launches normally (even without an Intel environment, compilation success serves as confirmation).
- **Complexity:** Low
- **Risk:** Low

**Step 1.5: Phase Gate — Phase 1 Verification**
- **Agent:** review-agent
- **Action:** Verify that Phase 1 is correctly completed in its entirety.
- **Verification:**
  - `swift build -c release` completes with zero errors.
  - Running `.build/release/VibingSpeech` displays a microphone icon in the menu bar.
  - The app terminates when "Quit" is selected from the menu.
- **Dependencies:** Steps 1.1, 1.2, 1.3, 1.4

---

### Phase 2: Data Models and Persistence Layer
**Purpose:** Build the persistence layer for app settings, history, and hotwords, establishing the data foundation for business logic.

**Step 2.1: Define ASRModelVariant Enum**
- **Agent:** coding-agent
- **Location:** `Sources/VibingSpeech/Models/ASRModelVariant.swift`
- **Action:** Define an enum for model selection.
- **Details:**
  - Define `enum ASRModelVariant: String, CaseIterable, Codable, Identifiable`.
  - Cases: `qwen3_0_6b_8bit`, `qwen3_1_7b_4bit`
  - `var id: String { rawValue }`
  - `var displayName: String` computed property: Returns `"Qwen3-ASR 0.6B (8-bit)"` and `"Qwen3-ASR 1.7B (4-bit)"` for each case respectively.
  - `var modelId: String` computed property: Returns `"aufklarer/Qwen3-ASR-0.6B-MLX-8bit"` and `"aufklarer/Qwen3-ASR-1.7B-MLX-4bit"` for each case. This is the value passed to `Qwen3ASRModel.fromPretrained(modelId:)`.
  - `var estimatedSize: String` computed property: Returns `"~1.0 GB"` and `"~2.1 GB"`.
  - `var estimatedMemory: String` computed property: Returns `"~1.5 GB"` and `"~3.5 GB"` (approximate peak memory usage).
  - `static var defaultVariant: ASRModelVariant { .qwen3_0_6b_8bit }` — Default is the lightweight model.
- **Dependencies:** Step 1.1
- **Verification:** File compiles and `ASRModelVariant.allCases.count == 2`.
- **Complexity:** Low
- **Risk:** Low

**Step 2.2: Define TranscriptionRecord Data Model**
- **Agent:** coding-agent
- **Location:** `Sources/VibingSpeech/Models/TranscriptionRecord.swift`
- **Action:** Define a data model representing one record of transcription history.
- **Details:**
  - Define `struct TranscriptionRecord: Codable, Identifiable, Equatable`.
  - Properties:
    - `let id: UUID` (generates `UUID()` by default)
    - `let text: String` (transcription result text)
    - `let timestamp: Date` (time of transcription completion)
    - `let wordCount: Int` (word count in the text, split by spaces; for Japanese/Chinese, use character count as wordCount)
    - `let durationSeconds: Double` (recording duration in seconds)
    - `let modelVariant: ASRModelVariant` (model used)
  - `var formattedTime: String` computed property: Formats `timestamp` as `HH:mm`.
  - `var formattedDate: String` computed property: "Today", "Yesterday", or `yyyy/MM/dd` format.
- **Dependencies:** Step 2.1
- **Verification:** File compiles.
- **Complexity:** Low
- **Risk:** Low

**Step 2.3: Define Hotword Data Model**
- **Agent:** coding-agent
- **Location:** `Sources/VibingSpeech/Models/Hotword.swift`
- **Action:** Define a data model for hotwords.
- **Details:**
  - Define `struct Hotword: Codable, Identifiable, Equatable, Hashable`.
  - Properties:
    - `let id: UUID` (default `UUID()`)
    - `let text: String` (hotword text)
    - `let createdAt: Date` (date added)
  - Initializer: `init(text: String)` — Auto-generates id and createdAt.
- **Dependencies:** Step 1.1
- **Verification:** File compiles.
- **Complexity:** Low
- **Risk:** Low

**Step 2.4: Implement SettingsStore**
- **Agent:** coding-agent
- **Location:** `Sources/VibingSpeech/Persistence/SettingsStore.swift`
- **Action:** Create a UserDefaults-based settings store.
- **Details:**
  - Define `@Observable final class SettingsStore`.
  - Settings to store:
    - `var selectedModel: ASRModelVariant` (UserDefaults key: `"selectedModel"`, default: `.qwen3_0_6b_8bit`)
    - `var soundFeedbackEnabled: Bool` (key: `"soundFeedbackEnabled"`, default: `false`)
    - `var textPolishEnabled: Bool` (key: `"textPolishEnabled"`, default: `true`)
    - `var historyRetention: HistoryRetention` (key: `"historyRetention"`, default: `.forever`)
    - `var appearanceMode: AppearanceMode` (key: `"appearanceMode"`, default: `.system`)
    - `var selectedMicrophoneID: String?` (key: `"selectedMicrophoneID"`, default: `nil` = System Default)
    - `var recordingHotkey: RecordingHotkey` (key: `"recordingHotkey"`, default: `.rightOption`)
    - `var language: String` (key: `"language"`, default: `"auto"`)
  - Internal enum definitions:
    - `enum HistoryRetention: String, CaseIterable, Codable { case forever, oneWeek, oneDay, never }` — displayName: "Forever", "1 Week", "1 Day", "Never"
    - `enum AppearanceMode: String, CaseIterable, Codable { case system, light, dark }` — displayName: "System", "Light", "Dark"
    - `enum RecordingHotkey: String, CaseIterable, Codable { case rightOption, leftControl }` — displayName: "Right Option", "Left Control" (extensible for future customization)
  - Each property's getter/setter reads/writes UserDefaults. Setters call `UserDefaults.standard.set(...)` in `didSet`.
  - `init()` loads initial values from UserDefaults.
  - Add an optional `directoryURL: URL?` parameter to the initializer for HistoryStore and HotwordStore. When `nil`, the default path is used; when specified, that path is used. This enables injecting a temporary directory for testing purposes.
- **Dependencies:** Step 2.1
- **Verification:** `swift build` succeeds.
- **Complexity:** Medium
- **Risk:** Low

**Step 2.5: Implement HistoryStore**
- **Agent:** coding-agent
- **Location:** `Sources/VibingSpeech/Persistence/HistoryStore.swift`
- **Action:** Create a JSON persistence store for transcription history.
- **Details:**
  - Define `@Observable final class HistoryStore`.
  - Properties:
    - `private(set) var records: [TranscriptionRecord]` — In-memory history array, newest first.
  - File path: `~/Library/Application Support/VibingSpeech/history.json`. Create the directory with `FileManager.default.createDirectory` if it doesn't exist.
  - Methods:
    - `func add(_ record: TranscriptionRecord)` — Prepend to the array and call `save()`.
    - `func delete(_ record: TranscriptionRecord)` — Delete the matching record and call `save()`.
    - `func clearAll()` — Delete all records and call `save()`.
    - `func pruneIfNeeded(retention: SettingsStore.HistoryRetention)` — Delete old records based on retention. `.forever` does nothing, `.oneWeek` deletes records older than 7 days, `.oneDay` deletes records older than 1 day, `.never` deletes all.
    - `private func save()` — Encode records with `JSONEncoder().encode` to `Data` and write to file.
    - `private func load()` — Read `Data` from file and decode with `JSONDecoder().decode` into records. If the file doesn't exist, use an empty array.
  - `var totalWordCount: Int` computed property: `records.reduce(0) { $0 + $1.wordCount }`
  - `var todayWordCount: Int` computed property: Sum of wordCount for today's records.
  - `init()` calls `load()`. Supports an optional `directoryURL: URL?` parameter for dependency injection.
- **Dependencies:** Step 2.2
- **Verification:** `swift build` succeeds.
- **Complexity:** Medium
- **Risk:** Low

**Step 2.6: Implement HotwordStore**
- **Agent:** coding-agent
- **Location:** `Sources/VibingSpeech/Persistence/HotwordStore.swift`
- **Action:** Create a JSON persistence store for the hotword dictionary.
- **Details:**
  - Define `@Observable final class HotwordStore`.
  - Properties:
    - `private(set) var hotwords: [Hotword]`
  - File path: `~/Library/Application Support/VibingSpeech/hotwords.json`
  - Methods:
    - `func add(_ text: String)` — If the text is not empty and not a duplicate, create a `Hotword(text:)`, add it, and call `save()`.
    - `func delete(_ hotword: Hotword)` — Delete and call `save()`.
    - `private func save()` — JSON encode and write to file.
    - `private func load()` — Load from file. If it doesn't exist, use an empty array.
  - `var hotwordTexts: [String]` computed property: `hotwords.map { $0.text }` — For passing to the Qwen3ASR prompt.
  - `init()` calls `load()`. Supports an optional `directoryURL: URL?` parameter for dependency injection.
- **Dependencies:** Step 2.3
- **Verification:** `swift build` succeeds.
- **Complexity:** Low
- **Risk:** Low

**Step 2.7: Phase Gate — Phase 2 Verification**
- **Agent:** review-agent
- **Action:** Verify that Phase 2 is correctly completed in its entirety.
- **Verification:**
  - `swift build -c release` completes with zero errors.
  - All data models conform to `Codable` and JSON encoding/decoding works correctly.
- **Dependencies:** All steps in Phase 2

---

### Phase 3: Audio Capture and ASR Engine
**Purpose:** Build microphone audio capture and the Qwen3-ASR transcription engine.

**Step 3.1: Implement AudioCaptureManager**
- **Agent:** coding-agent
- **Location:** `Sources/VibingSpeech/Audio/AudioCaptureManager.swift`
- **Action:** Create a microphone input capture manager using AVAudioEngine.
- **Details:**
  - Define `@Observable final class AudioCaptureManager`.
  - Properties:
    - `private let audioEngine = AVAudioEngine()`
    - `private(set) var isRecording = false`
    - `private(set) var audioLevel: Float = 0.0` (0.0–1.0, for UI volume indicator)
    - `private var audioBuffer: [Float] = []` — Accumulates PCM samples during recording
    - `private let targetSampleRate: Double = 16000.0`
    - `private let lock = NSLock()` — For thread-safe access to audioBuffer
  - Methods:
    - `func startRecording(microphoneID: String?)` — Start microphone input.
      - If `microphoneID` is specified, set the device on `audioEngine.inputNode` (using `AudioDeviceID` on macOS; `nil` uses the system default).
      - Get the output format of `audioEngine.inputNode` and set up a converter for 16kHz mono.
      - Set up a tap with `audioEngine.inputNode.installTap(onBus: 0, bufferSize: 4096, format: inputFormat)`. In the tap closure:
        - Use AVAudioConverter to convert from the input format to 16kHz mono Float32.
        - Add converted samples to `audioBuffer` (protected by NSLock).
        - Calculate the RMS level and update `audioLevel` (UI update via @MainActor).
      - `audioEngine.prepare()` → `audioEngine.start()`.
      - `isRecording = true`.
    - `func stopRecording() -> [Float]` — Stop recording and return the accumulated audio buffer.
      - `audioEngine.inputNode.removeTap(onBus: 0)`
      - `audioEngine.stop()`
      - `isRecording = false`
      - `audioLevel = 0.0`
      - Return a copy of `audioBuffer` while protecting with NSLock, then clear `audioBuffer`.
    - `func cancelRecording()` — Discard the recording (clear the buffer and stop).
      - Same as stopRecording but discards the buffer contents. No return value.
    - `static func availableMicrophones() -> [(id: String, name: String)]` — Return a list of connected microphone devices. Use CoreAudio's `AudioObjectGetPropertyData` to enumerate input devices from `kAudioHardwarePropertyDevices`.
- **Dependencies:** Step 1.1
- **Verification:** `swift build` succeeds. Live microphone capture testing is performed at the Phase 3 Gate.
- **Complexity:** High
- **Risk:** Medium — AVAudioEngine's sample rate conversion may have issues with Bluetooth devices like AirPods. Mitigation: Use AVAudioConverter, pass `nil` as the format to installTap to use the engine's default format, and perform conversion on the converter side.

**Step 3.2: Implement TranscriptionEngine**
- **Agent:** coding-agent
- **Location:** `Sources/VibingSpeech/Audio/TranscriptionEngine.swift`
- **Action:** Create a Qwen3ASR model wrapper to manage model loading, switching, and transcription execution.
- **Details:**
  - Define `@Observable final class TranscriptionEngine`.
  - Properties:
    - `private var model: Qwen3ASRModel?` — Currently loaded model.
    - `private(set) var currentVariant: ASRModelVariant?` — Variant of the currently loaded model.
    - `private(set) var isModelLoaded: Bool = false`
    - `private(set) var isLoading: Bool = false`
    - `private(set) var loadingProgress: String = ""` (status message: "Downloading model...", "Loading model...", etc.)
  - Methods:
    - `func loadModel(_ variant: ASRModelVariant) async throws` — Load a model.
      - If the same variant is already loaded, do nothing.
      - `isLoading = true`, `loadingProgress = "Loading \(variant.displayName)..."`
      - `model = try await Qwen3ASRModel.fromPretrained(modelId: variant.modelId)`
      - `currentVariant = variant`, `isModelLoaded = true`, `isLoading = false`
      - The model is automatically downloaded from HuggingFace and cached in `~/Library/Caches/qwen3-speech/` (built-in behavior of speech-swift).
    - `func transcribe(audio: [Float], sampleRate: Int = 16000) -> String` — Execute transcription.
      - Nil-check with `guard let model`. If nil, return an empty string.
      - Call `model.transcribe(audio: audio, sampleRate: sampleRate)` and return the result text.
      - Qwen3-ASR performs automatic language detection, so a language parameter is not needed (pass `language: nil`).
    - `func unloadModel()` — Free memory. `model = nil`, `isModelLoaded = false`, `currentVariant = nil`.
  - Error handling: If `loadModel` fails, set `isLoading = false`, `loadingProgress = "Failed to load model"`, and re-throw the error.
- **Dependencies:** Steps 1.1, 2.1
- **Verification:** `swift build` succeeds. Actual model loading tests are confirmed manually at the Phase 3 Gate (not included in automated tests due to model download time).
- **Complexity:** Medium
- **Risk:** Medium — The API signature of `Qwen3ASRModel.fromPretrained(modelId:)` may differ depending on the speech-swift version. Mitigation: Based on speech-swift source code and HuggingFace Usage documentation (`let model = try await Qwen3ASRModel.fromPretrained(modelId: "aufklarer/Qwen3-ASR-1.7B-MLX-8bit")`). If compile errors occur, try alternative APIs such as `loadFromHub()`.

**Step 3.3: Implement SoundFeedback Utility**
- **Agent:** coding-agent
- **Location:** `Sources/VibingSpeech/Utilities/SoundFeedback.swift`
- **Action:** Create a utility for playing recording start/stop sound effects.
- **Details:**
  - Define `enum SoundFeedback`.
  - `static func playStartSound()` — Use `NSSound(named: "Tink")?.play()` (macOS built-in sound). The design supports custom .aiff files from Resources if available, but initially uses system sounds.
  - `static func playStopSound()` — Use `NSSound(named: "Pop")?.play()`.
  - `static func playErrorSound()` — Use `NSSound(named: "Basso")?.play()`.
  - Each method takes an `isEnabled: Bool` parameter (default `true`); if `false`, does nothing.
- **Dependencies:** Step 1.1
- **Verification:** `swift build` succeeds.
- **Complexity:** Low
- **Risk:** Low

**Step 3.4: Phase Gate — Phase 3 Verification**
- **Agent:** review-agent
- **Action:** Verify that all Phase 3 components build correctly.
- **Verification:**
  - `swift build -c release` completes with zero errors.
  - Manual test: Launch the app and add a temporary test invocation inside `applicationDidFinishLaunching` (load `TranscriptionEngine`, run `AudioCaptureManager` for 3 seconds, then transcribe) to confirm that transcription works. Remove the test code after confirmation.
- **Dependencies:** All steps in Phase 3

---

### Phase 4: Global Hotkey and Text Insertion
**Purpose:** Enable invoking voice input via a shortcut key while using other applications, and build the mechanism for inserting transcription results into the active app.

**Step 4.1: Define KeyCodeConstants**
- **Agent:** coding-agent
- **Location:** `Sources/VibingSpeech/HotkeyManager/KeyCodeConstants.swift`
- **Action:** Define macOS key code constants.
- **Details:**
  - Define `enum KeyCode: UInt16`.
  - Constants: `rightOption = 61`, `leftControl = 59`, `escape = 53`, `v = 9` (for Cmd+V)
  - `static let commandMask: CGEventFlags = .maskCommand`
- **Dependencies:** Step 1.1
- **Verification:** Compiles.
- **Complexity:** Low
- **Risk:** Low

**Step 4.2: Implement GlobalHotkeyManager**
- **Agent:** coding-agent
- **Location:** `Sources/VibingSpeech/HotkeyManager/GlobalHotkeyManager.swift`
- **Action:** Create a global hotkey monitoring manager using CGEventTap.
- **Details:**
  - Define `@Observable final class GlobalHotkeyManager`.
  - Properties:
    - `var onHotkeyDown: (() -> Void)?` — Callback when the hotkey is pressed
    - `var onHotkeyUp: (() -> Void)?` — Callback when the hotkey is released
    - `var onEscapePressed: (() -> Void)?` — Callback when the Escape key is pressed
    - `private var eventTap: CFMachPort?`
    - `private var runLoopSource: CFRunLoopSource?`
    - `private var hotkeyCode: UInt16 = KeyCode.rightOption.rawValue`
    - `private var isHotkeyHeld: Bool = false`
    - `private var hotkeyPressTime: Date?`
    - `private let longPressThreshold: TimeInterval = 0.3` — Long press detection threshold
  - Methods:
    - `func start(keyCode: UInt16)` — Create a CGEventTap and start event monitoring.
      - `self.hotkeyCode = keyCode`
      - Use `CGEvent.tapCreate(tap: .cgSessionEventTap, place: .headInsertEventTap, options: .listenOnly, eventsOfInterest: CGEventMask(1 << CGEventType.flagsChanged.rawValue) | CGEventMask(1 << CGEventType.keyDown.rawValue) | CGEventMask(1 << CGEventType.keyUp.rawValue), callback: eventCallback, userInfo: Unmanaged.passUnretained(self).toOpaque())`.
      - Use `.listenOnly` (monitors without consuming events. Accessibility permission is still required, but events are not consumed).
      - Add to the main RunLoop with `CFRunLoopAddSource(CFRunLoopGetMain(), runLoopSource, .commonModes)`.
      - `CGEvent.tapEnable(tap: eventTap, enable: true)`
    - `func stop()` — Disable and release the eventTap.
    - `func updateHotkey(_ keyCode: UInt16)` — Change the hotkey key code.
    - Event callback (static func as a C function pointer):
      - Detect press/release of the key matching `hotkeyCode` in `flagsChanged` events.
      - On press: Set `isHotkeyHeld = true`, `hotkeyPressTime = Date()`, call `onHotkeyDown?()` on the main thread.
      - On release: Set `isHotkeyHeld = false`, call `onHotkeyUp?()` on the main thread.
      - On `keyDown` with keyCode == `KeyCode.escape.rawValue`, call `onEscapePressed?()`.
  - Long press vs. short press determination logic:
    - Short press (toggle mode): Time from `hotkeyPressTime` to release is less than `longPressThreshold`.
    - Long press (hold mode): Time is equal to or greater than `longPressThreshold`.
    - This determination is made on the `onHotkeyUp` side, and the caller (AppState) controls recording start/stop.
- **Dependencies:** Step 4.1
- **Verification:** `swift build` succeeds.
- **Complexity:** High
- **Risk:** High — CGEventTap requires Accessibility permission. If permission is not granted, `tapCreate` returns `nil`. Mitigation: If `tapCreate` returns `nil`, display an alert prompting the user to enable Accessibility permission.

**Step 4.3: Implement PermissionChecker**
- **Agent:** coding-agent
- **Location:** `Sources/VibingSpeech/Utilities/PermissionChecker.swift`
- **Action:** Create a utility for checking and requesting Accessibility and microphone permissions.
- **Details:**
  - Define `enum PermissionChecker`.
  - `static var isAccessibilityGranted: Bool` — Calls and returns `AXIsProcessTrusted()`.
  - `static func requestAccessibilityIfNeeded()` — If `AXIsProcessTrusted()` returns `false`, call `AXIsProcessTrustedWithOptions([kAXTrustedCheckOptionPrompt.takeUnretainedValue(): true] as CFDictionary)` to open the System Settings Accessibility pane.
  - `static func requestMicrophoneAccess() async -> Bool` — Calls `AVCaptureDevice.requestAccess(for: .audio)` and returns the result.
  - `static var isMicrophoneGranted: Bool` — `AVCaptureDevice.authorizationStatus(for: .audio) == .authorized`.
- **Dependencies:** Step 1.1
- **Verification:** `swift build` succeeds.
- **Complexity:** Low
- **Risk:** Low

**Step 4.4: Implement TextInsertionService**
- **Agent:** coding-agent
- **Location:** `Sources/VibingSpeech/TextInsertion/TextInsertionService.swift`
- **Action:** Create a service that inserts text into the active application via the clipboard.
- **Details:**
  - Define `enum TextInsertionService`.
  - `static func insertText(_ text: String)` method:
    1. Save the current clipboard contents: `let previousContents = NSPasteboard.general.pasteboardItems?.compactMap { ... }` (to restore later).
    2. `NSPasteboard.general.clearContents()`
    3. `NSPasteboard.general.setString(text, forType: .string)`
    4. Simulate Cmd+V:
       - `let source = CGEventSource(stateID: .hidSystemState)`
       - keyDown event: `CGEvent(keyboardEventSource: source, virtualKey: 9, keyDown: true)` (9 = 'v') with `.maskCommand` flag set.
       - keyUp event: Same with keyDown: false.
       - `event?.post(tap: .cgi)`
    5. Wait briefly (`DispatchQueue.main.asyncAfter(deadline: .now() + 0.1)`) then restore the previous clipboard contents. Restoration is optional — attempt it but ignore errors.
  - Note: `CGEvent.post` requires Accessibility permission.
- **Dependencies:** Step 4.1
- **Verification:** `swift build` succeeds. In a manual test, open a text editor and call this method to confirm that text is inserted.
- **Complexity:** Medium
- **Risk:** Medium — In some applications (e.g., Terminal), simulating Cmd+V may behave differently. Mitigation: This is the same constraint as the original Vibing and works in typical text input fields.

**Step 4.5: Phase Gate — Phase 4 Verification**
- **Agent:** review-agent
- **Action:** Verify that Phase 4 builds correctly and the basic hotkey mechanism functions.
- **Verification:**
  - `swift build -c release` completes with zero errors.
  - Manual test: With Accessibility permission granted, launch the app and press the Right Option key to confirm that logs are output to the console (temporarily add `print` statements).
- **Dependencies:** All steps in Phase 4

---

### Phase 5: UI (Main Window and Floating Overlay)
**Purpose:** Build a 3-tab main window equivalent to Vibing and a floating microphone overlay displayed during recording.

**Step 5.1: AppState — App-Wide State Management Object**
- **Agent:** coding-agent
- **Location:** `Sources/VibingSpeech/App/AppState.swift`
- **Action:** Create a central object that manages app-wide state and integrates all components.
- **Details:**
  - Define `@MainActor @Observable final class AppState`.
  - Held objects:
    - `let settings = SettingsStore()`
    - `let history = HistoryStore()`
    - `let hotwords = HotwordStore()`
    - `let audioCapture = AudioCaptureManager()`
    - `let transcriptionEngine = TranscriptionEngine()`
    - `let hotkeyManager = GlobalHotkeyManager()`
  - State properties:
    - `private(set) var recordingState: RecordingState = .idle`
    - `enum RecordingState { case idle, recording, transcribing }`
    - `private(set) var lastError: String?`
    - `private var hotkeyPressedAt: Date?`
    - `private var isToggleMode: Bool = false` — Short press toggle mode flag
  - Methods:
    - `func setup() async` — Initial setup:
      1. `PermissionChecker.requestAccessibilityIfNeeded()`
      2. `let micGranted = await PermissionChecker.requestMicrophoneAccess()`. If `false`, set message in `lastError`.
      3. `hotkeyManager.start(keyCode: KeyCode.rightOption.rawValue)` (pass the key code corresponding to settings.recordingHotkey)
      4. Set hotkey callbacks:
         - `hotkeyManager.onHotkeyDown = { [weak self] in self?.handleHotkeyDown() }`
         - `hotkeyManager.onHotkeyUp = { [weak self] in self?.handleHotkeyUp() }`
         - `hotkeyManager.onEscapePressed = { [weak self] in self?.handleEscapePressed() }`
      5. `try await transcriptionEngine.loadModel(settings.selectedModel)`
    - `private func handleHotkeyDown()`:
      - If `recordingState == .idle`: Set `hotkeyPressedAt = Date()`, call `startRecording()`.
      - If `recordingState == .recording && isToggleMode`: Call `stopRecordingAndTranscribe()` (stop when pressed again in toggle mode).
    - `private func handleHotkeyUp()`:
      - Guard: Return if `recordingState != .recording`.
      - If `isToggleMode` is true, return (up is ignored in toggle mode).
      - If elapsed time from `hotkeyPressedAt` is equal to or greater than `longPressThreshold (0.3s)`, call `stopRecordingAndTranscribe()` (hold mode complete).
      - Otherwise, set `isToggleMode = true` (short press → transition to toggle mode; next keyDown will stop).
    - `private func handleEscapePressed()`:
      - If `recordingState == .recording`, call `cancelRecording()`.
    - `private func startRecording()`:
      - `recordingState = .recording`
      - `isToggleMode = false`
      - `SoundFeedback.playStartSound(isEnabled: settings.soundFeedbackEnabled)`
      - `audioCapture.startRecording(microphoneID: settings.selectedMicrophoneID)`
    - `private func stopRecordingAndTranscribe()`:
      - `let audioSamples = audioCapture.stopRecording()`
      - `SoundFeedback.playStopSound(isEnabled: settings.soundFeedbackEnabled)`
      - `recordingState = .transcribing`
      - Asynchronous processing in a Task:
        - `let text = transcriptionEngine.transcribe(audio: audioSamples)`
        - If text is not empty:
          - `TextInsertionService.insertText(text)`
          - Create a `TranscriptionRecord` and add it with `history.add(record)`.
          - `history.pruneIfNeeded(retention: settings.historyRetention)`
        - `recordingState = .idle`
    - `private func cancelRecording()`:
      - `audioCapture.cancelRecording()`
      - `SoundFeedback.playErrorSound(isEnabled: settings.soundFeedbackEnabled)`
      - `recordingState = .idle`
      - `isToggleMode = false`
    - `func switchModel(_ variant: ASRModelVariant) async throws`:
      - `settings.selectedModel = variant`
      - `try await transcriptionEngine.loadModel(variant)`
- **Dependencies:** Steps 2.4–2.6, 3.1–3.3, 4.1–4.4
- **Verification:** `swift build` succeeds.
- **Complexity:** High
- **Risk:** Medium — State transition timing issues. Mitigation: All state changes are made on `@MainActor` to prevent race conditions.

**Step 5.2: RecordingOverlayPanel — Floating Microphone Icon**
- **Agent:** coding-agent
- **Location:** `Sources/VibingSpeech/Views/Overlay/RecordingOverlayPanel.swift`
- **Action:** Create a floating microphone icon overlay displayed on screen during recording.
- **Details:**
  - Define `class RecordingOverlayPanel: NSPanel`.
  - Initialization:
    - `super.init(contentRect: NSRect(x: 0, y: 0, width: 80, height: 80), styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)`
    - `self.level = .floating` — Always on top.
    - `self.isOpaque = false`
    - `self.backgroundColor = .clear`
    - `self.hasShadow = true`
    - `self.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]` — Visible on all desktops and in full-screen mode.
    - `self.isMovableByWindowBackground = true` — Draggable.
    - `self.ignoresMouseEvents = false` (to enable dragging)
  - SwiftUI content:
    - Embed a SwiftUI view using `NSHostingView`.
    - `RecordingOverlayView` SwiftUI View:
      - Circular background (60pt diameter, semi-transparent white/dark gray with `BlurEffect`)
      - SF Symbol `mic.fill` centered (24pt)
      - During recording, a pulse animation (`.scaleEffect` and `.opacity` varied with `withAnimation(.easeInOut(duration: 0.8).repeatForever(autoreverses: true))`)
      - When state is `transcribing`, display a `ProgressView()` (spinner).
      - Receives `@Binding var recordingState: RecordingState`.
  - Position: Near the bottom-right of the screen (offset from `NSScreen.main` coordinates). Use `center()` or similar for placement.
  - Show/hide:
    - `func showOverlay()` — `self.orderFront(nil)` + animation.
    - `func hideOverlay()` — `self.orderOut(nil)`.
- **Dependencies:** Step 5.1
- **Verification:** `swift build` succeeds.
- **Complexity:** Medium
- **Risk:** Low

**Step 5.3: HomeView — Home Screen**
- **Agent:** coding-agent
- **Location:** `Sources/VibingSpeech/Views/MainWindow/HomeView.swift`
- **Action:** Create the SwiftUI view corresponding to Vibing's home screen.
- **Details:**
  - Define `struct HomeView: View`. Receives `@Bindable var appState: AppState`.
  - Layout (following Vibing's screenshot):
    - Header: App name "VibingSpeech — Just Speak It!" + recording readiness indicator ("Ready to record" green dot; "Loading model..." orange dot during model loading).
    - Statistics section:
      - Left: Pen icon + `appState.history.todayWordCount` "words" / "Words today"
      - Right: Memo icon + `appState.history.totalWordCount` "words" / "Total words"
    - Recording Hotkey section:
      - "Recording Hotkey" label + "Long press = hold mode · Short press = toggle mode" description
      - Key name displayed on the right (e.g., "⌥ Right Option")
    - Translation section: "Translation" + "Off" dropdown (currently fixed to Off and disabled, for future implementation)
    - Cancel Recording: "Cancel Recording" + "Esc" label
    - Text Polish: "Text Polish" + Toggle switch (`appState.settings.textPolishEnabled`)
    - Sound Feedback: "Sound Feedback" + Toggle switch (`appState.settings.soundFeedbackEnabled`)
    - Language: "Language" + Picker ("Auto", "English", "Japanese", "Chinese", etc.) bound to: `appState.settings.language`
    - Appearance: "Appearance" + Picker ("System", "Light", "Dark") bound to: `appState.settings.appearanceMode`
    - Model: "ASR Model" + Picker (ASRModelVariant.allCases) bound to: Calls `appState.switchModel(variant)` on selection.
    - Microphone: "Microphone" + Picker (available microphone list + "System Default") bound to: `appState.settings.selectedMicrophoneID`
  - Style: Use `.formStyle(.grouped)` for a macOS Settings screen-style layout.
- **Dependencies:** Step 5.1
- **Verification:** `swift build` succeeds.
- **Complexity:** Medium
- **Risk:** Low

**Step 5.4: HotwordsView — Hotword Management Screen**
- **Agent:** coding-agent
- **Location:** `Sources/VibingSpeech/Views/MainWindow/HotwordsView.swift`
- **Action:** Create the SwiftUI view corresponding to Vibing's hotword management screen.
- **Details:**
  - Define `struct HotwordsView: View`. Receives `@Bindable var appState: AppState`.
  - Layout:
    - Header: "Hotwords" title.
    - Description section: Icon + "Hotword Enhancement" + "Add proper nouns, terms, names to improve recognition accuracy."
    - Text input field: `TextField("Enter new hotword...", text: $newHotword)` + "Add" button.
    - Hotword list: Display with `ForEach(appState.hotwords.hotwords)`. Each row shows the text and a delete button (trash icon).
    - When the list is empty: Display "No manual hotwords" + "Add proper nouns in the field above" placeholder.
  - `@State private var newHotword: String = ""`
  - On "Add" button press: `appState.hotwords.add(newHotword)`, `newHotword = ""`.
- **Dependencies:** Step 5.1
- **Verification:** `swift build` succeeds.
- **Complexity:** Low
- **Risk:** Low

**Step 5.5: HistoryView — History Screen**
- **Agent:** coding-agent
- **Location:** `Sources/VibingSpeech/Views/MainWindow/HistoryView.swift`
- **Action:** Create the SwiftUI view corresponding to Vibing's history screen.
- **Details:**
  - Define `struct HistoryView: View`. Receives `@Bindable var appState: AppState`.
  - Layout:
    - Header: "History" title + "Clear" button at top-right (clear all history, with confirmation alert).
    - Save History section: Icon + "Save History" + "How long to keep dictation history on device?" + dropdown Picker (`appState.settings.historyRetention`)
    - Date-grouped list: Group records by date (`formattedDate`) and display with `Section(header: Text("Today"))`, etc.
    - Each record:
      - Left: `formattedTime` + full text + `wordCount` displayed below
      - Right: Delete button (trash icon)
    - Text supports multi-line display (`.lineLimit(nil)`).
  - Empty state: "No transcription history" placeholder.
- **Dependencies:** Step 5.1
- **Verification:** `swift build` succeeds.
- **Complexity:** Medium
- **Risk:** Low

**Step 5.6: MainContentView — Tab Container**
- **Agent:** coding-agent
- **Location:** `Sources/VibingSpeech/Views/MainWindow/MainContentView.swift`
- **Action:** Create the main content view containing the Home/Hotwords/History 3-tab layout.
- **Details:**
  - Define `struct MainContentView: View`. Receives `@Bindable var appState: AppState`.
  - Layout: Use `NavigationSplitView` (sidebar + detail).
    - Sidebar:
      - `List(selection: $selectedTab)`:
        - `Label("Home", systemImage: "house")` (tag: `.home`)
        - `Label("Hotwords", systemImage: "text.badge.plus")` (tag: `.hotwords`)
        - `Label("History", systemImage: "clock")` (tag: `.history`)
    - Detail:
      - `switch selectedTab`:
        - `.home`: `HomeView(appState: appState)`
        - `.hotwords`: `HotwordsView(appState: appState)`
        - `.history`: `HistoryView(appState: appState)`
  - `@State private var selectedTab: Tab = .home`
  - `enum Tab: Hashable { case home, hotwords, history }`
  - Window size: `.frame(minWidth: 700, minHeight: 500)`
  - Footer: "Powered by speech-swift" link text + version display.
  - Appearance mode support: Set `.preferredColorScheme(...)` based on `appState.settings.appearanceMode`.
- **Dependencies:** Steps 5.3, 5.4, 5.5
- **Verification:** `swift build` succeeds.
- **Complexity:** Medium
- **Risk:** Low

**Step 5.7: Integrate Main Window and Overlay into AppDelegate**
- **Agent:** coding-agent
- **Location:** `Sources/VibingSpeech/App/AppDelegate.swift` (modify existing file)
- **Action:** Add main window display logic and floating overlay control to AppDelegate.
- **Details:**
  - Add properties to AppDelegate:
    - `private var mainWindow: NSWindow?`
    - `private var overlayPanel: RecordingOverlayPanel?`
    - `let appState = AppState()`
  - Inside `applicationDidFinishLaunching`:
    - `ArchitectureCheck.ensureAppleSilicon()` (existing)
    - Setup `appState`: `Task { await appState.setup() }`
    - Create `overlayPanel = RecordingOverlayPanel()`.
    - Set up monitoring for `recordingState` — show overlay when `.recording` / `.transcribing`, hide when `.idle`. Use the Observation framework's `withObservationTracking` or Combine's `sink`. The simplest approach is to add an `onRecordingStateChanged` callback to AppState that AppDelegate sets.
  - "Show Window" menu action:
    - If `mainWindow` is `nil`, create an `NSWindow` and set `contentView` to `NSHostingView(rootView: MainContentView(appState: appState))`. Window title: "VibingSpeech".
    - `mainWindow?.makeKeyAndOrderFront(nil)`
    - `NSApp.activate(ignoringOtherApps: true)`
  - Overlay control:
    - When `appState.recordingState` becomes `.recording`, call `overlayPanel?.showOverlay()`
    - When `.transcribing`, switch the overlay to a "processing" display (change animation)
    - When `.idle`, call `overlayPanel?.hideOverlay()`
- **Dependencies:** Steps 5.1, 5.2, 5.6
- **Verification:** `swift build` succeeds. On app launch, a microphone icon appears in the menu bar, and clicking "Show Window" displays the main screen.
- **Complexity:** High
- **Risk:** Medium — NSWindow and SwiftUI integration can make lifecycle management complex. Mitigation: Set `isReleasedWhenClosed = false` on the window to support re-display.

**Step 5.8: Phase Gate — Phase 5 Verification**
- **Agent:** review-agent
- **Action:** Verify that Phase 5 builds correctly and the UI is displayed.
- **Verification:**
  - `swift build -c release` completes with zero errors.
  - Manual test:
    - App launch displays a microphone icon in the menu bar.
    - "Show Window" displays the main screen, and Home/Hotwords/History tabs are switchable.
    - All setting items on the Home screen are displayed and operable.
    - Adding and deleting hotwords works.
- **Dependencies:** All steps in Phase 5

---

### Phase 6: E2E Integration — Recording → Transcription → Text Insertion Flow
**Purpose:** Integrate all components so that the complete flow of global hotkey → recording → transcription → text insertion works.

**Step 6.1: Finalize AppState Setup**
- **Agent:** coding-agent
- **Location:** `Sources/VibingSpeech/App/AppState.swift` (modify existing file)
- **Action:** Complete implementation of the `setup()` method and finalize the recording → transcription → insertion flow integration.
- **Details:**
  - Final checks in `setup()`:
    - If Accessibility permission is not granted, set a user-friendly error message in `lastError` when `hotkeyManager.start()` fails.
    - If model loading fails, also set a message in `lastError` and display it in the UI.
  - In `stopRecordingAndTranscribe()`:
    - If Text Polish is enabled, apply lightweight post-processing to the transcribed text:
      - Normalize consecutive spaces to a single space.
      - Capitalize the first letter of a line (for English text).
      - However, Qwen3-ASR already outputs fairly clean text, so keep processing minimal.
    - Confirm the timing of `history.pruneIfNeeded(retention: settings.historyRetention)` call.
  - On model switch (`switchModel`):
    - If a model switch is attempted during recording, ignore it (return if `recordingState != .idle`).
    - Call `unloadModel()` on the old model to free memory before loading the new model.
  - Error handling:
    - Handle cases where `transcriptionEngine.transcribe` might throw (empty string return for nil model is already implemented).
    - Add try-catch for `audioCapture.startRecording` in case AVAudioEngine fails to start. On failure, set `recordingState = .idle` and assign a message to `lastError`.
- **Dependencies:** Steps 5.1, 5.7
- **Verification:** `swift build` succeeds.
- **Complexity:** Medium
- **Risk:** Low

**Step 6.2: Phase Gate — Phase 6 Verification (E2E Test)**
- **Agent:** review-agent
- **Action:** Verify that the complete E2E flow works.
- **Verification:**
  - `swift build -c release` completes with zero errors.
  - Manual E2E test:
    1. Launch the app with `make build && make run`.
    2. Grant Accessibility permission.
    3. Model is automatically downloaded and loading completes (Home screen shows "Ready to record").
    4. Open a text editor (e.g., TextEdit) and give it focus.
    5. Long-press Right Option while speaking → release to start transcription → result text is inserted into the text editor.
    6. Short-press Right Option → toggle mode starts → press again → transcription → text insertion.
    7. Press Esc during recording → recording is cancelled, no text is inserted.
    8. Transcription results appear in the history screen.
    9. Add hotwords and verify behavior.
    10. Switch the model to 1.7B in settings → transcription still works.
    11. Floating microphone icon appears during recording and disappears after completion.
- **Dependencies:** All steps in Phase 6

---

### Phase 7: Documentation and Release Preparation
**Purpose:** Prepare the README, LICENSE, and build instructions for GitHub publication.

**Step 7.1: Create LICENSE File**
- **Agent:** devops-agent
- **Location:** `VibingSpeech/LICENSE`
- **Action:** Create an MIT license file.
- **Details:** Standard MIT license text. Copyright year: 2026. Author name is a placeholder `[Your Name]` for the user to replace with their own name.
- **Dependencies:** None
- **Verification:** File exists and contains "MIT License".
- **Complexity:** Low
- **Risk:** Low

**Step 7.2: Create README.md**
- **Agent:** documentation-agent
- **Location:** `VibingSpeech/README.md`
- **Action:** Create a README describing the project overview, features, build instructions, and usage.
- **Details:**
  - Section structure:
    - **VibingSpeech** — Title + one-line description
    - **Features** — Key features list (global hotkey, Qwen3-ASR, model selection, hotwords, history, floating overlay, 52 language support, fully on-device)
    - **Requirements** — macOS 14+, Apple Silicon (M1 or later), Xcode 15+ (Command Line Tools), Swift 5.9+
    - **Build & Run** — Steps: `git clone`, `cd VibingSpeech`, `make build`, `make run`. Explanation of first-launch model download.
    - **Permissions** — Instructions for configuring Accessibility (for global hotkey) and Microphone permissions.
    - **How to Use** — Hotkey operation instructions (long press/toggle/Esc).
    - **Model Selection** — Differences between 0.6B (8-bit) and 1.7B (4-bit), memory usage, approximate accuracy.
    - **Configuration** — Explanation of each setting item.
    - **Architecture** — Brief explanation of directory structure.
    - **Credits** — Credits to speech-swift (Apache 2.0), Qwen3-ASR (Alibaba).
    - **License** — MIT
  - Language: English (for international publication).
- **Dependencies:** Step 7.1
- **Verification:** File exists and renders correctly as markdown.
- **Complexity:** Low
- **Risk:** Low

**Step 7.3: Create .gitignore**
- **Agent:** devops-agent
- **Location:** `VibingSpeech/.gitignore`
- **Action:** Create a .gitignore for a Swift / SPM project.
- **Details:**
  - Patterns to include: `.build/`, `.swiftpm/`, `*.xcodeproj/`, `xcuserdata/`, `DerivedData/`, `.DS_Store`, `Thumbs.db`.
  - `Package.resolved` is **not** included in .gitignore (included in the repository for reproducibility).
- **Dependencies:** None
- **Verification:** File exists.
- **Complexity:** Low
- **Risk:** Low

**Step 7.4: Phase Gate — Phase 7 Verification**
- **Agent:** review-agent
- **Action:** Final check for release preparation.
- **Verification:**
  - `swift build -c release` completes with zero errors.
  - Following the `README.md` instructions, the `git clone` → `make build` → `make run` flow completes successfully.
  - LICENSE file contains the correct MIT text.
  - .gitignore is properly configured.
  - `git init && git add . && git status` shows no build artifacts included.
- **Dependencies:** All steps in Phase 7

---

## Risks and Mitigations

| Risk | Severity | Mitigation |
|---|---|---|
| `Qwen3ASRModel.fromPretrained(modelId:)` API has changed | High | Verified against the latest source of speech-swift v0.0.9. Matches HuggingFace Usage documentation. If compile errors occur, try `loadFromHub()`. (Step 3.2) |
| CGEventTap returns nil without Accessibility permission | Medium | Request permission with `PermissionChecker.requestAccessibilityIfNeeded()`. Also display permission status in the UI. (Step 4.3) |
| AVAudioEngine is unstable with Bluetooth microphones | Medium | Pass `nil` as the format to installTap and resample using AVAudioConverter. (Step 3.1) |
| speech-swift Metal shader library missing error | Medium | Include `xcodebuild -downloadComponent MetalToolchain` troubleshooting in README. Normally auto-built as an SPM dependency. (Step 7.2) |
| Initial model download takes a long time (0.6B: ~1GB, 1.7B: ~2.1GB) | Low | Show a loading indicator and size display in the UI. (Steps 5.3, 3.2) |
| Distribution without App Sandbox | Low | Gatekeeper warnings will appear without Notarization. Include `xattr -cr` command in README. (Step 7.2) |

## Success Criteria

1. `swift build -c release` completes with zero errors and 5 or fewer warnings.
2. The Right Option key's long press/short press initiates/stops voice recording while using other applications.
3. A floating microphone icon is displayed on screen during recording.
4. Qwen3-ASR-0.6B (8-bit) correctly transcribes Japanese/English speech.
5. Switching to Qwen3-ASR-1.7B (4-bit) and performing transcription works.
6. The transcription result is pasted at the cursor position of the active application.
7. Pressing Esc cancels recording and no text is inserted.
8. Adding and deleting hotwords works from the UI and is persisted.
9. Transcription history is displayed on screen and is persisted.
10. Users can build and run following the `git clone` → `make build` → `make run` procedure. The final deliverable is `VibingSpeech.app`.
11. On Intel Macs, an error message is displayed and the app terminates.