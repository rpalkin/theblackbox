<!-- MAP-MANAGED: {"generated_by":"map-learn","source":".map/master/learning-handoff.md","installed_at":"2026-06-25"} -->
<!-- map:start -->
# Architecture Patterns (Learned)

<!-- MAP-LEARN: populated by /map-learn. Edit freely, commit with project. -->

- **Application Support for app-owned metadata** (2026-06-25): When adding durable app-owned metadata to the macOS app, always store it under `FileManager.default.url(for: .applicationSupportDirectory, ...)` rather than the user-selected audio output directory because settings-controlled media locations should not own internal app database lifecycle. [workflow: map-efficient]

- **Menu bar app window extension** (2026-06-25): When adding secondary UI to a menu-bar-only SwiftUI app, always append a separate `Window(id:)` scene and open it with `@Environment(\.openWindow)` because this preserves the existing `MenuBarExtra` and `Settings` flow while still giving users a standalone window. [workflow: map-efficient]
<!-- map:end -->
