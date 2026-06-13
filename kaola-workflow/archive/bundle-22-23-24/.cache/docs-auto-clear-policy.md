evidence-binding: docs-auto-clear-policy 59bfeea8267e
changed_files:
  - docs/architecture.md
  - docs/decisions/D-24-01.md
summary:
  - docs/architecture.md now documents the MonitoringState failed/active contract, the exact user-facing hot-key monitoring error, auto-clear of only that stale error, preservation of unrelated errors, and cleanup routing through stopHotKeyMonitoring().
  - docs/decisions/D-24-01.md records the accepted #22/#23/#24 policy and teardown/subscriber-release invariant.
validation:
  - Read back docs/architecture.md and docs/decisions/D-24-01.md after editing.
  - git diff --check -- docs/architecture.md docs/decisions/D-24-01.md passed.
  - No production code was edited by this doc node.
residual_risk:
  - none
