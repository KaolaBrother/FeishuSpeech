# Issue 26 UAT2 Security Review

result: PASS
scope: FeishuSpeech/Services/HotKeyService.swift, FeishuSpeech/ViewModels/MainViewModel.swift, FeishuSpeechTests/HotKeyServiceTests.swift, FeishuSpeechTests/StreamingMainViewModelTests.swift
findings: none

## Evidence

- Authentication error privacy: `MainViewModel.streamingFailureMessage` pattern-matches `APIError.authFailed` but ignores its associated value and returns only the fixed Chinese feedback string. The catch path passes no provider text to status, overlay, or the hot-key state (`MainViewModel.swift:394-395,442-463`).
- Transcript and stale-callback containment: terminal provider events stop packet consumption before `finish`, while all streaming events are gated by the active generation. Abnormal teardown invalidates the generation and cursor before hiding the overlay, cleaning audio, and cancelling transport (`MainViewModel.swift:384-413,442-472,698-717`).
- Re-entry safety: identical error publications are suppressed, and a repeated hot-key error with no active generation does not repeat destructive teardown (`HotKeyService.swift:484-492`, `MainViewModel.swift:192-210`). This closes the observed feedback loop without weakening session invalidation on the first error.
- Input and permission boundary: the candidate adds no permission request, event-tap creation, clipboard operation, synthetic input, credential read, or network call. The production delta is limited to error-state handling, terminal-event control flow, and fixed error classification.
- Regression proof: the new tests assert one teardown, overlay dismissal, late partial/final no-op behavior, zero transcript output, and fixed auth feedback with no associated-value disclosure (`StreamingMainViewModelTests.swift:80-147`; `HotKeyServiceTests.swift:82-100`). Existing lifecycle-free evidence reports 184 tests with 0 failures in `/tmp/issue26-uat2-final-run.SzDD2f/full-test.log`; build-for-testing succeeded in `/tmp/issue26-uat2-baseline.cXr6eR/final-build.log`; `git diff --check` passed during this review.

verdict: pass
findings_blocking: 0
review_conclusion: The candidate preserves credential and transcript privacy while making terminal cleanup generation-safe and non-reentrant.
