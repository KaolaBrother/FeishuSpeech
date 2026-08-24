# Issue #40 v3 test receipt

Date: 2026-08-23 (Asia/Shanghai)

Baseline RED: `aec7aad8ca29eab8cbde90b23be5dbe66ce454e2` (`aec7aad`). The RED runs were executed against that exact commit before the visible v3 production repair. The current tree still has concurrent, uncommitted production changes in `FeishuSpeech/Controllers/ReviewWindowController.swift` and `FeishuSpeech/Views/TranscriptionReviewView.swift`; this test-author run did not edit or revert them.

## RED to GREEN delta

- UI/font/titlebar/no-retry/panel-size oracle: baseline `TranscriptionReviewViewTests`, 4 selected tests, 6 failures (obsolete `重试编辑`, transcript font 13.0 below the required 18pt, and three traffic-light overlap assertions); current run: 8 tests, 0 failures.
- Readiness oracle: baseline `ReviewWindowControllerReadinessTests`, 10 tests, 6 failures (activation-request false was terminal `pending(activationRejected)` and delayed/never-ready predicates did not poll/timeout); current run: 10 tests, 0 failures.
- Keyboard/confirm oracle: current run: 13 tests, 0 failures. Bare Return, keypad Enter, Command-Return variants, multiline Shift-Return, Option/Control pass-through, IME marked-text Return, exact untrimmed draft, whitespace rejection, selection/undo, accessibility role/value, Escape discard, and native multiline editor/scrolling all executed.
- Review-first coordinator/MainViewModel: current run: 30 tests, 0 failures, including the real production `ReviewWindowController`/`TranscriptionReviewView` path, durable draft/authority and explicit-confirm route.
- Security/fallback/delivery/pasteboard oracles: current runs were all 0-failure: fallback 16, destination delivery 13, pasteboard lifecycle 7, final text-output security 23.

Baseline failure signatures (the falsifying RED oracle) were: `test_frozenDraftExposesSendAndReturnWithoutRetryEditingControl` — `XCTAssertFalse failed` because the obsolete `重试编辑` text was present; `test_streamingReviewContentDoesNotIntersectTrafficLightControls` — `XCTAssertTrue failed` for each of the three traffic-light buttons; and `test_transcriptFontIsMateriallyLargerInStreamingAndEditableSurfaces` — measured streaming and editable font `13.0` was below the required `18.0`. Readiness failures were `test_activationRequestFailureIsAdvisoryWhenPredicatesAreReady` and `test_activationRequestFailurePollsDelayedPredicatesUntilReady` — actual `pending(activationRejected)` instead of `.ready`, plus zero polling counters; and `test_activationRequestFailureWithNeverReadyPredicatesTimesOutWithActualPredicate` — actual `pending(activationRejected)` instead of typed timeout with `lastUnmet: applicationActive`. These all failed on baseline `aec7aad8ca29eab8cbde90b23be5dbe66ce454e2` and are now covered by the passing runs below.

## Exact serialized commands and evidence

All commands used the macOS destination and disabled parallel test execution:

```text
set -o pipefail; xcodebuild -scheme FeishuSpeech -destination 'platform=macOS' -derivedDataPath /tmp/issue40-v3-green-view-derived -only-testing:FeishuSpeechTests/TranscriptionReviewViewTests test -parallel-testing-enabled NO -maximum-parallel-testing-workers 1 2>&1 | tee /tmp/issue40-v3-green-view.log
```

Result: `TranscriptionReviewViewTests` — 8 executed, 0 failures; `** TEST SUCCEEDED **`.
XCTest result: `/tmp/issue40-v3-green-view-derived/Logs/Test/Test-FeishuSpeech-2026.08.23_17-47-30-+0800.xcresult`

```text
set -o pipefail; xcodebuild -scheme FeishuSpeech -destination 'platform=macOS' -derivedDataPath /tmp/issue40-v3-green-keyboard2-derived -only-testing:FeishuSpeechTests/TranscriptionReviewViewKeyboardTests test -parallel-testing-enabled NO -maximum-parallel-testing-workers 1 2>&1 | tee /tmp/issue40-v3-green-keyboard2.log
```

Result: `TranscriptionReviewViewKeyboardTests` — 13 executed, 0 failures; `** TEST SUCCEEDED **`.
XCTest result: `/tmp/issue40-v3-green-keyboard2-derived/Logs/Test/Test-FeishuSpeech-2026.08.23_17-49-16-+0800.xcresult`

