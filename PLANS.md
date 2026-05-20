# VibingSpeech — Final Implementation Plan (Xcode-First Zero Build)

## 0. Status of This Document

- This document is the single authoritative implementation plan for VibingSpeech.
- It supersedes any previous plan.
- The repository is built from zero. The only pre-existing artifact is `docs/UI_connection.png` (a composite of the screenshots referenced below).
- Where the UI screenshots conflict with this document, **this document wins**, because the screenshots are older than the current plan.
- Where this document is silent on a visual detail, the screenshots are the visual reference of record.

## 1. Repository Starting State

At the time work begins, the repository contains only:

```
VibingSpeech/
└── docs/
    └── UI_connection.png   ← composite of the screenshots in section 9 (only visual reference)
```

Everything else is created from scratch.

Initial housekeeping, before any Xcode work:

1. Initialize Git at the repository root (if not already).
2. Create `.gitignore`, `README.md`, `CHANGELOG.md`, and `LICENSE` (MIT, author name placeholder).
3. Place this document at `PLANS.md`.
4. Leave `docs/UI_connection.png` untouched.

The `.gitignore` must include `.DS_Store`, `Thumbs.db`, `build/`, `DerivedData/`, `*.xcuserdata/`, `.swiftpm/`, and `*.xcworkspace/xcuserdata/`.

## 2. Development Environment

- Mac mini M4 (Apple Silicon, 24 GB unified memory, macOS 26 Tahoe or newer)
- Text encoding: UTF-8
- GPU acceleration: Apple Silicon Metal only (no CUDA path)
- Swift 6.3 or newer
- Xcode 26 or newer
- macOS deployment target: macOS 26 or newer
- `.xcodeproj` is the primary project format
- Xcode MCP server is the primary build/test/inspection tool; `xcodebuild` is a fallback only

## 3. Engineering Principles

- The user does not write code. Explanations must be simple and clear.
- For each problem, present exactly one recommended implementation; do not enumerate alternatives.
- After writing code, debug it, then refactor for maintainability.
- Prefer well-known, actively maintained open-source libraries. Avoid abandoned or obscure packages.
- If any dependency would force downgrading Swift, Xcode, or the macOS target below the requirements in section 2, stop and warn the user before proceeding.

## 4. High-Level Goals

Build VibingSpeech as an Apple-native macOS app that runs entirely on-device:

- Menu-bar resident, no Dock icon.
- Global hotkey triggers voice capture from any frontmost application.
- A floating overlay panel shows recording and transcription state.
- Qwen3-ASR transforms speech into text using MLX on Apple Silicon.
- Optional local Qwen3.5 text processing can refine the ASR output.
- Hotwords, transcription history, and user settings are stored locally.
- The result is pasted into the active application via a synthesized Cmd+V.
- App Sandbox is intentionally disabled. Code signing is local/ad-hoc for personal use; Developer ID and notarization are out of scope until a valid signing identity exists.
- Intel Macs are rejected at launch.

## 5. Build and Project Requirements

- Create a new Xcode project: `VibingSpeech.xcodeproj`.
- App target: macOS app, SwiftUI lifecycle, Swift 6.3, arm64 only.
- App Sandbox: off. No `com.apple.security.app-sandbox` entitlement. Do not invent unrelated entitlements.
- Hardened Runtime: enabled for archive builds, even for ad-hoc signing.
- Bundle identifier: `com.shuichi.VibingSpeech`.
- `Info.plist` keys (minimum):
  - `LSUIElement = YES` (no Dock icon, menu-bar accessory behavior)
  - `NSMicrophoneUsageDescription` with a clear, user-facing reason
  - `LSMinimumSystemVersion = 26.0`
- Signing for development and personal use: local/ad-hoc.
- Release builds and archives are produced through Xcode only. No SwiftPM-only release path.
- Xcode MCP server is used for project inspection, scheme management, builds, tests, diagnostics, and archive verification. `xcodebuild` is used only when MCP cannot perform the required action.

## 6. Project Structure

