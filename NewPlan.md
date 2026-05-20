# VibingSpeech Xcode-First Rewrite Plan

## Summary

- Rewrite VibingSpeech from scratch as an Apple-default native Xcode macOS app.
- Create `VibingSpeech.xcodeproj`, `VibingSpeech/`, and test targets as the new build authority.
- Keep the existing SwiftPM implementation only as legacy reference during the rewrite; do not link or refactor the current `Sources/` tree into the new app.
- Preserve the current feature set: menu bar app, no Dock icon, global hotkey, recording overlay, Qwen3-ASR transcription, optional local Qwen3.5 text processing, hotwords, history, settings, and local-only privacy.
- Target personal-use app archive creation through Xcode on Apple Silicon with App Sandbox disabled.

## Current Code Inventory

- Current repo shape:
  - SwiftPM executable app using `Package.swift`.
  - No `.xcodeproj` or `.xcworkspace` currently exists.
  - 24 Swift source files under `Sources/VibingSpeech`.
  - `Makefile` manually builds a SwiftPM binary, creates `VibingSpeech.app`, writes `Info.plist`, and copies `mlx.metallib`.
- Current baseline:
  - `swift build` succeeds.
  - One Swift 6.3 concurrency warning exists in `RecordingOverlayPanel.swift` around capturing `Timer?` in a `@Sendable` closure.
- Current app architecture:
  - `AppState` centralizes settings, history, hotwords, audio capture, ASR, text processing, hotkey state, and text insertion.
  - `AppDelegate` owns the menu bar item, main window, overlay panel, and startup setup.
  - SwiftUI UI is a `NavigationSplitView` with Home, Hotwords, and History.
  - Recording overlay is an AppKit `NSPanel` with SwiftUI waveform content.
- Current models:
  - ASR models:
    - `aufklarer/Qwen3-ASR-0.6B-MLX-8bit`
    - `aufklarer/Qwen3-ASR-1.7B-MLX-4bit`
    - `aufklarer/Qwen3-ASR-1.7B-MLX-8bit`
  - Text processing model:
    - `mlx-community/Qwen3.5-4B-MLX-4bit`
- Current libraries:
  - `speech-swift`
  - `mlx-swift-lm`
  - `swift-huggingface`
  - `swift-transformers`
  - SwiftUI, AppKit, AVFoundation, CoreAudio, CoreGraphics, Observation
- Current UI reference:
  - `docs/README_PNG/UI_main.png`
  - `docs/README_PNG/UI_Hotwords.png`
  - `docs/README_PNG/UI_History.png`

## Build And Project Requirements

- Use Swift 6.3 or higher.
- Use Xcode 26 or higher and macOS 26 or higher.
- Treat `.xcodeproj` as the primary project format.
- Use `Package.swift` only as a dependency manifest/reference for libraries incorporated into the Xcode project.
- For all Xcode project-related work, open the target project in Xcode first and use the `xcode` MCP server for:
  - project structure inspection
  - schemes
  - targets
  - build settings
  - builds
  - tests
  - diagnostics
  - archive verification
- Fall back to command-line `xcodebuild` only when:
  - no project is open in Xcode,
  - the MCP capability is unavailable,
  - or a specific diagnostic cannot be retrieved through MCP.
- Do not use SwiftPM-only release builds for the final app.
- Build Release and archive through Xcode against `VibingSpeech.xcodeproj`.
- Warn and stop if any dependency requires downgrading Swift, Xcode, or the macOS target below the stated requirements.

## New Project Structure

Create a new Apple-default Xcode app layout:

```text
VibingSpeech.xcodeproj
VibingSpeech/
  App/
  Core/
  Models/
  Services/
  Persistence/
  Views/
  Resources/
  Support/
VibingSpeechTests/
VibingSpeechUITests/
```

The existing `Sources/` tree remains untouched as legacy reference until the new app is verified.

Do not create broad scaffolding outside the new Xcode app structure unless the build system requires it.

## Dependency Plan

- Add Swift Package Dependencies through Xcode.
- Preferred dependency pins:
  - `speech-swift`: exact `0.0.15` if it resolves with the required APIs.
  - If `0.0.15` breaks the required APIs, use the currently proven `0.0.9` and document the compatibility reason in the project notes.
  - `mlx-swift-lm`: exact `3.31.3`.
  - `swift-huggingface`: `0.9.0` or newer compatible release.
  - `swift-transformers`: `1.3.0` or newer compatible release.
- Required products:
  - `Qwen3ASR`
  - `AudioCommon`
  - `MLXLLM`
  - `MLXLMCommon`
  - `MLXHuggingFace`
  - `HuggingFace`
  - `Tokenizers`
- Verify that MLX Metal resources are bundled correctly by the Xcode app build.
- Do not keep the current Makefile-based `mlx.metallib` copy step as the release path unless Xcode package integration cannot stage it correctly and the workaround is documented.

## Application Architecture

Use a service-oriented rewrite with narrow ownership:

