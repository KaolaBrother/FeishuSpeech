# Issue 27 review RED: R1-R4

## Record

- Reviewed baseline: `62832ad28ce13c8fa31320cfe194da0df9610cac`
- Test-only commit: `25aa505445a597abdf1b53964992b10da4fb645f`
- Test artifact: `FeishuSpeechTests/StreamingMainViewModelTests.swift`
- Production files were not edited or staged.

## R1 - AX action-2 acknowledgement

Test: `test_axOwnerDriftBeforeDifferingActionTwoPreservesPartialAndPublishesNonSuccess`

The test commits a held AX partial, moves the selected range before a differing action-2 final, and requires:

- no second AX write;
- the already visible partial remains unchanged;
- exactly one `.provisionalOutputPreserved` completion;
- no normal-success/error state, transcript-bearing feedback, one-shot fallback, or clipboard output.

Baseline failure signature:

`XCTAssertEqual failed: ("[]") is not equal to ("[FeishuSpeech.RecordingState.provisionalOutputPreserved]")`

The safety half already passes: the final write is correctly rejected and the partial is preserved. The RED assertion proves the coordinator currently misreports that rejection as normal success.

## R2 - typed drain-expiry classification

Tests:

- existing committed-output leg: `test_postReleaseDrainExpiryPreservesOutputAndSuppressesLatePacketCompletion`;
- new no-output/keyboard-LF leg: `test_postReleaseDrainExpiryReportsFixedFailureWhenNoSafeOutputWasCommitted`;
- new uncertain-delivery leg: `test_postReleaseDrainExpiryMapsUncertainKeyboardDeliveryToProvisionalPreserved`.

The no-output test covers both contentless input and an LF snapshot rejected specifically by the fixed-PID keyboard route. It requires no append transaction, no fallback output, and the fixed transcript-free `流式识别失败` error. The contentless case already follows this branch; the LF case demonstrates the classification gap.

LF baseline signatures:

- `XCTAssertEqual failed: ("[FeishuSpeech.RecordingState.emptyFinalPreservedPartial]") is not equal to ("[]")`
- `XCTAssertEqual failed: ("[]") is not equal to ("[\"流式识别失败\"]")`

Uncertain-delivery baseline signature:

`XCTAssertEqual failed: ("[FeishuSpeech.RecordingState.emptyFinalPreservedPartial]") is not equal to ("[FeishuSpeech.RecordingState.provisionalOutputPreserved]")`

Together the oracle requires:

- verified committed output -> `.emptyFinalPreservedPartial`;
- no safe committed output, including route-rejected LF -> fixed streaming failure;
- keyboard delivery uncertainty -> `.provisionalOutputPreserved`.

All no-copy, no-one-shot, no-synthetic-input, and transcript-redaction assertions remain explicit.

## R3 - atomic monotonic deadline admission

Tests:

- `test_packetReadyAtDrainDeadlineIsRejectedBeforeOutputEvenBeforeExpiryTaskRuns`;
- `test_finishReadyAtDrainDeadlineCannotReplaceCommittedPartialBeforeExpiryTaskRuns`;
- `test_zeroRemainingDrainBudgetFailsSynchronouslyWithoutStartingFinishOperation`.

These tests use a scripted monotonic time source and real controlled packet/finish continuations. The actual expiry task is intentionally configured one real second in the future, so the tests isolate the operation gate rather than relying on task scheduling.

Required behavior:

- a packet becoming ready exactly at the monotonic deadline cannot claim ownership or write;
- a finish becoming ready exactly at the deadline cannot replace a committed partial, which receives partial-preserved feedback;
- zero remaining budget fails before the operation task is created, so `finish()` is never called.

The reviewed baseline has no injectable monotonic-now seam. The tests therefore produce the accepted minimal compile RED:

- `StreamingMainViewModelTests.swift:1974:36: error: extra argument 'streamingMonotonicNow' in call`
- repeated for the finish and zero-budget tests at lines 2029 and 2087.

The anticipated seam is one initializer dependency with production default `ContinuousClock.now`:

`streamingMonotonicNow: @Sendable () -> ContinuousClock.Instant`

No production clock semantics are mocked; only the current monotonic instant is controlled.

## R4 - external cancellation settles the factory gate

Tests:

- `test_externalResetSettlesFactoryGateAndCancelsNonCooperativeLateSessionOnce`;
- `test_drainExpirySettlesFactoryGateAndCancelsNonCooperativeLateSessionOnce`.

The provider deliberately ignores task cancellation and returns a session only after reset or drain expiry has invalidated the generation. Both tests require the returned session to take the late-success path and be cancelled exactly once, with zero packet and finish calls.

Baseline signatures for both reset and expiry:

- `failed - timed out waiting for streaming coordinator state`
- `XCTAssertEqual failed: ("0") is not equal to ("1")`

The timeout is the awaited late-session cancel count; the explicit assertion confirms it remains zero because the abandoned iterator left the race gate open.

## Commands and evidence

Behavioral RED build before adding the clock-dependent R3 tests:

`xcodebuild -project FeishuSpeech.xcodeproj -scheme FeishuSpeech -destination 'platform=macOS' -derivedDataPath /tmp/feishuspeech-issue27-review-r1-r4 build-for-testing`

Behavioral RED execution:

`xcrun xctest -XCTest FeishuSpeechTests.StreamingMainViewModelTests /tmp/feishuspeech-issue27-review-r1-r4/Build/Products/Debug/FeishuSpeech.app/Contents/PlugIns/FeishuSpeechTests.xctest`

Evidence: `/tmp/feishuspeech-issue27-review-r1-r2-r4-red.log`

Final R3 compile-RED command:

`xcodebuild -project FeishuSpeech.xcodeproj -scheme FeishuSpeech -destination 'platform=macOS' -derivedDataPath /tmp/feishuspeech-issue27-review-r1-r4-final build-for-testing`

Evidence: `/tmp/feishuspeech-issue27-review-r3-compile-red.log`

`git diff --check` passed before commit. No green-suite verdict is claimed by test custody.
