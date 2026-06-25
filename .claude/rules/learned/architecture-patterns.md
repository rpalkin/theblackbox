<!-- MAP-MANAGED: {"generated_by":"map-learn","source":".map/master/learning-handoff.md","installed_at":"2026-06-25"} -->
<!-- map:start -->
# Architecture Patterns (Learned)

<!-- MAP-LEARN: populated by /map-learn. Edit freely, commit with project. -->

- **Application Support for app-owned metadata** (2026-06-25): When adding durable app-owned metadata to the macOS app, always store it under `FileManager.default.url(for: .applicationSupportDirectory, ...)` rather than the user-selected audio output directory because settings-controlled media locations should not own internal app database lifecycle. [workflow: map-efficient]

- **Menu bar app window extension** (2026-06-25): When adding secondary UI to a menu-bar-only SwiftUI app, always append a separate `Window(id:)` scene and open it with `@Environment(\.openWindow)` because this preserves the existing `MenuBarExtra` and `Settings` flow while still giving users a standalone window. [workflow: map-efficient]

- **Swift actor for ML service serialization** (2026-06-25): When adding an ML inference service to a SwiftUI macOS app, declare it as a Swift `actor` (not a class with DispatchQueue or @MainActor) so the runtime serializes concurrent calls automatically without blocking the main thread. Publish UI-visible state through a separate `@MainActor ObservableObject` and cross the boundary with explicit `MainActor.run` hops. [workflow: map-efficient]

- **Row-scoped ViewModel for per-item async operation gating** (2026-06-25): When a SwiftUI List renders rows that can each independently trigger an async operation, use a `@StateObject` row-scoped ViewModel per row to track per-row in-progress state, separate from any global service state. Global service flag handles serialization; per-row flag handles button label accuracy. [workflow: map-efficient]
<!-- map:end -->