```text
set -o pipefail; xcodebuild -scheme FeishuSpeech -destination 'platform=macOS' -derivedDataPath /tmp/issue40-v3-green-readiness-derived -only-testing:FeishuSpeechTests/ReviewWindowControllerReadinessTests test -parallel-testing-enabled NO -maximum-parallel-testing-workers 1 2>&1 | tee /tmp/issue40-v3-green-readiness.log
```

Result: `ReviewWindowControllerReadinessTests` — 10 executed, 0 failures; `** TEST SUCCEEDED **`.
XCTest result: `/tmp/issue40-v3-green-readiness-derived/Logs/Test/Test-FeishuSpeech-2026.08.23_17-49-32-+0800.xcresult`

```text
set -o pipefail; xcodebuild -scheme FeishuSpeech -destination 'platform=macOS' -derivedDataPath /tmp/issue40-v3-green-main-derived -only-testing:FeishuSpeechTests/ReviewFirstMainViewModelTests test -parallel-testing-enabled NO -maximum-parallel-testing-workers 1 2>&1 | tee /tmp/issue40-v3-green-main.log
```

Result: `ReviewFirstMainViewModelTests` — 30 executed, 0 failures; `** TEST SUCCEEDED **`.
XCTest result: `/tmp/issue40-v3-green-main-derived/Logs/Test/Test-FeishuSpeech-2026.08.23_17-49-49-+0800.xcresult`

```text
set -o pipefail; xcodebuild -scheme FeishuSpeech -destination 'platform=macOS' -derivedDataPath /tmp/issue40-v3-green-fallback-derived -only-testing:FeishuSpeechTests/ReviewFirstApplicationFallbackTests test -parallel-testing-enabled NO -maximum-parallel-testing-workers 1 2>&1 | tee /tmp/issue40-v3-green-fallback.log
```

Result: `ReviewFirstApplicationFallbackTests` — 16 executed, 0 failures; `** TEST SUCCEEDED **`.
XCTest result: `/tmp/issue40-v3-green-fallback-derived/Logs/Test/Test-FeishuSpeech-2026.08.23_17-50-10-+0800.xcresult`

```text
set -o pipefail; xcodebuild -scheme FeishuSpeech -destination 'platform=macOS' -derivedDataPath /tmp/issue40-v3-green-delivery-derived -only-testing:FeishuSpeechTests/ReviewDestinationDeliveryTests test -parallel-testing-enabled NO -maximum-parallel-testing-workers 1 2>&1 | tee /tmp/issue40-v3-green-delivery.log
```

Result: `ReviewDestinationDeliveryTests` — 13 executed, 0 failures; `** TEST SUCCEEDED **`.
XCTest result: `/tmp/issue40-v3-green-delivery-derived/Logs/Test/Test-FeishuSpeech-2026.08.23_17-50-27-+0800.xcresult`

```text
set -o pipefail; xcodebuild -scheme FeishuSpeech -destination 'platform=macOS' -derivedDataPath /tmp/issue40-v3-green-pasteboard-derived -only-testing:FeishuSpeechTests/ReviewPasteboardLifecycleTests test -parallel-testing-enabled NO -maximum-parallel-testing-workers 1 2>&1 | tee /tmp/issue40-v3-green-pasteboard.log
```

Result: `ReviewPasteboardLifecycleTests` — 7 executed, 0 failures; `** TEST SUCCEEDED **`.
XCTest result: `/tmp/issue40-v3-green-pasteboard-derived/Logs/Test/Test-FeishuSpeech-2026.08.23_17-50-43-+0800.xcresult`

```text
set -o pipefail; xcodebuild -scheme FeishuSpeech -destination 'platform=macOS' -derivedDataPath /tmp/issue40-v3-green-security-derived -only-testing:FeishuSpeechTests/FinalTextOutputSecurityTests test -parallel-testing-enabled NO -maximum-parallel-testing-workers 1 2>&1 | tee /tmp/issue40-v3-green-security.log
```

Result: `FinalTextOutputSecurityTests` — 23 executed, 0 failures; `** TEST SUCCEEDED **`.
XCTest result: `/tmp/issue40-v3-green-security-derived/Logs/Test/Test-FeishuSpeech-2026.08.23_17-50-59-+0800.xcresult`

## Required identity/layout guards