```
/Users/shuichi/Documents/GitHub/VibingSpeech/
├── .gitignore
├── README.md
├── CHANGELOG.md
├── LICENSE
├── docs/
│   ├── UI_connection.png
│   └── NewPlan.md
├── VibingSpeech.xcodeproj
└── VibingSpeech/
    ├── App/              # @main entry, AppDelegate-like coordinator, menu bar item
    ├── Core/             # enums, shared protocols, small utilities
    ├── Models/           # value-type domain models
    ├── Services/         # Hotkey, Microphone, ASR, TextProcessing, TextInsertion, Permission, Sound
    ├── Persistence/      # SettingsStore, HistoryRepository, HotwordRepository
    ├── Views/            # SwiftUI views, NSPanel-backed recording overlay
    ├── Resources/        # Assets, Info.plist, sounds
    └── Support/          # extensions, logging, Result helpers
VibingSpeechTests/
VibingSpeechUITests/
```

Do not create additional top-level scaffolding unless the build system demands it.

## 7. Dependencies

All dependencies are added through Xcode's Swift Package Dependencies UI. There is no standalone `Package.swift` for the app target.

- `speech-swift`
  - Preferred exact version: `0.0.15` if its API supports the required calls used by `ASRService`.
  - Fallback: exact `0.0.9`, with the reason recorded in `CHANGELOG.md` and a note added at the bottom of this document.
- `mlx-swift-lm`: exact `3.31.3`
- `swift-huggingface`: `0.9.0` or a newer compatible release
- `swift-transformers`: `1.3.0` or a newer compatible release

Linked products on the app target: `Qwen3ASR`, `AudioCommon`, `MLXLLM`, `MLXLMCommon`, `MLXHuggingFace`, `HuggingFace`, `Tokenizers`.

The MLX Metal library (`mlx.metallib`) must be bundled correctly by Xcode's package integration. A manual copy step is not part of the release path. If Xcode integration fails to stage the metallib, introduce a documented workaround inside the Xcode build phases rather than reintroducing a Makefile.

## 8. Application Architecture

The app uses a service-oriented architecture with narrow ownership. UI state and service state are kept separate. Long-running model work never runs on the main actor.

- `AppCoordinator`: lifecycle, startup, permission flow, menu-bar actions, window presentation, recording phase orchestration.
- `HotkeyService`: `CGEventTap` setup, right/left modifier handling, Esc cancellation, tap recovery, Accessibility failure reporting.
- `MicrophoneRecorder`: per-session `AVAudioEngine`, input device selection, conversion to 16 kHz mono Float32, RMS level metering, serialized start/stop/cancel, session-generation token to discard stale tap callbacks.
- `ASRService`: Qwen3-ASR model loading, variant switching, transcription execution, detected-language reporting.
- `TextProcessingService`: optional Qwen3.5 load/unload, preset prompts, custom prompt support, `<think>…</think>` stripping, thinking-disabled generation where supported.
- `TextInsertionService`: pasteboard snapshot, simulated Cmd+V via `CGEvent`, safe clipboard restoration.
- `PermissionService`: microphone and Accessibility permission state, deep links to System Settings.
- `SoundService`: start/stop/cancel feedback sounds.
- `SettingsStore`: `UserDefaults`-backed user settings.
- `HistoryRepository`: atomic JSON persistence for transcription history.
- `HotwordRepository`: atomic JSON persistence for hotwords.

UI is SwiftUI; the recording overlay uses an AppKit `NSPanel` hosting SwiftUI content. UIKit/AppKit may be mixed wherever it produces cleaner native behavior than SwiftUI alone (for example, the overlay panel, the menu bar item, and the `CGEventTap`).

## 9. Visual Reference (from `docs/UI_connection.png`)

The composite contains the following screens. Reproduce them faithfully, with the corrections listed in section 9.4.

### 9.1 Sidebar (present on every screen)

- Three items, each with an SF Symbol and label:
  - Home (`house`)
  - Hotwords (`text.badge.plus` or equivalent)
  - History (`clock`)
- The selected item uses an accent-tinted rounded background.
- A sidebar toggle button sits at the top-right of the sidebar, next to the traffic-light controls.

### 9.2 Home

Header row:

- Left: window title `VibingSpeech`.
- Inside the main content, a large pill-shaped header reads `VibingSpeech — Just Speak It!` with a status indicator on the right:
  - Green dot + "Ready to record" when the model is loaded and Accessibility is granted.
  - Orange dot + "Hotkey setup required" when Accessibility is missing.
  - Orange dot + "Loading model…" while the ASR model is loading.

