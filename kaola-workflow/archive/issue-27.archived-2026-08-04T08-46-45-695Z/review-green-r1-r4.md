# Issue 27 review GREEN: R1-R4

## Record

- Assigned task: repair independently reproduced lifecycle findings R1-R4 against test commit `25aa505`.
- Verification tier: `tests-green`.
- Production commit: `cbbbf2f fix: close streaming drain lifecycle races`.
- Production file changed: `FeishuSpeech/ViewModels/MainViewModel.swift`.
- `FeishuSpeech/Models/StreamingSpeechModels.swift` remained unchanged in this correction.
- No test, documentation, project-version, or workflow file was edited or committed by the implementing role.

## Baseline

Command:

```text
xcodebuild -project FeishuSpeech.xcodeproj -scheme FeishuSpeech -destination 'platform=macOS' -derivedDataPath /tmp/feishuspeech-issue27-review-r1-r4-impl build-for-testing
```

Result: exit `65`, `** TEST BUILD FAILED **`.

The baseline failed on the three R3 tests because `MainViewModel` did not accept the injected `streamingMonotonicNow` seam. The compiler reported `extra argument 'streamingMonotonicNow' in call`. Evidence: `/tmp/feishuspeech-issue27-review-r1-r4-impl-baseline.log`.

## Per-finding repair evidence

### R1 - AX terminal acknowledgement

The coordinator now inspects `CursorTextSession.state` after action-2 finalization. Only `.committed` is recorded as authoritative success. `.invalid` or any other uncommitted state records delivery uncertainty and publishes transcript-free `.provisionalOutputPreserved` feedback while preserving the existing visible partial.

Test: `test_axOwnerDriftBeforeDifferingActionTwoPreservesPartialAndPublishesNonSuccess` — passed.

### R2 - typed drain-expiry classification

The former recognition-presence boolean was replaced by typed output state: `none`, `committedSafe`, or `deliveryUncertain`. State changes are derived from verified AX session states and current-focus apply/final outcomes, not merely from receiving nonempty recognition text.

Drain expiry mapping:

- `committedSafe` -> `.emptyFinalPreservedPartial`;
- `deliveryUncertain` -> `.provisionalOutputPreserved`;
- `none` -> fixed `流式识别失败` error.

Tests:

- `test_postReleaseDrainExpiryReportsFixedFailureWhenNoSafeOutputWasCommitted` — passed.
- `test_postReleaseDrainExpiryMapsUncertainKeyboardDeliveryToProvisionalPreserved` — passed.
- Existing committed-output drain-expiry coverage also passed in the 91-test coordinator suite.

### R3 - atomic monotonic deadline admission

`MainViewModel` now accepts the minimal production-defaulted monotonic-now closure. The same lock-backed operation race gate checks the live post-release deadline immediately before claiming success. At or beyond the deadline, the result is rejected before output admission. A zero remaining budget returns `.timeout` before creating the operation task.

Tests:

- `test_packetReadyAtDrainDeadlineIsRejectedBeforeOutputEvenBeforeExpiryTaskRuns` — passed.
- `test_finishReadyAtDrainDeadlineCannotReplaceCommittedPartialBeforeExpiryTaskRuns` — passed.
- `test_zeroRemainingDrainBudgetFailsSynchronouslyWithoutStartingFinishOperation` — passed.

### R4 - parent cancellation settles the factory gate

The watched operation now uses a cancellation handler that settles the shared gate and finishes its stream before cancelling worker/watchdog tasks. A noncooperative factory returning later therefore takes `onLateSuccess`, and the returned session is cancelled exactly once rather than entering an abandoned success path.

Tests:

- `test_externalResetSettlesFactoryGateAndCancelsNonCooperativeLateSessionOnce` — passed.
- `test_drainExpirySettlesFactoryGateAndCancelsNonCooperativeLateSessionOnce` — passed.

## Final verification

### Build for testing

Command:

```text
xcodebuild -project FeishuSpeech.xcodeproj -scheme FeishuSpeech -destination 'platform=macOS' -derivedDataPath /tmp/feishuspeech-issue27-review-r1-r4-impl build-for-testing
```

Result: exit `0`, `** TEST BUILD SUCCEEDED **`.

### Eight review finding tests

Command: direct XCTest selection of the eight R1-R4 methods in `StreamingMainViewModelTests`.

Result: exit `0`; 8 tests executed, 0 failures. Evidence: `/tmp/feishuspeech-issue27-review-r1-r4-focused-final.log`.

### Full streaming coordinator suite

Command:

```text
xcrun xctest -XCTest 'FeishuSpeechTests.StreamingMainViewModelTests' /tmp/feishuspeech-issue27-review-r1-r4-impl/Build/Products/Debug/FeishuSpeech.app/Contents/PlugIns/FeishuSpeechTests.xctest
```

Result: exit `0`; 91 tests executed, 0 failures. Evidence: `/tmp/feishuspeech-issue27-review-r1-r4-streaming.log`.

### Full authored suite

Command:

```text
xcrun xctest /tmp/feishuspeech-issue27-review-r1-r4-impl/Build/Products/Debug/FeishuSpeech.app/Contents/PlugIns/FeishuSpeechTests.xctest
```

Result: exit `0`; 316 tests executed, 0 failures in 6.208 seconds. Evidence: `/tmp/feishuspeech-issue27-review-r1-r4-full.log`.

### Strict lint

Command:

```text
swiftlint lint --strict FeishuSpeech/ViewModels/MainViewModel.swift FeishuSpeech/Models/StreamingSpeechModels.swift
```

Result: exit `0`; 0 violations, 0 serious violations.

### Debug build

Command:

```text
xcodebuild -project FeishuSpeech.xcodeproj -scheme FeishuSpeech -configuration Debug -derivedDataPath /tmp/feishuspeech-issue27-review-r1-r4-debug build
```

Result: exit `0`, `** BUILD SUCCEEDED **`.

### Integrity, scope, and privacy

- `git diff --check` exited `0`.
- Commit `cbbbf2f` contains only `FeishuSpeech/ViewModels/MainViewModel.swift`.
- No transcript, credentials, API bodies, accessibility target content, or content hashes were added to logs.
- New diagnostics expose only typed preservation state and existing generation/attempt/operation metadata.
- The issue worktree was clean after the production commit; generated `default.profraw` was removed before commit.

## Result location

The repair landed in commit `cbbbf2f` in the issue-27 worktree. This receipt is stored at `kaola-workflow/issue-27/review-green-r1-r4.md` in the root checkout.
