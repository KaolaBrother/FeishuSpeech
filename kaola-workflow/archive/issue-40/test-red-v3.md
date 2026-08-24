# Issue #40 v3 UAT test-author RED receipt

Date: 2026-08-23 (Asia/Shanghai)

## Baseline

The focused RED runs were executed against the installed-UAT candidate and
current worktree `HEAD`:

`aec7aad8ca29eab8cbde90b23be5dbe66ce454e2` (`aec7aad`)

This is a baseline receipt, not a production implementation receipt. I only
edited test artifacts under `FeishuSpeechTests/` and the assigned receipt; no
production, documentation, mission-list, or architecture files were edited by
this test-author run. A concurrent production edit visible in the shared
worktree was preserved and not reverted.

## Acceptance tests authored

In `FeishuSpeechTests/TranscriptionReviewViewTests.swift`:

- `test_transcriptFontIsMateriallyLargerInStreamingAndEditableSurfaces`
  materializes the streaming/read-only SwiftUI surface and native editable
  `NSTextView`, requires both measured fonts to be at least 18pt, and requires
  the two surfaces to use the same measured size.
- `test_frozenDraftExposesSendAndReturnWithoutRetryEditingControl` requires
  the obsolete `重试编辑` text/control to be absent from the production view,
  requires the explicit `Button("发送")` confirmation control, and checks the
  pending/editable rendered surfaces for the removed control.
- `test_streamingReviewContentDoesNotIntersectTrafficLightControls` renders
  the real `ReviewWindowController`/`ReviewPanel` and checks the content frame
  against all three real titlebar traffic-light button frames.
- `test_reviewPanelRetainsExistingSizeAcrossStreamingAndEditableStates`
  captures the real panel size during streaming and asserts the same panel
  size after sealing and editable rendering.

In `FeishuSpeechTests/ReviewFirstMainViewModelTests.swift`:

- `test_reviewFirst_realProductionSurfaceMakesFrozenDraftConfirmableWithoutRetryEditing`
  drives the real production review controller through MainViewModel's
  streaming-to-sealing path. It proves a real editable `NSTextView` materializes
  and is attached to the retained `ReviewPanel`, readiness requests that real
  editor as first responder, the state becomes `.editable`, no delivery or
  accessibility/direct output occurs before confirmation, and the exact draft
  is delivered once only after the explicit confirm callback. A deterministic
  first-responder probe is used because headless AppKit may not install an OS
  first responder; production editor lookup and attachment predicates remain
  live and are not injected.

In `FeishuSpeechTests/ReviewWindowControllerReadinessTests.swift`:

- `test_activationRequestFailureIsAdvisoryWhenPredicatesAreReady` replaces the
  obsolete immediate `activationRejected` oracle and requires `.ready` when
  the real application/key/editor/first-responder predicates are ready.
- `test_activationRequestFailurePollsDelayedPredicatesUntilReady` requires
  polling through delayed application and panel-key readiness after the
  activation request returns false.
- `test_activationRequestFailureWithNeverReadyPredicatesTimesOutWithActualPredicate`
  requires typed `.timedOut(lastUnmet: .applicationActive)` and retained panel
  authority when actual readiness never becomes true.

## Serialized baseline RED run

Command:

```text
set -o pipefail; xcodebuild -scheme FeishuSpeech -destination 'platform=macOS' -derivedDataPath /tmp/issue40-v3-red-ui-derived-4 -only-testing:FeishuSpeechTests/TranscriptionReviewViewTests/test_transcriptFontIsMateriallyLargerInStreamingAndEditableSurfaces -only-testing:FeishuSpeechTests/TranscriptionReviewViewTests/test_frozenDraftExposesSendAndReturnWithoutRetryEditingControl -only-testing:FeishuSpeechTests/TranscriptionReviewViewTests/test_streamingReviewContentDoesNotIntersectTrafficLightControls -only-testing:FeishuSpeechTests/TranscriptionReviewViewTests/test_reviewPanelRetainsExistingSizeAcrossStreamingAndEditableStates test -parallel-testing-enabled NO -maximum-parallel-testing-workers 1 2>&1 | tee /tmp/issue40-v3-red-ui-final-3.log
```

Result: exit 65. `TranscriptionReviewViewTests` executed 4 tests with 6
failures (0 unexpected). The panel-size guard passed. The exact baseline
failures were:

- `test_frozenDraftExposesSendAndReturnWithoutRetryEditingControl`: line 75,
  `XCTAssertFalse failed - the frozen editable review must not expose the
  obsolete retry-editing control or text`.
- `test_streamingReviewContentDoesNotIntersectTrafficLightControls`: line 161,
  the same `XCTAssertTrue` failed three times, once for each traffic-light
  button, with `read-only streaming content must stay below and clear of
  titlebar traffic-light controls`.
