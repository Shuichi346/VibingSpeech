This PLANS.md is the initial plan. Do not modify the file based on it as a reference.

# Live Transcription Overlay

## Summary

- Add an optional **Live Transcription** mode, off by default, while preserving the current batch transcription flow when disabled.
- In live mode, show partial/final ASR text only in the recording overlay, never paste live into the target app.
- On stop, flush finalized ASR text, optionally run the existing LLM post-processing once on the complete transcript, then paste once.

## Key Changes

- Add `SettingsStore.liveTranscriptionEnabled`, persist it in `UserDefaults`, and add a **Live Transcription** switch on Home inside `SettingsCard`; disable changing it while recording/transcribing.
- Keep the current `finishRecordingAndTranscribe()` batch path unchanged when Live Transcription is off.
- Add a live ASR path using speech-swift's Qwen3 ASR + `SpeechVAD` streaming VAD components:
  - feed 16 kHz mic samples during recording;
  - show partial ASR about once per second;
  - finalize segments after natural pauses or `maxSegmentDuration` of 10 seconds;
  - use a less twitchy silence threshold around 0.6 seconds for natural dictation breaks.
- Add `SpeechVAD` as an explicit Xcode package product if direct app imports are needed for the live VAD processor.
- Extend `MicrophoneRecorder` with a non-blocking sample callback while keeping its current full-sample capture for fallback and compatibility.
- Add live transcript state to `RecordingOverlayState`: finalized ASR text, current partial text, and error/status for the live session.

## Overlay Behavior

- Preserve the existing compact bottom-centered mic overlay as the anchor.
- In live mode, add a separate bottom-centered transcript pop-up above the compact mic overlay; show only while recording.
- Partial text appears visually unstable/subdued and is replaced as newer partials arrive.
- Finalized ASR segments move into the stable transcript area.
- On cancel, discard live text and hide the overlay.
- On stop, hide the live overlay, flush remaining ASR, run final LLM processing if enabled, paste once, and write history.

## LLM/Text Processing

- Do not run LLM on partials or per-segment live text.
- If Text Processing is off, paste the accumulated finalized ASR text as-is.
- If Text Processing is on, run the existing `TextProcessingService.process(...)` once on the complete accumulated ASR text after stop, then paste the processed result.
- Preserve existing fallback behavior: if LLM fails, paste raw ASR, store history with the raw result, and surface the text-processing error.

## Test Plan

- Unit test `SettingsStore` persistence for `liveTranscriptionEnabled`.
- Unit test transcript accumulation: partial replacement, final segment commit, stop flush, cancel discard.
- Build with the Xcode project after edits.
- Manual checks:
  - Live off: current record-stop-transcribe-paste behavior remains unchanged.
  - Live on + LLM off: overlay shows partial/final text during recording and pastes once on stop.
  - Live on + LLM on: overlay shows ASR during recording, then final pasted text is LLM-processed once after stop.
  - No live paste occurs before stop.
  - Cancel does not paste or save history.
  - Long dictation, around 5 minutes, avoids the current single large post-stop ASR delay.
