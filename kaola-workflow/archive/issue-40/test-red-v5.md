# Issue #40 v5 TDD RED receipt

Date: 2026-08-24 (Asia/Shanghai)

## Custody and baseline

- Test author custody only; production was not edited by this lane.
- Rejected production baseline: `b321ac5d6c04c91ced9afeb2240f9566d9b8d305` (`git rev-parse HEAD`).
- The only pre-existing production worktree change is the behavior-preserving visibility seam in `FeishuSpeech/Services/ReviewDestinationDelivery.swift`: `private final class ReviewDeliveryMonitoringSession` -> `final class ReviewDeliveryMonitoringSession`.
- Seam diff SHA-256 (exact command: `git diff -- FeishuSpeech/Services/ReviewDestinationDelivery.swift | shasum -a 256`): `96ac2b0140f9b2b03b486ddc0c589284335efd902a21d172e0079e2d691d941a`.
- Runtime corroboration: [/tmp/FeishuSpeech_2026-08-24_084734_25BZ.sample.txt](/tmp/FeishuSpeech_2026-08-24_084734_25BZ.sample.txt), which shows `ReviewDeliveryMonitoringSession.performFinalPair` -> `WorkspaceCurrentFocusInputMonitor.postCompleteSyntheticPairIfInterferenceEpochIsUnchanged` -> nested `interferenceEpoch` getter waiting on the same nonrecursive mutex.

## Tests added

Test-only changes are limited to:

- `FeishuSpeechTests/FinalTextOutputSecurityTests.swift`
  - `test_baselineProductionFinalPairDetectsReentrantEpochAccessWithoutHanging`
  - `test_productionCommitGateNeverReentersNonrecursiveEpochLock`
  - `test_combinedEpochDriftBeforeCommitPostsNothing`
  - `ReentrancyDetectingInputMonitor` is an immediate-return diagnostic fixture; it does not call the real deadlocking lock.
- `FeishuSpeechTests/ReviewWindowControllerReadinessTests.swift`
  - `test_nonactivatingEditablePanelBecomesKeyWithoutActivatingFeishuSpeech`
  - `test_nonactivatingPanelKeepsCapturedTargetFrontmost`
  - `test_focusFailureKeepsVisibleSendAndDoesNotInstallGlobalReturnCapture`
- `FeishuSpeechTests/TranscriptionReviewViewTests.swift`
  - `test_v5SendButtonHasNoDefaultKeyEquivalent`
  - `test_exactUnmodifiedNonrepeatReturnThroughKeyPanelConfirmsExactlyOnce`
  - `test_exactUnmodifiedNonrepeatKeypadEnterThroughKeyPanelConfirmsExactlyOnce`
  - `test_controlReturnAndControlKeypadEnterProduceZeroIntentAndZeroDelivery`
  - native `NSEvent` dispatch uses `NSApp.sendEvent` for the added Return tests.

Existing coordinator tests remain authoritative for pre-confirm zero-output, exact draft/revision retention, one-shot confirmation, cancellation, delivery failure, uncertainty, and presentation-focus telemetry. No existing security/application-bound/multiline/stale-callback oracle was weakened.

## RED commands and exact failures

All commands were serialized with `-parallel-testing-enabled NO` on macOS.

1. Immediate seam oracle:

```text
xcodebuild -scheme FeishuSpeech -destination 'platform=macOS' \
  -parallel-testing-enabled NO \
  -only-testing:FeishuSpeechTests/FinalTextOutputSecurityTests/test_baselineProductionFinalPairDetectsReentrantEpochAccessWithoutHanging test
```

Result: **RED**, 1 test / 1 failure, 0.120 s. Failure:

```text
FinalTextOutputSecurityTests.test_baselineProductionFinalPairDetectsReentrantEpochAccessWithoutHanging
XCTAssertEqual failed: ("1") is not equal to ("0")
the production commit gate must not read interferenceEpoch again from inside its epoch gate
```

Result bundle: `/Users/ylpromax5/Library/Developer/Xcode/DerivedData/FeishuSpeech-cgiyjqtocfbabebmiznsskomsotp/Logs/Test/Test-FeishuSpeech-2026.08.24_10-23-26-+0800.xcresult`.

This is the required immediate non-hanging RED: the fake gate returned immediately and recorded exactly one nested epoch access; no real production lock was invoked.

2. Non-activating panel/readiness selectors:

