evidence-binding: n6-docs 1f1ca433822e
non_tdd_reason: docs update
regression-green: based on n3/n4/n5 validation and review evidence
changed_files:
  - docs/api.md
  - docs/decisions/D-11-01.md
summary:
  - docs/api.md now documents Feishu endpoints, direct HTTP completion rules, timeout buffered parse fallback, token expiry cache rules, cancellation behavior, and the test target caveat.
  - docs/decisions/D-11-01.md records the accepted bundle decision for #11/#12/#21.
validation:
  - read back docs/api.md and docs/decisions/D-11-01.md after editing
  - git diff --check passed
residual_risk:
  - AudioRecorderRecoveryTests.swift remains documented as an excluded pre-existing out-of-scope blocker.
  - swiftlint remains unavailable on PATH per n3/n4/n5 evidence.