Stats row (single rounded card):

- Left: pencil glyph, `N words`, caption "Words today".
- Right: document glyph, `N words`, caption "Total words".

Settings card (grouped, with dividers):

- `Recording Hotkey` row. Right side is a popover-style picker with two options: `⌥ Right Option` (default, checked) and `⌃ Left Control`. Helper text below: "Long press = hold mode · Short press = toggle mode".
- `Cancel Recording` row. Right side shows the static label `Esc`.
- Accessibility warning block (only when Accessibility permission is missing):
  - Orange triangle icon and orange text: "Accessibility permission is required for the global hotkey. Enable it in System Settings, then retry setup."
  - Two buttons: `Open Accessibility Settings`, `Retry Hotkey Setup`.
- `Text Processing (LLM)` row with a toggle. When on:
  - A green dot + "Text processing ready" appears beneath it.
  - A `Preset` row exposes a popover picker with three items:
    - `Fix Typos` (default)
    - `Bullet Points`
    - `Custom`
  - A `Model` row displays the LLM model name as a static label (for example, `Qwen3-4B-Instruct-2507 (4-bit)`). This row is read-only.
  - When the `Custom` preset is selected, a text editor for the custom system prompt appears below the `Model` row.
- `Sound Feedback` row with a toggle.
- `Language` row with a popover picker. Options at minimum: `Auto` (default), `English`, `Japanese`, `Chinese`.
- `Appearance` row with a popover picker: `System` (default), `Light`, `Dark`.
- `ASR Model` row with a popover picker listing the three variants in section 10.1, each followed by its estimated download size in parentheses.
- `Microphone` row with a popover picker. The first item is always `System Default`, followed by every connected input device by name (for example, `US-2x2HR`, `BlackHole 2ch`, `外部マイク`).

### 9.3 Hotwords

- Page title: `Hotwords`.
- Top card: blue glyph + bold `Hotword Enhancement` + caption "Add proper nouns, terms, names to improve recognition accuracy."
- Input row: a `TextField` labeled `Enter new hotword…` on the left, and an `Add` button on the right. The `Add` button is disabled while the field is empty or contains only whitespace.
- Below the input:
  - If the list is empty: a centered `ContentUnavailableView` with a plus-list glyph, bold title `No manual hotwords`, and caption "Add proper nouns in the field above".
  - If the list is non-empty: a list of rows. Each row shows the hotword text on the left and a trash button on the right. Swipe-to-delete is also supported.

### 9.4 History

- Page title: `History` with a `Clear` button at the top-right that opens a destructive confirmation.
- Top card: bold `Save History` + caption "How long to keep dictation history on device?" + a popover picker on the right with the values from `HistoryRetention` in section 10.6. The screenshot shows `Forever` as the example.
- Below the card: records grouped by date with section headers like `Today`, `Yesterday`, and `yyyy/MM/dd` for older dates.
- Each record row:
  - Left: timestamp in `HH:mm`.
  - Middle: the final inserted text, then a small caption with the word count (`N words`).
  - Right: a trash button to delete the single record. A copy-to-clipboard affordance is also exposed (context menu and/or hover button).
  - When the record was processed by the LLM, an additional disclosure shows the original ASR text underneath the processed text.
- A search field is available at the top of the list area (added per the New Plan, even though the screenshot omits it).

### 9.5 Recording overlay (not in screenshots; behavior from New Plan)

- Backed by a borderless `NSPanel` with `collectionBehavior` set so it appears on all spaces and during full-screen.
- States:
  - Idle: hidden.
  - Recording: compact capsule with an animated waveform driven by the recorder's RMS level.
  - Transcribing: same capsule footprint, with a determinate or indeterminate progress indicator.
- The timer driving the waveform uses a main-actor-safe pattern. It must not produce any Swift 6 `Sendable` warnings.

### 9.6 Corrections versus the screenshots (New Plan wins)

- The screenshots show only two ASR variants in some shots. The current plan requires **three** ASR variants (see 10.1).
- The screenshots show `Forever` only in the history retention example. The full set of values is in 10.6, including `Never`, which suppresses history writes entirely.
- The screenshots do not show a search field on History. The plan includes one.
- The screenshots do not show the "original ASR text" disclosure for LLM-processed records. The plan includes one.
- The screenshots do not show a `Cancel` button next to ASR model rows during recording. The plan forbids switching the ASR model while recording or transcribing; the picker is simply disabled in those phases.

