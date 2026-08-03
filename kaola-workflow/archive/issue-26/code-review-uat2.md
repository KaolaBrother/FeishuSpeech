# Issue 26 UAT2 Correctness Review

result: PASS
scope: FeishuSpeech/Services/HotKeyService.swift, FeishuSpeech/ViewModels/MainViewModel.swift, FeishuSpeechTests/HotKeyServiceTests.swift, FeishuSpeechTests/StreamingMainViewModelTests.swift
candidate_diff_sha256: 778bf3b8873fc1dc197858a0d83cf06c7182351c2e307c1ec932662618bd7322
findings: none

## Correctness evidence

- Error-loop closure: `terminateAbnormally` invalidates the active generation and hides the overlay before publishing its fixed error. The resulting hot-key error echo now sees no active generation and an already-equal view-model error, so it cannot start a second teardown. `HotKeyService.setError` independently suppresses repeated identical publications.
- Single terminal path: `consumePackets` reports whether a provider event was terminal, and `consumeAudio` returns after that event instead of falling through to `finishConsumedAudio`. The first terminal handler therefore owns the one abnormal teardown and one transport cancellation.
- Overlay and generation ordering: abnormal teardown invalidates the generation and cursor, closes ingress, clears interaction references, stops the timer, and calls `hide` before recorder cleanup and session cancellation. With error re-entry removed, the overlay generation is not continuously advanced and the hide animation can complete.
- Late-callback rejection: every streaming event remains gated by `isActive(identity)`. The new terminal-failure regression injects late partial and final events after teardown and proves zero Accessibility writes, zero current-focus insertion, zero recovery copy, and no transcript exposure.
- Current-focus and secure-input preservation: the candidate does not change cursor capability selection, current-focus delivery, final-only destination validation, or Secure Input guards. Existing current-focus success/failure/security tests and active-session Secure Input invalidation tests remain green.
- Authentication feedback: provider `APIError.authFailed` is mapped to the fixed `认证失败，请检查应用凭据` string without using the associated backend value. The regression proves the associated secret/transcript marker reaches neither visible status nor overlay feedback.

## Validation evidence

- Independent lifecycle-free XCTest execution passed 184 of 184 tests with zero failures: `env DYLD_LIBRARY_PATH=/tmp/issue26-uat2-baseline.cXr6eR/Build/Products/Debug/FeishuSpeech.app/Contents/MacOS /Applications/Xcode.app/Contents/Developer/usr/bin/xctest /tmp/issue26-uat2-baseline.cXr6eR/Build/Products/Debug/FeishuSpeech.app/Contents/PlugIns/FeishuSpeechTests.xctest`.
- Independent strict SwiftLint passed with 0 violations across 26 production files.
- Independent `git diff --check` passed with no output.
- Supplied current-candidate build-for-testing evidence ends with `TEST BUILD SUCCEEDED` in `/tmp/issue26-uat2-baseline.cXr6eR/final-build.log`.
- No application was launched, no credential was accessed, and no macOS permission request was triggered during review.

verdict: pass
findings_blocking: 0
review_conclusion: The candidate closes the recursive error teardown, preserves protected output behavior, and proves one terminal cleanup with reliable overlay dismissal.