- `test_reviewPanelRetainsExistingSizeAcrossStreamingAndEditableStates` passed and verifies the existing `ReviewPanel` frame size is unchanged across streaming, sealing, and editable states.
- `test_reviewPanel_isOneNSPanelWithSafeReadOnlyAndEditableAuthorityModes` passed and verifies one retained `ReviewPanel` identity, with no second panel allocation during editable transition.
- `test_streamingReviewContentDoesNotIntersectTrafficLightControls` passed and checks the real production panel's content against all three traffic-light controls.
- `test_productionEditorMaterializesInRetainedPanelAndSurvivesReadinessRetry` passed. It uses the production review surface/editor lookup and verifies the materialized editor is attached to, and remains in, the same retained panel across readiness retry; the explicit first-responder testing seam is deterministic.

`git diff --check` passed after the runs. In the worktree, no production, source documentation, mission-list, or architecture file was changed by this test-author run; the only written workflow artifact is this explicitly assigned receipt. No candidate-caused test failure was observed in the final serialized oracle.

## Final v3 rerun after feedback-copy repairs

The two production feedback-copy repairs are now visible in the shared tree:

- `.activationFailed`: `无法激活目标应用；请确认后再发送。`
- `.deliveryUncertain`: `输入状态不确定；再次发送可能造成重复输入。`

The two new copy oracles were rerun first, serialized:

```text
set -o pipefail; xcodebuild -scheme FeishuSpeech -destination 'platform=macOS' -derivedDataPath /tmp/issue40-v3-green-feedback-derived -only-testing:FeishuSpeechTests/TranscriptionReviewViewTests/test_deliveryUncertainFeedbackWarnsAboutPossibleDuplicateSendWithoutRetryEditing -only-testing:FeishuSpeechTests/TranscriptionReviewViewTests/test_activationFailedFeedbackNamesTargetApplicationWithoutPreparationOrRetryText test -parallel-testing-enabled NO -maximum-parallel-testing-workers 1 2>&1 | tee /tmp/issue40-v3-green-feedback.log
```

Result: `TranscriptionReviewViewTests` — 2 executed, 0 failures; `** TEST SUCCEEDED **`.
XCTest result: `/tmp/issue40-v3-green-feedback-derived/Logs/Test/Test-FeishuSpeech-2026.08.23_18-02-44-+0800.xcresult`

The complete focused v3 matrix was then rerun serialized. Each command used
`-parallel-testing-enabled NO -maximum-parallel-testing-workers 1`:

```text
set -o pipefail; xcodebuild -scheme FeishuSpeech -destination 'platform=macOS' -derivedDataPath /tmp/issue40-v3-green-view-final-derived -only-testing:FeishuSpeechTests/TranscriptionReviewViewTests test -parallel-testing-enabled NO -maximum-parallel-testing-workers 1 2>&1 | tee /tmp/issue40-v3-green-view-final.log
```

Result: `TranscriptionReviewViewTests` — 10 executed, 0 failures.
XCTest result: `/tmp/issue40-v3-green-view-final-derived/Logs/Test/Test-FeishuSpeech-2026.08.23_18-03-06-+0800.xcresult`

```text
set -o pipefail; xcodebuild -scheme FeishuSpeech -destination 'platform=macOS' -derivedDataPath /tmp/issue40-v3-green-keyboard-final-derived -only-testing:FeishuSpeechTests/TranscriptionReviewViewKeyboardTests test -parallel-testing-enabled NO -maximum-parallel-testing-workers 1 2>&1 | tee /tmp/issue40-v3-green-keyboard-final.log
```

Result: `TranscriptionReviewViewKeyboardTests` — 13 executed, 0 failures.
XCTest result: `/tmp/issue40-v3-green-keyboard-final-derived/Logs/Test/Test-FeishuSpeech-2026.08.23_18-03-21-+0800.xcresult`

```text
set -o pipefail; xcodebuild -scheme FeishuSpeech -destination 'platform=macOS' -derivedDataPath /tmp/issue40-v3-green-readiness-final-derived -only-testing:FeishuSpeechTests/ReviewWindowControllerReadinessTests test -parallel-testing-enabled NO -maximum-parallel-testing-workers 1 2>&1 | tee /tmp/issue40-v3-green-readiness-final.log
```

Result: `ReviewWindowControllerReadinessTests` — 10 executed, 0 failures.
XCTest result: `/tmp/issue40-v3-green-readiness-final-derived/Logs/Test/Test-FeishuSpeech-2026.08.23_18-03-37-+0800.xcresult`

```text
set -o pipefail; xcodebuild -scheme FeishuSpeech -destination 'platform=macOS' -derivedDataPath /tmp/issue40-v3-green-main-final-derived -only-testing:FeishuSpeechTests/ReviewFirstMainViewModelTests test -parallel-testing-enabled NO -maximum-parallel-testing-workers 1 2>&1 | tee /tmp/issue40-v3-green-main-final.log
```

