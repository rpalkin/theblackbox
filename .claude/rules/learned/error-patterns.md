<!-- MAP-MANAGED: {"generated_by":"map-learn","source":".map/master/learning-handoff.md","installed_at":"2026-06-25"} -->
<!-- map:start -->
# Error Patterns (Learned)

<!-- MAP-LEARN: populated by /map-learn. Edit freely, commit with project. -->

- **MAP mutation boundary needs commit baselines** (2026-06-25): When running multi-subtask MAP workflows, create per-subtask commits or expect mutation-boundary guards to lose isolation because recording prior subtasks as `uncommitted` prevents later subtasks from proving their own diff cleanly. [workflow: map-efficient]
<!-- map:end -->
