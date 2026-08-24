# Issue #40 v6 installed UAT diagnosis: `无法确认输入位置`

Date: 2026-08-24 (Asia/Shanghai)

## User-visible failure

The installed v5 candidate showed `无法确认输入位置` immediately after the accepted Fn hold,
before the streaming preview could become useful. The rejected candidate was stopped before repair.

## Evidence and root cause

- The installed v5 process launched at 19:04:19. The system Accessibility TCC row was last modified
  at 19:04:24. Permission therefore landed after application initialization.
- `SystemReviewSubmissionLifecycleObserver` installed its workspace/local/global monitors once from
  `init`. If the global key monitor was unavailable before Accessibility authorization completed,
  `installObservers()` removed the partial observer set and left `isArmed == false`.
- The former `acquireLease` implementation only checked that dead observer set. It never retried
  installation, so `SystemReviewSubmissionFacade.captureTarget` returned
  `ReviewPreBoundaryFailure.accessibilityFailure` on every later Fn hold in the same process.
- `MainViewModel.completeReviewTargetCapture` translated every typed capture failure into the exact
  user-visible `无法确认输入位置` abnormal termination. This is why recording and recognition did not
  start; neither async line was itself failing.
- TCC showed Accessibility authorization for the old ad-hoc code requirement pinned to CDHash
  `b33203991a38cedfa991c7f0903a5cdade74c669`, matching the v5 installed receipt.

Verdict: high-confidence authorization-ordering defect. It is not a microphone, Feishu API,
recognition, recorder-barrier, Send, Return, or target-consumption failure.

## Inline repair

Production commit: `39848ee4` (`fix: retry review target observers after accessibility grant`)

- `acquireLease` now verifies the complete three-workspace-token/local-monitor/global-monitor set.
- If initialization preceded authorization, it removes any partial state and reinstalls the complete
  observer set immediately before the fixed original-target lease is acquired.
- A failed reinstall remains a typed pre-boundary failure. It cannot emit a character, image,
  pasteboard mutation, activation, AX insertion, or Unicode event.
- Capture failures now log only the public typed enum, never application text or transcript content.
- Recording/capture and recognition/provider remain independent asynchronous roots. Their ordering
  and state machines were not joined or changed.

## Validation

- Focused nine-suite matrix: 324 executed, 0 failed, 0 skipped; `TEST SUCCEEDED`.
- Full serialized macOS target: 537 executed, 0 failed, 1 expected Issue #34 live-TCP skip;
  `TEST SUCCEEDED`.
- Debug build: `BUILD SUCCEEDED`.
- Release build: `BUILD SUCCEEDED`.
- SwiftLint strict: 0 violations in 36 files.
- `git diff --check`: pass.
- Worktree branch pushed and clean at documentation head `ae53360`; production repair is `39848ee`.

## Installed-runtime boundary

The v6 app is now Apple Development-signed with TeamIdentifier `D5KY7PZC5N` so future local
replacements using the same identity have a stable designated requirement rather than a per-build
ad-hoc CDHash. The current system TCC row still names the rejected v5 ad-hoc requirement, so the
installed v6 process correctly reports Accessibility false until the owner reauthorizes the current
`/Applications/FeishuSpeech.app`. System Settings was opened to Privacy & Security > Accessibility.

Owner UAT remains pending after that one security-sensitive manual authorization. The issue must
remain open until Fn produces the streaming preview, Fn release produces the durable editable draft,
and preview-local Send or qualified Return produces exactly one original-target output attempt.
