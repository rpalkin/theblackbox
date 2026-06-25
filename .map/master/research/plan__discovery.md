## Already Implemented
- Current recording URL is tracked during active recording: `RecordingState.currentRecordingURL` exists at `whisperer/whispererApp.swift:62`, is set from `recordingService.currentRecordingURL` after start at `whisperer/whispererApp.swift:108`, and is set to the saved URL after manual stop at `whisperer/whispererApp.swift:136`.
- Saved audio file URL is returned by the recording service on stop: `AudioRecordingService.stopRecording()` returns `URL` at `whisperer/Services/AudioRecordingService.swift:167`, receives `savedURL` from capture at `whisperer/Services/AudioRecordingService.swift:183`, and returns it at `whisperer/Services/AudioRecordingService.swift:196`.
- Saved audio file URL is also surfaced for external ScreenCaptureKit stops: `onRecordingStoppedExternally` is declared at `whisperer/Services/AudioRecordingService.swift:90` and invoked with `savedURL` at `whisperer/Services/AudioRecordingService.swift:278`; `RecordingState` stores it at `whisperer/whispererApp.swift:91`.
- Recording duration is tracked in-memory while recording: `RecordingState.recordingDuration` exists at `whisperer/whispererApp.swift:58`, is reset on start at `whisperer/whispererApp.swift:107`, incremented once per second at `whisperer/whispererApp.swift:168`, and formatted at `whisperer/whispererApp.swift:195-199`.
- Audio output files already get timestamped filenames: `UnifiedAudioCapture.generateFilename()` formats the current date at `whisperer/Services/UnifiedAudioCapture.swift:282-285`.

## Existing Files
- `whisperer/whispererApp.swift`: app entry, `MenuBarExtra`, `Settings` scene, and `RecordingState` recording lifecycle. Relevant lines: `whisperer/whispererApp.swift:34-49`, `whisperer/whispererApp.swift:55-200`.
- `whisperer/Services/AudioRecordingService.swift`: recording orchestrator, stop path, notification, unexpected-stop path. Relevant lines: `whisperer/Services/AudioRecordingService.swift:74-105`, `whisperer/Services/AudioRecordingService.swift:163-201`, `whisperer/Services/AudioRecordingService.swift:261-279`.
- `whisperer/Services/UnifiedAudioCapture.swift`: creates output directory and timestamped `.m4a` output URL. Relevant lines: `whisperer/Services/UnifiedAudioCapture.swift:93-112`, `whisperer/Services/UnifiedAudioCapture.swift:280-285`.
- `whisperer/Views/MenuBarView.swift`: existing menu UI with recording controls, settings, and quit actions. Relevant lines: `whisperer/Views/MenuBarView.swift:11-17`, `whisperer/Views/MenuBarView.swift:116-172`.
- `whisperer/Views/SettingsView.swift`: existing standalone SwiftUI settings scene style and dark-friendly controls. Relevant lines: `whisperer/Views/SettingsView.swift:10-14`, `whisperer/Views/SettingsView.swift:90`.
- `whisperer/Models/AppSettings.swift`: app settings singleton and output directory handling, currently defaults output recordings to Documents/Whisperer, not Application Support. Relevant lines: `whisperer/Models/AppSettings.swift:11-21`, `whisperer/Models/AppSettings.swift:26-42`.

## Files to Create
- `whisperer/Models/RecordingHistoryItem.swift`: SwiftData `@Model` for `timestamp`, `duration`, and `audioFileURL` or a persistable URL representation.
- `whisperer/Services/RecordingHistoryStore.swift` or equivalent: setup/access boundary for SwiftData model container stored under Application Support if not handled entirely in `WhispererApp`.
- `whisperer/Views/RecordingHistoryView.swift`: list/search UI for recordings, explicitly excluding transcription content.
- Potentially `whisperer/Views/RecordingHistoryWindow.swift` is not required if a SwiftUI `Window` scene is sufficient.

## Patterns Found
- App uses SwiftUI scene composition: `MenuBarExtra` plus `Settings` in `whisperer/whispererApp.swift:34-49`; a new history window can follow this with another `Window` or `WindowGroup` scene.
- Recording state is centralized in `@MainActor RecordingState`, with stop paths in `stopRecordingAsync()` and `onRecordingStoppedExternally`, so history creation should be wired into both successful stop paths and not into `cancelRecording()`.
- Existing UI uses compact SwiftUI views, SF Symbols, dark-mode-compatible `Color.primary.opacity(...)`, and no custom design system.
- Existing persistence is UserDefaults only; no `SwiftData`, `@Model`, `ModelContainer`, `ApplicationSupportDirectory`, `History`, or transcription model was found by searches for `SwiftData|@Model|ModelContainer|History|ApplicationSupport|audioFileURL|transcription|Transcript`.

## Risks / Unknowns
- Duration must be captured before resetting/stopping timer; manual stop currently calls `stopTimer()` before awaiting stop, but `recordingDuration` remains available in memory at `whisperer/whispererApp.swift:129-137`.
- External stop path currently receives only `savedURL`; history insertion there needs access to the current in-memory `recordingDuration` before any state reset at `whisperer/whispererApp.swift:85-92`.
- SwiftData storage location must be explicitly placed under Application Support to satisfy the requirement; default SwiftData container location should not be assumed.
- `URL` persistence in SwiftData may require choosing between `URL` attribute support and storing `audioFileURL.path`/bookmark data; since the requested field is `audioFileURL`, the implementation contract should preserve a URL-facing API even if persisted as a string internally.
- The screenshot includes transcription text and an audio player; transcription is explicitly out of scope. A minimal history list should not introduce transcript schema/UI.
- No automated test target exists per project guidance; validation is likely build/manual unless a lightweight test target is added intentionally.