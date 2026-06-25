# Spec: SwiftData Recording History Window

## Decisions Made
| # | Question | Decision | Rationale |
|---|---|---|---|
| 1 | What should be persisted? | Persist one history item per successfully saved recording with timestamp, duration, and audioFileURL. | Matches the request and avoids storing transient or failed/cancelled recordings. |
| 2 | Where should persistence live? | Use SwiftData with an explicit store under the app's Application Support directory. | The user explicitly requested SwiftData in Application Support. |
| 3 | What should create history entries? | `RecordingState` should insert after successful manual stop and after the existing external-stop callback. | These paths already own `savedURL` and in-memory duration evidence: `whisperer/whispererApp.swift:133-137`, `whisperer/whispererApp.swift:85-92`. |
| 4 | What should the history UI show? | A separate dark-friendly macOS window with a search field and a list of recordings showing date/time, duration, and file name/path affordance. | The screenshot shows a standalone list window; transcript snippets are out of scope. |
| 5 | Should the screenshot's transcription/player controls be implemented? | No. Transcription is out of scope; audio playback/waveform controls are not required for this task. | The user explicitly excluded transcription and only requested storage plus list display. |

## Contradiction
The UI reference contains transcription-like text and expanded audio controls, but the stated scope only includes recording metadata history. The plan must preserve the recognizable history-list shape while not introducing transcript schema, transcription processing, waveform rendering, or player controls.

## Invariants
- INV-1: A history item is created only after a recording file has been successfully finalized and a saved audio URL is available.
- INV-2: Cancelled, failed, or partial recordings must not create history items.
- INV-3: The persisted history API exposes timestamp, duration, and audioFileURL for each item.
- INV-4: The SwiftData store is located under Application Support, not in the user-selected recording output folder.

## Constraints
- HC-1: Use SwiftData for recording history persistence.
- HC-2: Store SwiftData data in Application Support.
- HC-3: Do not implement audio transcription or transcript display in this task.
- HC-4: Preserve the existing menu-bar-only app behavior; adding history must not introduce a Dock-primary application flow.
- CCR-1: New Swift files must be added to the Xcode project so the app target builds.
- CCR-2: Successful manual stop and external ScreenCaptureKit stop must both be covered by history insertion.

## Edge Cases
- A recording stops externally after ScreenCaptureKit target disappearance; existing code finalizes and calls `onRecordingStoppedExternally` with `savedURL` at `whisperer/Services/AudioRecordingService.swift:267-278`.
- A recording is cancelled; existing `cancelRecordingAsync()` clears `currentRecordingURL` and should not create history at `whisperer/whispererApp.swift:153-160`.
- The Application Support directory does not exist; the SwiftData setup must create the required app subdirectory before opening the store.
- The audio file referenced by an older history entry may be moved or deleted; the list should still render metadata without crashing.
- Duration should be captured before any future reset of `recordingDuration`; current stop paths leave the value available around `whisperer/whispererApp.swift:129-137` and `whisperer/whispererApp.swift:85-92`.

## Acceptance Criteria
- AC-1: After a successful manual stop, a new SwiftData history record exists with the recording timestamp, final duration, and saved audioFileURL.
- AC-2: After an external successful stop, a new SwiftData history record exists with the recording timestamp, final duration, and saved audioFileURL.
- AC-3: Cancelling or failing a recording does not create a history record.
- AC-4: The SwiftData model/container stores history data in an Application Support location.
- AC-5: The app exposes a separate history window from the menu-bar UI.
- AC-6: The history window displays persisted recordings as a list, newest first, with date/time, duration, and audio file identity/path affordance.
- AC-7: The history window includes a search field that filters the displayed list by visible recording metadata such as date or file name/path.
- AC-8: The history implementation contains no transcription model, no transcript field, and no transcript text UI.

## Requirements Index

<!-- mapify:requirements-index:v1 -->
```yaml
requirements:
  - id: AC-1
    kind: acceptance_criterion
  - id: AC-2
    kind: acceptance_criterion
  - id: AC-3
    kind: acceptance_criterion
  - id: AC-4
    kind: acceptance_criterion
  - id: AC-5
    kind: acceptance_criterion
  - id: AC-6
    kind: acceptance_criterion
  - id: AC-7
    kind: acceptance_criterion
  - id: AC-8
    kind: acceptance_criterion
  - id: INV-1
    kind: invariant
  - id: INV-2
    kind: invariant
  - id: INV-3
    kind: invariant
  - id: INV-4
    kind: invariant
  - id: HC-1
    kind: hard_constraint
  - id: HC-2
    kind: hard_constraint
  - id: HC-3
    kind: hard_constraint
  - id: HC-4
    kind: hard_constraint
  - id: CCR-1
    kind: cross_cutting
  - id: CCR-2
    kind: cross_cutting
```
<!-- /mapify:requirements-index:v1 -->

## Architecture Graph

```text
Successful recording stop
  -> RecordingState captures timestamp/duration/savedURL
  -> SwiftData RecordingHistoryItem insert
  -> Application Support model container
  -> History window @Query
  -> Search-filtered list UI

MenuBarExtra
  -> Start/Stop controls (existing)
  -> Open History action
  -> Separate History Window scene
```

## Security Boundaries
- The app stores local metadata only: timestamp, duration, and audio file URL/path. It must not store transcript text or audio contents in SwiftData.
- The history store is local Application Support data. It must not upload, sync, or expose recording metadata outside the local app.
- File URLs can reveal user paths; UI should show them only inside the local app and avoid logging full history lists.

## Out of Scope
- Audio transcription, transcript persistence, transcript search, transcript snippets, and transcript UI.
- Waveform rendering, audio playback controls, speed controls, and expanded player details from the screenshot.
- Importing existing `.m4a` files into history or backfilling pre-feature recordings.
- Deleting recordings or history entries.
- Changing the user-selected recording output directory behavior.

### Already Implemented
- Current recording URL is tracked during active recording: `RecordingState.currentRecordingURL` exists at `whisperer/whispererApp.swift:62`, is set from `recordingService.currentRecordingURL` after start at `whisperer/whispererApp.swift:108`, and is set to the saved URL after manual stop at `whisperer/whispererApp.swift:136`.
- Saved audio file URL is returned by the recording service on stop: `AudioRecordingService.stopRecording()` returns `URL` at `whisperer/Services/AudioRecordingService.swift:167`, receives `savedURL` from capture at `whisperer/Services/AudioRecordingService.swift:183`, and returns it at `whisperer/Services/AudioRecordingService.swift:196`.
- Saved audio file URL is surfaced for external ScreenCaptureKit stops: `onRecordingStoppedExternally` is declared at `whisperer/Services/AudioRecordingService.swift:90` and invoked with `savedURL` at `whisperer/Services/AudioRecordingService.swift:278`.
- Recording duration is tracked in-memory while recording: `RecordingState.recordingDuration` exists at `whisperer/whispererApp.swift:58`, is reset on start at `whisperer/whispererApp.swift:107`, incremented at `whisperer/whispererApp.swift:168`, and formatted at `whisperer/whispererApp.swift:195-199`.

## Open Questions
- Should the history window include a button to reveal the audio file in Finder? This is a natural file identity affordance, but not required by the prompt.
- If SwiftData cannot persist `URL` directly in the selected deployment settings, implementation may persist a path string while exposing an `audioFileURL` computed property. This must still satisfy the user-facing field contract.
