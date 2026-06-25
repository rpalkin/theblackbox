---
paths:
  - "**/*.swift"
---
<!-- MAP-MANAGED: {"generated_by":"map-learn","source":".map/master/learning-handoff.md","installed_at":"2026-06-25"} -->
<!-- map:start -->

# Implementation Patterns (Learned)

<!-- MAP-LEARN: populated by /map-learn. Edit freely, commit with project. -->

- **SwiftData URL persistence facade** (2026-06-25): When a SwiftData model needs to expose a `URL`, always persist a stable path string internally and expose a computed `URL` facade because SwiftData stores primitive fields more predictably while callers keep a URL-shaped API. [workflow: map-efficient]
  ```swift
  @Model
  final class RecordingHistoryItem {
      private var audioFilePath: String

      var audioFileURL: URL {
          get { URL(fileURLWithPath: audioFilePath) }
          set { audioFilePath = newValue.path }
      }
  }
  ```

- **Shared SwiftData container boundary** (2026-06-25): When multiple app flows insert and query the same SwiftData records, always centralize `ModelContainer` creation in a store boundary because separate ad-hoc containers can drift in schema, location, or lifecycle. [workflow: map-efficient]

- **Persist only after finalized outputs** (2026-06-25): When recording completion has success, cancel, and error paths, always insert history only from paths that have a finalized saved file URL because cancel/failure paths can otherwise persist partial or deleted recordings. [workflow: map-efficient]
<!-- map:end -->