- `test_transcriptFontIsMateriallyLargerInStreamingAndEditableSurfaces`: line
  34, measured streaming/read-only font `13.0` is less than required `18.0`;
  line 60, measured editable font `13.0` is less than required `18.0`.

The Xcode result bundle is:

`/tmp/issue40-v3-red-ui-derived-4/Logs/Test/Test-FeishuSpeech-2026.08.23_17-37-52-+0800.xcresult`

The raw log is `/tmp/issue40-v3-red-ui-final-3.log`.

## Readiness activation-advisory RED run

The focused readiness suite was run serialized against the same baseline SHA:

```text
set -o pipefail; xcodebuild -scheme FeishuSpeech -destination 'platform=macOS' -derivedDataPath /tmp/issue40-v3-readiness-red-derived -only-testing:FeishuSpeechTests/ReviewWindowControllerReadinessTests test -parallel-testing-enabled NO -maximum-parallel-testing-workers 1 2>&1 | tee /tmp/issue40-v3-readiness-red.log
```

Result: exit 65. `ReviewWindowControllerReadinessTests` executed 10 tests with
6 failures (0 unexpected); the existing readiness/security tests passed. The
exact failures proving the pre-repair behavior were:

- `test_activationRequestFailureIsAdvisoryWhenPredicatesAreReady`: line 35,
  actual `pending(activationRejected)` was not expected `.ready`.
- `test_activationRequestFailurePollsDelayedPredicatesUntilReady`: line 67,
  actual `pending(activationRejected)` was not expected `.ready`; lines 72-74
  also showed zero sleeps/application checks/panel-key checks, proving no
  readiness polling occurred.
- `test_activationRequestFailureWithNeverReadyPredicatesTimesOutWithActualPredicate`:
  line 95, actual `pending(activationRejected)` was not expected typed
  `pending(timedOut(lastUnmet: applicationActive))`.

The Xcode result bundle is:

`/tmp/issue40-v3-readiness-red-derived/Logs/Test/Test-FeishuSpeech-2026.08.23_17-41-09-+0800.xcresult`

The raw log is `/tmp/issue40-v3-readiness-red.log`.

## Coordinator proof run

The real production-window coordinator case was run serialized with:

```text
set -o pipefail; xcodebuild -scheme FeishuSpeech -destination 'platform=macOS' -derivedDataPath /tmp/issue40-v3-red-coordinator-derived-3 -only-testing:FeishuSpeechTests/ReviewFirstMainViewModelTests/test_reviewFirst_realProductionSurfaceMakesFrozenDraftConfirmableWithoutRetryEditing test -parallel-testing-enabled NO -maximum-parallel-testing-workers 1 2>&1 | tee /tmp/issue40-v3-red-coordinator-final-2.log
```

It compiled and exercised the retained production panel/editor/readiness path
against the same `aec7aad` baseline. The coordinator case completed without
assertion failures; the UI acceptance cases above remain RED and are the
falsifying evidence for the installed-UAT defects. The Xcode result bundle is:

`/tmp/issue40-v3-red-coordinator-derived-3/Logs/Test/Test-FeishuSpeech-2026.08.23_17-36-36-+0800.xcresult`

## Hygiene

`git diff --check` passed after the final test edits. The worktree changes are
limited to:

- `FeishuSpeechTests/ReviewFirstMainViewModelTests.swift`
- `FeishuSpeechTests/ReviewWindowControllerReadinessTests.swift`
- `FeishuSpeechTests/TranscriptionReviewViewTests.swift`

## Delivery-uncertain duplicate-warning RED follow-up

The current production tree still has the baseline commit
`aec7aad8ca29eab8cbde90b23be5dbe66ce454e2` plus uncommitted concurrent
production edits. I added the test-only oracle
`test_deliveryUncertainFeedbackWarnsAboutPossibleDuplicateSendWithoutRetryEditing`
in `FeishuSpeechTests/TranscriptionReviewViewTests.swift`. It requires the
delivery-uncertain fixed feedback to explicitly contain both `再次发送` and
`重复`, while requiring that `重试编辑` remains absent.

Exact serialized RED command:

```text
set -o pipefail; xcodebuild -scheme FeishuSpeech -destination 'platform=macOS' -derivedDataPath /tmp/issue40-v3-red-delivery-uncertain-derived-2 -only-testing:FeishuSpeechTests/TranscriptionReviewViewTests/test_deliveryUncertainFeedbackWarnsAboutPossibleDuplicateSendWithoutRetryEditing test -parallel-testing-enabled NO -maximum-parallel-testing-workers 1 2>&1 | tee /tmp/issue40-v3-red-delivery-uncertain-2.log
```

