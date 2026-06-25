---
paths:
  - "**/test_*"
  - "**/tests/**"
  - "**/*_test.*"
  - "**/*.test.*"
---
<!-- MAP-MANAGED: {"generated_by":"map-learn","source":".map/master/learning-handoff.md","installed_at":"2026-06-25"} -->
<!-- map:start -->

# Testing Strategies (Learned)

<!-- MAP-LEARN: populated by /map-learn. Edit freely, commit with project. -->

- **Xcode build as target-membership proof** (2026-06-25): When an Xcode project uses `PBXFileSystemSynchronizedRootGroup`, always verify new Swift files with `xcodebuild` instead of editing `project.pbxproj` by hand because the synchronized group target membership is proven by compilation, not explicit source build phase entries. [workflow: map-efficient]

- **Scope exclusion grep for UI constraints** (2026-06-25): When a UI task explicitly excludes features such as transcript, waveform, or playback, always run a targeted source search for those terms in the new view because a successful build alone does not prove out-of-scope UI was avoided. [workflow: map-efficient]

- **Smoke-test track-index ordering with known source content** (2026-06-25): When decoding multi-track audio where track identity is inferred from index position (e.g. AVAssetReader track 0 = system, track 1 = mic), always smoke-test using a recording with distinguishable content in each track and assert the role-labeled outputs are non-interchangeable. A swapped index compiles and runs without error but silently inverts semantically distinct fields. [workflow: map-efficient]
<!-- map:end -->