```text
xcodebuild -scheme FeishuSpeech -destination 'platform=macOS' \
  -parallel-testing-enabled NO \
  -only-testing:FeishuSpeechTests/ReviewWindowControllerReadinessTests/test_nonactivatingEditablePanelBecomesKeyWithoutActivatingFeishuSpeech \
  -only-testing:FeishuSpeechTests/ReviewWindowControllerReadinessTests/test_nonactivatingPanelKeepsCapturedTargetFrontmost test
```

Result: **RED**, 2 tests / 4 failures, 0.109 s. Failures:

```text
test_nonactivatingEditablePanelBecomesKeyWithoutActivatingFeishuSpeech
XCTAssertTrue failed - the review panel must be non-activating so the captured target remains frontmost
XCTAssertTrue failed - the non-activating review panel must become key only when explicitly needed
test_nonactivatingPanelKeepsCapturedTargetFrontmost
XCTAssertEqual failed: ("1") is not equal to ("0") - focus assistance must not activate FeishuSpeech or steal the captured target
XCTAssertTrue failed - nonactivating style assertion
```

Result bundle: `/Users/ylpromax5/Library/Developer/Xcode/DerivedData/FeishuSpeech-cgiyjqtocfbabebmiznsskomsotp/Logs/Test/Test-FeishuSpeech-2026.08.24_10-23-54-+0800.xcresult`.

3. Native Return/default-button selectors:

```text
xcodebuild -scheme FeishuSpeech -destination 'platform=macOS' \
  -parallel-testing-enabled NO \
  -only-testing:FeishuSpeechTests/TranscriptionReviewViewTests/test_v5SendButtonHasNoDefaultKeyEquivalent \
  -only-testing:FeishuSpeechTests/TranscriptionReviewViewKeyboardTests/test_exactUnmodifiedNonrepeatReturnThroughKeyPanelConfirmsExactlyOnce \
  -only-testing:FeishuSpeechTests/TranscriptionReviewViewKeyboardTests/test_exactUnmodifiedNonrepeatKeypadEnterThroughKeyPanelConfirmsExactlyOnce \
  -only-testing:FeishuSpeechTests/TranscriptionReviewViewKeyboardTests/test_controlReturnAndControlKeypadEnterProduceZeroIntentAndZeroDelivery test
```

The initial run used the equivalent combined native selector before the final test-name split. It executed 3 tests: the two native Return/Control paths passed, while the default-key-equivalent oracle failed:

```text
TranscriptionReviewViewTests.test_v5SendButtonHasNoDefaultKeyEquivalent
XCTAssertFalse failed - Send must be an explicit button intent, not an AppKit default Return key equivalent
```

The native unmodified Return/keypad and Control+Return/keypad tests therefore have executable coverage against the real AppKit event path; their baseline behavior is recorded as passing while the independent default-button acceptance is RED. The corresponding result bundle is `/Users/ylpromax5/Library/Developer/Xcode/DerivedData/FeishuSpeech-cgiyjqtocfbabebmiznsskomsotp/Logs/Test/Test-FeishuSpeech-2026.08.24_10-24-09-+0800.xcresult`.

## Scope note

The v5 submission-control-plane/executor surface is not yet present in the baseline production tree, so no test invented a parallel fake executor or called nonexistent APIs. Existing coordinator tests continue to exercise the safe public/internal state surface for pre-boundary and post-boundary draft/authority/zero-output behavior; the production owner must reconcile the deadline/FIFO/one-shot/cancellation/executor contracts after this RED receipt, then these test oracles can be extended against the concrete production types.

`git diff --check` passed after the test edits.

The blueprint focused security command was also run serialized:

```text
xcodebuild -scheme FeishuSpeech -destination 'platform=macOS' \
  -parallel-testing-enabled NO \
  -only-testing:FeishuSpeechTests/FinalTextOutputSecurityTests \
  -only-testing:FeishuSpeechTests/CurrentFocusAppendSessionTests test
```

Result: **RED**, 73 tests / 2 failures / 0 unexpected, 0.289 s of test execution. The 38
`CurrentFocusAppendSessionTests` all passed; 33 of 35 `FinalTextOutputSecurityTests` passed and the only
failures were the two new reentrancy oracles above. Result bundle:
`/Users/ylpromax5/Library/Developer/Xcode/DerivedData/FeishuSpeech-cgiyjqtocfbabebmiznsskomsotp/Logs/Test/Test-FeishuSpeech-2026.08.24_10-30-13-+0800.xcresult`.