Result: exit 65. One test executed, one failure. Failure signature:

```text
TranscriptionReviewViewTests.test_deliveryUncertainFeedbackWarnsAboutPossibleDuplicateSendWithoutRetryEditing
XCTAssertTrue failed - delivery uncertainty feedback must explicitly warn that another Send may duplicate prior output
```

The failing assertion is at
`FeishuSpeechTests/TranscriptionReviewViewTests.swift:130`; the current
production copy is `输入状态不确定；请确认后再发送。`, which does not warn that
another explicit send may duplicate prior output. `重试编辑` remains absent,
so the failure is specifically the missing duplication warning rather than a
request to restore the removed action.

XCTest result:
`/tmp/issue40-v3-red-delivery-uncertain-derived-2/Logs/Test/Test-FeishuSpeech-2026.08.23_17-54-44-+0800.xcresult`

Raw log: `/tmp/issue40-v3-red-delivery-uncertain-2.log`.

## Activation-failure copy RED follow-up

In the same test-only feedback pass I added
`test_activationFailedFeedbackNamesTargetApplicationWithoutPreparationOrRetryText`.
It requires the fixed `.activationFailed` feedback to name target application
activation failure with an explicit-send instruction, accepts the canonical
copy `无法激活目标应用；请确认后再发送。`, rejects the stale preparation copy
`编辑器正在准备，请稍候。`, and continues to reject `重试编辑`.

Exact combined serialized RED command:

```text
set -o pipefail; xcodebuild -scheme FeishuSpeech -destination 'platform=macOS' -derivedDataPath /tmp/issue40-v3-red-feedback-derived -only-testing:FeishuSpeechTests/TranscriptionReviewViewTests/test_deliveryUncertainFeedbackWarnsAboutPossibleDuplicateSendWithoutRetryEditing -only-testing:FeishuSpeechTests/TranscriptionReviewViewTests/test_activationFailedFeedbackNamesTargetApplicationWithoutPreparationOrRetryText test -parallel-testing-enabled NO -maximum-parallel-testing-workers 1 2>&1 | tee /tmp/issue40-v3-red-feedback.log
```

Result: exit 65. Two tests executed, three assertion failures:

```text
TranscriptionReviewViewTests.test_activationFailedFeedbackNamesTargetApplicationWithoutPreparationOrRetryText
XCTAssertTrue failed - activation failure after readiness must name target application activation and require explicit confirmation
XCTAssertFalse failed - activation failure must not claim the editor is still preparing after readiness failed

TranscriptionReviewViewTests.test_deliveryUncertainFeedbackWarnsAboutPossibleDuplicateSendWithoutRetryEditing
XCTAssertTrue failed - delivery uncertainty feedback must explicitly warn that another Send may duplicate prior output
```

The activation failure assertions are at
`FeishuSpeechTests/TranscriptionReviewViewTests.swift:158` and `:162`; the
delivery-uncertain assertion is at line `130`. `重试编辑` stayed absent in both
runtime states, so these RED failures isolate the two fixed-feedback copy
regressions. XCTest result:
`/tmp/issue40-v3-red-feedback-derived/Logs/Test/Test-FeishuSpeech-2026.08.23_17-56-12-+0800.xcresult`

Raw log: `/tmp/issue40-v3-red-feedback.log`.

The existing coordinator oracle was also rerun to ensure the copy regression
did not weaken delivery uncertainty custody:

```text
set -o pipefail; xcodebuild -scheme FeishuSpeech -destination 'platform=macOS' -derivedDataPath /tmp/issue40-v3-red-feedback-coordinator-derived -only-testing:FeishuSpeechTests/ReviewFirstMainViewModelTests/test_reviewFirst_nonCancellationDeliveryFailureReturnsFrozenDraftToEditableWithoutRecoveryCopy test -parallel-testing-enabled NO -maximum-parallel-testing-workers 1 2>&1 | tee /tmp/issue40-v3-red-feedback-coordinator.log
```

Result: `ReviewFirstMainViewModelTests.test_reviewFirst_nonCancellationDeliveryFailureReturnsFrozenDraftToEditableWithoutRecoveryCopy` — 1 executed, 0 failures; `** TEST SUCCEEDED **`.
This loop retains the exact frozen draft and authority, asserts no recovery copy/direct output, and invokes the accepted draft-change callback after `.deliveryUncertain` to clear feedback without auto-retry.

XCTest result:
`/tmp/issue40-v3-red-feedback-coordinator-derived/Logs/Test/Test-FeishuSpeech-2026.08.23_17-56-53-+0800.xcresult`

Raw log: `/tmp/issue40-v3-red-feedback-coordinator.log`.