## 10. Public Types and Data

### 10.1 ASRModelVariant

A `String`-backed `CaseIterable` `Codable` enum with three cases:

| case | display name | HF model ID | est. size | est. memory |
|---|---|---|---|---|
| `qwen3_0_6b_8bit` | `Qwen3-ASR 0.6B (8-bit)` | `aufklarer/Qwen3-ASR-0.6B-MLX-8bit` | `~1.0 GB` | `~1.5 GB` |
| `qwen3_1_7b_4bit` | `Qwen3-ASR 1.7B (4-bit)` | `aufklarer/Qwen3-ASR-1.7B-MLX-4bit` | `~2.1 GB` | `~3.0 GB` |
| `qwen3_1_7b_8bit` | `Qwen3-ASR 1.7B (8-bit)` | `aufklarer/Qwen3-ASR-1.7B-MLX-8bit` | `~2.3 GB` | `~3.5 GB` |

Default: `qwen3_0_6b_8bit`.

### 10.2 TextProcessingPreset

Cases: `fixTypos`, `bulletPoints`, `custom`.

Each preset returns a system prompt parameterized by the detected language and the user's selected `LanguageMode`. The Qwen3.5 LLM identifier used by `TextProcessingService` is `mlx-community/Qwen3.5-4B-MLX-4bit`. The on-screen `Model` label in the Home view reflects this value.

The `custom` preset uses a user-supplied system prompt persisted in `SettingsStore`.

The service always strips any `<think>…</think>` blocks from generated output before returning text.

### 10.3 TranscriptionRecord

Fields: `id: UUID`, `finalText: String`, `originalASRText: String?`, `timestamp: Date`, `wordCount: Int`, `durationSeconds: Double`, `modelVariant: ASRModelVariant`, `wasProcessedByLLM: Bool`.

Word count rule: for whitespace-separated languages, count whitespace-delimited tokens; for CJK text (detected by Unicode script), count characters in `Letter` and `Other_Letter` categories. The exact rule is enforced by unit tests.

### 10.4 Hotword

Fields: `id: UUID`, `text: String` (trimmed, non-empty), `createdAt: Date`.

### 10.5 RecordingPhase

Cases: `idle`, `recording`, `transcribing`.

### 10.6 HistoryRetention

Cases: `forever`, `oneWeek`, `oneDay`, `never`. When `never`, history records are neither written to disk nor held in memory.

### 10.7 AppearanceMode

Cases: `system`, `light`, `dark`. Applied with `.preferredColorScheme`.

### 10.8 LanguageMode

Cases at minimum: `auto`, `english`, `japanese`, `chinese`. `auto` enables ASR language detection.

### 10.9 RecordingHotkey

Cases: `rightOption`, `leftControl`. Default: `rightOption`.

## 11. Core Behavior

### 11.1 Launch

- Check architecture. If not `arm64`, present a modal alert and terminate.
- Install the menu-bar item (`Show Window`, `Quit`).
- Begin asynchronous startup: load settings, repositories, then ASR model.
- Open the main window early enough that the model loading state is visible to the user.

### 11.2 Permissions

- Request microphone permission on first launch via `AVCaptureDevice.requestAccess(for: .audio)`.
- Check Accessibility with `AXIsProcessTrusted()` before starting the hotkey tap.
- If Accessibility is missing, render the Home view's warning block and disable the hotkey-dependent UI affordances. Provide `Open Accessibility Settings` (deep link to `x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility`) and `Retry Hotkey Setup`.

### 11.3 Hotkey

- Create a `CGEventTap` listening to `flagsChanged` for the configured modifier and to `keyDown` for `Esc`.
- Right Option: detected via the right-side modifier mask.
- Left Control: detected via the left-side modifier mask.
- Press semantics:
  - Long press (held ≥ 300 ms): enter hold mode on key-down, stop and transcribe on key-up.
  - Short press (< 300 ms on key-up): enter toggle mode. The next press of the same key stops and transcribes.
- Esc: cancels an active recording with no insertion.
- If the tap is invalidated by the system, attempt re-creation. If re-creation fails, surface the Accessibility warning state.

### 11.4 Audio Capture

