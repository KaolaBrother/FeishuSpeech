# Finish all accepted audio after Fn release and restore silent-session resilience for issue #27

- item: Diagnose the Release UAT logs and trace both premature release sealing and active-without-output through the current streaming lifecycle.
  status: done
  dispatched: Unified-log evidence to investigator at `kaola-workflow/issue-27/diagnostic-logs.md`; lifecycle trace to code-explorer at `kaola-workflow/issue-27/lifecycle-trace.md`.
  result: Field evidence in both reports confirms post-release valid responses were locally suppressed and silent-active periods were repeated HTTP-200 backend code 10024 recovery loops.

- item: Add regression tests that reproduce delayed final recognition after Fn release and recoverable silent or disconnected active sessions.
  status: done
  dispatched: Regression-first XCTest changes to tdd-guide in the issue worktree, with baseline and follow-up RED receipts recorded in `kaola-workflow/issue-27/test-red.md` and `kaola-workflow/issue-27/test-red-followup.md`.
  result: Test-only commits `e8d859a` and `eb9f0b3` prove release suppression, cancelled retry, stale backoff, keyboard final divergence, and missing watchdog/drain policy seams.

- item: Design a concrete release-drain and retry-liveness state transition that preserves generation and cursor safety.
  status: done
  dispatched: Dependency-safe production blueprint to code-architect at `kaola-workflow/issue-27/release-drain-blueprint.md`.
  result: Blueprint separates capture close from terminal recognition close, preserves generation/output gates, and specifies bounded 30-second operation watchdogs plus a 60-second post-barrier drain.

- item: Implement the smallest production fix that drains accepted recording recognition before sealing output and restores resilient streaming progress.
  status: done
  dispatched: Keyboard reconciliation landed via implementer at `kaola-workflow/issue-27/keyboard-final-green.md`; coordinator lifecycle, retry reset, operation watchdog, and drain budget now dispatched to implementer with receipt at `kaola-workflow/issue-27/coordinator-green.md`.
  result: Production commits `6066a72` and `62832ad` make authoritative keyboard finals, same-generation release drain, retry reset, operation watchdogs, and bounded expiry green across 308 tests.

- item: Replace obsolete tests that still require release-time terminal revisions to be discarded.
  status: done
  dispatched: Contradictory CurrentFocus and coordinator old-contract assertions to tdd-guide, with migration receipt at `kaola-workflow/issue-27/test-contract-migration.md`.
  result: Test-only commit `c522afb` replaces rejected release-suppression assertions while retaining every fixed-PID, security, interference, uncertainty, empty-final, equal-final, and stale-generation gate.

- item: Migrate the remaining coordinator tests that require immediate post-release cancellation instead of bounded same-generation drain.
  status: done
  dispatched: Seven stale lifecycle assertions identified by the coordinator implementation to tdd-guide, with receipt at `kaola-workflow/issue-27/test-contract-migration-2.md`.
  result: Test-only commit `c067d2d` migrates eight actual stale methods and retains fixed-PID, rebind, unsafe-text, fallback, replay-deduplication, feedback, and stale-write assertions; coordinator suite 83/83 green.

- item: Independently review correctness, concurrency, privacy, and regression coverage for the revised lifecycle.
  status: done
  dispatched: Initial correctness/security reviews recorded at `review-correctness.md` and `review-security.md`; post-fix re-review now dispatched to both reviewers against commit `cbbbf2f` and will append final verdicts to those files.
  result: Final independent verdicts PASS; correctness R1-R4 resolved and no security/privacy P0-P3 remains.

- item: Add regression tests for correctness findings R1-R4 covering AX final failure, typed expiry state, atomic deadline admission, and late factory cancellation.
  status: done
  dispatched: Finding-specific RED XCTest custody to tdd-guide, with evidence at `kaola-workflow/issue-27/review-red-r1-r4.md`.
  result: Test-only commit `25aa505` reproduces all four findings with five runtime failures and one minimal clock-injection compile seam across eight tests.

- item: Fix independently reproduced correctness findings R1-R4 without weakening the passed security boundaries.
  status: done
  dispatched: Finding-specific coordinator repairs to implementer in owned production files, with evidence at `kaola-workflow/issue-27/review-green-r1-r4.md`.
  result: Production commit `cbbbf2f` makes all eight finding tests green, coordinator 91/91, full suite 316/316, strict lint and Debug build green.

- item: Run focused and full tests, strict lint, Debug and Release builds, then install one unlaunched Release copy in Applications.
  status: done
  dispatched: Self-owned build-8 bump and isolated full validation are green; final single-copy Applications installation follows documentation docking, with evidence at `kaola-workflow/issue-27/release-validation.md`.
  result: Build 8 validated with 316/316 tests, strict lint, Debug/Release builds and signature checks; one unlaunched Release 1.0 (8) now occupies Applications and the prior build is recoverable in Trash.

- item: Dock verified documentation, record owner UAT as the remaining closure gate, and finalize the workflow cycle.
  status: done
  dispatched: Verified behavior/build-8 documentation update to doc-updater, with commit and docking receipt at `kaola-workflow/issue-27/doc-update.md`; workflow finalization follows installation.
  result: Documentation-only commit `b78e68a` is docked, no credential UAT is claimed, and issue #27 is ready for keep-open finalization pending owner test.
