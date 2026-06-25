# Task Plan: SwiftData Recording History Window

## Overview
- Goal: Persist completed recording history with SwiftData in Application Support and expose it in a separate searchable history window.
- Source spec: `.map/master/spec_master.md`
- Blueprint: `.map/master/blueprint.json`
- Runtime state dependency: none; this is local app code and local SwiftData persistence.
- Already implemented and excluded from execution scope: existing saved URL plumbing and in-memory duration tracking.

## Subtasks

### ST-001: Create SwiftData history model and Application Support container
- **Status:** pending
- **Expected Diff Size:** small
- **Concern Type:** data
- **One Logical Step:** true
- **AAG Contract:** Actor -> add SwiftData RecordingHistoryItem and Application Support container setup -> app has a durable history store contract
- **Validation Criteria:** VC1 [AC-4]: SwiftData ModelContainer configuration points to an Application Support URL and creates the required directory if missing.
- **Validation Criteria:** VC2 [INV-3]: RecordingHistoryItem exposes timestamp, duration, and audioFileURL to callers, even if the URL is persisted internally as a path string.
- **Validation Criteria:** VC3 [INV-4]: The SwiftData store path is separate from the user-selected audio output directory.
- **Validation Criteria:** VC4 [HC-1]: The persistence implementation uses SwiftData @Model/ModelContainer rather than UserDefaults or ad-hoc files.
- **Validation Criteria:** VC5 [HC-2]: The store URL is under FileManager Application Support for the app.
- **Dependencies:** []
- **Affected Files:** `whisperer/Models/RecordingHistoryItem.swift`, `whisperer/Services/RecordingHistoryStore.swift`, `whisperer.xcodeproj/project.pbxproj`

### ST-002: Insert history records on successful recording completion
- **Status:** pending
- **Expected Diff Size:** small
- **Concern Type:** runtime
- **One Logical Step:** true
- **AAG Contract:** RecordingState -> insert history item after successful savedURL stop paths -> completed recordings become durable history entries
- **Validation Criteria:** VC1 [AC-1]: Manual stop inserts a SwiftData record using the savedURL and final in-memory duration.
- **Validation Criteria:** VC2 [AC-2]: External successful stop inserts a SwiftData record using the callback savedURL and final in-memory duration.
- **Validation Criteria:** VC3 [AC-3]: cancelRecording and error paths do not insert history records.
- **Validation Criteria:** VC4 [INV-1]: Insert happens only after a finalized saved audio URL exists.
- **Validation Criteria:** VC5 [INV-2]: Failed, cancelled, or partial recordings are not persisted as history.
- **Validation Criteria:** VC6 [CCR-2]: Both manual and external stop paths use the same insertion helper or equivalent shared behavior.
- **Dependencies:** [ST-001]
- **Affected Files:** `whisperer/whispererApp.swift`, `whisperer/Models/RecordingHistoryItem.swift`, `whisperer/Services/RecordingHistoryStore.swift`

### ST-003: Expose a separate history window from the menu-bar app
- **Status:** pending
- **Expected Diff Size:** small
- **Concern Type:** ui
- **One Logical Step:** true
- **AAG Contract:** MenuBarView/WhispererApp -> add history Window scene and open action -> user can open recording history separately
- **Validation Criteria:** VC1 [AC-5]: Menu-bar UI exposes an action that opens a separate history window.
- **Validation Criteria:** VC2 [HC-4]: Existing MenuBarExtra behavior and settings scene remain intact.
- **Validation Criteria:** VC3 [CCR-1]: New Swift files and scene/view references are included in the app target/project so the app builds.
- **Dependencies:** [ST-001]
- **Affected Files:** `whisperer/whispererApp.swift`, `whisperer/Views/MenuBarView.swift`, `whisperer/Views/RecordingHistoryView.swift`, `whisperer.xcodeproj/project.pbxproj`

### ST-004: Build recording history list and search UI
- **Status:** pending
- **Expected Diff Size:** medium
- **Concern Type:** ui
- **One Logical Step:** true
- **AAG Contract:** RecordingHistoryView -> query and filter SwiftData history items -> user sees searchable recording list
- **Validation Criteria:** VC1 [AC-6]: History window renders persisted recordings newest first with date/time, duration, and file name/path affordance.
- **Validation Criteria:** VC2 [AC-7]: Search field filters visible rows by recording metadata such as date text or file name/path.
- **Validation Criteria:** VC3 [AC-8]: View code contains no transcript field, no transcription text rendering, and no transcription model dependency.
- **Validation Criteria:** VC4 [HC-3]: Screenshot-inspired UI excludes transcription, waveform, and player controls from this task.
- **Dependencies:** [ST-001, ST-003]
- **Affected Files:** `whisperer/Views/RecordingHistoryView.swift`, `whisperer/Models/RecordingHistoryItem.swift`, `whisperer.xcodeproj/project.pbxproj`

## Execution Order
- ST-001 -> ST-002
- ST-001 -> ST-003 -> ST-004

## Spec Coverage
- AC-1 -> ST-002
- AC-2 -> ST-002
- AC-3 -> ST-002
- AC-4 -> ST-001
- AC-5 -> ST-003
- AC-6 -> ST-004
- AC-7 -> ST-004
- AC-8 -> ST-004
- INV-1 -> ST-002
- INV-2 -> ST-002
- INV-3 -> ST-001
- INV-4 -> ST-001
- HC-1 -> ST-001
- HC-2 -> ST-001
- HC-3 -> ST-004
- HC-4 -> ST-003
- CCR-1 -> ST-003
- CCR-2 -> ST-002

## Notes
- Highest-risk first subtask is ST-001 because SwiftData store location must be explicitly under Application Support and new files must be included in the Xcode target.
- ST-002 must avoid inserting history for cancel/failure paths and should cover both manual stop and existing external stop callback.
- ST-004 should use the screenshot only as a visual reference for a dark list/search window; transcript text, waveform, and playback controls stay out of scope.