- Create a fresh `AVAudioEngine` per session.
- Serialize start/stop/cancel through a dedicated dispatch queue or actor.
- Use a session-generation token; tap callbacks for stale sessions are discarded.
- Install the tap with the input node's native format. Convert to 16 kHz mono Float32 using `AVAudioConverter`.
- Compute RMS per buffer for the overlay's waveform.
- Before invoking ASR, enforce a minimum-samples guard to avoid known short-audio crashes inside the ASR pipeline.

### 11.5 Transcription

- Run on a background task (off the main actor).
- Pass the language hint corresponding to `LanguageMode`. `auto` uses the model's detection.
- Return trimmed text and the detected language.
- If the ASR model is not loaded, refuse to start recording.
- Refuse to switch the ASR model while the phase is `recording` or `transcribing`.

### 11.6 Hotwords

- Persist hotwords as a JSON array.
- Wire hotwords into ASR only if `speech-swift`'s selected API exposes a prompt-bias or context parameter. If not, persist the dictionary but do not claim it affects recognition; the UI text in section 9.3 must remain accurate, but the absence of bias support must be noted in `CHANGELOG.md`.

### 11.7 Optional Text Processing

- Disabled by default. The toggle on Home turns the feature on or off.
- When turned on:
  - Begin loading `mlx-community/Qwen3.5-4B-MLX-4bit`.
  - Show the green "Text processing ready" indicator once loaded.
- When turned off: unload the model and free memory.
- Guard against on/off race conditions while loading is in flight using a load-generation token.
- If processing fails for a given transcription, paste the raw ASR text and surface a non-blocking error.
- The Preset picker and the optional custom prompt editor only appear when the feature is on.

### 11.8 Text Insertion

- Snapshot the current pasteboard (`NSPasteboardItem` data for known types).
- Replace the pasteboard contents with the final text.
- Post a synthesized Cmd+V (`CGEvent` keyDown + keyUp on key code 9 with `.maskCommand`).
- After a short delay, restore the snapshot **only if** the current pasteboard still contains the value we placed; otherwise, leave the user's new clipboard content alone.

### 11.9 History

- If `HistoryRetention` is `never`, do not create records and do not write the file. The in-memory list is also kept empty.
- Otherwise, prepend new records and persist atomically (write to a temp file, then `replaceItem`).
- `pruneIfNeeded` enforces `oneDay` and `oneWeek` retention.
- If the JSON file fails to decode, preserve the corrupted file (rename it with a timestamp suffix) and start with an empty in-memory list. Do not overwrite the user's data.

## 12. GUI Implementation Notes

- Use SwiftUI for all main views and the sidebar. AppKit is used where it produces better native behavior: the `NSStatusItem` menu bar entry, the `NSPanel` overlay, the global `CGEventTap`, and the synthesized Cmd+V.
- Use grouped rows with system materials and rounded backgrounds to match the screenshots.
- Use SF Symbols. Use semantic colors (`.accentColor`, `.secondary`, `.orange` for the Accessibility warning, `.green` for ready indicators).
- Use `ContentUnavailableView` for empty Hotwords and empty History.
- Bind `Appearance` to `.preferredColorScheme` on the root scene.
- The main window's minimum size is approximately 760 × 560 points.
- Sidebar is `NavigationSplitView` with a `.sidebar` list. Selection persists across launches.
- The window is created on demand from the menu-bar item and survives close (set `isReleasedWhenClosed = false`).

## 13. No-Sandbox and Signing Conditions

- `App Sandbox`: disabled (justified by `CGEventTap`, cross-app Cmd+V, and Accessibility-controlled event posting).
- `Hardened Runtime`: enabled for archive builds.
- Required `Info.plist` keys are listed in section 5.
- Code signing during development and personal use: local/ad-hoc.
- Developer ID signing and notarization are out of scope until a valid identity is installed; when they become available, add them via Xcode without changing the entitlements profile.

## 14. Testing and Verification

All builds happen through the Xcode MCP server against the active scheme, unless that path is unavailable.

Minimum automated tests:

