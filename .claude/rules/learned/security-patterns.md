<!-- MAP-MANAGED: {"generated_by":"map-learn","source":"inline-summary","installed_at":"2026-06-25"} -->
<!-- map:start -->
# Security Patterns (Learned)

<!-- MAP-LEARN: populated by /map-learn. Edit freely, commit with project. -->

- **Add sandbox entitlements before writing dependent code** (2026-06-25): When a macOS sandboxed app requires a new capability (network.client for model download, device.audio-input, etc.), add the entitlement to the .entitlements file in the first subtask before any code that depends on it. Missing sandbox entitlements produce a silent OS denial — no thrown Swift error, no useful console message — making the root cause extremely hard to diagnose after the fact. [workflow: map-efficient]
<!-- map:end -->