Result: `ReviewFirstMainViewModelTests` — 30 executed, 0 failures.
XCTest result: `/tmp/issue40-v3-green-main-final-derived/Logs/Test/Test-FeishuSpeech-2026.08.23_18-03-54-+0800.xcresult`

```text
set -o pipefail; xcodebuild -scheme FeishuSpeech -destination 'platform=macOS' -derivedDataPath /tmp/issue40-v3-green-fallback-final-derived -only-testing:FeishuSpeechTests/ReviewFirstApplicationFallbackTests test -parallel-testing-enabled NO -maximum-parallel-testing-workers 1 2>&1 | tee /tmp/issue40-v3-green-fallback-final.log
```

Result: `ReviewFirstApplicationFallbackTests` — 16 executed, 0 failures.
XCTest result: `/tmp/issue40-v3-green-fallback-final-derived/Logs/Test/Test-FeishuSpeech-2026.08.23_18-04-12-+0800.xcresult`

```text
set -o pipefail; xcodebuild -scheme FeishuSpeech -destination 'platform=macOS' -derivedDataPath /tmp/issue40-v3-green-delivery-final-derived -only-testing:FeishuSpeechTests/ReviewDestinationDeliveryTests test -parallel-testing-enabled NO -maximum-parallel-testing-workers 1 2>&1 | tee /tmp/issue40-v3-green-delivery-final.log
```

Result: `ReviewDestinationDeliveryTests` — 13 executed, 0 failures.
XCTest result: `/tmp/issue40-v3-green-delivery-final-derived/Logs/Test/Test-FeishuSpeech-2026.08.23_18-04-28-+0800.xcresult`

```text
set -o pipefail; xcodebuild -scheme FeishuSpeech -destination 'platform=macOS' -derivedDataPath /tmp/issue40-v3-green-pasteboard-final-derived -only-testing:FeishuSpeechTests/ReviewPasteboardLifecycleTests test -parallel-testing-enabled NO -maximum-parallel-testing-workers 1 2>&1 | tee /tmp/issue40-v3-green-pasteboard-final.log
```

Result: `ReviewPasteboardLifecycleTests` — 7 executed, 0 failures.
XCTest result: `/tmp/issue40-v3-green-pasteboard-final-derived/Logs/Test/Test-FeishuSpeech-2026.08.23_18-04-44-+0800.xcresult`

```text
set -o pipefail; xcodebuild -scheme FeishuSpeech -destination 'platform=macOS' -derivedDataPath /tmp/issue40-v3-green-security-final-derived -only-testing:FeishuSpeechTests/FinalTextOutputSecurityTests test -parallel-testing-enabled NO -maximum-parallel-testing-workers 1 2>&1 | tee /tmp/issue40-v3-green-security-final.log
```

Result: `FinalTextOutputSecurityTests` — 23 executed, 0 failures.
XCTest result: `/tmp/issue40-v3-green-security-final-derived/Logs/Test/Test-FeishuSpeech-2026.08.23_18-04-59-+0800.xcresult`

The targeted coordinator pair was also rerun:

```text
set -o pipefail; xcodebuild -scheme FeishuSpeech -destination 'platform=macOS' -derivedDataPath /tmp/issue40-v3-green-coordinator-final-derived -only-testing:FeishuSpeechTests/ReviewFirstMainViewModelTests/test_reviewFirst_realProductionSurfaceMakesFrozenDraftConfirmableWithoutRetryEditing -only-testing:FeishuSpeechTests/ReviewFirstMainViewModelTests/test_reviewFirst_nonCancellationDeliveryFailureReturnsFrozenDraftToEditableWithoutRecoveryCopy test -parallel-testing-enabled NO -maximum-parallel-testing-workers 1 2>&1 | tee /tmp/issue40-v3-green-coordinator-final.log
```

Result: 2 executed, 0 failures. This preserves the real production panel/editor
confirm path and the delivery-uncertain exact-draft/no-auto-retry callback path.
XCTest result: `/tmp/issue40-v3-green-coordinator-final-derived/Logs/Test/Test-FeishuSpeech-2026.08.23_18-05-16-+0800.xcresult`

Both prior copy findings are closed by the final focused oracle: the
delivery-uncertain view warns about possible duplicate explicit Send, and the
activation-failed view names target-application activation failure without
claiming the editor is still preparing. All final runs passed, and `git
diff --check` passed after the rerun. The shared worktree's concurrent
production/docs changes were preserved and not edited by this test-author run.