- `AppCoordinator`
  - Owns app lifecycle, startup, permission flow, menu bar actions, window presentation, recording phase, and high-level orchestration.
- `HotkeyService`
  - Owns `CGEventTap`, right/left modifier key handling, Esc cancellation, tap recovery, and Accessibility failure reporting.
- `MicrophoneRecorder`
  - Owns `AVAudioEngine`, input device selection, 16 kHz mono Float32 conversion, audio level metering, and session-safe start/stop/cancel.
- `ASRService`
  - Owns Qwen3-ASR model loading, selected model switching, transcription execution, and detected-language return values.
- `TextProcessingService`
  - Owns optional Qwen3.5 loading, unloading, generation settings, preset prompts, custom prompt processing, and `<think>` tag cleanup.
- `TextInsertionService`
  - Owns pasteboard snapshot, text insertion through Cmd+V, and safe clipboard restoration.
- `PermissionService`
  - Owns microphone permission, Accessibility permission, and System Settings deep links.
- `SoundService`
  - Owns start, stop, and cancel sound feedback.
- `SettingsStore`
  - Owns UserDefaults-backed user settings.
- `HistoryRepository`
  - Owns atomic JSON history persistence.
- `HotwordRepository`
  - Owns atomic JSON hotword persistence.

Keep UI state separate from service state where possible. Long-running model work must not run on the main actor.

## Public Types And Data

Define these core types in the new app:

- `ASRModelVariant`
  - Cases:
    - `qwen3_0_6b_8bit`
    - `qwen3_1_7b_4bit`
    - `qwen3_1_7b_8bit`
  - Metadata:
    - display name
    - HuggingFace model ID
    - estimated download size
    - estimated memory
- `TextProcessingPreset`
  - Cases:
    - `fixTypos`
    - `bulletPoints`
    - `custom`
  - Provides the system prompt for detected language and ASR language.
- `TranscriptionRecord`
  - Stores ID, final text, optional original ASR text, timestamp, word count, duration, and ASR model.
- `Hotword`
  - Stores ID, text, and creation date.
- `RecordingPhase`
  - Cases:
    - `idle`
    - `recording`
    - `transcribing`
- `RecordingHotkey`
  - Cases:
    - right Option
    - left Control
- `HistoryRetention`
  - Cases:
    - forever
    - one week
    - one day
    - never
- `AppearanceMode`
  - Cases:
    - system
    - light
    - dark
- `LanguageMode`
  - At minimum:
    - auto
    - English
    - Japanese
    - Chinese

## Core Behavior

- App launch:
  - Check Apple Silicon at startup.
  - If not arm64, show a blocking alert and terminate.
  - Show the main settings window early enough that model download/loading status is visible.
  - Create a menu bar item with short actions:
    - Show Window
    - Quit
- No Dock icon:
  - Set `LSUIElement = YES` in `Info.plist`.
  - Use accessory/menu-bar behavior intentionally.
- Permissions:
  - Request microphone permission.
  - Check Accessibility permission before starting the global hotkey.
  - If Accessibility is missing, show UI state with:
    - Open Accessibility Settings
    - Retry Hotkey Setup
- Recording:
  - Default hotkey is Right Option.
  - Long press starts recording on key down and stops/transcribes on key up.
  - Short press enters toggle mode; the next press stops/transcribes.
  - Esc cancels active recording and inserts no text.
  - Ignore recording start while ASR model is not loaded.
  - Reject ASR model switching while recording or transcribing.
- Audio:
  - Create a fresh `AVAudioEngine` per recording session.
  - Serialize start/stop/cancel.
  - Use a session generation token to ignore stale tap callbacks.
  - Convert input to 16 kHz mono Float32.
  - Maintain a minimum sample guard before ASR to avoid known short-audio crashes.
- Transcription:
  - Run ASR off the main actor.
  - Use ASR language detection when available.
  - Return final trimmed text and detected language.
- Hotwords:
  - Preserve the hotword UI and persisted dictionary.
  - Wire hotwords into ASR only if the selected `speech-swift` API exposes context or prompt-bias support.
  - If the selected API does not support hotword context, keep the dictionary as local data and do not claim it affects recognition.
- Text processing:
  - Disabled by default unless the user has enabled it in settings.
  - Load Qwen3.5 only when enabled.
  - Unload when disabled.
  - Protect against ON/OFF race conditions while the model is loading.
  - Use thinking-disabled generation context where supported.
  - If processing fails, paste raw ASR text and show an error.
- Text insertion:
  - Save the current pasteboard contents.
  - Put final text on the pasteboard.
  - Simulate Cmd+V using `CGEvent`.
  - Restore the pasteboard only if no other app has changed it.
- History:
  - If retention is Never, do not create or write history records.
  - Use atomic JSON writes.
  - Preserve corrupted JSON files instead of overwriting them on decode failure.

## GUI Design