- `ASRModelVariant` metadata (display name, HF ID, size strings).
- Text processing preset prompt generation for each language combination.
- Language normalization (e.g., `auto`, `en`, `ja`, `zh`).
- Word counting for both CJK and whitespace-separated text.
- `SettingsStore` defaults and round-trip persistence.
- `HistoryRetention` behavior, including `never` writing zero records.
- Hotword trimming, duplicate rejection, and ordering.
- Corrupted-JSON load preserves the file and yields an empty in-memory state.
- Pasteboard snapshot and conditional restore.
- Short-audio guard rejects buffers below the threshold.

Manual integration checks:

- First-launch flows for Microphone and Accessibility permissions.
- Hotkey hold mode and toggle mode from another app.
- Esc cancels with no insertion.
- Pasting into TextEdit, Notes, Safari address bar, and a terminal.
- ASR model switching only when idle.
- Text processing on/off with the model load/unload working correctly.
- Hotwords add, delete, empty state.
- History grouping, search, copy, delete, clear, and `Never` retention.
- Overlay visibility and animations across spaces and full-screen.

Release and archive checks:

- Release build succeeds through Xcode.
- Archive succeeds and the exported app launches.
- `codesign -d --entitlements - <app>` confirms `com.apple.security.app-sandbox` is absent.
- Gatekeeper behavior (with ad-hoc signing) is documented in `README.md`.

## 15. Acceptance Criteria

- The final deliverable is `VibingSpeech.app`, built and archived through Xcode.
- Builds successfully with Swift 6.3+ and Xcode 26+.
- No SwiftPM-only release path is used.
- No CUDA code paths exist.
- No cloud communication occurs except for first-run model downloads from HuggingFace.
- No user audio or transcribed text is uploaded anywhere.
- Global hotkey recording works from other applications.
- Transcription results are pasted into the frontmost application via simulated Cmd+V.
- Esc cancels recording without inserting text.
- The overlay accurately reflects `idle`, `recording`, and `transcribing`.
- Hotwords and history persist locally and survive relaunch.
- `HistoryRetention = never` writes no transcription records.
- Text processing is optional and entirely local.
- App Sandbox is disabled, and entitlements stay minimal.
- Intel Macs are rejected at launch with a clear alert.

## 16. Implementation Order

1. Create `PLANS.md` (this document), `.gitignore`, `README.md`, `CHANGELOG.md`, `LICENSE`.
2. Re-examine `docs/UI_connection.png` immediately before UI work. Where it disagrees with this document, follow this document.
3. Create `VibingSpeech.xcodeproj` (macOS app, SwiftUI, Swift 6.3, arm64-only, Sandbox off, Hardened Runtime on).
4. Add Swift Package Dependencies through Xcode (`speech-swift`, `mlx-swift-lm`, `swift-huggingface`, `swift-transformers`) and link the products listed in section 7.
5. Configure `Info.plist`, signing settings, and the no-sandbox configuration.
6. Build an empty menu-bar app through the Xcode MCP server and confirm: no Dock icon, menu-bar item present, Quit works.
7. Implement Core models and Persistence stores with unit tests.
8. Implement `PermissionService`, `HotkeyService`, and `TextInsertionService`.
9. Implement `MicrophoneRecorder` (16 kHz mono Float32, session token, RMS metering).
10. Implement `ASRService` (load, switch, transcribe).
11. Implement `TextProcessingService` (optional, default off).
12. Implement `AppCoordinator` and the recording phase flow.
13. Implement the main SwiftUI window (Home, Hotwords, History) per section 9.
14. Implement the `NSPanel` recording overlay with a main-actor-safe timer.
15. Run all Xcode builds and tests; target zero warnings, including no `Sendable` warnings.
16. Run the manual integration checks in section 14.
17. Produce and verify a personal-use Xcode archive; confirm sandbox-free with `codesign`.

## 17. Assumptions and Notes

- The screenshots in `docs/UI_connection.png` are older than this document. Visual details not contradicted here should be reproduced faithfully; contradictions follow this document.
- The on-screen label `Qwen3-4B-Instruct-2507 (4-bit)` appearing in one Home screenshot is illustrative. The actual model used by `TextProcessingService` is `mlx-community/Qwen3.5-4B-MLX-4bit`. The Home view must display whatever model identifier the service is configured to load, so the label stays accurate over time.
- If `speech-swift 0.0.15` does not expose the required APIs, fall back to `0.0.9` and append a "Dependency notes" subsection at the end of this file recording the reason, the date, and the specific API mismatch observed.