The coordinator/lifecycle focused command was run separately to preserve the existing v4 state and
zero-output oracles while the v5 production surface is absent:

```text
xcodebuild -scheme FeishuSpeech -destination 'platform=macOS' \
  -parallel-testing-enabled NO \
  -only-testing:FeishuSpeechTests/ReviewFirstMainViewModelTests \
  -only-testing:FeishuSpeechTests/ReviewFirstApplicationFallbackTests \
  -only-testing:FeishuSpeechTests/StreamingMainViewModelTests test
```

It executed 152 tests with 0 failures in 7.938 s; this is supporting baseline evidence only. Result bundle:
`/Users/ylpromax5/Library/Developer/Xcode/DerivedData/FeishuSpeech-cgiyjqtocfbabebmiznsskomsotp/Logs/Test/Test-FeishuSpeech-2026.08.24_10-30-48-+0800.xcresult`.

## Final post-split selector snapshot

After splitting the native Return tests to the exact blueprint selectors and removing two non-oracle
`NSButton` unwraps that were not materialized by SwiftUI in this headless host, the complete added selector
set was rerun in one serialized command (10 tests):

```text
xcodebuild -scheme FeishuSpeech -destination 'platform=macOS' -parallel-testing-enabled NO \
  -only-testing:FeishuSpeechTests/FinalTextOutputSecurityTests/test_baselineProductionFinalPairDetectsReentrantEpochAccessWithoutHanging \
  -only-testing:FeishuSpeechTests/FinalTextOutputSecurityTests/test_productionCommitGateNeverReentersNonrecursiveEpochLock \
  -only-testing:FeishuSpeechTests/FinalTextOutputSecurityTests/test_combinedEpochDriftBeforeCommitPostsNothing \
  -only-testing:FeishuSpeechTests/ReviewWindowControllerReadinessTests/test_nonactivatingEditablePanelBecomesKeyWithoutActivatingFeishuSpeech \
  -only-testing:FeishuSpeechTests/ReviewWindowControllerReadinessTests/test_nonactivatingPanelKeepsCapturedTargetFrontmost \
  -only-testing:FeishuSpeechTests/ReviewWindowControllerReadinessTests/test_focusFailureKeepsVisibleSendAndDoesNotInstallGlobalReturnCapture \
  -only-testing:FeishuSpeechTests/TranscriptionReviewViewTests/test_v5SendButtonHasNoDefaultKeyEquivalent \
  -only-testing:FeishuSpeechTests/TranscriptionReviewViewKeyboardTests/test_exactUnmodifiedNonrepeatReturnThroughKeyPanelConfirmsExactlyOnce \
  -only-testing:FeishuSpeechTests/TranscriptionReviewViewKeyboardTests/test_exactUnmodifiedNonrepeatKeypadEnterThroughKeyPanelConfirmsExactlyOnce \
  -only-testing:FeishuSpeechTests/TranscriptionReviewViewKeyboardTests/test_controlReturnAndControlKeypadEnterProduceZeroIntentAndZeroDelivery test
```

Result: **RED**, 10 tests / 7 failures / 0 unexpected, 0.381 s. The three deterministic baseline failures are:

```text
FinalTextOutputSecurityTests.test_baselineProductionFinalPairDetectsReentrantEpochAccessWithoutHanging
XCTAssertEqual ("1") != ("0")
FinalTextOutputSecurityTests.test_productionCommitGateNeverReentersNonrecursiveEpochLock
XCTAssertEqual ("1") != ("0")
TranscriptionReviewViewTests.test_v5SendButtonHasNoDefaultKeyEquivalent
XCTAssertFalse failed - Send must be an explicit button intent, not an AppKit default Return key equivalent
```

The non-activating panel selectors add four expected current-production failures (style-mask,
`becomesKeyOnlyIfNeeded`, activation count), while
`test_focusFailureKeepsVisibleSendAndDoesNotInstallGlobalReturnCapture` and all three native event-routing
selectors passed. Result bundle:
`/Users/ylpromax5/Library/Developer/Xcode/DerivedData/FeishuSpeech-cgiyjqtocfbabebmiznsskomsotp/Logs/Test/Test-FeishuSpeech-2026.08.24_10-28-29-+0800.xcresult`.