- Match the existing screenshots in `docs/README_PNG`.
- Use SwiftUI with native macOS patterns:
  - sidebar navigation
  - grouped settings sections
  - SF Symbols
  - `ContentUnavailableView`
  - semantic colors and system materials
  - Light/Dark/System appearance
- Main window:
  - Sidebar items:
    - Home
    - Hotwords
    - History
  - Home view:
    - app title and readiness status
    - today word count
    - total word count
    - recording hotkey
    - cancel key
    - text processing toggle and preset
    - sound feedback
    - language
    - appearance
    - ASR model
    - microphone
  - Hotwords view:
    - explanatory header
    - text field
    - add button
    - list with delete controls
    - empty state
  - History view:
    - retention picker
    - clear button with confirmation
    - search
    - date-grouped records
    - copy and delete controls
    - original text display for LLM-processed records
- Recording overlay:
  - Use a dedicated AppKit `NSPanel`.
  - Show on all spaces and full-screen contexts.
  - Use a compact waveform capsule during recording.
  - Use progress indication during transcription.
  - Hide when idle.
  - Remove the current timer Sendable warning in the rewrite by using a main-actor-safe timer pattern.

## No-Sandbox And Signing Conditions

- App Sandbox must remain disabled.
- Reason:
  - global `CGEventTap`
  - cross-app Cmd+V simulation
  - Accessibility-controlled event posting
- Required app metadata:
  - `LSUIElement = YES`
  - `NSMicrophoneUsageDescription`
  - bundle identifier such as `com.shuichi.VibingSpeech`
  - Apple Silicon-only build settings
- Entitlements:
  - Do not include `com.apple.security.app-sandbox`.
  - Do not invent unnecessary entitlements.
- Signing:
  - Current machine has no valid code-signing identities.
  - Use local/ad-hoc signing for personal-use builds.
  - Developer ID signing and notarization are out of scope until a valid identity is installed.
- Archive:
  - Create archive through Xcode.
  - Verify the archived app launches locally.
  - Verify the archived app has no sandbox entitlement.

## Testing And Verification

- Build after code edits through the Xcode MCP server.
- Use the active Xcode project and scheme.
- Minimum automated tests:
  - ASR model enum metadata.
  - text processing prompt generation.
  - language normalization.
  - word count for CJK and whitespace-separated languages.
  - settings persistence defaults.
  - history retention, including Never.
  - hotword trimming and duplicate handling.
  - corrupted JSON load preserves file and uses empty in-memory state.
  - pasteboard snapshot and restore logic.
  - short-audio guard.
- Manual integration tests:
  - first launch.
  - microphone permission flow.
  - Accessibility missing state and retry.
  - menu bar item.
  - no Dock icon.
  - main window opens from menu.
  - Home, Hotwords, and History navigation.
  - add/delete hotwords.
  - history search, copy, delete, clear.
  - microphone picker.
  - ASR model loading.
  - recording overlay show/hide.
  - hold-to-record.
  - toggle recording.
  - Esc cancellation.
  - paste into TextEdit.
  - ASR model switch after returning to idle.
  - text processing enabled and disabled.
- Release/archive checks:
  - Release build succeeds through Xcode.
  - Archive succeeds through Xcode.
  - Archived app launches.
  - `codesign` inspection confirms App Sandbox is absent.
  - Gatekeeper result is documented as local/ad-hoc personal-use behavior.

## Acceptance Criteria

- The final deliverable is `VibingSpeech.app` built and archived through Xcode.
- The app builds with Swift 6.3+ and Xcode 26+.
- No SwiftPM-only release path is required for personal-use packaging.
- No CUDA paths are introduced.
- No cloud communication occurs except first-run model downloads.
- No user audio or transcribed text is uploaded.
- Global hotkey recording works from other applications.
- The transcription result is pasted into the active app.
- Esc cancels recording without insertion.
- The floating overlay accurately reflects recording and transcribing states.
- History and hotwords persist locally.
- History retention Never writes no transcription records.
- Text processing is optional and local.
- App Sandbox is disabled.
- Intel Macs are rejected at launch.

## Implementation Order

1. Create `NewPlan.md` first.
2. Create the fresh Xcode project.
3. Add package dependencies through Xcode.
4. Add app metadata, Info.plist values, signing settings, and no-sandbox configuration.
5. Build an empty menu bar app through Xcode MCP.
6. Add core models and stores with tests.
7. Add permission, hotkey, and text insertion services.
8. Add microphone recording service.
9. Add ASR service and model loading.
10. Add optional text processing service.
11. Add app coordinator and recording state flow.
12. Add main SwiftUI window.
13. Add recording overlay panel.
14. Run Xcode builds and tests.
15. Run manual end-to-end checks.
16. Create and verify a personal-use Xcode archive.

## Assumptions

- Preserve all current README-level features.
- Use the current UI images as visual targets.
- Use Apple-default Xcode layout for the rewrite.
- Keep legacy SwiftPM code untouched until the new app is verified.
- Use local/ad-hoc signing for now.
- Developer ID signing and notarization can be added later when a valid signing identity exists.
